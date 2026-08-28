import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const serverURL=new URL("../src/server.js",import.meta.url);
const databaseURL=new URL("../src/database.js",import.meta.url);

test("Together endpoints tersedia",async()=>{
  const source=await readFile(serverURL,"utf8");
  for(const route of [
    "/api/together/plans",
    "/api/together/plans/:id/rsvp",
    "/api/together/plans/:id/vote",
    "/api/together/plans/:id/messages",
    "/api/together/plans/:id/photos",
    "/api/collections/:id/members",
    "/api/together/plans/:id/moment"
  ]) assert.ok(source.includes(route),`missing ${route}`);
  assert.ok(source.includes("push_together"));
  assert.ok(source.includes("loadDiningPlans"));
  assert.ok(source.includes("planId"));
});

test("Together migration non destructive dan FK lengkap",async()=>{
  const source=await readFile(databaseURL,"utf8");
  for(const table of [
    "collection_members",
    "dining_plans",
    "dining_plan_members",
    "dining_plan_candidates",
    "dining_plan_votes",
    "dining_plan_messages",
    "dining_plan_photos"
  ]) assert.ok(source.includes(`CREATE TABLE IF NOT EXISTS ${table}`),`missing ${table}`);
  assert.ok(source.includes("ADD COLUMN IF NOT EXISTS push_together"));
  assert.ok(source.includes("ADD COLUMN IF NOT EXISTS plan_id UUID REFERENCES dining_plans"));
  assert.ok(source.indexOf("CREATE TABLE IF NOT EXISTS restaurants") < source.indexOf("CREATE TABLE IF NOT EXISTS dining_plan_candidates"));
  assert.ok(source.indexOf("CREATE TABLE IF NOT EXISTS dining_plan_candidates") < source.indexOf("CREATE TABLE IF NOT EXISTS dining_plan_votes"));
});

test('Together lifecycle guards dan validasi target tersedia', async () => {
  const server=await readFile(serverURL,"utf8");
  assert.match(server, /Voting sudah ditutup/);
  assert.match(server, /Salah satu foodie tidak ditemukan/);
  assert.match(server, /Salah satu kandidat restoran belum tersedia di Fodd/);
  assert.match(server, /ON CONFLICT DO NOTHING RETURNING user_id/);
  assert.match(server, /Restoran belum tersedia di Fodd/);
  assert.match(server, /Daftar kolaborator hanya tersedia untuk anggota collection/);
});
