import * as Notifications from "expo-notifications";
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldPlaySound: false,
    shouldSetBadge: false,
    shouldShowBanner: true,
    shouldShowList: true,
  }),
});
const TAG = "dozycat-bedtime";
export async function bedtimeReminder(enabled: boolean, hour: number) {
  if (enabled) {
    await Notifications.setNotificationChannelAsync("gentle", {
      name: "懒猫的轻声提醒",
      importance: Notifications.AndroidImportance.DEFAULT,
      sound: null,
    });
    const permission = await Notifications.requestPermissionsAsync();
    if (
      !permission.granted &&
      permission.ios?.status !==
        Notifications.IosAuthorizationStatus.PROVISIONAL
    )
      throw new Error("通知权限没有开启。你可以在系统设置中允许懒猫提醒。");
  }
  const existing = await Notifications.getAllScheduledNotificationsAsync();
  const matches = existing.filter((n) => n.content.data?.tag === TAG);
  // Schedule before removing the previous reminder so a failure preserves it.
  if (enabled)
    await Notifications.scheduleNotificationAsync({
      content: {
        title: "懒猫",
        body: "今天已经很努力了。要不要慢慢准备睡觉？",
        data: { tag: TAG },
        sound: false,
      },
      trigger: {
        type: Notifications.SchedulableTriggerInputTypes.DAILY,
        hour,
        minute: 0,
        channelId: "gentle",
      },
    });
  await Promise.all(
    matches.map((n) =>
      Notifications.cancelScheduledNotificationAsync(n.identifier),
    ),
  );
}
