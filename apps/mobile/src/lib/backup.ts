import * as DocumentPicker from "expo-document-picker";
import * as Sharing from "expo-sharing";
import { File, Paths } from "expo-file-system";
export async function exportFile(content: string, filename: string) {
  if (!(await Sharing.isAvailableAsync()))
    throw new Error("这台设备暂时不能打开分享菜单。");
  const file = new File(Paths.cache, filename);
  file.create({ overwrite: true });
  try {
    file.write(content);
    await Sharing.shareAsync(file.uri, {
      mimeType: "application/json",
      UTI: "public.json",
      dialogTitle: "保存你的小传",
    });
  } finally {
    if (file.exists) file.delete();
  }
}
export async function pickBackup() {
  const result = await DocumentPicker.getDocumentAsync({
    type: ["application/json", "text/plain"],
    copyToCacheDirectory: true,
  });
  if (result.canceled) return null;
  const asset = result.assets[0];
  const file = new File(asset.uri);
  try {
    if ((asset.size ?? file.size) > 64_000_000)
      throw new Error("请选择 64 MB 以内的小传备份。");
    return await file.text();
  } finally {
    if (file.uri.startsWith(Paths.cache.uri) && file.exists) file.delete();
  }
}
