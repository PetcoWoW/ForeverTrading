// Every crafting recipe of WoW Forever, from the Blizzard API (namespace static-forever-us), written to
// Data/Recipes.lua for "Best use" (what a material goes into). Run by .github/workflows/recipes.yml.
//   BLIZZARD_CLIENT_ID, BLIZZARD_CLIENT_SECRET   API client
//   OUT                                          where to write (default Data/Recipes.lua)
import { writeFileSync } from "node:fs";

const NS = process.env.NAMESPACE || "static-forever-us";
const OUT = process.env.OUT || "Data/Recipes.lua";
// gathering professions make nothing from materials (Mining's smelting does: it stays)
const SKIP = new Set(["Herbalism", "Skinning", "Fishing"]);

async function token() {
  const id = process.env.BLIZZARD_CLIENT_ID, secret = process.env.BLIZZARD_CLIENT_SECRET;
  if (!id || !secret) throw new Error("BLIZZARD_CLIENT_ID and BLIZZARD_CLIENT_SECRET must be set");
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
async function get(path, tries = 4) {
  for (let i = 0; ; i++) {
    const res = await fetch(`https://us.api.blizzard.com${path}?namespace=${NS}&locale=en_US`,
      { headers: { Authorization: `Bearer ${auth}` } });
    if (res.ok) return res.json();
    if (res.status === 404) return null;
    if (i >= tries) throw new Error(`${path}: HTTP ${res.status}`);
    await new Promise(r => setTimeout(r, 1000 * (i + 1)));
  }
}

// a few at a time: the API allows 100 a second
async function pool(list, n, fn) {
  const out = new Array(list.length);
  let next = 0;
  await Promise.all(Array.from({ length: n }, async () => {
    while (next < list.length) { const k = next++; out[k] = await fn(list[k]); }
  }));
  return out;
}

export function Quantity(q) {
  if (!q) return 1;
  if (typeof q.value === "number") return q.value;
  if (typeof q.minimum === "number") return (q.minimum + (q.maximum ?? q.minimum)) / 2;
  return 1;
}

const index = await get("/data/wow/profession/index");
const wanted = [];
for (const p of index.professions) {
  if (SKIP.has(p.name) || /\[DNT\]|test/i.test(p.name)) continue;
  const prof = await get(`/data/wow/profession/${p.id}`);
  for (const tier of prof?.skill_tiers || []) {
    const t = await get(`/data/wow/profession/${p.id}/skill-tier/${tier.id}`);
    for (const c of t?.categories || []) for (const r of c.recipes || []) wanted.push({ prof: p.id, id: r.id });
  }
}
const seen = new Set();
const unique = wanted.filter(w => !seen.has(w.id) && seen.add(w.id));
const recipes = await pool(unique, 8, async w => {
  const r = await get(`/data/wow/recipe/${w.id}`);
  if (!r?.crafted_item?.id || !r.reagents?.length) return null; // enchantments make no item
  return { id: r.id, prof: w.prof, name: r.name, out: r.crafted_item.id, qty: Quantity(r.crafted_quantity),
    reagents: r.reagents.map(x => [x.reagent.id, x.quantity]) };
});
const list = recipes.filter(Boolean).sort((a, b) => a.id - b.id);
const lua = s => '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';

// The recipe items (Recipe: / Pattern: / Plans: / Formula: / Schematic: / Manual: / Design:), matched to the recipes by
// name: the craft window says if a recipe is on the auction house, and a recipe without one is learned from a trainer.
// A failed search writes no table (the addon then says nothing about where a recipe comes from).
export function RecipeName(itemName) {
  const m = /^(recipe|pattern|plans|formula|schematic|manual|design|technique)\s*:\s*(.+)$/i.exec(String(itemName || "").trim());
  return m ? m[2].trim().toLowerCase() : null;
}
async function recipeItems() {
  const out = new Map();
  for (let page = 1, pages = 1; page <= pages && page <= 20; page++) {
    const res = await fetch(`https://us.api.blizzard.com/data/wow/search/item?namespace=${NS}&locale=en_US&item_class.id=9&orderby=id&_pageSize=1000&_page=${page}`,
      { headers: { Authorization: `Bearer ${auth}` } });
    if (!res.ok) throw new Error(`item search: HTTP ${res.status}`);
    const j = await res.json();
    pages = j.pageCount || 1;
    for (const r of j.results || []) {
      const d = r.data || {};
      const name = typeof d.name === "string" ? d.name : (d.name?.en_US || "");
      const key = RecipeName(name);
      if (!key || !d.id) continue;
      if (!out.has(key)) out.set(key, []);
      out.get(key).push(d.id);
    }
  }
  return out;
}
let items = null;
try { items = await recipeItems(); } catch (e) { console.log(`recipe items skipped: ${e.message}`); }
// a search that found next to nothing is a broken search, not a world of trainer recipes
if (items && items.size < 50) { console.log(`recipe items skipped: only ${items.size} found`); items = null; }
const names = new Set(list.map(r => r.name.toLowerCase()));
const itemLines = items ? [...items].filter(([k]) => names.has(k)).sort(([a], [b]) => a < b ? -1 : 1)
  .map(([k, ids]) => `[${lua(k)}]={${ids.sort((a, b) => a - b).join(",")}},`) : null;
const lines = list.map(r => `[${r.id}]={${r.prof},${r.out},${r.qty},${lua(r.name)},${r.reagents.flat().join(",")}},`);
writeFileSync(OUT, `-- Wolf of Booty Bay: every crafting recipe of WoW Forever, from the Blizzard API (${NS}).
-- Generated by tools/recipes/build.mjs - don't edit by hand.
-- [recipeID] = { profession, item made, how many, name, material, count, material, count, ... }
local ADDON, FT = ...
FT.RECIPE_DB = {
${lines.join("\n")}
}
${itemLines ? `-- the recipe items that teach them, by recipe name (lower case): [name] = { itemID, ... }; none = from a trainer
FT.RECIPE_ITEMS = {
${itemLines.join("\n")}
}
` : ""}`);
console.log(`${list.length} recipes (of ${unique.length} listed), ${itemLines ? itemLines.length : "no"} with recipe items -> ${OUT}`);
