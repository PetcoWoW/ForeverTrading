// node --test tools/feed/build.test.mjs : two fake hourly downloads, then the sales and prices they must give
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import zlib from "node:zlib";
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
  const data = lua.match(/\[114\] = \{ t = (\d+), firstDay = \d+, seen = "([0-9,]*)", data = "([^"]*)"/);
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

test("fills older days from a backfill, never over the robot's own", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "feed-"));
  const cache = path.join(dir, "cache"), out = path.join(dir, "Feed.lua"), bf = path.join(dir, "backfill");
  fs.mkdirSync(bf);
  const now = 1795500100, day = Math.floor(now / 86400);
  // item 7911: two older days and today (today must not be touched)
  fs.writeFileSync(path.join(bf, "114-test.json.gz"), zlib.gzipSync(JSON.stringify({
    seen: [day - 2], items: { 7911: { [day - 2]: 4000, [day - 1]: 4500, [day]: 1 } },
  })));
  execFileSync("node", [path.join(here, "build.mjs")], {
    env: { ...process.env, FEED_FIXTURE: path.join(here, "test", "run1"), FEED_OUT: out, FEED_CACHE: cache,
      FEED_NOW: String(now), FEED_HOUSES: "", FEED_BACKFILL: bf },
  });
  const lua = fs.readFileSync(out, "utf8");
  const data = lua.match(/\[114\] = \{ t = \d+, firstDay = (\d+), seen = "([0-9,]*)", data = "([^"]*)"/);
  assert.ok(data, "house 114 written");
  const first = Number(data[1]);
  assert.ok(data[2].split(",").map(Number).includes(day - 2), "the backfill's scanned day counts as seen");
  const row = data[3].split(";").find((e) => e.startsWith("7911=")).split("=")[1].split(",");
  const lows = row.slice(7).map((v) => (v === "" ? null : parseInt(v, 36)));
  assert.equal(lows[day - 2 - first], 4000);
  assert.equal(lows[day - 1 - first], 4500);
  assert.notEqual(lows[day - first], 1, "today stays the robot's own");
});

test("the frequent checks skip a download Blizzard hasn't refreshed", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "feed-"));
  const cache = path.join(dir, "cache"), out = path.join(dir, "Feed.lua"), gho = path.join(dir, "gh-out");
  const check = (fixture, now) => {
    fs.writeFileSync(gho, "");
    execFileSync("node", [path.join(here, "build.mjs")], {
      env: { ...process.env, FEED_FIXTURE: path.join(here, "test", fixture), FEED_OUT: out, FEED_CACHE: cache,
        FEED_NOW: String(now), FEED_HOUSES: "", FEED_ONLY_NEW: "1", GITHUB_OUTPUT: gho },
    });
    return fs.readFileSync(gho, "utf8").trim();
  };
  assert.equal(check("run1", 1795500100), "changed=true"); // nothing built before
  const first = fs.readFileSync(out, "utf8");
  assert.equal(check("run1", 1795500100 + 900), "changed=false"); // same snapshot 15 minutes later
  assert.equal(fs.readFileSync(out, "utf8"), first, "nothing rewritten");
  assert.equal(check("run2", 1795503700), "changed=true"); // Blizzard refreshed
});

test("ships what sold day by day (the Radar)", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "feed-"));
  const cache = path.join(dir, "cache"), out = path.join(dir, "Feed.lua");
  run("run1", out, cache, 1795500100);
  const lua = fs.readFileSync(out, "utf8");
  assert.match(lua, /soldFirst = \d+, sold = "[0-9a-z=,;]*"/);
});

test("ships what sold hour by hour (the item page's timeline)", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "feed-"));
  const cache = path.join(dir, "cache"), out = path.join(dir, "Feed.lua");
  run("run1", out, cache, 1795500100);
  run("run2", out, cache, 1795503700);
  const lua = fs.readFileSync(out, "utf8");
  const m = lua.match(/\[114\] = \{[^\n]*hourFirst = (\d+), hourly = "([0-9a-z=,;/]*)"/);
  assert.ok(m, "hourly written");
  const hour = Math.floor(1795503600 / 3600);
  assert.equal(Number(m[1]), hour - 47);
  // goods 12359: 15 sold in the last hour (the only one watched); its time of day: 15 an hour at that UTC hour
  const line = m[2].split(";").find((e) => e.startsWith("12359="));
  assert.ok(line, "12359 has an hourly line");
  const [last, tod] = line.split("=")[1].split("/");
  const lastVals = last.split(",");
  assert.equal(lastVals.length, 48);
  assert.equal(parseInt(lastVals[47], 36), 15);
  assert.equal(lastVals[0], "", "hours not watched are empty");
  const todVals = tod.split(",");
  assert.equal(todVals.length, 24);
  assert.equal(parseInt(todVals[hour % 24], 36), 150);
});
