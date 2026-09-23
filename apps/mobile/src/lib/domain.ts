export type Category = "happy" | "body" | "people" | "everyday";
export type Moment = {
  id: string;
  at: number;
  text: string;
  category: Category;
};
export type Message = {
  id: string;
  at: number;
  role: "user" | "assistant";
  text: string;
  source?: "local" | "model";
};
export type Event = {
  id: string;
  at: number;
  kind: "water" | "walk" | "rest" | "sleep" | "checkin";
  mind?: number;
  body?: number;
  minutes?: number;
};
export type Settings = {
  nickname: string;
  waterGoal: number;
  provider: "local" | "deepseek" | "openai" | "custom";
  baseUrl: string;
  model: string;
  includeMemories: boolean;
  reminderHour: number;
  reminderEnabled: boolean;
};
export type RestSession = {
  id: string;
  startedAt: number;
  endsAt: number;
  minutes: number;
};
export type AppState = {
  version: 1;
  moments: Moment[];
  messages: Message[];
  events: Event[];
  settings: Settings;
  rest: RestSession | null;
  onboarded: boolean;
};

export const categoryLabels: Record<Category, string> = {
  happy: "开心的",
  body: "身体",
  people: "人",
  everyday: "日常",
};
export const defaults: Settings = {
  nickname: "",
  waterGoal: 8,
  provider: "local",
  baseUrl: "https://api.deepseek.com",
  model: "deepseek-chat",
  includeMemories: false,
  reminderHour: 22,
  reminderEnabled: false,
};
export const emptyState = (): AppState => ({
  version: 1,
  moments: [],
  messages: [],
  events: [],
  settings: { ...defaults },
  rest: null,
  onboarded: false,
});
export function dayKey(at = Date.now()) {
  const d = new Date(at);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
export function todayEvents(events: Event[], at = Date.now()) {
  return events.filter((e) => dayKey(e.at) === dayKey(at));
}
export function latestCheckin(events: Event[]) {
  return [...events].reverse().find((e) => e.kind === "checkin");
}
export function weekData(events: Event[], now = Date.now()) {
  return Array.from({ length: 7 }, (_, i) => {
    const date = new Date(now);
    date.setDate(date.getDate() - 6 + i);
    const daily = todayEvents(events, +date);
    return {
      date: +date,
      key: dayKey(+date),
      checkin: latestCheckin(daily),
      water: daily.filter((e) => e.kind === "water").length,
      rests: daily.filter((e) => e.kind === "rest").length,
    };
  });
}
export function mergeMoments(existing: Moment[], incoming: Moment[]) {
  const byId = new Map(existing.map((m) => [m.id, m]));
  for (const m of incoming) {
    if (!byId.has(m.id)) byId.set(m.id, m);
  }
  return [...byId.values()].sort((a, b) => b.at - a.at);
}
export function finishRest(state: AppState, now = Date.now()): AppState {
  const session = state.rest;
  if (!session || now < session.endsAt) return state;
  return {
    ...state,
    rest: null,
    events: state.events.some((e) => e.id === session.id)
      ? state.events
      : [
          ...state.events,
          {
            id: session.id,
            at: session.endsAt,
            kind: "rest",
            minutes: session.minutes,
          },
        ],
  };
}
export function appendReply(
  state: AppState,
  message: Message,
  replyTo: string,
): AppState {
  // A response arriving after the user cleared the conversation must not
  // resurrect that conversation.
  if (!state.messages.some((m) => m.id === replyTo)) return state;
  return { ...state, messages: [...state.messages, message].slice(-300) };
}
const isObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const text = (v: unknown, max: number): v is string =>
  typeof v === "string" && v.length <= max;
const timestamp = (v: unknown): v is number =>
  typeof v === "number" && Number.isFinite(v) && v > 0 && v < 8640000000000000;
const validId = (v: unknown): v is string => text(v, 128) && v.length > 0;
const validMoment = (v: unknown): v is Moment =>
  isObject(v) &&
  validId(v.id) &&
  timestamp(v.at) &&
  text(v.text, 4000) &&
  !!v.text.trim() &&
  ["happy", "body", "people", "everyday"].includes(v.category as string);
const unique = (items: { id: string }[]) =>
  new Set(items.map((i) => i.id)).size === items.length;

export function parseMomentBackup(raw: string): Moment[] {
  if (raw.length > 64_000_000)
    throw new Error("文件太大了，请使用 64 MB 以内的小传备份。");
  let data: unknown;
  try {
    data = JSON.parse(raw);
  } catch {
    throw new Error("这不是有效的 JSON 备份。");
  }
  if (
    !isObject(data) ||
    data.format !== "dozycat-moments" ||
    data.version !== 1 ||
    !Array.isArray(data.moments) ||
    data.moments.length > 5000 ||
    !data.moments.every(validMoment) ||
    !unique(data.moments)
  )
    throw new Error("备份格式不匹配，原有小传没有改动。");
  return data.moments.map((m) => ({
    id: m.id,
    at: m.at,
    text: m.text,
    category: m.category,
  }));
}
export function serializeMoments(moments: Moment[]) {
  return JSON.stringify(
    { format: "dozycat-moments", version: 1, moments },
    null,
    2,
  );
}
export function parseState(raw: string): AppState {
  const s: unknown = JSON.parse(raw);
  if (
    !isObject(s) ||
    s.version !== 1 ||
    !Array.isArray(s.moments) ||
    s.moments.length > 5000 ||
    !s.moments.every(validMoment) ||
    !unique(s.moments) ||
    !Array.isArray(s.messages) ||
    !s.messages.every(
      (m) =>
        isObject(m) &&
        validId(m.id) &&
        timestamp(m.at) &&
        ["user", "assistant"].includes(m.role as string) &&
        text(m.text, 16000) &&
        (m.source === undefined ||
          ["local", "model"].includes(m.source as string)),
    ) ||
    !Array.isArray(s.events) ||
    !s.events.every(
      (e) =>
        isObject(e) &&
        validId(e.id) &&
        timestamp(e.at) &&
        ["water", "walk", "rest", "sleep", "checkin"].includes(
          e.kind as string,
        ) &&
        (e.kind !== "checkin" ||
          [e.mind, e.body].every(
            (n) => typeof n === "number" && n >= 0 && n <= 100,
          )) &&
        (e.minutes === undefined ||
          (typeof e.minutes === "number" &&
            Number.isFinite(e.minutes) &&
            e.minutes >= 0)),
    )
  )
    throw new Error(
      "本地记录无法读取，已保留原文件。请先导出原始数据，再尝试恢复。",
    );
  const cfg = s.settings;
  if (
    !isObject(cfg) ||
    !text(cfg.nickname, 40) ||
    !Number.isInteger(cfg.waterGoal) ||
    (cfg.waterGoal as number) < 1 ||
    (cfg.waterGoal as number) > 20 ||
    !["local", "openai", "deepseek", "custom"].includes(
      cfg.provider as string,
    ) ||
    !text(cfg.baseUrl, 2048) ||
    !text(cfg.model, 200) ||
    typeof cfg.includeMemories !== "boolean" ||
    !Number.isInteger(cfg.reminderHour) ||
    (cfg.reminderHour as number) < 0 ||
    (cfg.reminderHour as number) > 23 ||
    typeof cfg.reminderEnabled !== "boolean" ||
    typeof s.onboarded !== "boolean"
  )
    throw new Error("本地设置格式不完整，已保留原文件。");
  if (
    s.rest !== null &&
    (!isObject(s.rest) ||
      !validId(s.rest.id) ||
      !timestamp(s.rest.startedAt) ||
      !timestamp(s.rest.endsAt) ||
      typeof s.rest.minutes !== "number" ||
      ![1, 3, 5, 10].includes(s.rest.minutes) ||
      s.rest.endsAt !== s.rest.startedAt + s.rest.minutes * 60000)
  )
    throw new Error("休息记录无法读取，已保留原文件。");
  return s as AppState;
}
export function modelEndpoint(base: string) {
  let url: URL;
  try {
    url = new URL(base.trim());
  } catch {
    throw new Error("请输入完整的 HTTPS 服务地址。");
  }
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    url.search ||
    url.hash
  )
    throw new Error("模型服务需要 HTTPS 地址，不能包含密码、查询参数或片段。");
  url.pathname = `${url.pathname.replace(/\/+$/, "")}/chat/completions`;
  return url.toString();
}
export function localReply(input: string) {
  if (/累|疲惫|困|撑不住/.test(input))
    return "先把肩膀放下来一点吧。要不要陪我休息几分钟，别的事待会儿再想。";
  if (/开心|高兴|太好了|喜欢/.test(input))
    return "听起来是值得藏进口袋的一件小事。想留住它的话，可以把这句话收进小传。";
  if (/难过|伤心|孤独|空落/.test(input))
    return "我在这里陪着你。现在不用急着变好，想说什么就慢慢说。";
  return "嗯，我听着呢。你可以把心里的话放在这里，不用整理得很漂亮。";
}
