export type PairInvite = {
  version: 1;
  room_id: string;
  desktop_public_key: string;
  psk: string;
  expires_at: number;
};
// Parsing is not authentication. Invites are kept only in memory until a native
// Noise implementation and desktop responder are available.
export function parseInvite(input: string, now = Date.now()): PairInvite {
  if (input.length > 2048 || !input.startsWith("dozycat://pair?"))
    throw new Error("这不是懒猫的设备连接码。请在电脑端打开“添加手机”。");
  let data: unknown;
  try {
    const url = new URL(input);
    if (
      url.hostname !== "pair" ||
      url.pathname ||
      url.searchParams.size !== 1 ||
      !url.searchParams.has("data") ||
      url.hash
    )
      throw new Error();
    data = JSON.parse(url.searchParams.get("data")!);
  } catch {
    throw new Error("连接码格式不完整，请重新生成。");
  }
  const v = data as Partial<PairInvite> | null;
  if (
    !v ||
    typeof v !== "object" ||
    v.version !== 1 ||
    typeof v.room_id !== "string" ||
    !/^[A-Za-z0-9_-]{22}$/.test(v.room_id) ||
    typeof v.desktop_public_key !== "string" ||
    !/^[A-Za-z0-9_-]{43}$/.test(v.desktop_public_key) ||
    typeof v.psk !== "string" ||
    !/^[A-Za-z0-9_-]{43}$/.test(v.psk) ||
    typeof v.expires_at !== "number" ||
    !Number.isSafeInteger(v.expires_at)
  )
    throw new Error("连接码版本或内容不匹配，请更新电脑端后重试。");
  if (v.expires_at <= now || v.expires_at > now + 120000)
    throw new Error(
      "连接码已过期，或两台设备的时间不一致。请在电脑上重新生成。",
    );
  return {
    version: 1,
    room_id: v.room_id,
    desktop_public_key: v.desktop_public_key,
    psk: v.psk,
    expires_at: v.expires_at,
  };
}
