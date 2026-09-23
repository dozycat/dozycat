export async function bedtimeReminder(enabled: boolean, _hour: number) {
  if (enabled)
    throw new Error("浏览器预览不支持本地定时提醒，请在手机 Expo Go 中开启。");
}
