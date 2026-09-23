import * as Crypto from "expo-crypto";
import {
  createContext,
  use,
  useCallback,
  useEffect,
  useRef,
  useState,
  ReactNode,
} from "react";
import {
  AppState,
  Event,
  Moment,
  Settings,
  emptyState,
  mergeMoments,
  parseState,
} from "./domain";
import { readDocument, writeDocument } from "./storage";

type Store = {
  state: AppState;
  ready: boolean;
  error: string;
  loadError: boolean;
  update: (fn: (s: AppState) => AppState) => void;
  retrySave: () => void;
  addEvent: (kind: Event["kind"], fields?: Partial<Event>) => void;
  saveMoment: (text: string, category: Moment["category"], id?: string) => void;
  importMoments: (moments: Moment[]) => void;
  settings: (patch: Partial<Settings>) => void;
};
const Context = createContext<Store | null>(null);
export const uid = () => Crypto.randomUUID();
export function StoreProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState(emptyState);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState("");
  const [loadError, setLoadError] = useState(false);
  const current = useRef(state);
  const active = useRef(true);
  const queue = useRef(Promise.resolve());
  useEffect(() => {
    let cancelled = false;
    active.current = true;
    readDocument()
      .then((raw) => {
        if (cancelled) return;
        const next = raw ? parseState(raw) : emptyState();
        current.current = next;
        setState(next);
      })
      .catch((e) => {
        if (cancelled) return;
        setLoadError(true);
        setError(e instanceof Error ? e.message : "无法打开本地记录。");
      })
      .finally(() => {
        if (!cancelled) setReady(true);
      });
    return () => {
      active.current = false;
      cancelled = true;
    };
  }, []);
  const persist = useCallback((next: AppState) => {
    queue.current = queue.current
      .catch(() => {})
      .then(() => writeDocument(JSON.stringify(next)))
      .then(() => {
        if (active.current) setError("");
      })
      .catch(() => {
        if (active.current) setError("这次改动还没存好，请保留页面并重试。");
      });
  }, []);
  const update = useCallback(
    (fn: (s: AppState) => AppState) => {
      if (!ready || loadError) return;
      const next = fn(current.current);
      current.current = next;
      setState(next);
      persist(next);
    },
    [ready, loadError, persist],
  );
  const addEvent = useCallback(
    (kind: Event["kind"], fields: Partial<Event> = {}) =>
      update((s) => ({
        ...s,
        events: [...s.events, { ...fields, id: uid(), at: Date.now(), kind }],
      })),
    [update],
  );
  const saveMoment = useCallback(
    (text: string, category: Moment["category"], id?: string) =>
      update((s) => {
        const old = s.moments.find((m) => m.id === id);
        if (!text.trim() || (!old && s.moments.length >= 5000)) return s;
        const moment = {
          id: id ?? uid(),
          at: old?.at ?? Date.now(),
          text: text.trim().slice(0, 4000),
          category,
        };
        return {
          ...s,
          moments: [
            moment,
            ...s.moments.filter((m) => m.id !== moment.id),
          ].sort((a, b) => b.at - a.at),
        };
      }),
    [update],
  );
  return (
    <Context
      value={{
        state,
        ready,
        error,
        loadError,
        update,
        retrySave: () => {
          if (!loadError) persist(current.current);
        },
        addEvent,
        saveMoment,
        importMoments: (moments) =>
          update((s) => {
            const merged = mergeMoments(s.moments, moments);
            if (merged.length > 5000)
              throw new Error("合并后超过 5000 条，请先整理小传。");
            return { ...s, moments: merged };
          }),
        settings: (patch) =>
          update((s) => ({ ...s, settings: { ...s.settings, ...patch } })),
      }}
    >
      {children}
    </Context>
  );
}
export function useStore() {
  const store = use(Context);
  if (!store) throw new Error("StoreProvider is missing");
  return store;
}
