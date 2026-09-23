import { Stack } from "expo-router/stack";
import { StatusBar } from "expo-status-bar";
import { ActivityIndicator, View } from "react-native";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { StoreProvider, useStore } from "@/lib/app-store";
import { C, Button, T } from "@/components/ui";
import { useState } from "react";
import { readDocument } from "@/lib/storage";
import { exportFile } from "@/lib/backup";

function AppShell() {
  const store = useStore();
  const [recoveryStatus, setRecoveryStatus] = useState("");
  return (
    <View style={{ flex: 1, backgroundColor: "#EFEEE9", alignItems: "center" }}>
      <StatusBar style="dark" />
      <View
        style={{
          width: "100%",
          maxWidth: 560,
          flex: 1,
          backgroundColor: C.paper,
          borderLeftWidth: 1,
          borderRightWidth: 1,
          borderColor: C.line,
        }}
      >
        {!store.ready ? (
          <View
            style={{
              flex: 1,
              justifyContent: "center",
              alignItems: "center",
              gap: 16,
            }}
          >
            <ActivityIndicator color={C.blue} />
            <T color={C.secondary}>懒猫伸个懒腰…</T>
          </View>
        ) : store.loadError ? (
          <View style={{ padding: 30, gap: 20 }}>
            <T>暂时打不开本地记录</T>
            <T color={C.secondary}>{store.error}</T>
            <T size={12}>
              已停止写入，避免覆盖你的数据。请保留应用，联系支持协助恢复。
            </T>
            <T size={12}>
              原始数据以明文导出，不包含安全存储中的 API
              Key。请只保存到你信任的位置。
            </T>
            <Button
              secondary
              onPress={() => {
                void readDocument()
                  .then(async (raw) => {
                    if (raw === null)
                      throw new Error("没有找到可以导出的记录。");
                    await exportFile(raw, "dozycat-recovery.json");
                    setRecoveryStatus("已交给系统保存或分享。");
                  })
                  .catch((e) =>
                    setRecoveryStatus(
                      e instanceof Error ? e.message : "暂时无法导出。",
                    ),
                  );
              }}
            >
              导出本机原始数据
            </Button>
            {Boolean(recoveryStatus) && <T size={12}>{recoveryStatus}</T>}
          </View>
        ) : (
          <>
            <Stack
              screenOptions={{
                headerStyle: { backgroundColor: C.paper },
                headerTintColor: C.ink,
                headerShadowVisible: false,
                headerTitleStyle: { fontSize: 17, fontWeight: "500" },
                contentStyle: { backgroundColor: C.paper },
                headerBackButtonDisplayMode: "minimal",
              }}
            >
              <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
              <Stack.Screen
                name="moment"
                options={{ title: "留住一件小事", presentation: "modal" }}
              />
              <Stack.Screen
                name="checkin"
                options={{ title: "此刻的你", presentation: "modal" }}
              />
              <Stack.Screen
                name="rest"
                options={{
                  title: "休息时刻",
                  presentation: "fullScreenModal",
                  headerShown: false,
                }}
              />
              <Stack.Screen
                name="sleep"
                options={{
                  title: "睡前模式",
                  presentation: "fullScreenModal",
                  headerShown: false,
                }}
              />
              <Stack.Screen name="devices" options={{ title: "我的设备" }} />
              <Stack.Screen name="data" options={{ title: "我的数据" }} />
            </Stack>
            {Boolean(store.error) && (
              <View
                style={{ padding: 14, backgroundColor: C.coralPale, gap: 8 }}
              >
                <T size={12}>{store.error}</T>
                <Button onPress={store.retrySave} secondary>
                  重试保存
                </Button>
              </View>
            )}
          </>
        )}
      </View>
    </View>
  );
}
export default function RootLayout() {
  return (
    <SafeAreaProvider>
      <StoreProvider>
        <AppShell />
      </StoreProvider>
    </SafeAreaProvider>
  );
}
