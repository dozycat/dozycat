import { useState } from "react";
import { View } from "react-native";
import { Button, C, Card, Page, T } from "@/components/ui";
import { useStore } from "@/lib/app-store";
import {
  Moment,
  dayKey,
  parseMomentBackup,
  serializeMoments,
} from "@/lib/domain";
import { exportFile, pickBackup } from "@/lib/backup";
export default function DataPage() {
  const { state, importMoments } = useStore();
  const [status, setStatus] = useState("");
  const [busy, setBusy] = useState(false);
  const [pending, setPending] = useState<Moment[] | null>(null);
  const [exporting, setExporting] = useState(false);
  async function run(task: () => Promise<void>) {
    setBusy(true);
    setStatus("");
    try {
      await task();
    } catch (e) {
      setStatus(
        e instanceof Error ? e.message : "操作没有完成，原有数据仍在。",
      );
    } finally {
      setBusy(false);
    }
  }
  return (
    <Page title="我的数据">
      <T size={26}>你的故事，{"\n"}由你保管。</T>
      <Card>
        <T size={14}>这台设备里有</T>
        <View style={{ flexDirection: "row", gap: 24 }}>
          <T size={22}>
            {state.moments.length}
            <T size={11} color={C.secondary}>
              {" "}
              条小传
            </T>
          </T>
        </View>
        <T size={12} color={C.secondary}>
          目前没有云端副本。手机记录保存在本地
          SQLite；浏览器预览保存在当前浏览器。卸载或清除浏览器数据可能丢失记录。
        </T>
      </Card>
      <Card>
        <T size={16}>带走你的小传</T>
        <T size={12} color={C.secondary}>
          导出可阅读的 JSON 文件。只包含小传。这不是加密备份，请选择你信任的保存位置。
        </T>
        {exporting ? (
          <>
            <Button
              disabled={busy}
              onPress={() =>
                void run(async () => {
                  await exportFile(
                    serializeMoments(state.moments),
                    `dozycat-moments-${dayKey()}.json`,
                  );
                  setExporting(false);
                  setStatus("已交给系统保存或分享，请确认文件已保存。");
                })
              }
            >
              导出明文小传
            </Button>
            <Button secondary onPress={() => setExporting(false)}>
              取消
            </Button>
          </>
        ) : (
          <Button secondary icon="download" onPress={() => setExporting(true)}>
            导出小传
          </Button>
        )}
      </Card>
      <Card>
        <T size={16}>把小传带回来</T>
        <T size={12} color={C.secondary}>
          读取 dozycat JSON 备份，检查后再合并。同 ID
          的现有小传优先保留，不会覆盖你现在的修改。
        </T>
        <Button
          secondary
          icon="upload"
          disabled={busy}
          onPress={() =>
            void run(async () => {
              const raw = await pickBackup();
              if (raw !== null) setPending(parseMomentBackup(raw));
            })
          }
        >
          选择备份文件
        </Button>
        {pending && (
          <>
            <T size={13}>
              读到 {pending.length} 条小传，其中{" "}
              {
                pending.filter(
                  (m) => !state.moments.some((old) => old.id === m.id),
                ).length
              }{" "}
              条为新内容。
            </T>
            <Button
              onPress={() => {
                try {
                  importMoments(pending);
                  setPending(null);
                  setStatus("小传已合并。");
                } catch (e) {
                  setStatus(e instanceof Error ? e.message : "合并失败。");
                }
              }}
            >
              确认合并
            </Button>
            <Button secondary onPress={() => setPending(null)}>
              取消导入
            </Button>
          </>
        )}
      </Card>
      {Boolean(status) && (
        <T size={13} color={C.secondary}>
          {status}
        </T>
      )}
    </Page>
  );
}
