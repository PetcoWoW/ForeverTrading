#!/usr/bin/env node
// The Wolf of Booty Bay - the price feed builder.
//
// Downloads every WoW Forever auction house from Blizzard's Game Data API (namespace dynamic-forever-<region>),
// compares it with the last run's download, and writes Data/Feed.lua: for every house and item the lowest price
// now, how many are listed, in how many auctions, what sold over the last 7 days and the daily lows of the last
// 7 days. Run hourly by .github/workflows/feed.yml; written from scratch for this addon.
//
//   BLIZZARD_CLIENT_ID=... BLIZZARD_CLIENT_SECRET=... node tools/feed/build.mjs
//
// Options (environment):
//   FEED_REGIONS  comma list of us,eu,kr,tw (default: us)
//   FEED_HOUSES   comma list of house ids to build (default: all twelve; see HOUSES below)
//   FEED_CACHE    folder for the last download and the history (default: tools/feed/cache)
//   FEED_OUT      the Lua file to write (default: Data/Feed.lua)
//   FEED_FIXTURE  a folder of saved API answers to build from instead of the network (tests)
//   FEED_NOW      the time to stamp the build with, unix seconds (tests)

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const REGIONS = (process.env.FEED_REGIONS || "us").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
const CACHE = path.resolve(process.env.FEED_CACHE || path.join(ROOT, "tools", "feed", "cache"));
const OUT = path.resolve(process.env.FEED_OUT || path.join(ROOT, "Data", "Feed.lua"));
const FIXTURE = process.env.FEED_FIXTURE ? path.resolve(process.env.FEED_FIXTURE) : null;
const NOW = process.env.FEED_NOW ? Number(process.env.FEED_NOW) : Math.floor(Date.now() / 1000);

// Forever's auction houses (the same ids in every region; KR and TW only run PvP and Normal)
const HOUSES = {
  110: "PvP Alliance", 113: "PvP Horde", 116: "PvP Neutral",
  111: "Normal Alliance", 114: "Normal Horde", 117: "Normal Neutral",
  119: "Roleplay Alliance", 120: "Roleplay Horde", 121: "Roleplay Neutral",
  123: "Roleplay PvP Alliance", 124: "Roleplay PvP Horde", 125: "Roleplay PvP Neutral",
};
const REGION_IDS = { us: 1, kr: 2, eu: 3, tw: 4 };
const ONLY = process.env.FEED_HOUSES
  ? new Set(process.env.FEED_HOUSES.split(",").map((s) => Number(s.trim())).filter(Boolean))
  : null;
const KEEP_DAYS = 14;         // daily lows kept and shipped
const SALES_DAYS = 7;         // what sold: over the last week
const MAX_GAP = 3 * 3600;     // two downloads further apart than this: no sales are counted between them
// A listing gone by the next download: with more than 2 hours left it was bought (or taken off by its seller,
// which looks the same from outside); with under 30 minutes left it ran out. 30 min - 2 h: can't tell, not counted.
const SOLD_BANDS = new Set(["LONG", "VERY_LONG"]);
const EXPIRED_BANDS = new Set(["SHORT"]);

const log = (...a) => console.log("[feed]", ...a);

// ---------------------------------------------------------------------------------------------------------------
// Blizzard's API
// ---------------------------------------------------------------------------------------------------------------
async function token() {
  const id = process.env.BLIZZARD_CLIENT_ID, secret = process.env.BLIZZARD_CLIENT_SECRET;
  const missing = [!id && "BLIZZARD_CLIENT_ID", !secret && "BLIZZARD_CLIENT_SECRET"].filter(Boolean);
  if (missing.length) throw new Error(`missing: ${missing.join(" and ")} (repository secrets, Settings > Secrets and variables > Actions)`);
  const res = await fetch("https://oauth.battle.net/token", {
    method: "POST",
    headers: {
      Authorization: "Basic " + Buffer.from(`${id}:${secret}`).toString("base64"),
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });
  if (res.status === 401 || res.status === 400) throw new Error(`Battle.net refused the key (HTTP ${res.status}): check the client ID and secret were pasted whole, with no spaces`);
  if (!res.ok) throw new Error(`token: HTTP ${res.status}`);
  return (await res.json()).access_token;
}

async function getJSON(url, auth, tries = 3) {
  for (let i = 1; ; i++) {
    try {
      const res = await fetch(url, { headers: { Authorization: `Bearer ${auth}` } });
      if (res.status === 404) return { body: null, modified: null };
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const modified = res.headers.get("last-modified");
      return { body: await res.json(), modified: modified ? Math.floor(Date.parse(modified) / 1000) : null };
    } catch (e) {
      if (i >= tries) throw new Error(`${url}: ${e.message}`);
      await new Promise((r) => setTimeout(r, 2000 * i));
    }
  }
}

// every listing of one house: [{ id, item, qty, unit, tl }], and the time Blizzard last refreshed it
async function fetchHouse(region, houseId, auth) {
  if (FIXTURE) {
    const file = path.join(FIXTURE, `${region}-${houseId}.json`);
    if (!fs.existsSync(file)) return null;
    const j = JSON.parse(fs.readFileSync(file, "utf8"));
    return { listings: toListings(j.auctions, j.commodities), modified: j.modified || NOW };
  }
  const base = `https://${region}.api.blizzard.com/data/wow/ruleset/2/auctions/${houseId}`;
  const q = `?namespace=dynamic-forever-${region}&locale=en_US`;
  const [items, goods] = await Promise.all([getJSON(base + q, auth), getJSON(`${base}/commodities${q}`, auth)]);
  if (!items.body && !goods.body) return null;
  const modified = Math.max(items.modified || 0, goods.modified || 0) || NOW;
  return { listings: toListings(items.body?.auctions, goods.body?.auctions), modified };
}

function toListings(items, goods) {
  const out = [];
  for (const a of items || []) {
    const qty = a.quantity || 1;
    if (!a.item?.id || !a.buyout) continue; // bid-only listings have no price to go by
    out.push({ id: a.id, item: a.item.id, qty, unit: Math.ceil(a.buyout / qty), tl: a.time_left });
  }
  for (const a of goods || []) {
    if (!a.item?.id || !a.unit_price) continue;
    out.push({ id: a.id, item: a.item.id, qty: a.quantity || 1, unit: a.unit_price, tl: a.time_left });
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------
// Cache: the last download of each house (to see what vanished) and the rolling history
// ---------------------------------------------------------------------------------------------------------------
const readJSON = (file, fallback) => {
  try { return JSON.parse(fs.readFileSync(file, "utf8")); } catch { return fallback; }
};
const writeJSON = (file, data) => {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data));
};
const utcDay = (t) => Math.floor(t / 86400);

// ---------------------------------------------------------------------------------------------------------------
// One house: now, what sold since the last download, the history
// ---------------------------------------------------------------------------------------------------------------
function processHouse(region, houseId, got, hist) {
  const t = got.modified;
  const day = utcDay(t);
  // now, per item
  const now = new Map(); // item -> { p, q, n }
  const byId = new Map();
  for (const l of got.listings) {
    byId.set(l.id, l);
    const e = now.get(l.item);
    if (!e) now.set(l.item, { p: l.unit, q: l.qty, n: 1 });
    else {
      if (l.unit < e.p) e.p = l.unit;
      e.q += l.qty;
      e.n += 1;
    }
  }
  // what vanished since the last download
  const prevFile = path.join(CACHE, `prev-${region}-${houseId}.json`);
  const prev = readJSON(prevFile, null);
  const sales = new Map(); // item -> { sold, value, expired }
  const add = (item, k, v) => {
    let s = sales.get(item);
    if (!s) { s = { sold: 0, value: 0, expired: 0 }; sales.set(item, s); }
    s[k] += v;
  };
  let watched = 0;
  if (prev && prev.t < t && t - prev.t <= MAX_GAP) {
    watched = t - prev.t;
    for (const [idText, [item, qty, unit, tl]] of Object.entries(prev.a)) {
      const cur = byId.get(Number(idText));
      if (!cur) {
        if (SOLD_BANDS.has(tl)) { add(item, "sold", qty); add(item, "value", qty * unit); }
        else if (EXPIRED_BANDS.has(tl)) add(item, "expired", qty);
      } else if (cur.qty < qty) {
        // part of a stack of goods bought
        add(item, "sold", qty - cur.qty);
        add(item, "value", (qty - cur.qty) * unit);
      }
    }
  } else if (prev && prev.t >= t) {
    log(`${region} ${houseId}: Blizzard hasn't refreshed it since the last run`);
  }
  const a = {};
  for (const l of got.listings) a[l.id] = [l.item, l.qty, l.unit, l.tl];
  if (!prev || prev.t < t) writeJSON(prevFile, { t, a });

  // the history: daily lows, daily sales and how long each day was watched
  const h = hist[houseId] || (hist[houseId] = { items: {}, watched: {} });
  if (watched > 0) h.watched[day] = (h.watched[day] || 0) + watched;
  for (const [item, e] of now) {
    const r = h.items[item] || (h.items[item] = { l: {}, s: {} });
    if (r.l[day] === undefined || e.p < r.l[day]) r.l[day] = e.p;
  }
  for (const [item, s] of sales) {
    const r = h.items[item] || (h.items[item] = { l: {}, s: {} });
    const d = r.s[day] || (r.s[day] = [0, 0, 0]);
    d[0] += s.sold; d[1] += s.value; d[2] += s.expired;
  }
  // forget what's older than the window
  const from = day - KEEP_DAYS + 1;
  for (const d of Object.keys(h.watched)) if (Number(d) < from) delete h.watched[d];
  for (const [item, r] of Object.entries(h.items)) {
    for (const d of Object.keys(r.l)) if (Number(d) < from) delete r.l[d];
    for (const d of Object.keys(r.s)) if (Number(d) < from) delete r.s[d];
    if (!now.has(Number(item)) && Object.keys(r.l).length === 0 && Object.keys(r.s).length === 0) delete h.items[item];
  }
  return { t, now, h, day };
}

// ---------------------------------------------------------------------------------------------------------------
// The Lua file
// ---------------------------------------------------------------------------------------------------------------
const b36 = (n) => (n === undefined || n === null ? "" : Math.round(n).toString(36));

// one house: "item=p,q,n,sold,value,watchedHours,expired,low0..low13;" in base 36; low0 is the oldest day
function encodeHouse(res) {
  const { now, h, day } = res;
  const days = [];
  for (let d = day - KEEP_DAYS + 1; d <= day; d++) days.push(d);
  let watchedSec = 0;
  for (const d of days.slice(-SALES_DAYS)) watchedSec += h.watched[d] || 0;
  const parts = [];
  const ids = Object.keys(h.items).map(Number).sort((x, y) => x - y);
  for (const item of ids) {
    const r = h.items[item];
    const e = now.get(item);
    let sold = 0, value = 0, expired = 0;
    for (const d of days.slice(-SALES_DAYS)) {
      const s = r.s[d];
      if (s) { sold += s[0]; value += s[1]; expired += s[2]; }
    }
    const lows = days.map((d) => b36(r.l[d]));
    parts.push(`${item}=${[e ? b36(e.p) : "", e ? b36(e.q) : "", e ? b36(e.n) : "", b36(sold), b36(value),
      b36(watchedSec / 3600), b36(expired), ...lows].join(",")};`);
  }
  return { text: parts.join(""), firstDay: days[0], items: ids.length, listed: now.size };
}

function luaString(s) {
  // the data has only [0-9a-z=,;]: a plain quoted string is safe
  return `"${s}"`;
}

function writeLua(results) {
  const lines = [
    "-- Generated by tools/feed/build.mjs - do not edit by hand.",
    `-- WoW Forever auction prices from Blizzard's Game Data API, built ${new Date(NOW * 1000).toISOString()}.`,
    "local ADDON, FT = ...",
    "FT.FEED = {",
    "    v = 1,",
    `    built = ${NOW},`,
    `    days = ${KEEP_DAYS},`,
    "    regions = {",
  ];
  for (const [region, houses] of Object.entries(results)) {
    lines.push(`        [${REGION_IDS[region]}] = {`);
    lines.push(`            name = "${region}",`);
    lines.push("            houses = {");
    for (const [houseId, enc] of Object.entries(houses)) {
      lines.push(`                [${houseId}] = { t = ${enc.t}, firstDay = ${enc.firstDay}, data = ${luaString(enc.text)} },`);
    }
    lines.push("            },");
    lines.push("        },");
  }
  lines.push("    },", "}", "");
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, lines.join("\n"));
}

// ---------------------------------------------------------------------------------------------------------------
async function main() {
  fs.mkdirSync(CACHE, { recursive: true });
  const auth = FIXTURE ? null : await token();
  const results = {};
  let total = 0;
  for (const region of REGIONS) {
    if (!REGION_IDS[region]) throw new Error(`unknown region ${region}`);
    const histFile = path.join(CACHE, `history-${region}.json`);
    const hist = readJSON(histFile, {});
    results[region] = {};
    for (const houseId of Object.keys(HOUSES).map(Number).filter((id) => !ONLY || ONLY.has(id))) {
      const got = await fetchHouse(region, houseId, auth);
      if (!got || got.listings.length === 0) continue;
      const res = processHouse(region, houseId, got, hist);
      const enc = encodeHouse(res);
      results[region][houseId] = { ...enc, t: res.t };
      total += got.listings.length;
      log(`${region} ${houseId} ${HOUSES[houseId]}: ${got.listings.length} listings, ${enc.listed} items listed, ${enc.items} in history`);
    }
    writeJSON(histFile, hist);
  }
  if (total === 0) throw new Error("no listings downloaded: nothing written");
  writeLua(results);
  log(`wrote ${path.relative(ROOT, OUT)} (${(fs.statSync(OUT).size / 1024).toFixed(0)} KB)`);
}

main().catch((e) => {
  console.error("[feed] failed:", e.message);
  process.exit(1);
});
