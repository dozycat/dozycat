//! 疲劳能量模型 — 纯逻辑，无 OS 依赖，两端共用同一套常数。
//!
//! 输入：每分钟一个内容盲采样（计数与布尔，无任何内容）。
//! 输出：能量刻度更新 + 补血 nudge。数学见 docs/FATIGUE.md。

/// 一分钟的劳动采样。全部是计数/布尔——没有键值、没有窗口内容。
#[derive(Debug, Clone, Default)]
pub struct MinuteSample {
    pub keys: u32,
    pub clicks: u32,
    pub scrolls: u32,
    /// 前台 app 切换次数
    pub switches: u32,
    /// 前台 app 名（只用于会议启发式与日志，不参与打分）
    pub front_app: String,
    /// 会议中（v0: app 启发式；v1: 麦克风/摄像头占用）
    pub meeting: bool,
    /// 这一分钟是否空闲（分钟末尾无输入 ≥ 55s）
    pub idle: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub enum NudgeKind {
    LongSitting,
    PostMeeting,
    LowPhysical,
    HighChurn,
}

#[derive(Debug, Clone)]
pub enum Output {
    Minute {
        intensity: f32,
        phys: f32,
        mind: f32,
        active_streak_min: u32,
        meeting: bool,
    },
    Nudge {
        kind: NudgeKind,
        message: String,
    },
}

/// 强度折算与能量损耗的全部常数（docs/FATIGUE.md 的唯一事实来源在这里）。
pub mod tuning {
    pub const KEYS_FULL: f32 = 300.0; // 这个键速算「满强度输入」
    pub const POINTER_FULL: f32 = 60.0;
    pub const SWITCHES_FULL: f32 = 6.0;
    pub const MEETING_FLOOR: f32 = 0.7; // 开会最少算 0.7 强度

    pub const PHYS_BASE_DRAIN: f32 = 0.10; // 每活跃分钟
    pub const PHYS_INTENSITY_DRAIN: f32 = 0.25;
    pub const MIND_BASE_DRAIN: f32 = 0.05;
    pub const MIND_SWITCH_DRAIN: f32 = 0.20;
    pub const MIND_MEETING_DRAIN: f32 = 0.25;
    pub const MIND_LONG_FOCUS_DRAIN: f32 = 0.10; // 连续活跃 > 60min 后叠加

    pub const RECOVERY_AFTER_IDLE_MIN: u32 = 3; // 离开满 3 分钟才开始回血
    pub const PHYS_RECOVERY: f32 = 0.5; // 每空闲分钟
    pub const MIND_RECOVERY: f32 = 0.3;

    pub const LONG_SITTING_MIN: u32 = 90;
    pub const MEETING_COUNTS_AFTER_MIN: u32 = 20; // 会议 ≥20min 结束才提示补血
    /// 会议态消失后要连续确认这么多分钟才算「会真的结束了」——
    /// 防止开会中途切去记笔记的那一分钟误触发「会开完了」。
    pub const MEETING_END_CONFIRM_MIN: u32 = 3;
    pub const LOW_PHYS_THRESHOLD: f32 = 30.0;
    pub const HIGH_CHURN_STREAK_MIN: u32 = 15; // 连续高切换分钟数
    pub const NUDGE_COOLDOWN_MIN: u32 = 45; // 同类 nudge 冷却
}

pub struct EnergyModel {
    pub phys: f32,
    pub mind: f32,
    minute: u64,
    active_streak: u32,
    idle_streak: u32,
    meeting_streak: u32,
    /// 会议态消失后的连续分钟数（结束确认用，见 MEETING_END_CONFIRM_MIN）
    meeting_gap: u32,
    churn_streak: u32,
    last_nudge: [Option<u64>; 4],
}

impl EnergyModel {
    pub fn new(phys: f32, mind: f32) -> Self {
        Self {
            phys,
            mind,
            minute: 0,
            active_streak: 0,
            idle_streak: 0,
            meeting_streak: 0,
            meeting_gap: 0,
            churn_streak: 0,
            last_nudge: [None; 4],
        }
    }

    pub fn intensity(s: &MinuteSample) -> f32 {
        use tuning::*;
        let keys = (s.keys as f32 / KEYS_FULL).min(1.0);
        let pointer = ((s.clicks + s.scrolls) as f32 / POINTER_FULL).min(1.0);
        let switches = (s.switches as f32 / SWITCHES_FULL).min(1.0);
        let mut i = 0.5 * keys + 0.3 * pointer + 0.2 * switches;
        if s.meeting {
            i = i.max(MEETING_FLOOR);
        }
        i.clamp(0.0, 1.0)
    }

    pub fn step(&mut self, s: &MinuteSample) -> Vec<Output> {
        use tuning::*;
        self.minute += 1;
        let mut out = Vec::new();
        let i = Self::intensity(s);
        let active = !s.idle || s.meeting;

        // 会议结束 = 会议态消失并连续确认 MEETING_END_CONFIRM_MIN 分钟。
        // 中途切去别的 app 记一两分钟笔记不算结束（v0 的 app 启发式误差兜底）。
        let mut meeting_ended_after = 0u32;
        if s.meeting {
            self.meeting_streak += 1;
            self.meeting_gap = 0;
        } else if self.meeting_streak > 0 {
            self.meeting_gap += 1;
            if self.meeting_gap >= MEETING_END_CONFIRM_MIN {
                meeting_ended_after = self.meeting_streak;
                self.meeting_streak = 0;
                self.meeting_gap = 0;
            }
        }

        if active {
            self.active_streak += 1;
            self.idle_streak = 0;

            self.phys -= PHYS_BASE_DRAIN + PHYS_INTENSITY_DRAIN * i;
            let switch_factor = (s.switches as f32 / SWITCHES_FULL).min(1.0);
            let mut mind_drain = MIND_BASE_DRAIN + MIND_SWITCH_DRAIN * switch_factor;
            if s.meeting {
                mind_drain += MIND_MEETING_DRAIN;
            }
            if self.active_streak > 60 {
                mind_drain += MIND_LONG_FOCUS_DRAIN;
            }
            self.mind -= mind_drain;

            if switch_factor >= 0.8 {
                self.churn_streak += 1;
            } else {
                self.churn_streak = 0;
            }
        } else {
            self.active_streak = 0;
            self.churn_streak = 0;
            self.idle_streak += 1;
            if self.idle_streak >= RECOVERY_AFTER_IDLE_MIN {
                self.phys += PHYS_RECOVERY;
                self.mind += MIND_RECOVERY;
            }
        }
        self.phys = self.phys.clamp(0.0, 100.0);
        self.mind = self.mind.clamp(0.0, 100.0);

        // ---- nudges（带冷却，一次只说一句）----
        let nudge = if meeting_ended_after >= MEETING_COUNTS_AFTER_MIN {
            Some((
                NudgeKind::PostMeeting,
                "会开完了吧？高强度输出后要补血，起来走两步～".to_string(),
            ))
        } else if self.active_streak >= LONG_SITTING_MIN {
            Some((
                NudgeKind::LongSitting,
                format!("坐了 {} 分钟啦，去接杯水回血？", self.active_streak),
            ))
        } else if active && self.phys < LOW_PHYS_THRESHOLD {
            Some((
                NudgeKind::LowPhysical,
                format!(
                    "生理能量掉到 {} 了，眼睛离开屏幕一会儿好不好？",
                    self.phys as u32
                ),
            ))
        } else if self.churn_streak >= HIGH_CHURN_STREAK_MIN {
            Some((
                NudgeKind::HighChurn,
                "感觉你在好多事之间跳，挑一件收个尾？".to_string(),
            ))
        } else {
            None
        };

        if let Some((kind, message)) = nudge {
            let slot = kind_slot(&kind);
            let ready = match self.last_nudge[slot] {
                Some(at) => self.minute - at >= NUDGE_COOLDOWN_MIN as u64,
                None => true,
            };
            if ready {
                self.last_nudge[slot] = Some(self.minute);
                out.push(Output::Nudge { kind, message });
            }
        }

        out.push(Output::Minute {
            intensity: i,
            phys: self.phys,
            mind: self.mind,
            active_streak_min: self.active_streak,
            meeting: s.meeting,
        });
        out
    }
}

fn kind_slot(k: &NudgeKind) -> usize {
    match k {
        NudgeKind::LongSitting => 0,
        NudgeKind::PostMeeting => 1,
        NudgeKind::LowPhysical => 2,
        NudgeKind::HighChurn => 3,
    }
}

/// 会议 app 启发式（v0）。v1 用麦克风/摄像头占用替代。
pub fn looks_like_meeting(front_app: &str) -> bool {
    const MEETING_APPS: &[&str] = &[
        "zoom.us",
        "Zoom",
        "Microsoft Teams",
        "FaceTime",
        "Webex",
        "TencentMeeting",
        "腾讯会议",
        "VooV Meeting",
        "Google Meet",
    ];
    MEETING_APPS.iter().any(|m| front_app.contains(m))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn coding_minute() -> MinuteSample {
        MinuteSample {
            keys: 250,
            clicks: 20,
            scrolls: 30,
            switches: 1,
            front_app: "Cursor".into(),
            ..Default::default()
        }
    }

    fn meeting_minute() -> MinuteSample {
        MinuteSample {
            keys: 5,
            front_app: "zoom.us".into(),
            meeting: true,
            idle: true, // 手不动，但在开会——仍是劳动
            ..Default::default()
        }
    }

    fn idle_minute() -> MinuteSample {
        MinuteSample {
            idle: true,
            front_app: "Finder".into(),
            ..Default::default()
        }
    }

    #[test]
    fn intense_coding_drains_and_eventually_nudges() {
        let mut m = EnergyModel::new(80.0, 80.0);
        let mut nudged = false;
        for _ in 0..95 {
            for o in m.step(&coding_minute()) {
                if let Output::Nudge { kind, .. } = o {
                    if kind == NudgeKind::LongSitting {
                        nudged = true;
                    }
                }
            }
        }
        assert!(m.phys < 60.0, "1.5h 高强度后生理应明显下降: {}", m.phys);
        assert!(nudged, "连续活跃 ≥90min 应触发久坐提醒");
    }

    fn has_post_meeting(outs: &[Output]) -> bool {
        outs.iter()
            .any(|o| matches!(o, Output::Nudge { kind: NudgeKind::PostMeeting, .. }))
    }

    #[test]
    fn meeting_end_triggers_recovery_nudge_after_confirmation() {
        let mut m = EnergyModel::new(80.0, 80.0);
        for _ in 0..30 {
            m.step(&meeting_minute());
        }
        assert!(m.mind < 72.0, "半小时会议应磨掉可感知的心理能量");
        // 结束确认期内（前 2 分钟）不提示
        assert!(!has_post_meeting(&m.step(&idle_minute())));
        assert!(!has_post_meeting(&m.step(&idle_minute())));
        // 第 3 分钟确认会议真的结束 → 补血提示
        assert!(
            has_post_meeting(&m.step(&idle_minute())),
            "≥20min 会议结束（确认 3 分钟后）应提示补血"
        );
    }

    #[test]
    fn brief_alt_tab_does_not_end_meeting() {
        let mut m = EnergyModel::new(80.0, 80.0);
        for _ in 0..25 {
            m.step(&meeting_minute());
        }
        // 会中切出去记 2 分钟笔记……
        assert!(!has_post_meeting(&m.step(&coding_minute())));
        assert!(!has_post_meeting(&m.step(&coding_minute())));
        // ……又回到会议：不能算会议结束
        m.step(&meeting_minute());
        for _ in 0..3 {
            assert!(
                !has_post_meeting(&m.step(&meeting_minute())),
                "回到会议后不应触发「会开完了」"
            );
        }
    }

    #[test]
    fn short_meeting_does_not_nudge() {
        let mut m = EnergyModel::new(80.0, 80.0);
        for _ in 0..10 {
            m.step(&meeting_minute());
        }
        for _ in 0..5 {
            assert!(!has_post_meeting(&m.step(&idle_minute())));
        }
    }

    #[test]
    fn walking_away_recovers() {
        let mut m = EnergyModel::new(40.0, 40.0);
        for _ in 0..20 {
            m.step(&idle_minute());
        }
        assert!(m.phys > 47.0, "20min 离开应回血: {}", m.phys);
        assert!(m.mind > 44.0);
    }

    #[test]
    fn nudge_cooldown_holds() {
        let mut m = EnergyModel::new(80.0, 80.0);
        let mut count = 0;
        for _ in 0..130 {
            for o in m.step(&coding_minute()) {
                if matches!(o, Output::Nudge { kind: NudgeKind::LongSitting, .. }) {
                    count += 1;
                }
            }
        }
        assert_eq!(count, 1, "冷却期内同类 nudge 不应重复");
    }

    #[test]
    fn meeting_heuristic() {
        assert!(looks_like_meeting("zoom.us"));
        assert!(looks_like_meeting("腾讯会议"));
        assert!(!looks_like_meeting("Cursor"));
    }
}
