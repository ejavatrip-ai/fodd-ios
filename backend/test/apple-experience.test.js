import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const serverURL=new URL("../src/server.js",import.meta.url);
const databaseURL=new URL("../src/database.js",import.meta.url);
const pushURL=new URL("../src/push.js",import.meta.url);

test("Apple Experience Live Activity endpoints tersedia",async()=>{
  const source=await readFile(serverURL,"utf8");
  assert.ok(source.includes('/api/together/plans/:id/live-activity'));
  assert.match(source,/broadcastDiningLiveActivity/);
  assert.match(source,/version:"7\.4"/);
});

test("Live Activity migration additive dan setelah dining_plans",async()=>{
  const source=await readFile(databaseURL,"utf8");
  assert.ok(source.includes("CREATE TABLE IF NOT EXISTS live_activity_tokens"));
  assert.ok(source.indexOf("CREATE TABLE IF NOT EXISTS dining_plans") < source.indexOf("CREATE TABLE IF NOT EXISTS live_activity_tokens"));
  assert.match(source,/UNIQUE \(user_id,plan_id\)/);
});

test("APNs Live Activity menggunakan topic dan push type Apple",async()=>{
  const source=await readFile(pushURL,"utf8");
  assert.match(source,/push-type\.liveactivity/);
  assert.match(source,/"apns-push-type":"liveactivity"/);
  assert.match(source,/"content-state"/);
  assert.match(source,/event === "end"/);
});
