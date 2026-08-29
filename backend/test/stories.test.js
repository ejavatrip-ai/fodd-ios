import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const serverURL=new URL("../src/server.js",import.meta.url);
const databaseURL=new URL("../src/database.js",import.meta.url);

test("Food Stories 24 jam endpoints tersedia",async()=>{
  const source=await readFile(serverURL,"utf8");
  for(const route of [
    "/api/stories",
    "/api/stories/archive",
    "/api/stories/:id/view",
    "/api/stories/:id/reaction",
    "/api/stories/:id/viewers",
    "/api/stories/:id/reply"
  ]) assert.ok(source.includes(route),`missing ${route}`);
  assert.match(source,/expires_at>NOW\(\)/);
  assert.match(source,/visibleActiveStory/);
});

test("Food Stories migration additive dan privacy lengkap",async()=>{
  const source=await readFile(databaseURL,"utf8");
  for(const table of ["stories","story_audience","story_views","story_reactions"])
    assert.ok(source.includes(`CREATE TABLE IF NOT EXISTS ${table}`),`missing ${table}`);
  assert.match(source,/INTERVAL '24 hours'/);
  assert.match(source,/visibility IN \('everyone','friends','close_foodies','selected','only_me'\)/);
  assert.ok(source.indexOf("CREATE TABLE IF NOT EXISTS users") < source.indexOf("CREATE TABLE IF NOT EXISTS stories"));
});
