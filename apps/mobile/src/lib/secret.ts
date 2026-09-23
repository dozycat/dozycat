import * as SecureStore from "expo-secure-store";
import { parseCredential } from "./credential";
const KEY = "dozycat.model-key";
export const getSecret = async () =>
  parseCredential(await SecureStore.getItemAsync(KEY));
export async function setSecret(value: string, endpoint?: string) {
  if (value && !endpoint) throw new Error("密钥必须绑定模型服务地址。");
  if (value)
    await SecureStore.setItemAsync(
      KEY,
      JSON.stringify({ key: value, endpoint }),
      { keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY },
    );
  else await SecureStore.deleteItemAsync(KEY);
}
