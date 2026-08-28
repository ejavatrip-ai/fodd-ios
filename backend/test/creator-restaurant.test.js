import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const serverURL=new URL("../src/server.js",import.meta.url);
const databaseURL=new URL("../src/database.js",import.meta.url);

test("Creator & Restaurant Studio endpoints tersedia",async()=>{
  const source=await readFile(serverURL,"utf8");
  for(const route of [
    "/api/creator/me",
    "/api/restaurants/:id/claim",
    "/api/me/restaurant-claims",
    "/api/my-restaurants",
    "/api/restaurant-studio/restaurants/:id",
    "/api/restaurants/:id/menu",
    "/api/restaurants/:id/posts",
    "/api/admin/restaurant-claims",
    "/api/admin/creators/:id"
  ]) assert.ok(source.includes(route),`missing ${route}`);
  assert.match(source,/Verified Restaurant|terverifikasi|is_verified/);
  assert.match(source,/restaurantManagementAccess/);
});

test("Creator & Restaurant migration additive",async()=>{
  const source=await readFile(databaseURL,"utf8");
  for(const column of ["is_creator","creator_verified","creator_category","creator_website","creator_since","is_verified"])
    assert.ok(source.includes(column),`missing ${column}`);
  for(const table of ["restaurant_claims","restaurant_owners","restaurant_menu_items","restaurant_posts"])
    assert.ok(source.includes(`CREATE TABLE IF NOT EXISTS ${table}`),`missing ${table}`);
  assert.ok(source.indexOf("CREATE TABLE IF NOT EXISTS restaurants") < source.indexOf("CREATE TABLE IF NOT EXISTS restaurant_claims"));
});

test("Restaurant permission dan verification guard tersedia",async()=>{
  const source=await readFile(serverURL,"utf8");
  assert.match(source,/Restoran terverifikasi hanya dapat diubah oleh pengelolanya/);
  assert.match(source,/Anda bukan pengelola restoran ini/);
  assert.match(source,/Staff tidak dapat mengubah profil restoran/);
  assert.match(source,/INSERT INTO restaurant_owners/);
  assert.match(source,/UPDATE restaurants SET is_verified=TRUE/);
});
