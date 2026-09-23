import { goBack } from "@/lib/navigation";
import { router } from "expo-router";
import { useState } from "react";
import { View } from "react-native";
import { Button, C, Card, Chip, Page, T } from "@/components/ui";
import { useStore } from "@/lib/app-store";
import { latestCheckin, todayEvents } from "@/lib/domain";
const levels = [
  { label: "有点低", value: 20 },
  { label: "偏低", value: 40 },
  { label: "还好", value: 60 },
  { label: "不错", value: 80 },
  { label: "充足", value: 95 },
];
export default function Checkin() {
  const { state, addEvent } = useStore();
  const previous = latestCheckin(todayEvents(state.events));
  const [mind, setMind] = useState<number | undefined>(previous?.mind);
  const [body, setBody] = useState<number | undefined>(previous?.body);
  return (
    <Page title="此刻的你">
      <View style={{ gap: 10, paddingVertical: 12 }}>
        <T size={26}>先问问自己，{"\n"}今天感觉怎么样？</T>
        <T size={13} color={C.secondary}>
          没有标准答案，也不用为了谁打起精神。
        </T>
      </View>
      {[
        {
          label: "心里的电量",
          subtitle: "心情、专注、与人相处的余力",
          value: mind,
          set: setMind,
          color: C.blue,
        },
        {
          label: "身体的电量",
          subtitle: "睡意、疲惫、身体的轻松程度",
          value: body,
          set: setBody,
          color: C.coral,
        },
      ].map((item) => (
        <Card key={item.label}>
          <T size={17}>{item.label}</T>
          <T size={12} color={C.secondary}>
            {item.subtitle}
          </T>
          <View
            style={{
              flexDirection: "row",
              gap: 8,
              flexWrap: "wrap",
              paddingVertical: 10,
            }}
          >
            {levels.map((l) => (
              <Chip
                key={l.value}
                selected={item.value === l.value}
                onPress={() => item.set(l.value)}
              >
                {l.label}
              </Chip>
            ))}
          </View>
          <T size={30} color={item.color}>
            {item.value ?? "—"}{" "}
            <T size={12} color={C.muted}>
              / 100
            </T>
          </T>
        </Card>
      ))}
      <Button
        disabled={mind === undefined || body === undefined}
        onPress={() => {
          addEvent("checkin", { mind, body });
          goBack();
        }}
      >
        记下现在的自己
      </Button>
      <T size={11} color={C.muted}>
        这是你自己的感受记录，不是健康测量或诊断。
      </T>
    </Page>
  );
}
