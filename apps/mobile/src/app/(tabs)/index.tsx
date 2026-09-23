import { useClock } from "@/hooks/use-clock";
import { router } from "expo-router";
import { Pressable, View } from "react-native";
import * as Haptics from "expo-haptics";
import { Cat } from "@/components/cat";
import {
  Button,
  C,
  Card,
  Icon,
  Page,
  Row,
  SectionLabel,
  T,
} from "@/components/ui";
import { useStore } from "@/lib/app-store";
import { todayEvents, latestCheckin } from "@/lib/domain";
export default function Today() {
  const now = useClock();
  const { state, addEvent, update } = useStore();
  const daily = todayEvents(state.events, now);
  const water = daily.filter((e) => e.kind === "water");
  const checkin = latestCheckin(daily);
  const walked = daily.some((e) => e.kind === "walk");
  const hour = new Date(now).getHours();
  const greeting =
    hour < 6
      ? "夜深了，慢慢放下吧。"
      : hour < 11
        ? "早安，今天也慢慢来。"
        : hour < 14
          ? "午后，留一点时间给自己。"
          : hour < 18
            ? "下午好，歇一会儿吧。"
            : "晚上好，今天辛苦啦。";
  return (
    <Page
      title="今日"
      hideHeader
      subtitle={new Date(now).toLocaleDateString("zh-CN", {
        month: "long",
        day: "numeric",
        weekday: "long",
      })}
      right={
        <View style={{ flexDirection: "row", alignItems: "center", gap: 5 }}>
          <View
            style={{
              width: 5,
              height: 5,
              borderRadius: 3,
              backgroundColor: C.sage,
            }}
          />
          <T size={10} color={C.secondary}>
            只在此刻，陪着你
          </T>
        </View>
      }
    >
      <View
        style={{
          alignItems: "center",
          paddingTop: 16,
          paddingBottom: 4,
          gap: 13,
        }}
      >
        <Cat size={188} />
        <T size={25} style={{ textAlign: "center", letterSpacing: -0.6 }}>
          {greeting}
        </T>
        <T size={13} color={C.secondary} style={{ textAlign: "center" }}>
          不用每一分钟都很有用。{"\n"}来我这里，做一会儿无所事事的人。
        </T>
        <View style={{ flexDirection: "row", gap: 10, paddingTop: 9 }}>
          <Button onPress={() => router.push("/rest")} icon="pause">
            {state.rest ? "继续休息" : "休息一会儿"}
          </Button>
        </View>
      </View>
      {!state.onboarded && (
        <Card style={{ backgroundColor: "#F4F2EB", borderWidth: 0 }}>
          <T size={14}>一只只负责你的猫。</T>
          <T size={12} color={C.secondary}>
            我关心你的心情、休息和那些值得记住的小事。先在这里住下，不需要账号。
          </T>
          <Pressable
            accessibilityRole="button"
            onPress={() => update((s) => ({ ...s, onboarded: true }))}
            style={{ minHeight: 38, justifyContent: "center" }}
          >
            <T size={12} weight="600">
              好，我们慢慢熟悉 →
            </T>
          </Pressable>
        </Card>
      )}
      <View style={{ gap: 16 }}>
        <SectionLabel aside="你的感受，你说了算">今日能量</SectionLabel>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="记录今日心理和生理能量"
          onPress={() => router.push("/checkin")}
          style={{
            flexDirection: "row",
            paddingVertical: 18,
            borderTopWidth: 1,
            borderBottomWidth: 1,
            borderColor: C.line,
          }}
        >
          <Energy label="心理能量" value={checkin?.mind} color={C.blue} />
          <View
            style={{ width: 1, backgroundColor: C.line, marginHorizontal: 22 }}
          />
          <Energy label="生理能量" value={checkin?.body} color={C.coral} />
        </Pressable>
        <Pressable
          accessibilityRole="button"
          onPress={() => router.push("/checkin")}
          style={{
            flexDirection: "row",
            gap: 8,
            alignItems: "center",
            minHeight: 28,
          }}
        >
          <Icon name="edit" size={13} color={C.secondary} />
          <T size={11} color={C.secondary}>
            {checkin
              ? "来自今天的自我记录 · 点击更新"
              : "现在感觉怎么样？轻轻记一下"}
          </T>
        </Pressable>
      </View>
      <View style={{ gap: 10 }}>
        <SectionLabel aside="把自己照顾好一点点">今天的小事</SectionLabel>
        <Card style={{ paddingVertical: 6 }}>
          <Row
            icon="water"
            title={`喝一杯水`}
            subtitle={`${water.length} / ${state.settings.waterGoal} 杯 · 按你的身体需要来`}
            end={
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="记一杯水"
                disabled={water.length >= 30}
                onPress={() => {
                  addEvent("water");
                  void Haptics.selectionAsync().catch(() => {});
                }}
                style={{
                  minWidth: 44,
                  minHeight: 44,
                  alignItems: "center",
                  justifyContent: "center",
                  backgroundColor: C.bluePale,
                  borderRadius: 22,
                }}
              >
                <Icon name="plus" size={18} color={C.blue} />
              </Pressable>
            }
          />
          {water.length > 0 && (
            <Pressable
              accessibilityRole="button"
              onPress={() =>
                update((s) => ({
                  ...s,
                  events: s.events.filter((e) => e.id !== water.at(-1)?.id),
                }))
              }
              style={{ alignSelf: "flex-end", paddingBottom: 8, minHeight: 30 }}
            >
              <T size={11} color={C.secondary}>
                撤销上一杯
              </T>
            </Pressable>
          )}
          <View style={{ height: 1, backgroundColor: C.line }} />
          <Row
            icon="walk"
            title="出去走一小圈"
            subtitle={
              walked ? "今天已经出去透过气了" : "不用赶路，看看路边的树"
            }
            end={
              <Pressable
                accessibilityRole="button"
                accessibilityLabel={walked ? "撤销散步记录" : "记一次散步"}
                onPress={() =>
                  walked
                    ? update((s) => ({
                        ...s,
                        events: s.events.filter(
                          (e) =>
                            !(
                              e.kind === "walk" &&
                              daily.some((d) => d.id === e.id)
                            ),
                        ),
                      }))
                    : addEvent("walk")
                }
                style={{
                  minWidth: 44,
                  minHeight: 44,
                  alignItems: "center",
                  justifyContent: "center",
                  borderRadius: 22,
                  backgroundColor: walked ? C.coralPale : C.paper,
                }}
              >
                <Icon
                  name={walked ? "check" : "plus"}
                  color={walked ? C.coral : C.secondary}
                  size={18}
                />
              </Pressable>
            }
          />
          <View style={{ height: 1, backgroundColor: C.line }} />
          <Row
            icon="moon"
            title="给今天一个温柔的句号"
            subtitle="三件小事，然后好好睡觉"
            onPress={() => router.push("/sleep")}
          />
        </Card>
      </View>
      <Pressable
        accessibilityRole="button"
        onPress={() => router.push("/moment")}
        style={{
          padding: 20,
          backgroundColor: C.bluePale,
          borderRadius: 20,
          flexDirection: "row",
          alignItems: "center",
          gap: 15,
        }}
      >
        <Icon name="book" color={C.blue} />
        <View style={{ flex: 1 }}>
          <T size={14}>今天，有什么想留下的吗？</T>
          <T size={11} color={C.secondary}>
            很小的事，也值得被记得。
          </T>
        </View>
        <Icon name="arrow" size={16} color={C.blue} />
      </Pressable>
      <T
        size={10}
        color={C.muted}
        style={{ textAlign: "center", letterSpacing: 2 }}
      >
        工作交给别的 AI，我只负责你。
      </T>
    </Page>
  );
}
function Energy({
  label,
  value,
  color,
}: {
  label: string;
  value?: number;
  color: string;
}) {
  return (
    <View style={{ flex: 1, gap: 7 }}>
      <T size={11} color={C.secondary}>
        {label}
      </T>
      <View style={{ flexDirection: "row", alignItems: "baseline", gap: 5 }}>
        <T
          size={37}
          style={{ fontVariant: ["tabular-nums"], lineHeight: 46 }}
          weight="300"
        >
          {value ?? "—"}
        </T>
        <T size={11} color={C.muted}>
          / 100
        </T>
      </View>
      <View style={{ height: 4, backgroundColor: C.line, borderRadius: 2 }}>
        <View
          style={{
            width: `${value ?? 0}%`,
            height: 4,
            borderRadius: 2,
            backgroundColor: color,
          }}
        />
      </View>
    </View>
  );
}
