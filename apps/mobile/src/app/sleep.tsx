import { goBack } from "@/lib/navigation";
import { router } from "expo-router";
import { useState } from "react";
import { Pressable, ScrollView, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { Cat } from "@/components/cat";
import { Button, C, Field, Icon, T } from "@/components/ui";
import { useStore } from "@/lib/app-store";
import { todayEvents } from "@/lib/domain";
export default function Sleep() {
  const { state, addEvent, saveMoment } = useStore();
  const [text, setText] = useState("");
  const [saved, setSaved] = useState(false);
  const [checked, setChecked] = useState<number[]>([]);
  const slept = todayEvents(state.events).some((e) => e.kind === "sleep");
  const insets = useSafeAreaInsets();
  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      keyboardShouldPersistTaps="handled"
      style={{ flex: 1, backgroundColor: C.night }}
      contentContainerStyle={{
        paddingHorizontal: 28,
        paddingTop: insets.top + 18,
        paddingBottom: insets.bottom + 30,
        gap: 27,
      }}
    >
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="离开睡前模式"
        onPress={() => goBack()}
        style={{
          alignSelf: "flex-end",
          minHeight: 44,
          minWidth: 44,
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <Icon name="close" color="#CCCAC4" />
      </Pressable>
      <View style={{ alignItems: "center", gap: 18 }}>
        <T size={10} color="#ADAFB7" style={{ letterSpacing: 4 }}>
          晚 安 时 间
        </T>
        <Cat asleep size={155} />
        <T color="#F0EFEA" size={28}>
          今天，就到这里吧。
        </T>
        <T size={13} color="#B9BAC0" style={{ textAlign: "center" }}>
          没有做完的事，留给明天。{"\n"}现在的你，只需要好好休息。
        </T>
      </View>
      <View style={{ gap: 5 }}>
        {["把灯调暗一点", "把手机放远一点", "给自己一个深呼吸"].map((t, i) => (
          <Pressable
            key={t}
            accessibilityRole="checkbox"
            accessibilityState={{ checked: checked.includes(i) }}
            onPress={() =>
              setChecked((c) =>
                c.includes(i) ? c.filter((n) => n !== i) : [...c, i],
              )
            }
            style={{
              minHeight: 56,
              borderBottomWidth: 1,
              borderBottomColor: "#404249",
              flexDirection: "row",
              alignItems: "center",
              gap: 13,
            }}
          >
            <View
              style={{
                width: 23,
                height: 23,
                borderRadius: 12,
                borderColor: "#666976",
                borderWidth: 1,
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              {checked.includes(i) && (
                <Icon name="check" size={14} color="#DCC7B0" />
              )}
            </View>
            <T color="#DBDAD7" size={14}>
              {t}
            </T>
          </Pressable>
        ))}
      </View>
      <View style={{ gap: 12 }}>
        <T size={12} color="#B9BAC0">
          今天有一件值得感谢的小事吗？
        </T>
        <Field
          accessibilityLabel="睡前小事"
          multiline
          maxLength={4000}
          value={text}
          onChangeText={(t) => {
            setText(t);
            setSaved(false);
          }}
          placeholder="很小很小也可以…"
          placeholderTextColor="#92949E"
          style={{
            minHeight: 100,
            backgroundColor: "#35383F",
            borderColor: "#454850",
            color: "#F0EFEA",
            textAlignVertical: "top",
          }}
        />
        <Button
          secondary
          disabled={!text.trim() || saved || state.moments.length >= 5000}
          onPress={() => {
            saveMoment(text, "happy");
            setSaved(true);
          }}
        >
          {saved ? "已收进小传" : "留住这件小事"}
        </Button>
      </View>
      <Button
        secondary
        onPress={() => {
          if (!slept) addEvent("sleep");
          goBack();
        }}
      >
        {slept ? "晚安，再见" : "晚安，懒猫"}
      </Button>
      <T size={10} color="#92949E" style={{ textAlign: "center" }}>
        只记下你说晚安的时刻，不推测睡眠时长。
      </T>
    </ScrollView>
  );
}
