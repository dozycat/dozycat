import { useEffect, useId, useRef, useState } from "react";
import { AccessibilityInfo, Animated, Easing, View } from "react-native";
import Svg, { Defs, Ellipse, LinearGradient, Path, Rect, Stop } from "react-native-svg";

export function Cat({
  size = 180,
  asleep = false,
}: {
  size?: number;
  asleep?: boolean;
}) {
  const gradientId = useId().replace(/:/g, "");
  const scale = size / 110;
  const top = asleep ? 22 : 13;
  const inset = asleep ? 2 : 4;
  const breathe = useRef(new Animated.Value(0)).current;
  const [blink, setBlink] = useState(false);
  const [reduce, setReduce] = useState(false);
  useEffect(() => {
    AccessibilityInfo.isReduceMotionEnabled().then(setReduce);
    const sub = AccessibilityInfo.addEventListener(
      "reduceMotionChanged",
      setReduce,
    );
    return () => sub.remove();
  }, []);
  useEffect(() => {
    if (reduce || asleep) {
      breathe.setValue(0);
      return;
    }
    const animation = Animated.loop(
      Animated.sequence([
        Animated.timing(breathe, {
          toValue: 1,
          duration: 3400,
          easing: Easing.inOut(Easing.sin),
          useNativeDriver: process.env.EXPO_OS !== "web",
        }),
        Animated.timing(breathe, {
          toValue: 0,
          duration: 3400,
          easing: Easing.inOut(Easing.sin),
          useNativeDriver: process.env.EXPO_OS !== "web",
        }),
      ]),
    );
    animation.start();
    return () => animation.stop();
  }, [breathe, reduce, asleep]);
  useEffect(() => {
    if (asleep || reduce) return;
    let timeout: ReturnType<typeof setTimeout>;
    const interval = setInterval(() => {
      setBlink(true);
      timeout = setTimeout(() => setBlink(false), 150);
    }, 5600);
    return () => {
      clearInterval(interval);
      clearTimeout(timeout);
    };
  }, [asleep, reduce]);
  // Geometry and palette ported from desktop Sources/DeskCat.swift (110 × 96).
  return (
    <View
      accessible
      accessibilityLabel={asleep ? "安睡的懒猫" : "轻轻呼吸的懒猫"}
      style={{ width: size, height: size * 96 / 110 }}
    >
      <Animated.View style={{
        width: size, height: size * 96 / 110,
        transform: [
          { translateY: breathe.interpolate({ inputRange: [0, 1], outputRange: [0, -5 * scale] }) },
          { scale: breathe.interpolate({ inputRange: [0, 1], outputRange: [1, 1.02] }) },
        ],
      }}>
        {[true, false].map((left) => (
          <View key={String(left)} style={{
            position: "absolute",
            left: (left ? 12 : 69) * scale,
            top: (asleep ? 10 : 4) * scale,
            width: 29 * scale, height: 27 * scale,
            backgroundColor: "#FFFFFF",
            borderTopLeftRadius: (left ? 22 : 7) * scale,
            borderTopRightRadius: (left ? 7 : 22) * scale,
            borderBottomLeftRadius: (left ? 8 : 14) * scale,
            borderBottomRightRadius: (left ? 14 : 8) * scale,
            borderCurve: "continuous",
            transform: [{ rotate: `${(left ? -1 : 1) * (asleep ? 8 : 4)}deg` }],
            boxShadow: `0 ${4 * scale}px ${6 * scale}px rgba(46,46,51,0.08)`,
          }} />
        ))}
        <View style={{
          position: "absolute", left: inset * scale, top: top * scale,
          width: (110 - inset * 2) * scale, height: (96 - top) * scale,
          borderRadius: "50%", backgroundColor: "#FFFFFF",
          boxShadow: `0 ${10 * scale}px ${12 * scale}px rgba(46,46,51,0.12)`,
        }} />
        <Svg style={{ position: "absolute", left: 0, top: 0 }} width={size} height={size * 96 / 110} viewBox="0 0 110 96">
          <Defs>
            <LinearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
              <Stop offset="0" stopColor="#FFFFFF" />
              <Stop offset="0.5" stopColor="#FFFFFF" />
              <Stop offset="1" stopColor="#F4F3EF" />
            </LinearGradient>
          </Defs>
          <Ellipse cx={55} cy={top + (96 - top) / 2} rx={55 - inset} ry={(96 - top) / 2} fill={`url(#${gradientId})`} />
          {asleep || blink ? (
            <>
              <Rect x={asleep ? 26 : 27} y={asleep ? 53.75 : 50.75} width={asleep ? 12 : 11} height={asleep ? 2.5 : 1.2} rx={1.25} fill="#2E2E33" />
              <Rect x={72} y={asleep ? 53.75 : 50.75} width={asleep ? 12 : 11} height={asleep ? 2.5 : 1.2} rx={1.25} fill="#2E2E33" />
            </>
          ) : (
            <>
              <Path d="M29 49h7a2 2 0 0 1 2 2c0 2.5-2.5 4-5.5 4S27 53.5 27 51a2 2 0 0 1 2-2Z" fill="#2E2E33" />
              <Path d="M74 49h7a2 2 0 0 1 2 2c0 2.5-2.5 4-5.5 4S72 53.5 72 51a2 2 0 0 1 2-2Z" fill="#2E2E33" />
            </>
          )}
          <Ellipse cx={55} cy={asleep ? 64.5 : 61.5} rx={3} ry={2.5} fill="#FFB3A6" />
        </Svg>
      </Animated.View>
    </View>
  );
}
