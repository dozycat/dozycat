import { router } from "expo-router";
import { useState } from "react";
import { Pressable, View } from "react-native";
import {
  C,
  Card,
  Chip,
  Empty,
  Field,
  Icon,
  Page,
  SmallButton,
  T,
} from "@/components/ui";
import { useStore } from "@/lib/app-store";
import { Category, categoryLabels, dayKey } from "@/lib/domain";
export default function Moments() {
  const { state } = useStore();
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<Category | null>(null);
  const visible = state.moments.filter(
    (m) =>
      (!filter || m.category === filter) &&
      m.text.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()),
  );
  return (
    <Page
      title="小传"
      subtitle={`${state.moments.length} 件小事，被好好记着`}
      right={
        <SmallButton
          icon="plus"
          label="写一条小传"
          onPress={() => router.push("/moment")}
        />
      }
    >
      <View style={{ gap: 10 }}>
        <T size={27}>日子很长，{"\n"}小事慢慢收藏。</T>
        <T size={12} color={C.secondary}>
          不是每一天都特别，但每一天都属于你。
        </T>
      </View>
      <View style={{ flexDirection: "row", alignItems: "center", gap: 10 }}>
        <Icon name="search" size={18} color={C.muted} />
        <Field
          accessibilityLabel="搜索小传"
          placeholder="找一件事、一个人、一种心情"
          value={query}
          onChangeText={setQuery}
          style={{ flex: 1 }}
        />
      </View>
      <View style={{ flexDirection: "row", gap: 7, flexWrap: "wrap" }}>
        <Chip selected={!filter} onPress={() => setFilter(null)}>
          全部
        </Chip>
        {(Object.keys(categoryLabels) as Category[]).map((c) => (
          <Chip key={c} selected={filter === c} onPress={() => setFilter(c)}>
            {categoryLabels[c]}
          </Chip>
        ))}
      </View>
      {!visible.length ? (
        <Empty
          title={query || filter ? "还没找到这件小事" : "故事，从一件小事开始"}
          description={
            query || filter
              ? "换个词，或者看看其他分类。"
              : "一次见面、一顿好吃的饭，或者终于松一口气的瞬间。"
          }
        >
          <Pressable
            accessibilityRole="button"
            onPress={() => router.push("/moment")}
            style={{ padding: 12 }}
          >
            <T size={13} color={C.blue}>
              写下第一条小传 →
            </T>
          </Pressable>
        </Empty>
      ) : (
        visible.map((m) => (
          <Pressable
            key={m.id}
            accessibilityRole="button"
            accessibilityLabel={`编辑小传：${m.text.slice(0, 25)}`}
            onPress={() =>
              router.push({ pathname: "/moment", params: { id: m.id } })
            }
          >
            <Card>
              <View
                style={{
                  flexDirection: "row",
                  justifyContent: "space-between",
                }}
              >
                <T size={11} color={C.muted}>
                  {dayKey(m.at) === dayKey()
                    ? "今天"
                    : new Date(m.at).toLocaleDateString("zh-CN", {
                        year: "numeric",
                        month: "long",
                        day: "numeric",
                      })}
                </T>
                <View
                  style={{ flexDirection: "row", gap: 5, alignItems: "center" }}
                >
                  <View
                    style={{
                      width: 5,
                      height: 5,
                      borderRadius: 3,
                      backgroundColor: m.category === "body" ? C.coral : C.blue,
                    }}
                  />
                  <T size={11} color={C.secondary}>
                    {categoryLabels[m.category]}
                  </T>
                </View>
              </View>
              <T size={16} style={{ lineHeight: 28 }}>
                {m.text}
              </T>
            </Card>
          </Pressable>
        ))
      )}
      <T size={10} color={C.muted} style={{ textAlign: "center" }}>
        小传保存在这台设备上。
      </T>
    </Page>
  );
}
