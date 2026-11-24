// node --test tools/feed/build.test.mjs : two fake hourly downloads, then the sales and prices they must give
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const run = (fixture, out, cache, now, houses) =>
  execFileSync("node", [path.join(here, "build.mjs")], {
    env: { ...process.env, FEED_FIXTURE: path.join(here, "test", fixture), FEED_OUT: out, FEED_CACHE: cache,
      FEED_NOW: String(now), FEED_HOUSES: houses || "" },
  });

test("counts what sold between two downloads", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "feed-"));
  const cache = path.join(dir, "cache"), out = path.join(dir, "Feed.lua");
  run("run1", out, cache, 1795500100);
  run("run2", out, cache, 1795503700);
  const lua = fs.readFileSync(out, "utf8");
  const data = lua.match(/\[114\] = \{ t = (\d+), firstDay = \d+, seen = "([0-9,]*)", data = "([^"]*)" \}/);
  assert.ok(data, "house 114 written");
  assert.equal(Number(data[1]), 1795503600);
  const items = Object.fromEntries(data[3].split(";").filter(Boolean).map((e) => {
    const [id, rest] = e.split("=");
    return [id, rest.split(",").map((v) => (v === "" ? null : parseInt(v, 36)))];
  }));
  // item 7911: lowest now 5500, 3 listed in 2 auctions, 1 bought for 5000, today's low 5000
  assert.deepEqual(items["7911"].slice(0, 7), [5500, 3, 2, 1, 5000, 1, 0]);
  assert.equal(items["7911"][items["7911"].length - 1], 5000); // today: the last daily low
  assert.equal(items["7911"].length, 7 + 30); // 30 days of lows shipped
  assert.equal(data[2], String(Math.floor(1795503600 / 86400))); // the one day it was downloaded on
  // goods 12359: 15 of a stack bought at 142, 40 ran out, the 30-min-to-2-h listing not counted
  assert.deepEqual(items["12359"].slice(0, 7), [139, 35, 2, 15, 15 * 142, 1, 40]);
  // the bid-only listing has no price: not shipped
  assert.equal(items["13444"], undefined);
});

test("builds only the houses asked for", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "feed-"));
  const out = path.join(dir, "Feed.lua");
  run("run1", out, path.join(dir, "cache"), 1795500100, "114,116");
  const lua = fs.readFileSync(out, "utf8");
  assert.match(lua, /\[114\] = \{/);
  assert.doesNotMatch(lua, /\[117\] = \{/);
});
