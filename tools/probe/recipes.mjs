// One-off: walk WoW Forever's profession data in the Blizzard API. Prints shapes and counts only.
const id = process.env.BLIZZARD_CLIENT_ID, secret = process.env.BLIZZARD_CLIENT_SECRET;
const tok = await fetch("https://oauth.battle.net/token", {
  method: "POST",
  headers: { Authorization: "Basic " + Buffer.from(`${id}:${secret}`).toString("base64"),
    "Content-Type": "application/x-www-form-urlencoded" },
  body: "grant_type=client_credentials",
}).then(r => r.json()).then(j => j.access_token);
const get = async p => {
  const r = await fetch(`https://us.api.blizzard.com${p}${p.includes("?") ? "&" : "?"}namespace=static-forever-us&locale=en_US`, { headers: { Authorization: `Bearer ${tok}` } });
  return r.ok ? r.json() : { status: r.status };
};
const idx = await get("/data/wow/profession/index");
console.log("PROFS", JSON.stringify(idx.professions.map(p => [p.id, p.name])));
const bs = await get("/data/wow/profession/164");
console.log("BS keys", Object.keys(bs), JSON.stringify(bs.skill_tiers));
const tierId = bs.skill_tiers?.[0]?.id;
if (tierId) {
  const tier = await get(`/data/wow/profession/164/skill-tier/${tierId}`);
  console.log("TIER keys", Object.keys(tier), "cats", tier.categories?.length,
    "recipes", tier.categories?.reduce((n, c) => n + c.recipes.length, 0));
  const rid = tier.categories?.[0]?.recipes?.[0]?.id;
  console.log("FIRST CAT", JSON.stringify(tier.categories?.[0]).slice(0, 400));
  if (rid) console.log("RECIPE", JSON.stringify(await get(`/data/wow/recipe/${rid}`)).slice(0, 1200));
}
