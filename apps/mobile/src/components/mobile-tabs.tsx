import {
  Tabs,
  TabList,
  TabTrigger,
  TabSlot,
  TabTriggerSlotProps,
} from "expo-router/ui";
import { Pressable, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { Stack } from "expo-router/stack";
import { usePathname } from "expo-router";
import { C, Icon, IconName } from "./ui";
function TabButton({
  isFocused,
  children,
  icon,
  ...props
}: TabTriggerSlotProps & { icon: IconName }) {
  return (
    <Pressable
      {...props}
      accessibilityRole="tab"
      accessibilityState={{ selected: isFocused }}
      aria-selected={isFocused}
      style={{
        flex: 1,
        minHeight: 62,
        alignItems: "center",
        justifyContent: "center",
        gap: 5,
      }}
    >
      <Icon name={icon} size={22} color={isFocused ? C.ink : C.muted} />
      <Text
        style={{
          color: isFocused ? C.ink : C.muted,
          fontSize: 10,
          fontWeight: isFocused ? "600" : "400",
        }}
      >
        {children}
      </Text>
      {isFocused && (
        <View
          style={{
            width: 4,
            height: 4,
            borderRadius: 2,
            backgroundColor: C.coral,
            position: "absolute",
            bottom: 0,
          }}
        />
      )}
    </Pressable>
  );
}
export function MobileTabs() {
  const insets = useSafeAreaInsets();
  const path = usePathname();
  const title =
    (
      {
        "/": "今日",
        "/moments": "小传",
        "/settings": "设置",
      } as Record<string, string>
    )[path] ?? "dozycat";
  return (
    <Tabs style={{ flex: 1 }}>
      <Stack.Screen options={{ title, headerShown: path !== "/" }} />
      <TabSlot style={{ flex: 1 }} />
      <TabList
        style={{
          backgroundColor: C.paper,
          borderTopColor: C.line,
          borderTopWidth: 1,
          paddingHorizontal: 12,
          paddingBottom: Math.max(insets.bottom, 12),
          paddingTop: 6,
        }}
      >
        <TabTrigger name="today" href="/" asChild>
          <TabButton icon="sun">今日</TabButton>
        </TabTrigger>
        <TabTrigger name="moments" href="/moments" asChild>
          <TabButton icon="book">小传</TabButton>
        </TabTrigger>
        <TabTrigger name="settings" href="/settings" asChild>
          <TabButton icon="settings">设置</TabButton>
        </TabTrigger>
      </TabList>
    </Tabs>
  );
}
