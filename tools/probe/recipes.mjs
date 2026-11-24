// One-off: does the Blizzard API serve profession/recipe data for WoW Forever? Prints status codes only.
const id = process.env.BLIZZARD_CLIENT_ID, secret = process.env.BLIZZARD_CLIENT_SECRET;
const tok = await fetch("https://oauth.battle.net/token", {
  method: "POST",
  headers: { Authorization: "Basic " + Buffer.from(`${id}:${secret}`).toString("base64"),
    "Content-Type": "application/x-www-form-urlencoded" },
  body: "grant_type=client_credentials",
}).then(r => r.json()).then(j => j.access_token);
const nss = ["static-forever-us", "static-us", "static-classic1x-us", "static-classic-us"];
const paths = ["/data/wow/profession/index", "/data/wow/profession/164", "/data/wow/recipe/2661", "/data/wow/item/2840"];
for (const ns of nss) for (const p of paths) {
  const r = await fetch(`https://us.api.blizzard.com${p}?namespace=${ns}&locale=en_US`, { headers: { Authorization: `Bearer ${tok}` } });
  let extra = "";
  if (r.ok) {
    const j = await r.json();
    extra = JSON.stringify(j).slice(0, 300);
  }
  console.log(ns, p, r.status, extra);
}
