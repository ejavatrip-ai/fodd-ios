import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const serverURL=new URL("../src/server.js",import.meta.url);
const databaseURL=new URL("../src/database.js",import.meta.url);

test("7.2 story polls dan highlights endpoints tersedia",async()=>{
  const source=await readFile(serverURL,"utf8");
  for(const route of ["/api/stories/:id/poll","/api/highlights/user/:userId","/api/highlights/:id/stories","/api/highlights","/api/smart/taste-match/:userId"])
    assert.ok(source.includes(route),`missing ${route}`);
});

test("7.2 migration poll/highlight additive",async()=>{
  const source=await readFile(databaseURL,"utf8");
  assert.match(source,/ADD COLUMN IF NOT EXISTS poll_question/);
  for(const table of ["story_poll_votes","story_highlights","story_highlight_items"])
    assert.ok(source.includes(`CREATE TABLE IF NOT EXISTS ${table}`),`missing ${table}`);
});

test("Taste Match memakai Taste DNA dan privacy",async()=>{
  const source=await readFile(serverURL,"utf8");
  assert.match(source,/buildTasteDNA\(req\.user\.id\)/);
  assert.match(source,/pairBlocked\(req\.user\.id,req\.params\.userId\)/);
  assert.match(source,/Taste Twins/);
});
