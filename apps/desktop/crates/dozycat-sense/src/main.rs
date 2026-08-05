//! dozycat-sense 守护循环：5s tick 采样系统计数器 → 1min 聚合 → 能量模型 → JSONL。
//!
//! 内容盲：只读 CoreGraphics 的事件计数器与空闲秒数（无键值、无坐标、无截图），
//! 外加前台 app 名。原始计数不出本进程；输出只有能量语义。
//!
//! 环境变量：
//!   DOZYCAT_TICK_SECS   tick 间隔（默认 5；演示可设 1）
//!   DOZYCAT_TICKS_PER_MINUTE  每「分钟」的 tick 数（默认 12；演示可设 3）
//!   DOZYCAT_STORE       LoroStore 路径（默认 ~/.dozycat/store.db；"off" 关闭落账）

use dozycat_core::{EnergyEvent, LoroStore};
use dozycat_sense::{looks_like_meeting, EnergyModel, MinuteSample, Output};
use std::process::Command;
use std::time::Duration;

// CoreGraphics 事件计数器（系统级聚合计数，无需辅助功能权限）。
#[link(name = "CoreGraphics", kind = "framework")]
extern "C" {
    fn CGEventSourceCounterForEventType(state: i32, event_type: u32) -> u32;
    fn CGEventSourceSecondsSinceLastEventType(state: i32, event_type: u32) -> f64;
}

const COMBINED_SESSION_STATE: i32 = 0; // kCGEventSourceStateCombinedSessionState
const KEY_DOWN: u32 = 10; // kCGEventKeyDown
const LEFT_MOUSE_DOWN: u32 = 1;
const RIGHT_MOUSE_DOWN: u32 = 3;
const SCROLL_WHEEL: u32 = 22;
const ANY_INPUT: u32 = u32::MAX; // kCGAnyInputEventType

fn counter(event_type: u32) -> u32 {
    unsafe { CGEventSourceCounterForEventType(COMBINED_SESSION_STATE, event_type) }
}

fn idle_seconds() -> f64 {
    unsafe { CGEventSourceSecondsSinceLastEventType(COMBINED_SESSION_STATE, ANY_INPUT) }
}

/// 前台 app 名。v0 走 lsappinfo（系统自带，两步：front → ASN → name）；
/// v1 换 NSWorkspace 通知。
fn front_app() -> String {
    let asn = match Command::new("lsappinfo").arg("front").output() {
        Ok(out) => String::from_utf8_lossy(&out.stdout).trim().to_string(),
        Err(_) => return String::new(),
    };
    if asn.is_empty() {
        return String::new();
    }
    if let Ok(out) = Command::new("lsappinfo").args(["info", "-only", "name", &asn]).output() {
        // 形如: "LSDisplayName"="Cursor"
        let s = String::from_utf8_lossy(&out.stdout);
        if let Some(eq) = s.rfind('=') {
            return s[eq + 1..].trim().trim_matches('"').to_string();
        }
    }
    String::new()
}

fn json_escape(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}

fn emit(output: &Output, front: &str) {
    match output {
        Output::Minute { intensity, phys, mind, active_streak_min, meeting } => {
            println!(
                "{{\"kind\":\"minute\",\"intensity\":{intensity:.2},\"phys\":{phys:.1},\
                 \"mind\":{mind:.1},\"activeStreakMin\":{active_streak_min},\
                 \"meeting\":{meeting},\"frontApp\":\"{}\"}}",
                json_escape(front)
            );
        }
        Output::Nudge { kind, message } => {
            println!(
                "{{\"kind\":\"nudge\",\"nudge\":\"{kind:?}\",\"message\":\"{}\"}}",
                json_escape(message)
            );
        }
    }
}

fn env_u64(name: &str, default: u64) -> u64 {
    std::env::var(name).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
}

/// 打开共享内核账本（DOZYCAT_STORE=off 关闭）。
fn open_store() -> Option<LoroStore> {
    let path = std::env::var("DOZYCAT_STORE").unwrap_or_else(|_| {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
        format!("{home}/.dozycat/store.db")
    });
    if path == "off" {
        return None;
    }
    if let Some(dir) = std::path::Path::new(&path).parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    match LoroStore::open(std::path::Path::new(&path)) {
        Ok(store) => {
            eprintln!("dozycat-sense: energy ledger → {path}");
            Some(store)
        }
        Err(e) => {
            eprintln!("dozycat-sense: store unavailable ({e}), running without ledger");
            None
        }
    }
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn record(store: &Option<LoroStore>, output: &Output, phys: f64, mind: f64) {
    let Some(store) = store else { return };
    let kind = match output {
        Output::Minute { .. } => "minute".to_string(),
        Output::Nudge { kind, .. } => format!("nudge:{kind:?}"),
    };
    let event = EnergyEvent { at_ms: now_ms(), device: "mac".into(), phys, mind, kind };
    if let Err(e) = store.record_energy(&event) {
        eprintln!("dozycat-sense: ledger write failed: {e}");
    }
}

fn main() {
    let tick = Duration::from_secs(env_u64("DOZYCAT_TICK_SECS", 5).max(1));
    let ticks_per_minute = (env_u64("DOZYCAT_TICKS_PER_MINUTE", 12) as u32).max(1);
    // 「这一分钟是否空闲」= 分钟末尾连续无输入 ≥ 窗口的 90%（默认 60s → 54s）
    let idle_threshold = tick.as_secs_f64() * ticks_per_minute as f64 * 0.9;
    let store = open_store();

    // 初始能量：宿主注入（DOZYCAT_INIT_*，pet 持库时由它提供）优先，
    // 其次从自己的账本恢复（独立运行模式），最后默认 72/72。
    let resume = store.as_ref().and_then(|s| s.latest_energy());
    let phys0 = std::env::var("DOZYCAT_INIT_PHYS").ok().and_then(|v| v.parse().ok())
        .or(resume.as_ref().map(|e| e.phys as f32)).unwrap_or(72.0);
    let mind0 = std::env::var("DOZYCAT_INIT_MIND").ok().and_then(|v| v.parse().ok())
        .or(resume.as_ref().map(|e| e.mind as f32)).unwrap_or(72.0);

    let mut model = EnergyModel::new(phys0, mind0);
    let mut prev_keys = counter(KEY_DOWN);
    let mut prev_clicks = counter(LEFT_MOUSE_DOWN).wrapping_add(counter(RIGHT_MOUSE_DOWN));
    let mut prev_scrolls = counter(SCROLL_WHEEL);
    let mut prev_front = front_app();

    let mut acc = MinuteSample { front_app: prev_front.clone(), ..Default::default() };
    let mut ticks = 0u32;

    eprintln!(
        "dozycat-sense: content-blind fatigue sensing (tick {}s, {} ticks/minute)",
        tick.as_secs(),
        ticks_per_minute
    );

    loop {
        std::thread::sleep(tick);
        ticks += 1;

        let keys = counter(KEY_DOWN);
        let clicks = counter(LEFT_MOUSE_DOWN).wrapping_add(counter(RIGHT_MOUSE_DOWN));
        let scrolls = counter(SCROLL_WHEEL);
        acc.keys += keys.wrapping_sub(prev_keys);
        acc.clicks += clicks.wrapping_sub(prev_clicks);
        acc.scrolls += scrolls.wrapping_sub(prev_scrolls);
        (prev_keys, prev_clicks, prev_scrolls) = (keys, clicks, scrolls);

        let front = front_app();
        if !front.is_empty() && front != prev_front {
            acc.switches += 1;
            prev_front = front.clone();
            acc.front_app = front;
        }
        acc.meeting = acc.meeting || looks_like_meeting(&acc.front_app);

        if ticks >= ticks_per_minute {
            acc.idle = idle_seconds() >= idle_threshold && acc.keys == 0 && acc.clicks == 0;
            let front = acc.front_app.clone();
            for output in model.step(&acc) {
                emit(&output, &front);
                record(&store, &output, model.phys as f64, model.mind as f64);
            }
            acc = MinuteSample { front_app: front, ..Default::default() };
            ticks = 0;
        }
    }
}
