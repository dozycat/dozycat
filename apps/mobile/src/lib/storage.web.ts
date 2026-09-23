const KEY = "dozycat.mobile.v1";
export const readDocument = async () =>
  typeof window === "undefined" ? null : window.localStorage.getItem(KEY);
export const writeDocument = async (value: string) => {
  window.localStorage.setItem(KEY, value);
};
