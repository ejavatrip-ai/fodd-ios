import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const serverURL=new URL("../src/server.js",import.meta.url);
const databaseURL=new URL("../src/database.js",import.meta.url);

test("8.0 Complete Hangout endpoints tersedia",async()=>{
  const source=await readFile(serverURL,"utf8");
  for(const path of [
    "/api/hangout/preferences","/api/hangout/available","/api/hangout/quick",
    "/time-options","/time-vote","/presence","/split-bill",
    "/api/hangout/wishlists","/api/hangout/passport","/api/hangout/recap/monthly","/api/product-events"
  ]) assert.ok(source.includes(path),`missing ${path}`);
});

test("8.0 migration additive tersedia",async()=>{
  const source=await readFile(databaseURL,"utf8");
  for(const table of [
    "hangout_preferences","dining_plan_time_options","dining_plan_time_votes","dining_plan_presence",
    "split_bills","split_bill_participants","hangout_wishlists","hangout_wishlist_members","hangout_wishlist_restaurants","product_events"
  ]) assert.ok(source.includes(`CREATE TABLE IF NOT EXISTS ${table}`),`missing ${table}`);
  assert.ok(source.indexOf("CREATE TABLE IF NOT EXISTS dining_plans") < source.indexOf("CREATE TABLE IF NOT EXISTS dining_plan_time_options"));
  assert.match(source,/receipt_image/);
});

test("8.0 privacy undangan diterapkan",async()=>{
  const source=await readFile(serverURL,"utf8");
  assert.match(source,/hangoutInviteAllowed/);
  assert.match(source,/invite_policy/);
  assert.match(source,/close_foodies/);
  assert.match(source,/membatasi undangan nongkrong/);
});
