import Storage from "expo-sqlite/kv-store";
const KEY = "dozycat.mobile.v1";
export const readDocument = () => Storage.getItem(KEY);
export const writeDocument = (value: string) => Storage.setItem(KEY, value);
