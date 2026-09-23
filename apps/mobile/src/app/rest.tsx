import { goBack } from "@/lib/navigation";
import { router } from "expo-router";
import { useEffect, useState } from "react";
import { AppState, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { Cat } from "@/components/cat";
import { Button, C, Chip, Page, SmallButton, T } from "@/components/ui";
import { uid, useStore } from "@/lib/app-store";
import { finishRest } from "@/lib/domain";
export default function Rest() {
  const { state, update } = useStore();
  const [minutes, setMinutes] = useState(5);
  const [now, setNow] = useState(Date.now());
  const [done, setDone] = useState(false);
  const insets = useSafeAreaInsets();
  const session = state.rest;
  const seconds = session
    ? Math.max(0, Math.ceil((session.endsAt - now) / 1000))
    : minutes * 60;
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 500);
    const listener = AppState.addEventListener("change", () =>
      setNow(Date.now()),
    );
    return () => {
      clearInterval(timer);
      listener.remove();
    };
  }, []);
  useEffect(() => {
    if (!session || now < session.endsAt) return;
    update((s) => finishRest(s, now));
    setDone(true);
  }, [session, now, update]);
  return (
    <View style={{ flex: 1, paddingTop: insets.top, backgroundColor: C.paper }}>
      <View style={{ alignItems: "flex-end", paddingHorizontal: 14 }}>
        <SmallButton
          icon="close"
          label="收起休息计时"
          onPress={() => goBack()}
        />
      </View>
      <Page title="休息时刻">
        <View style={{ alignItems: "center", paddingVertical: 30, gap: 24 }}>
          <T size={11} color={C.secondary} style={{ letterSpacing: 3 }}>
            给自己一点留白
          </T>
          <Cat asleep size={200} />
          <T size={28}>
            {done
              ? "这一小会儿，只属于你。"
              : session
                ? "眼睛离开屏幕一会儿吧。"
                : "我们一起，什么都不做。"}
          </T>
          <T size={13} color={C.secondary} style={{ textAlign: "center" }}>
            {done
              ? "休息已经记好了。慢慢回来，不着急。"
              : "松开肩膀，喝口水。\n不用盯着倒计时，我会记着。"}
          </T>
          {!done && (
            <T
              size={58}
              weight="200"
              style={{ fontVariant: ["tabular-nums"], letterSpacing: 2 }}
            >
              {String(Math.floor(seconds / 60)).padStart(2, "0")}:
              {String(seconds % 60).padStart(2, "0")}
            </T>
          )}
          {!session && !done && (
            <View style={{ flexDirection: "row", gap: 8 }}>
              {[1, 3, 5, 10].map((m) => (
                <Chip
                  key={m}
                  selected={minutes === m}
                  onPress={() => setMinutes(m)}
                >
                  {m} 分钟
                </Chip>
              ))}
            </View>
          )}
          <View style={{ alignSelf: "stretch", gap: 12 }}>
            {done ? (
              <Button onPress={() => goBack()}>慢慢回去</Button>
            ) : session ? (
              <>
                <Button onPress={() => goBack()} secondary>
                  收起，继续休息
                </Button>
                <Button
                  secondary
                  onPress={() => {
                    update((s) => ({ ...s, rest: null }));
                    setDone(false);
                  }}
                >
                  提前结束，不计入记录
                </Button>
              </>
            ) : (
              <Button
                onPress={() => {
                  const start = Date.now();
                  setNow(start);
                  update((s) => ({
                    ...s,
                    rest: {
                      id: uid(),
                      startedAt: start,
                      endsAt: start + minutes * 60000,
                      minutes,
                    },
                  }));
                }}
              >
                开始这段休息
              </Button>
            )}
          </View>
          <T size={10} color={C.muted} style={{ textAlign: "center" }}>
            锁屏后计时仍按实际时间计算；回到此页时确认完成。
          </T>
        </View>
      </Page>
    </View>
  );
}
