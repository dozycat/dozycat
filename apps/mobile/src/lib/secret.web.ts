// Browser preview deliberately keeps model credentials in memory only.
import type { Credential } from "./credential";
let key: Credential | null = null;
export const getSecret = async () => key;
export const setSecret = async (value: string, endpoint?: string) => {
  if (value && !endpoint) throw new Error("密钥必须绑定模型服务地址。");
  key = value ? { key: value, endpoint: endpoint! } : null;
};
