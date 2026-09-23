import { goBack } from "@/lib/navigation";
import { router, useLocalSearchParams } from "expo-router";
import { useState } from "react";
import { View } from "react-native";
import { Button, C, Card, Chip, Field, Page, T } from "@/components/ui";
import { useStore } from "@/lib/app-store";
import { Category, categoryLabels } from "@/lib/domain";
export default function MomentEditor() {
  const params = useLocalSearchParams<{ id?: string; text?: string }>();
  const { state, saveMoment, update } = useStore();
  const old = state.moments.find((m) => m.id === params.id);
  const [text, setText] = useState(old?.text ?? params.text ?? "");
  const [category, setCategory] = useState<Category>(
    old?.category ?? "everyday",
  );
  const [deleting, setDeleting] = useState(false);
  const full = !old && state.moments.length >= 5000;
  return (
    <Page title={old ? "这件小事" : "留住一件小事"}>
      <T size={24}>不必写得很好，{"\n"}写你想记得的就好。</T>
      <Field
        accessibilityLabel="小传内容"
        autoFocus
        multiline
        maxLength={4000}
        placeholder="今天，有什么让你停留了一下？"
        value={text}
        onChangeText={setText}
        style={{
          minHeight: 230,
          textAlignVertical: "top",
          backgroundColor: C.card,
          lineHeight: 28,
          fontSize: 17,
        }}
      />
      <T size={11} color={C.muted} style={{ textAlign: "right" }}>
        {text.length} / 4000
      </T>
      <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 8 }}>
        {(Object.keys(categoryLabels) as Category[]).map((c) => (
          <Chip
            key={c}
            selected={category === c}
            onPress={() => setCategory(c)}
          >
            {categoryLabels[c]}
          </Chip>
        ))}
      </View>
      {full && <T color="#AB534C">小传已达 5000 条，请先整理或导出。</T>}
      <Button
        disabled={!text.trim() || full}
        onPress={() => {
          saveMoment(text, category, old?.id);
          goBack();
        }}
      >
        {old ? "保存修改" : "收进小传"}
      </Button>
      {old &&
        (deleting ? (
          <Card style={{ backgroundColor: C.coralPale }}>
            <T size={14}>确定删除这条小传？删除后无法在这里撤销。</T>
            <Button
              danger
              onPress={() => {
                update((s) => ({
                  ...s,
                  moments: s.moments.filter((m) => m.id !== old.id),
                }));
                goBack();
              }}
            >
              确认删除
            </Button>
            <Button secondary onPress={() => setDeleting(false)}>
              再留着吧
            </Button>
          </Card>
        ) : (
          <Button secondary onPress={() => setDeleting(true)}>
            删除这条小传
          </Button>
        ))}
    </Page>
  );
}
