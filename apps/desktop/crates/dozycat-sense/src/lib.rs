//! 疲劳能量模型 — 纯逻辑，无 OS 依赖，两端共用同一套常数。
//!
//! 输入：每分钟一个内容盲采样（计数与布尔，无任何内容）。
//! 输出：能量刻度更新 + 补血 nudge。数学见 docs/FATIGUE.md。

/// 摄像头在位信号（可选，pet 侧采样后经 hints 文件送进来）。
/// 只有一个布尔跨过边界——画面帧不出采样器。Unknown = 没开摄像头感知
/// 或提示过期，模型退回 v0 的纯键鼠语义。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Presence {
    #[default]
    Unknown,
    /// 摄像头里有人脸：人在屏幕前
    Present,
    /// 摄像头里没有人脸：人离开了
    Away,
}

/// 活动类别（pet 侧从前台 app + OCR 关键词规则分类，5 分钟一档）。
/// 只有类别标签跨过边界——OCR 文本不出 pet。Unknown 退回 v0 语义。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Activity {
    #[default]
    Unknown,
    /// 深度产出：写代码、写文档
    Deep,
    /// 沟通：微信 / Slack / 邮件这类聊天
    Comms,
    /// 会议（活动分类到会议时与 app 启发式取并）
    Meeting,
    /// 阅读浏览
    Browse,
    /// 娱乐：视频、游戏
    Fun,
}

/// 一分钟的劳动采样。计数/布尔/类别——没有键值、没有窗口内容、没有画面。
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
    /// 摄像头在位（v2；Unknown 退回 v0 语义）
    pub presence: Presence,
    /// 活动类别（v2；Unknown 退回 v0 语义）
    pub activity: Activity,
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
        seated_streak_min: u32,
        meeting: bool,
        presence: Presence,
        activity: Activity,
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
    pub const PHYS_RECOVERY: f32 = 0.5; // 每空闲分钟（红利期之后）
    pub const MIND_RECOVERY: f32 = 0.3;
    /// 短憩红利：回血起算后的前 10 分钟双倍速——接杯水、走两步这种
    /// 短休息的恢复效率最高（微休息文献同款结论）。没有它，nudge 让人
    /// 「去接杯水」账上却几乎不奖励，反馈环是断的。
    pub const RECOVERY_FAST_MIN: u32 = 10;
    pub const PHYS_RECOVERY_FAST: f32 = 1.0;
    pub const MIND_RECOVERY_FAST: f32 = 0.5;

    // ---- v2：摄像头在位 + 活动类别 ----
    /// 摄像头确认离开只要 2 分钟就起算回血（比纯键鼠推断的 3 分钟快，
    /// 因为「没人脸」比「没输入」证据硬——停下来想事不会被误判成离开）
    pub const RECOVERY_AFTER_AWAY_MIN: u32 = 2;
    /// 在座但手不动（读文档、看视频）：不回血，久坐照旧磨损
    pub const PASSIVE_SITTING_DRAIN: f32 = 0.03; // 每分钟，约合每小时 1.8 点
    /// 被动娱乐/浏览时心理轻微回血——歇的是脑子，不是身体
    pub const MIND_PASSIVE_RECOVERY: f32 = 0.05;
    /// 活动类别对心理损耗的系数（生理损耗只看强度和久坐，不看在干什么）
    pub const MIND_MULT_DEEP: f32 = 1.2; // 深度产出最费执行功能
    pub const MIND_MULT_COMMS: f32 = 0.9; // 聊天有社交负荷但执行负荷低
    pub const MIND_MULT_BROWSE: f32 = 0.8;
    pub const MIND_MULT_FUN: f32 = 0.5; // 打着游戏刷着视频，脑子在放松

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
    /// 连续在座分钟数（v2）：输入活跃或摄像头见人都算在座。
    /// 有了它，看视频那种「手不动但一直坐着」也会累进久坐提醒。
    seat_streak: u32,
    /// 摄像头确认离开的连续分钟数（v2 回血起算用）
    away_streak: u32,
    /// 本次休息已经回血的分钟数（短憩红利的计时器；一动就归零）
    rest_streak: u32,
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
            seat_streak: 0,
            away_streak: 0,
            rest_streak: 0,
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

        // 会议 = app 启发式 ∪ 活动分类（OCR 语义那条线也能认出会议界面）
        let meeting = s.meeting || s.activity == Activity::Meeting;
        let mut i = Self::intensity(s);
        if meeting {
            i = i.max(MEETING_FLOOR);
        }
        let active = !s.idle || meeting;
        // 在座 = 手在动，或摄像头见人。摄像头说人在而手不动（读文档、看视频、
        // 想事），是「被动在座」——不回血；摄像头没开就退回 v0 的输入推断。
        let seated = active || s.presence == Presence::Present;

        // 会议结束 = 会议态消失并连续确认 MEETING_END_CONFIRM_MIN 分钟。
        // 中途切去别的 app 记一两分钟笔记不算结束（v0 的 app 启发式误差兜底）。
        let mut meeting_ended_after = 0u32;
        if meeting {
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

        if seated {
            self.seat_streak += 1;
            self.away_streak = 0;
        } else {
            self.seat_streak = 0;
            if s.presence == Presence::Away {
                self.away_streak += 1;
            }
        }

        if active {
            self.active_streak += 1;
            self.idle_streak = 0;
            self.rest_streak = 0;

            // 生理损耗只看强度和坐着本身，不看在干什么——身体不在乎你是
            // 写代码还是刷视频，在乎的是这一小时没起身。
            self.phys -= PHYS_BASE_DRAIN + PHYS_INTENSITY_DRAIN * i;

            // 心理损耗看的是执行功能的开销：切换、会议、连续专注是加项，
            // 活动类别是系数——同样的键速，写代码比在微信聊天磨脑子。
            let switch_factor = (s.switches as f32 / SWITCHES_FULL).min(1.0);
            let activity_mult = match s.activity {
                Activity::Deep => MIND_MULT_DEEP,
                Activity::Comms => MIND_MULT_COMMS,
                Activity::Browse => MIND_MULT_BROWSE,
                Activity::Fun => MIND_MULT_FUN,
                Activity::Meeting | Activity::Unknown => 1.0,
            };
            let mut mind_drain =
                (MIND_BASE_DRAIN + MIND_SWITCH_DRAIN * switch_factor) * activity_mult;
            if meeting {
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
        } else if seated {
            // 被动在座（摄像头见人、手不动）：不算离开、不回血。身体还坐着，
            // 每分钟照磨一点；娱乐或浏览时脑子在歇，心理轻微回血。
            self.active_streak = 0;
            self.churn_streak = 0;
            self.idle_streak += 1;
            self.rest_streak = 0;
            self.phys -= PASSIVE_SITTING_DRAIN;
            if matches!(s.activity, Activity::Fun | Activity::Browse) {
                self.mind += MIND_PASSIVE_RECOVERY;
            }
        } else {
            self.active_streak = 0;
            self.churn_streak = 0;
            self.idle_streak += 1;
            // 回血起算：摄像头确认离开 2 分钟就够（证据硬）；
            // 没有摄像头就沿用「连续无输入 3 分钟」的保守推断。
            let resting = if s.presence == Presence::Away {
                self.away_streak >= RECOVERY_AFTER_AWAY_MIN
            } else {
                self.idle_streak >= RECOVERY_AFTER_IDLE_MIN
            };
            if resting {
                // 短憩红利：本次休息的前 10 个回血分钟双倍速，之后回到常速。
                // 站起来一刻钟 ≈ 回 11 点——胶囊文案说的就是这笔账。
                self.rest_streak += 1;
                if self.rest_streak <= RECOVERY_FAST_MIN {
                    self.phys += PHYS_RECOVERY_FAST;
                    self.mind += MIND_RECOVERY_FAST;
                } else {
                    self.phys += PHYS_RECOVERY;
                    self.mind += MIND_RECOVERY;
                }
            }
        }
        self.phys = self.phys.clamp(0.0, 100.0);
        self.mind = self.mind.clamp(0.0, 100.0);

        // ---- nudges（带冷却，一次只说一句）----
        // 久坐看 seat_streak：摄像头在位时，刷两小时视频和写两小时代码
        // 一样会被提醒起身——身体不区分这两件事。
        let nudge = if meeting_ended_after >= MEETING_COUNTS_AFTER_MIN {
            Some((
                NudgeKind::PostMeeting,
                "会开完了吧？高强度输出后要补血，起来走两步～".to_string(),
            ))
        } else if self.seat_streak >= LONG_SITTING_MIN {
            Some((
                NudgeKind::LongSitting,
                format!("坐了 {} 分钟啦，去接杯水回血？", self.seat_streak),
            ))
        } else if seated && self.phys < LOW_PHYS_THRESHOLD {
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
            seated_streak_min: self.seat_streak,
            meeting,
            presence: s.presence,
            activity: s.activity,
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
        // 20 分钟离开：3 分钟确认 + 10 分钟红利（×1.0）+ 7 分钟常速（×0.5）
        // 生理应回约 13.5
        let mut m = EnergyModel::new(40.0, 40.0);
        for _ in 0..20 {
            m.step(&idle_minute());
        }
        assert!(m.phys > 52.0, "20min 离开应回约 13.5: {}", m.phys);
        assert!(m.mind > 46.0);
    }

    // ---- 短憩红利（产品逻辑：nudge 让你接杯水，账上必须奖励）----

    #[test]
    fn quarter_hour_break_pays_back_double_digits() {
        // 胶囊文案的那笔账：「站起来歇一刻钟，能回十来点」。
        // 15 分钟 = 3 确认 + 10 红利（+10）+ 2 常速（+1）→ +11
        let mut m = EnergyModel::new(50.0, 50.0);
        for _ in 0..15 {
            m.step(&idle_minute());
        }
        assert!(
            (m.phys - 61.0).abs() < 1.0,
            "一刻钟应回十来点生理: {}",
            m.phys
        );
    }

    #[test]
    fn rest_bonus_resets_after_interruption() {
        // 红利跟「本次休息」走：中途回来敲一分钟键盘，下次休息重新确认、
        // 红利重新计——不能把上一场没用完的红利接着花
        let mut m = EnergyModel::new(50.0, 50.0);
        for _ in 0..15 {
            m.step(&idle_minute());
        }
        let after_first_break = m.phys;
        m.step(&coding_minute());
        // 新一场休息：前 2 分钟确认期不回血
        m.step(&idle_minute());
        m.step(&idle_minute());
        let before_recovery = m.phys;
        m.step(&idle_minute()); // 第 3 分钟起算，且应是红利速率
        assert!(
            (m.phys - before_recovery - 1.0).abs() < 0.01,
            "新休息的第一个回血分钟应是红利速率 +1.0: {}",
            m.phys - before_recovery
        );
        assert!(m.phys < after_first_break + 2.0, "中断的代价要真实入账");
    }

    #[test]
    fn long_lounging_tapers() {
        // 边际递减：同样 20 分钟，休息的第一段比第二段回得多——
        // 躺一下午不该和四次短憩一个价
        let mut m = EnergyModel::new(20.0, 20.0);
        for _ in 0..20 {
            m.step(&idle_minute());
        }
        let first = m.phys - 20.0;
        let mid = m.phys;
        for _ in 0..20 {
            m.step(&idle_minute());
        }
        let second = m.phys - mid;
        assert!(
            first > second + 3.0,
            "前 20 分钟（含红利）应明显多于后 20 分钟: {first} vs {second}"
        );
    }

    #[test]
    fn meeting_blocks_recovery() {
        // 手不动但在开会：一分钟都不回血（活跃分钟只会掉）
        let mut m = EnergyModel::new(60.0, 60.0);
        let mut last = m.phys;
        for _ in 0..30 {
            m.step(&meeting_minute());
            assert!(m.phys <= last, "会议中生理只降不升");
            last = m.phys;
        }
    }

    #[test]
    fn energy_clamps_at_ceiling() {
        let mut m = EnergyModel::new(99.0, 99.0);
        for _ in 0..40 {
            m.step(&idle_minute());
        }
        assert_eq!(m.phys, 100.0);
        assert_eq!(m.mind, 100.0);
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

    // ---- v2：摄像头在位 + 活动类别 ----

    fn watching_video_minute() -> MinuteSample {
        MinuteSample {
            idle: true, // 手不动
            front_app: "Safari".into(),
            presence: Presence::Present, // 但人在屏幕前
            activity: Activity::Fun,
            ..Default::default()
        }
    }

    fn away_minute() -> MinuteSample {
        MinuteSample {
            idle: true,
            front_app: "Finder".into(),
            presence: Presence::Away,
            ..Default::default()
        }
    }

    #[test]
    fn watching_video_is_not_a_break() {
        // v0 会把「看视频手不动」误判成离开回血；v2 摄像头见人 → 被动在座：
        // 生理继续缓慢消耗，心理轻微回血（歇的是脑子不是身体）。
        let mut m = EnergyModel::new(50.0, 50.0);
        for _ in 0..30 {
            m.step(&watching_video_minute());
        }
        assert!(m.phys < 50.0, "看视频身体还坐着，不该回血: {}", m.phys);
        assert!(m.phys > 47.0, "被动在座只是缓慢消耗: {}", m.phys);
        assert!(m.mind > 50.0, "娱乐时脑子在歇，心理应轻微回血: {}", m.mind);
    }

    #[test]
    fn video_marathon_still_counts_as_sitting() {
        // 久坐看 seat_streak：刷 90 分钟视频和写 90 分钟代码一样提醒起身
        let mut m = EnergyModel::new(80.0, 80.0);
        let mut nudged = false;
        for _ in 0..95 {
            for o in m.step(&watching_video_minute()) {
                if matches!(o, Output::Nudge { kind: NudgeKind::LongSitting, .. }) {
                    nudged = true;
                }
            }
        }
        assert!(nudged, "摄像头在位下，纯看视频的久坐也应触发提醒");
    }

    #[test]
    fn camera_confirmed_leave_recovers_faster() {
        // 摄像头确认离开：第 2 分钟就起算回血（纯键鼠推断要等 3 分钟）
        let mut with_camera = EnergyModel::new(40.0, 40.0);
        let mut without = EnergyModel::new(40.0, 40.0);
        for _ in 0..3 {
            with_camera.step(&away_minute());
            without.step(&idle_minute());
        }
        assert!(
            with_camera.phys > without.phys,
            "3 分钟后摄像头档应已多回一分钟血: {} vs {}",
            with_camera.phys,
            without.phys
        );
    }

    #[test]
    fn wechat_chat_wears_mind_less_than_deep_work() {
        // 同样的输入量，微信聊天的心理磨损应小于写代码
        let chat = MinuteSample { activity: Activity::Comms, ..coding_minute() };
        let deep = MinuteSample { activity: Activity::Deep, ..coding_minute() };
        let mut chatting = EnergyModel::new(80.0, 80.0);
        let mut coding = EnergyModel::new(80.0, 80.0);
        for _ in 0..60 {
            chatting.step(&chat);
            coding.step(&deep);
        }
        assert!(
            chatting.mind > coding.mind,
            "一小时聊天 vs 一小时深度产出: {} vs {}",
            chatting.mind,
            coding.mind
        );
        assert!(
            (chatting.phys - coding.phys).abs() < 0.01,
            "生理损耗不看在干什么，只看强度: {} vs {}",
            chatting.phys,
            coding.phys
        );
    }

    #[test]
    fn activity_meeting_counts_as_meeting() {
        // OCR 语义认出会议界面（app 启发式没认出）也应走会议语义
        let m_min = MinuteSample {
            idle: true,
            front_app: "Arc".into(), // 浏览器里开会，app 名认不出
            activity: Activity::Meeting,
            ..Default::default()
        };
        let mut m = EnergyModel::new(80.0, 80.0);
        for _ in 0..30 {
            m.step(&m_min);
        }
        assert!(m.mind < 72.0, "浏览器里的半小时会议也应磨心理能量: {}", m.mind);
        m.step(&idle_minute());
        m.step(&idle_minute());
        assert!(
            has_post_meeting(&m.step(&idle_minute())),
            "OCR 认出的会议结束后同样提示补血"
        );
    }

    #[test]
    fn unknown_hints_degrade_to_v0() {
        // 没开摄像头、没有活动提示：行为必须和 v0 完全一致（老测试就是证明），
        // 这里只确认 Default 就是 Unknown。
        let s = MinuteSample::default();
        assert_eq!(s.presence, Presence::Unknown);
        assert_eq!(s.activity, Activity::Unknown);
    }
}
