export type Credential = { key: string; endpoint: string };
export function parseCredential(value: string | null): Credential | null {
  if (!value) return null;
  try {
    const data = JSON.parse(value);
    if (typeof data?.key === "string" && typeof data?.endpoint === "string")
      return { key: data.key, endpoint: data.endpoint };
  } catch {
    /* Legacy/unbound secrets must be re-entered. */
  }
  return null;
}
