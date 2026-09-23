import { ReactNode } from "react";
import {
  Pressable,
  ScrollView,
  Text,
  TextInput,
  View,
  TextStyle,
  ViewStyle,
  TextInputProps,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { Stack } from "expo-router/stack";
import Svg, { Circle, Path, Rect, Line, Polyline } from "react-native-svg";

export const C = {
  paper: "#FAFAF8",
  ink: "#2E2E33",
  secondary: "#73716B",
  muted: "#A19D94",
  line: "#E8E6E0",
  blue: "#7C8DB5",
  coral: "#EE917D",
  bluePale: "#EEF1F6",
  coralPale: "#FAEBE5",
  card: "#FFFFFF",
  sage: "#7E9682",
  night: "#292C31",
};
export type IconName =
  | "sun"
  | "chat"
  | "book"
  | "chart"
  | "settings"
  | "arrow"
  | "plus"
  | "check"
  | "water"
  | "moon"
  | "walk"
  | "close"
  | "back"
  | "shield"
  | "phone"
  | "search"
  | "send"
  | "edit"
  | "download"
  | "upload"
  | "trash"
  | "pause";
export function Icon({
  name,
  size = 22,
  color = C.ink,
}: {
  name: IconName;
  size?: number;
  color?: string;
}) {
  const paths: Partial<Record<IconName, string>> = {
    chat: "M20 11a8 8 0 0 1-8 8H4l1.5-4A8 8 0 1 1 20 11Z",
    book: "M12 5C9 3 5 3 3 4v15c3-1 6-1 9 1 3-2 6-2 9-1V4c-2-1-6-1-9 1Zm0 0v15",
    chart: "M4 18V9m5 9V5m5 13v-7m5 7V3",
    arrow: "m9 5 7 7-7 7",
    plus: "M12 5v14M5 12h14",
    check: "m5 12 4 4L19 6",
    water: "M12 3c-1 3-7 8-7 12a7 7 0 0 0 14 0c0-4-6-9-7-12Z",
    moon: "M20 14A9 9 0 0 1 10 3a9 9 0 1 0 10 11Z",
    walk: "m9 10 3-4 4 4 4 1M12 6l-1 8-5 6m5-6 5 1 1 5M5 12l4-2",
    close: "m6 6 12 12M18 6 6 18",
    back: "m14 5-7 7 7 7",
    shield: "m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6l8-3Zm-4 9 3 3 5-6",
    send: "m3 3 18 9-18 9 3-9-3-9Zm3 9h15",
    edit: "m15 4 5 5M4 20l5-1L21 7l-5-5L4 14v6Z",
    download: "M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5",
    upload: "M12 16V4m-5 5 5-5 5 5M4 16v5h16v-5",
    trash: "M3 6h18M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7",
    pause: "M8 5v14M16 5v14",
  };
  return (
    <Svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke={color}
      strokeWidth={1.6}
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      {name === "sun" ? (
        <>
          <Circle cx={12} cy={12} r={4} />
          <Path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5" />
        </>
      ) : name === "settings" ? (
        <>
          <Circle cx={12} cy={12} r={3} />
          <Path d="m9 3 6 0 1 3 3 1 2 5-2 5-3 1-1 3H9l-1-3-3-1-2-5 2-5 3-1 1-3Z" />
        </>
      ) : name === "phone" ? (
        <>
          <Rect x={6} y={2} width={12} height={20} rx={3} />
          <Line x1={10} x2={14} y1={18} y2={18} />
        </>
      ) : name === "search" ? (
        <>
          <Circle cx={10.5} cy={10.5} r={6.5} />
          <Polyline points="16,16 21,21" />
        </>
      ) : (
        <Path d={paths[name]} />
      )}
    </Svg>
  );
}
export function T({
  children,
  size = 15,
  color = C.ink,
  style,
  weight,
}: {
  children: ReactNode;
  size?: number;
  color?: string;
  style?: TextStyle;
  weight?: TextStyle["fontWeight"];
}) {
  return (
    <Text
      selectable
      style={{
        fontSize: size,
        lineHeight: size * 1.6,
        color,
        fontWeight: weight,
        ...style,
      }}
    >
      {children}
    </Text>
  );
}
export function Page({
  children,
  title,
  right,
  subtitle,
  hideHeader = false,
}: {
  children: ReactNode;
  title: string;
  hideHeader?: boolean;
  right?: ReactNode;
  subtitle?: string;
}) {
  const insets = useSafeAreaInsets();
  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      keyboardShouldPersistTaps="handled"
      style={{ flex: 1, backgroundColor: C.paper }}
      contentContainerStyle={{ padding: 24, paddingTop: 24 + (hideHeader ? insets.top : 0), paddingBottom: 36, gap: 24 }}
    >
      <Stack.Screen options={{ title, ...(hideHeader ? { headerShown: false } : {}) }} />
      {subtitle ? (
        <View
          style={{
            flexDirection: "row",
            alignItems: "center",
            justifyContent: "space-between",
          }}
        >
          <T size={12} color={C.secondary}>
            {subtitle}
          </T>
          {right}
        </View>
      ) : (
        right
      )}
      <View style={{ gap: 24 }}>{children}</View>
    </ScrollView>
  );
}
export function Card({
  children,
  style,
}: {
  children: ReactNode;
  style?: ViewStyle;
}) {
  return (
    <View
      style={{
        backgroundColor: C.card,
        borderWidth: 1,
        borderColor: C.line,
        borderRadius: 24,
        borderCurve: "continuous",
        padding: 20,
        gap: 12,
        ...style,
      }}
    >
      {children}
    </View>
  );
}
export function Button({
  children,
  onPress,
  secondary,
  disabled,
  icon,
  danger,
  label,
}: {
  children: ReactNode;
  onPress: () => void;
  secondary?: boolean;
  disabled?: boolean;
  icon?: IconName;
  danger?: boolean;
  label?: string;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => ({
        minHeight: 48,
        paddingHorizontal: 20,
        paddingVertical: 12,
        borderRadius: 30,
        flexDirection: "row",
        alignItems: "center",
        justifyContent: "center",
        gap: 9,
        backgroundColor: secondary ? C.paper : danger ? "#AB534C" : C.ink,
        borderWidth: secondary ? 1 : 0,
        borderColor: C.line,
        opacity: disabled ? 0.4 : pressed ? 0.7 : 1,
      })}
    >
      {icon && (
        <Icon name={icon} size={18} color={secondary ? C.ink : "#FFF"} />
      )}
      <Text
        style={{
          color: secondary ? C.ink : "#FFF",
          fontSize: 14,
          fontWeight: "500",
        }}
      >
        {children}
      </Text>
    </Pressable>
  );
}
export function SmallButton({
  icon,
  label,
  onPress,
}: {
  icon: IconName;
  label: string;
  onPress: () => void;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={onPress}
      style={({ pressed }) => ({
        width: 44,
        height: 44,
        borderRadius: 22,
        backgroundColor: pressed ? C.line : "transparent",
        alignItems: "center",
        justifyContent: "center",
      })}
    >
      <Icon name={icon} />
    </Pressable>
  );
}
export function Chip({
  children,
  selected,
  onPress,
}: {
  children: ReactNode;
  selected?: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ selected }}
      onPress={onPress}
      style={{
        minHeight: 40,
        paddingVertical: 9,
        paddingHorizontal: 16,
        borderRadius: 24,
        backgroundColor: selected ? C.ink : "transparent",
        borderWidth: 1,
        borderColor: selected ? C.ink : C.line,
      }}
    >
      <Text style={{ color: selected ? "#FFF" : C.secondary, fontSize: 13 }}>
        {children}
      </Text>
    </Pressable>
  );
}
export function Field(props: TextInputProps) {
  return (
    <TextInput
      placeholderTextColor={C.muted}
      {...props}
      style={[
        {
          minHeight: 50,
          padding: 14,
          backgroundColor: "#F4F3EF",
          borderWidth: 1,
          borderColor: C.line,
          borderRadius: 14,
          fontSize: 15,
          color: C.ink,
        },
        props.style,
      ]}
    />
  );
}
export function SectionLabel({
  children,
  aside,
}: {
  children: ReactNode;
  aside?: string;
}) {
  return (
    <View
      style={{
        flexDirection: "row",
        justifyContent: "space-between",
        alignItems: "center",
      }}
    >
      <T size={14} weight="600">
        {children}
      </T>
      {Boolean(aside) && (
        <T size={11} color={C.muted}>
          {aside}
        </T>
      )}
    </View>
  );
}
export function Empty({
  icon = "book",
  title,
  description,
  children,
}: {
  icon?: IconName;
  title: string;
  description: string;
  children?: ReactNode;
}) {
  return (
    <View style={{ paddingVertical: 30, alignItems: "center", gap: 14 }}>
      <View
        style={{
          width: 60,
          height: 60,
          borderRadius: 30,
          backgroundColor: C.bluePale,
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <Icon name={icon} color={C.blue} size={25} />
      </View>
      <T size={19}>{title}</T>
      <T
        size={13}
        color={C.secondary}
        style={{ textAlign: "center", maxWidth: 280 }}
      >
        {description}
      </T>
      {children}
    </View>
  );
}
export function Row({
  icon,
  title,
  subtitle,
  onPress,
  end,
}: {
  icon: IconName;
  title: string;
  subtitle?: string;
  onPress?: () => void;
  end?: ReactNode;
}) {
  const content = (
    <>
      <View
        style={{
          width: 42,
          height: 42,
          borderRadius: 15,
          backgroundColor: C.paper,
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <Icon name={icon} color={C.secondary} size={20} />
      </View>
      <View style={{ flex: 1 }}>
        <T size={14}>{title}</T>
        {Boolean(subtitle) && (
          <T size={11} color={C.secondary}>
            {subtitle}
          </T>
        )}
      </View>
      {end ?? (onPress && <Icon name="arrow" size={16} color={C.muted} />)}
    </>
  );
  return onPress ? (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={{
        minHeight: 62,
        flexDirection: "row",
        alignItems: "center",
        gap: 12,
      }}
    >
      {content}
    </Pressable>
  ) : (
    <View
      style={{
        minHeight: 62,
        flexDirection: "row",
        alignItems: "center",
        gap: 12,
      }}
    >
      {content}
    </View>
  );
}
