import { router } from "expo-router";
import { useState } from "react";
import { Switch, View } from "react-native";
import {
  Button,
  C,
  Card,
  Chip,
  Page,
  Row,
  SectionLabel,
  T,
} from "@/components/ui";
import { Cat } from "@/components/cat";
import { useStore } from "@/lib/app-store";
import { bedtimeReminder } from "@/lib/reminders";
export default function SettingsPage() {
  const { state, settings } = useStore();
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);
  async function reminder(
    enabled: boolean,
    hour = state.settings.reminderHour,
  ) {
    setBusy(true);
    setNotice("");
    try {
      await bedtimeReminder(enabled, hour);
      settings({ reminderEnabled: enabled, reminderHour: hour });
    } catch (e) {
      setNotice(e instanceof Error ? e.message : "暂时无法设置提醒。");
    } finally {
      setBusy(false);
    }
  }
  return (
    <Page title="设置">
      <View style={{ flexDirection: "row", gap: 15, alignItems: "center" }}>
        <Cat size={65} />
        <View>
          <T size={22}>让这里，更像你的家。</T>
          <T size={11} color={C.secondary}>
            不需要账号，从这台设备开始。
          </T>
        </View>
      </View>
      <View style={{ gap: 12 }}>
        <SectionLabel>设备连接</SectionLabel>
        <Card style={{ paddingVertical: 8 }}>
          <Row
            icon="phone"
            title="我的设备"
            subtitle="与电脑上的懒猫相认"
            onPress={() => router.push("/devices")}
          />
        </Card>
      </View>
      <View style={{ gap: 12 }}>
        <SectionLabel>一些小习惯</SectionLabel>
        <Card>
          <T size={14}>每日喝水记录目标</T>
          <View
            style={{
              flexDirection: "row",
              alignItems: "center",
              justifyContent: "space-between",
            }}
          >
            <Button
              secondary
              disabled={state.settings.waterGoal <= 1}
              onPress={() =>
                settings({ waterGoal: state.settings.waterGoal - 1 })
              }
            >
              −
            </Button>
            <T size={24}>
              {state.settings.waterGoal}{" "}
              <T size={12} color={C.secondary}>
                杯
              </T>
            </T>
            <Button
              secondary
              disabled={state.settings.waterGoal >= 20}
              onPress={() =>
                settings({ waterGoal: state.settings.waterGoal + 1 })
              }
            >
              ＋
            </Button>
          </View>
          <T size={10} color={C.secondary}>
            只是记录习惯；按你的身体需要调整，不是饮水建议。
          </T>
        </Card>
        <Card>
          <Row
            icon="moon"
            title="睡前轻声提醒"
            subtitle="只用本机通知，不发送到服务器"
            end={
              <Switch
                accessibilityLabel="睡前提醒"
                disabled={busy}
                value={state.settings.reminderEnabled}
                onValueChange={(v) => void reminder(v)}
                trackColor={{ true: C.blue }}
              />
            }
          />
          <View style={{ flexDirection: "row", gap: 8 }}>
            {[21, 22, 23].map((h) => (
              <Chip
                key={h}
                selected={h === state.settings.reminderHour}
                onPress={() => {
                  if (!busy)
                    state.settings.reminderEnabled
                      ? void reminder(true, h)
                      : settings({ reminderHour: h });
                }}
              >
                {h}:00
              </Chip>
            ))}
          </View>
        </Card>
      </View>
      {Boolean(notice) && (
        <T size={12} color={C.secondary}>
          {notice}
        </T>
      )}
      <Card style={{ paddingVertical: 8 }}>
        <Row
          icon="shield"
          title="我的数据"
          subtitle="导出、导入与本机数据管理"
          onPress={() => router.push("/data")}
        />
      </Card>
      <View style={{ alignItems: "center", gap: 5 }}>
        <T size={18} style={{ letterSpacing: -0.8 }}>
          dozycat
        </T>
        <T size={10} color={C.muted}>
          一个不帮你干活的 AI · v0.1.0
        </T>
      </View>
    </Page>
  );
}
