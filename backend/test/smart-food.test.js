import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const serverURL=new URL("../src/server.js",import.meta.url);
const databaseURL=new URL("../src/database.js",import.meta.url);

test("Smart Food endpoints tersedia",async()=>{
  const source=await readFile(serverURL,"utf8");
  for(const route of ["/api/smart/preferences","/api/smart/events","/api/smart/dashboard"]){
    assert.ok(source.includes(route),`missing ${route}`);
  }
  assert.ok(source.includes("becauseYouLiked"));
  assert.ok(source.includes("hiddenGems"));
  assert.ok(source.includes("moodCatalog"));
});

test("migration Smart Food tersedia dan non destructive",async()=>{
  const source=await readFile(databaseURL,"utf8");
  assert.ok(source.includes("CREATE TABLE IF NOT EXISTS taste_preferences"));
  assert.ok(source.includes("CREATE TABLE IF NOT EXISTS smart_events"));
  assert.ok(source.includes("ADD COLUMN IF NOT EXISTS push_recommendations"));
  assert.ok(source.includes("smart_events_user_created_idx"));
  assert.ok(source.indexOf("CREATE TABLE IF NOT EXISTS restaurants") < source.indexOf("CREATE TABLE IF NOT EXISTS smart_events"),"restaurants must exist before smart_events FK");
});
