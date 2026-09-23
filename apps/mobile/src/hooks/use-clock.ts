import { useEffect, useState } from "react";
import { AppState } from "react-native";
export function useClock() {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const refresh = () => setNow(Date.now());
    const timer = setInterval(refresh, 30000);
    const subscription = AppState.addEventListener("change", refresh);
    return () => {
      clearInterval(timer);
      subscription.remove();
    };
  }, []);
  return now;
}
