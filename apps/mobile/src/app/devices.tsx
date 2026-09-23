import { useEffect, useRef, useState } from "react";
import { CameraView, useCameraPermissions } from "expo-camera";
import { Platform, View } from "react-native";
import { Button, C, Card, Icon, Page, T } from "@/components/ui";
import { parseInvite } from "@/lib/pairing";
import link, { LinkStatus } from "../../modules/dozycat-link";

const initial: LinkStatus = { phase: "idle", fingerprint: "", message: "", paired: false, approved: false };
export default function Devices() {
  const [permission, requestPermission] = useCameraPermissions();
  const [scanning, setScanning] = useState(false);
  const [status, setStatus] = useState<LinkStatus>(initial);
  const latest = useRef(status);
  const scanLock = useRef(false);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [removing, setRemoving] = useState(false);
  const [ready, setReady] = useState(!link);
  useEffect(() => {
    if (!link) return;
    let mounted = true;
    let eventReceived = false;
    const subscription = link.addListener("onStatus", (state) => {
      eventReceived = true;
      latest.current = state;
      if (mounted) setStatus(state);
    });
    void link.status().then((state) => {
      if (!mounted || eventReceived) return;
      latest.current = state; setStatus(state);
    }).catch(() => {
      if (mounted) setMessage("暂时无法读取设备授权，请解锁手机后重试。");
    }).finally(() => { if (mounted) setReady(true); });
    return () => {
      mounted = false; subscription.remove();
      if (latest.current.phase !== "connected") void link!.cancel().catch(() => {});
    };
  }, []);
  async function action(task: () => Promise<void>) {
    setBusy(true); setMessage("");
    try { await task(); }
    catch { setMessage("操作没有完成。请确认局域网权限、两端状态后重试。"); }
    finally { setBusy(false); }
  }
  async function scan() {
    await action(async () => {
      const result = permission?.granted ? permission : await requestPermission();
      if (!result.granted) { setMessage("请在系统设置中允许懒猫使用相机。"); return; }
      scanLock.current = false;
      setScanning(true);
    });
  }
  const connecting = ["starting", "discovering", "connecting", "handshaking", "waiting"].includes(status.phase);
  return (
    <Page title="我的设备">
      <View style={{ flexDirection: "row", gap: 13, alignItems: "center" }}>
        <Icon name="shield" size={28} color={C.blue} />
        <View style={{ flex: 1 }}>
          <T size={20}>同一只猫，两处陪伴。</T>
          <T size={12} color={C.secondary}>用扫码相认，不需要账号。</T>
        </View>
      </View>
      {!link ? (
        <Card>
          <T size={17}>设备连接尚未在这个安装包中启用</T>
          <T size={13} color={C.secondary}>
            {Platform.OS === "android"
              ? "Android 端正在接入加密连接。你的小传仍保存在手机里。"
              : Platform.OS === "web"
                ? "请用支持设备连接的手机安装包扫码。网页预览不会建立设备授权。"
                : "Expo Go 仅供预览。设备配对需要包含原生连接模块的开发安装包。"}
          </T>
        </Card>
      ) : (
        <>
          <Card>
            <T size={18}>{status.phase === "connected" ? "电脑已连接" : status.paired ? "已绑定电脑" : "还没有连接电脑"}</T>
            <T size={13} color={C.secondary}>
              {status.message || (status.paired ? "两端打开设备页，在同一 Wi-Fi 下重新连接。" : "在电脑端打开「设置 → 设备」，点击「添加手机」。")}
            </T>
            {status.phase === "connected" && <T size={12} color={C.secondary}>设备授权和加密连接已就绪。小传自动同步尚未开放。</T>}
          </Card>
          {status.phase === "compare" ? (
            <Card style={{ backgroundColor: C.bluePale }}>
              <T size={16}>两端显示的校验码一样吗？</T>
              <T size={19} style={{ fontVariant: ["tabular-nums"], letterSpacing: 1 }}>{status.fingerprint}</T>
              <T size={12} color={C.secondary}>请完整核对手机和电脑上的八组字符；确认后，再在电脑上允许连接。</T>
              <Button disabled={busy || status.approved} onPress={() => void action(() => link!.approve(status.fingerprint))}>
                {status.approved ? "已确认，等待电脑" : "一致，允许连接"}
              </Button>
              <Button secondary disabled={busy} onPress={() => void action(() => link!.cancel())}>不一致，取消连接</Button>
            </Card>
          ) : connecting ? (
            <Button secondary onPress={() => void action(() => link!.cancel())}>取消连接</Button>
          ) : status.phase === "connected" ? (
            <Button secondary disabled={busy} onPress={() => void action(() => link!.cancel())}>断开连接</Button>
          ) : status.paired ? (
            <Button disabled={busy || !ready} onPress={() => void action(() => link!.reconnect())}>连接已绑定的电脑</Button>
          ) : !scanning ? (
            <Button disabled={busy || !ready} icon="phone" onPress={() => void scan()}>扫描电脑连接码</Button>
          ) : null}
          {scanning && (
            <>
              <View style={{ height: 300, overflow: "hidden", borderRadius: 24 }}>
                <CameraView style={{ flex: 1 }} facing="back" barcodeScannerSettings={{ barcodeTypes: ["qr"] }}
                  onBarcodeScanned={({ data }) => {
                    if (scanLock.current) return;
                    scanLock.current = true; setScanning(false);
                    void action(async () => {
                      try { parseInvite(data); } catch (error) {
                        setMessage(error instanceof Error ? error.message : "连接码不可用。"); return;
                      }
                      await link!.pair(data);
                    });
                  }} />
              </View>
              <Button secondary onPress={() => { scanLock.current = true; setScanning(false); }}>取消扫码</Button>
            </>
          )}
          {status.paired && (
            removing ? <Card>
              <T size={14}>移除后，这台电脑需要重新扫码才能连接。已收到的数据不会被远程删除。</T>
              <Button danger disabled={busy} onPress={() => void action(async () => { await link!.removeDevice(); setRemoving(false); })}>确认移除电脑</Button>
              <Button secondary onPress={() => setRemoving(false)}>保留设备</Button>
            </Card> : <Button secondary disabled={busy} onPress={() => setRemoving(true)}>移除已绑定电脑</Button>
          )}
        </>
      )}
      {Boolean(message) && <Card style={{ backgroundColor: C.bluePale }}><T size={13}>{message}</T></Card>}
      <T size={12} color={C.secondary}>当前连接要求手机与电脑在同一 Wi-Fi，并允许局域网访问。二维码两分钟内有效；相机只用于扫码。</T>
    </Page>
  );
}
