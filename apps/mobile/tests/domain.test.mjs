import test from "node:test";
import assert from "node:assert/strict";
import {
  emptyState,
  parseState,
  parseMomentBackup,
  serializeMoments,
  mergeMoments,
  dayKey,
  todayEvents,
  weekData,
  modelEndpoint,
  finishRest,
} from "../src/lib/domain.ts";
import { parseInvite } from "../src/lib/pairing.ts";
import { appendReply } from "../src/lib/domain.ts";
import { parseCredential } from "../src/lib/credential.ts";
const moment = {
  id: "one",
  at: new Date(2026, 8, 11, 12).getTime(),
  category: "happy",
  text: "一件小事",
};
test("late model responses do not resurrect cleared conversations", () => {
  const state = emptyState();
  const response = {
    id: "r",
    role: "assistant",
    at: moment.at,
    text: "reply",
    source: "model",
  };
  assert.equal(appendReply(state, response, "cleared-user-message"), state);
  state.messages = [{ id: "u", role: "user", at: moment.at, text: "hi" }];
  assert.equal(appendReply(state, response, "u").messages.length, 2);
});
test("credentials retain their endpoint binding and reject unbound legacy keys", () => {
  assert.equal(parseCredential("unbound-key"), null);
  assert.equal(parseCredential(JSON.stringify({ key: "test" })), null);
  assert.deepEqual(
    parseCredential(
      JSON.stringify({
        key: "test",
        endpoint: "https://example.com/v1/chat/completions",
      }),
    ),
    { key: "test", endpoint: "https://example.com/v1/chat/completions" },
  );
});

test("fresh state round-trips without fabricated history", () => {
  const state = emptyState();
  assert.deepEqual(parseState(JSON.stringify(state)), state);
  assert.equal(weekData(state.events).filter((d) => d.checkin).length, 0);
});
test("backup round-trip strips credentials and preserves Unicode", () => {
  const data = { ...moment, text: "小猫 🐈 和晚霞", psk: "never-import" };
  const result = parseMomentBackup(serializeMoments([data]));
  assert.deepEqual(result, [{ ...moment, text: data.text }]);
});
test("invalid backups never become data", () => {
  for (const bad of [
    "bad",
    "{}",
    JSON.stringify({
      format: "dozycat-moments",
      version: 2,
      moments: [moment],
    }),
    serializeMoments([{ ...moment, category: "admin" }]),
    serializeMoments([{ ...moment, at: -1 }]),
    serializeMoments([{ ...moment, text: " " }]),
    serializeMoments([moment, moment]),
  ])
    assert.throws(() => parseMomentBackup(bad));
});
test("oversized backups are rejected", () =>
  assert.throws(() => parseMomentBackup(" ".repeat(64_000_001))));
test("merge preserves local edits and deduplicates IDs", () => {
  const result = mergeMoments(
    [moment],
    [
      { ...moment, text: "old backup" },
      { ...moment, id: "two", at: moment.at + 1000 },
    ],
  );
  assert.equal(result.length, 2);
  assert.equal(result[1].text, moment.text);
  assert.equal(result[0].id, "two");
});
test("corrupted persisted settings fail closed", () => {
  for (const patch of [
    { waterGoal: 0 },
    { waterGoal: 21 },
    { provider: "unknown" },
    { includeMemories: "yes" },
    { reminderHour: 25 },
  ]) {
    const s = emptyState();
    Object.assign(s.settings, patch);
    assert.throws(() => parseState(JSON.stringify(s)));
  }
});
test("invalid persisted energy is rejected", () => {
  const s = emptyState();
  s.events = [{ id: "x", at: moment.at, kind: "checkin", mind: 101, body: 60 }];
  assert.throws(() => parseState(JSON.stringify(s)));
});
test("daily water count follows local calendar boundaries", () => {
  const morning = new Date(2026, 8, 12, 0, 1).getTime();
  const yesterday = new Date(2026, 8, 11, 23, 59).getTime();
  assert.notEqual(dayKey(morning), dayKey(yesterday));
  assert.equal(
    todayEvents(
      [
        { id: "1", at: yesterday, kind: "water" },
        { id: "2", at: morning, kind: "water" },
      ],
      morning,
    ).length,
    1,
  );
});
test("weekly chart uses the last self-report of each day", () => {
  const events = [
    { id: "1", kind: "checkin", at: moment.at, mind: 20, body: 40 },
    { id: "2", kind: "checkin", at: moment.at + 1000, mind: 80, body: 60 },
  ];
  const week = weekData(events, moment.at + 2000);
  assert.equal(week.length, 7);
  assert.equal(week[6].checkin.mind, 80);
  assert.equal(week[0].checkin, undefined);
});
test("model addresses enforce HTTPS and avoid embedded credentials", () => {
  assert.equal(
    modelEndpoint("https://api.example.com/v1/"),
    "https://api.example.com/v1/chat/completions",
  );
  for (const url of [
    "http://example.com",
    "https://user:pass@example.com",
    "https://example.com?key=secret",
    "https://example.com/#fragment",
    "not a url",
  ])
    assert.throws(() => modelEndpoint(url));
});
test("rest completion survives suspension and is idempotent", () => {
  const s = emptyState();
  s.rest = {
    id: "rest1",
    startedAt: moment.at,
    endsAt: moment.at + 60000,
    minutes: 1,
  };
  assert.equal(finishRest(s, moment.at + 1000), s);
  const done = finishRest(s, moment.at + 70000);
  assert.equal(done.rest, null);
  assert.equal(done.events.length, 1);
  assert.equal(done.events[0].at, moment.at + 60000);
  assert.equal(finishRest(done, moment.at + 90000), done);
});
test("rest state with a duplicate event is settled without awarding twice", () => {
  const s = emptyState();
  s.rest = {
    id: "r",
    startedAt: moment.at,
    endsAt: moment.at + 60000,
    minutes: 1,
  };
  s.events = [{ id: "r", at: moment.at + 60000, kind: "rest", minutes: 1 }];
  assert.equal(finishRest(s, moment.at + 60001).events.length, 1);
});
const invite = {
  version: 1,
  room_id: "A".repeat(22),
  desktop_public_key: "B".repeat(43),
  psk: "C".repeat(43),
  expires_at: moment.at + 10000,
};
const encode = (value) =>
  "dozycat://pair?data=" + encodeURIComponent(JSON.stringify(value));
test("pair invitation accepts a bounded fresh payload, without trusting it", () =>
  assert.deepEqual(parseInvite(encode(invite), moment.at), invite));
test("pair invitation rejects expired, foreign and oversized payloads", () => {
  for (const value of [
    encode({ ...invite, expires_at: moment.at - 1 }),
    encode({ ...invite, expires_at: moment.at + 120001 }),
    encode({ ...invite, psk: "123456" }),
    "https://example.com/pair",
    encode(invite) + "&server=evil",
    "dozycat://pair?data=" + "x".repeat(2050),
  ])
    assert.throws(() => parseInvite(value, moment.at));
});
