// The Forever study's raw data: every item WoW Forever added (or brought from Season of Discovery) that Classic
// didn't have, from the Blizzard API, with what it is, what it does, and which recipes make it or use it.
// Writes tools/study/forever-items.json. Not shipped in the addon: it's for reading (and for tables built from it).
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";

const NS = process.env.NAMESPACE || "static-forever-us";
const NEW_FROM = 24400; // Classic's items end around 24,300; everything above came later
const OUT = "tools/study/forever-items.json";

async function token() {
  const id = process.env.BLIZZARD_CLIENT_ID, secret = process.env.BLIZZARD_CLIENT_SECRET;
  if (!id || !secret) throw new Error("BLIZZARD_CLIENT_ID / BLIZZARD_CLIENT_SECRET missing");
  const res = await fetch("https://oauth.battle.net/token", {
    method: "POST",
    headers: { Authorization: "Basic " + Buffer.from(`${id}:${secret}`).toString("base64"),
      "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=client_credentials",
  });
  if (!res.ok) throw new Error(`token: HTTP ${res.status}`);
  return (await res.json()).access_token;
}
const auth = await token();
async function api(url, tries = 4) {
  for (let i = 0; i < tries; i++) {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${auth}` } });
    if (res.ok) return res.json();
    if (res.status === 404) return null;
    await new Promise(r => setTimeout(r, 500 * (i + 1)));
  }
  return null;
}
const en = v => (v && typeof v === "object") ? (v.en_US ?? v.display_string ?? "") : (v ?? "");

// 1. which recipes make and use what (from the recipe list this robot just built)
const made = {}, used = {};
const PROF = { 164: "Blacksmithing", 165: "Leatherworking", 171: "Alchemy", 197: "Tailoring", 202: "Engineering",
  333: "Enchanting", 185: "Cooking", 186: "Mining", 129: "First Aid", 755: "Jewelcrafting", 356: "Fishing" };
for (const line of readFileSync("Data/Recipes.lua", "utf8").split("\n")) {
  const m = /^\[(\d+)\]=\{(\d+),(\d+),(\d+),"((?:[^"\\]|\\.)*)"((?:,\d+)*)\}/.exec(line);
  if (!m) continue;
  const prof = PROF[m[2]] || m[2], out = +m[3], name = m[5];
  const mats = (m[6] || "").split(",").filter(Boolean).map(Number);
  (made[out] ||= []).push({ prof, recipe: name, mats: mats.reduce((a, x, i) => (i % 2 ? a[a.length - 1].push(x) : a.push([x]), a), []) });
  for (let i = 0; i < mats.length; i += 2) (used[mats[i]] ||= []).push({ prof, makes: out, recipe: name, n: mats[i + 1] });
}

// 2. every newer item, class by class (one search stops at 1,000)
const found = new Map();
for (let cls = 0; cls <= 17; cls++) {
  for (let page = 1, pages = 1; page <= pages && page <= 30; page++) {
    const j = await api(`https://us.api.blizzard.com/data/wow/search/item?namespace=${NS}&locale=en_US&item_class.id=${cls}&id=[${NEW_FROM},]&orderby=id&_pageSize=1000&_page=${page}`);
    if (!j) break;
    pages = j.pageCount || 1;
    for (const r of j.results || []) {
      const d = r.data || {};
      if (d.id >= NEW_FROM) found.set(d.id, d);
    }
  }
}
// and any newer id the recipes mention that the search missed
for (const id of new Set([...Object.keys(made), ...Object.keys(used)].map(Number)))
  if (id >= NEW_FROM && !found.has(id)) found.set(id, { id });
console.log(`newer items: ${found.size}`);

// 3. the details (what it does) for everything that isn't plain gear; gear keeps the search's summary
const GEAR = new Set([2, 4]); // weapons, armor
const ids = [...found.keys()].sort((a, b) => a - b);
const items = [];
let next = 0;
async function worker() {
  while (next < ids.length) {
    const id = ids[next++];
    const s = found.get(id);
    const crafted = made[id] || used[id];
    let d = s;
    if (!s.name || !GEAR.has(s.item_class?.id) || crafted) d = (await api(`https://us.api.blizzard.com/data/wow/item/${id}?namespace=${NS}&locale=en_US`)) || s;
    const p = d.preview_item || {};
    items.push({
      id, name: en(d.name), quality: en(d.quality?.name) || d.quality?.type, class: en(d.item_class?.name),
      sub: en(d.item_subclass?.name), level: d.level, req: d.required_level, slot: en(d.inventory_type?.name),
      buy: d.purchase_price, sell: d.sell_price, bind: en(p.binding?.name),
      spells: (p.spells || []).map(x => en(x.description)).filter(Boolean),
      stats: (p.stats || []).map(x => en(x.display?.display_string)).filter(Boolean),
      text: en(d.description) || en(p.description) || undefined,
      unique: en(p.unique_equipped) || undefined,
      madeBy: made[id], usedIn: used[id],
    });
  }
}
await Promise.all(Array.from({ length: 8 }, worker));
items.sort((a, b) => a.id - b.id);
mkdirSync("tools/study", { recursive: true });
writeFileSync(OUT, JSON.stringify({ built: new Date().toISOString(), namespace: NS, from: NEW_FROM, items }, null, 0)
  .replace(/\},\{"id"/g, '},\n{"id"'));
console.log(`${items.length} items -> ${OUT}`);
