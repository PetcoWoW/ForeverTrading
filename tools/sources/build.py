#!/usr/bin/env python3
"""Where every item comes from, for Wolf: Data/Sources.lua.

Built from ForeverDB (github.com/foreverfraddons/forever-db, GPL-3.0; its Drop Tables counts CC BY-SA 4.0), Wolf's
recipe list (Data/Recipes.lua) and Wolf's own hand table (tools/sources/hand.json: Forever knowledge the databases
don't carry, each line with where it came from). Writes the gap list (tools/sources/gaps.txt): items sold on the
auction house that Wolf can't place - the build fails on them unless they're in hand.json.

  python3 tools/sources/build.py <forever-db checkout> [Data/Feed.lua with prices, for the gap list]
"""
import json, os, re, sys, collections
from lupa import LuaRuntime, lua_type

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FDB = sys.argv[1] if len(sys.argv) > 1 else "/tmp/forever-db"
FEED = sys.argv[2] if len(sys.argv) > 2 else None
OUT = os.path.join(ROOT, "Data", "Sources.lua")
GAPS = os.path.join(ROOT, "tools", "sources", "gaps.txt")
HAND = os.path.join(ROOT, "tools", "sources", "hand.json")
TOP = 4  # sources kept per kind and item

lua = LuaRuntime(unpack_returned_tuples=True)
def load(folder, files):
    for f in files:
        p = os.path.join(FDB, folder, f)
        if os.path.exists(p):
            lua.execute(open(p, encoding="utf-8").read())
load("ForeverDB", sorted(f for f in os.listdir(os.path.join(FDB, "ForeverDB")) if f.endswith(".lua")))
load("ForeverDB_Full", sorted(f for f in os.listdir(os.path.join(FDB, "ForeverDB_Full")) if f.endswith(".lua")))
G = lua.globals()
D, F = G.ForeverDB, G.ForeverDBFull

def T(x):
    """a Lua table as a Python dict (one level); anything else as is"""
    return dict(x.items()) if lua_type(x) == "table" else x

def pairs_list(x):
    """ForeverDB's flat {id, chance, id, chance, ...}"""
    t = T(x) or {}
    vals = [t[k] for k in sorted(t)]
    return [(vals[i], vals[i + 1]) for i in range(0, len(vals) - 1, 2)]

item = {}
for k, v in D.item.items():
    v = T(v)
    item[int(k)] = v
def item_name(i):
    v = item.get(i)
    return v.get(1) if v else None

# ---- the hand table: Forever knowledge the databases don't have -------------------------------------------
hand = json.load(open(HAND)) if os.path.exists(HAND) else {}

umap = {int(k): T(v).get(1) for k, v in D.umap.items()}
# the instances (their map ids): ForeverDB's zone positions (spz) stop at the door, its spawns (spw) don't
INSTANCE = {30: "Alterac Valley", 33: "Shadowfang Keep", 34: "The Stockade", 36: "The Deadmines", 43: "Wailing Caverns",
    47: "Razorfen Kraul", 48: "Blackfathom Deeps", 70: "Uldaman", 90: "Gnomeregan", 109: "Sunken Temple",
    129: "Razorfen Downs", 189: "Scarlet Monastery", 209: "Zul'Farrak", 229: "Blackrock Spire", 230: "Blackrock Depths",
    249: "Onyxia's Lair", 289: "Scholomance", 309: "Zul'Gurub", 329: "Stratholme", 349: "Maraudon", 369: "Deeprun Tram",
    389: "Ragefire Chasm", 409: "Molten Core", 429: "Dire Maul", 469: "Blackwing Lair", 489: "Warsong Gulch",
    509: "Ruins of Ahn'Qiraj", 529: "Arathi Basin", 531: "Temple of Ahn'Qiraj", 533: "Naxxramas"}
def zones(key, n=2):
    """the zones a creature (c) or object (o) is found in, most spots first (an instance by its spawns)"""
    z = F.spz[key] if F.spz else None
    if z is None:
        sp = D.spw[key] if D.spw else None
        out = []
        for _, pt in (sp.items() if sp is not None else []):
            name = INSTANCE.get(T(pt).get(1))
            if name and name not in out:
                out.append(name)
        hz = hand.get("npcZones", {}).get(key[1:]) if key.startswith("c") else None
        if not out and hz:
            out.append(hz)
        return out[:n]
    counts = []
    for m, pts in z.items():
        name = umap.get(int(m))
        if not name:
            continue
        counts.append((len(T(pts) or {}), name))
    counts.sort(key=lambda x: -x[0])
    out = []
    for _, name in counts:
        if name not in out:
            out.append(name)
        if len(out) >= n:
            break
    return out

nfac = {int(k): v for k, v in D.nfac.items()}
MF = {int(k): v for k, v in hand.get("merchantsFavor", {}).items()}   # vendor npc -> camp

# ---- Wolf's recipes: what's crafted, from what ----------------------------------------------------------
crafted, mats_of, recipe_rows = set(), set(), []
for line in open(os.path.join(ROOT, "Data", "Recipes.lua"), encoding="utf-8"):
    m = re.match(r'\[(\d+)\]=\{(\d+),(\d+),(\d+),"((?:[^"\\]|\\.)*)"((?:,\d+)*)\}', line)
    if not m:
        continue
    out = int(m.group(3))
    mats = [int(x) for x in m.group(6).split(",") if x][0::2]
    recipe_rows.append((int(m.group(1)), out, mats))
    crafted.add(out)
    mats_of.update(mats)
recipe_items = set()
for m in re.finditer(r'=\{([\d,]+)\},', open(os.path.join(ROOT, "Data", "Recipes.lua"), encoding="utf-8").read().split("FT.RECIPE_ITEMS", 1)[-1]):
    recipe_items.update(int(x) for x in m.group(1).split(",") if x)

# recipes that can't exist in Forever: an item they make or use isn't in the game (Season of Discovery leftovers)
def real(i):
    v = item.get(i)
    return bool(v and v.get(1))
dead = sorted(r for r, out, mats in recipe_rows if not real(out) or any(not real(x) for x in mats))

# ---- which items get a line ----------------------------------------------------------------------------
ah = set()
if FEED and os.path.exists(FEED):
    for m in re.finditer(r'data = "([^"]*)"', open(FEED, encoding="utf-8").read()):
        for k in re.findall(r'(?:^|;)(\d+)=', m.group(1)):
            i = int(k)
            if i < 400000:
                ah.add(i)
want = (ah | crafted | mats_of | recipe_items) & set(item)

npcs, objs, quests = {}, {}, {}
def npc_ref(n):
    if n not in npcs:
        v = T(D.npc[n]) or {}
        lv = ""
        if v.get(3):
            lv = str(v[3]) if v.get(3) == v.get(4) or not v.get(4) else "%s-%s" % (v[3], v[4])
        rank = v.get(5)
        npcs[n] = "|".join([v.get(1) or "?", ",".join(zones("c%d" % n)), lv, nfac.get(n, "")] + ([str(rank)] if rank else []))
    return n
# a chest, box or crate (not a node you gather): Wolf shows these only when nothing else gives the item
CHESTY = re.compile(r"(?i)chest|box|crate|cache|strongbox|footlocker|coffer|trunk|basket|barrel|sack|\bbag\b|locker|stash|bundle|cask|urn\b|reliquary|container|treasure|supplies|pile of")
def obj_ref(o):
    if o not in objs:
        v = T(D.obj[o]) or {}
        name = v.get(1) or "?"
        objs[o] = "|".join([name, ",".join(zones("o%d" % o, 3))] + (["c"] if CHESTY.search(name) else []))
    return o

# a vendor that's somewhere in the world: test and unused NPCs (no spawn anywhere) sell nothing
def vendor_real(n):
    v = T(D.npc[n]) or {}
    name = v.get(1) or ""
    if not name or re.search(r"\[UNUSED\]|TEST|Chest$|Repair Bot|Reagent Bot", name):
        return False
    return bool(zones("c%d" % n)) or n in MF
def quest_ref(q):
    if q not in quests:
        v = T(D.quest[q]) or {}
        quests[q] = "%s|%s" % ((v.get(1) or "?").replace("|", "/"), v.get(2) or "")
    return q

def spawned(n):
    """a creature somewhere in the world (a zone, an instance): summoned dummies and test NPCs aren't"""
    return bool(zones("c%d" % n))

def best(rows, ref, fake_ok=False):
    """the best sources: known chances first, highest first; unknown rates (0) after. Creatures that spawn
    nowhere (an engineer's target dummy) only when nothing else gives it"""
    rows = [(s, c) for s, c in rows if s]
    if ref is npc_ref:
        real_rows = [(s, c) for s, c in rows if spawned(s)]
        rows = real_rows or (rows if fake_ok else [])
    rows.sort(key=lambda r: (r[1] == 0, -r[1]))
    return ["%d:%d" % (ref(s), c) for s, c in rows[:TOP]]

lines, kinds = {}, collections.Counter()
for i in sorted(want):
    parts = []
    d = best(pairs_list(D.drop[i]), npc_ref)
    if F.drop and F.drop[i] is not None:  # the uncapped list, when the capped one is empty
        d = d or best(pairs_list(F.drop[i]), npc_ref)
    if d: parts.append("d=" + ",".join(d))
    s = best(pairs_list(D.skin[i]), npc_ref)
    if s: parts.append("s=" + ",".join(s))
    o = best(pairs_list(D.odrop[i]), obj_ref)
    if o: parts.append("o=" + ",".join(o))
    c = [(a, b) for a, b in pairs_list(D.idrop[i]) if real(a)]
    c.sort(key=lambda r: -r[1])
    if c: parts.append("i=" + ",".join("%d:%d" % r for r in c[:TOP]))
    vend = [int(x) for x in (T(D.vend[i]) or {}).values()]
    if vend:
        # Merchant's Favor first (its own line), then the vendor of your side
        mf = [n for n in vend if n in MF]
        rest = [n for n in vend if n not in MF and vendor_real(n)]
        if mf: parts.append("f=" + ",".join(str(npc_ref(n)) for n in mf[:2]))
        if rest: parts.append("v=" + ",".join(str(npc_ref(n)) for n in rest[:6]))
    r = [int(x) for x in (T(D.rew[i]) or {}).values()]
    if r: parts.append("q=" + ",".join(str(quest_ref(q)) for q in r[:2]))
    w = D.world[i]
    if w is not None: parts.append("w=%d" % w)
    if not parts:
        # nothing else gives it: the creatures that spawn nowhere, rather than no line
        d = best(pairs_list(D.drop[i]), npc_ref, True)
        if not d and F.drop and F.drop[i] is not None:
            d = best(pairs_list(F.drop[i]), npc_ref, True)
        if d: parts.append("d=" + ",".join(d))
    if parts:
        lines[i] = ";".join(parts)
        for p in parts: kinds[p[0]] += 1

# ---- Wolf's own notes: hand items, then the rules (by name and item class) for what nothing else places -----
notes = {}
for k, v in hand.get("items", {}).items():
    if int(k) in item:
        notes[int(k)] = v["text"]
rules = hand.get("rules", [])
for i in sorted((ah | mats_of | recipe_items) & set(item)):
    if i in notes or i in lines or i in crafted:
        continue
    v = item[i]
    name, cls = v.get(1) or "", "%s.%s" % (v.get(5), v.get(6))
    for r in rules:
        if "class" in r and not (cls == r["class"] or cls.startswith(r["class"] + ".")):
            continue
        if "name" in r and not re.search(r["name"], name):
            continue
        notes[i] = r["text"]
        break

# ---- the gap list: sold on the auction house, and Wolf can't say where it comes from ----------------------
placed = set(lines) | crafted | set(notes)
gaps = sorted(i for i in ah if i in item and real(i) and i not in placed)

# ---- item lists by name (events and PvP): the id that trades, else the first real one ----------------------
by_name = collections.defaultdict(list)
for i, v in item.items():
    if v.get(1):
        by_name[v[1].lower()].append(i)
lists = {}
for key, spec in hand.get("lists", {}).items():
    if key.startswith("_"):
        continue
    ids = []
    for nm in spec["names"]:
        cands = sorted(by_name.get(nm.lower(), []))
        traded = [i for i in cands if i in ah]
        pick = (traded or cands)[:1]
        if not pick:
            print("list %s: no item named %r" % (key, nm))
        ids.extend(pick)
    lists[key] = ids

# ---- events: Forever's calendar (ForeverDB's holiday table), the next 400 days ---------------------------------
import datetime
from zoneinfo import ZoneInfo
PT = ZoneInfo("America/Los_Angeles")  # the realms' clock (US)
def unpack(p):
    mi, h, d, mo, y = p & 63, (p >> 6) & 31, ((p >> 14) & 63) + 1, ((p >> 20) & 15) + 1, ((p >> 24) & 31) + 2000
    return y, mo, d, h, mi
now = datetime.datetime.now(PT)
until = now + datetime.timedelta(days=400)
EVENT = {  # ForeverDB holiday id -> (key, Wolf's name, where)
    263: ("faire", "Darkmoon Faire", "Elwynn Forest"), 264: ("faire", "Darkmoon Faire", "Mulgore"),
    1840: ("bg", "Call to Arms: Darkspear Islands", ""), 1841: ("bg", "Call to Arms: Arathi Basin", ""),
    1842: ("bg", "Call to Arms: Warsong Gulch", ""), 141: ("veil", "Feast of Winter Veil", ""),
    327: ("lunar", "Lunar Festival", ""), 335: ("love", "Love is in the Air", ""), 181: ("noble", "Noblegarden", ""),
    341: ("midsummer", "Midsummer Fire Festival", ""), 324: ("hallow", "Hallow's End", ""), 321: ("harvest", "Harvest Festival", ""),
    201: ("children", "Children's Week", ""),
}
events = []
for hid, (key, name, where) in EVENT.items():
    v = T(D.hol[hid])
    if not v:
        continue
    durs = [int(x) for x in (T(v.get(7)) or {}).values()]
    dates = [unpack(int(x)) for x in (T(v.get(8)) or {}).values()]
    hours = durs[0] if durs else 168
    starts = []
    for (y, mo, d, h, mi) in dates:
        if mo > 12 or d > 31:
            continue
        if y >= 2031:  # a yearly template: every year on that day
            for yy in range(now.year - 1, now.year + 2):
                try: starts.append(datetime.datetime(yy, mo, d, h, mi, tzinfo=PT))
                except ValueError: pass
        else:
            try: starts.append(datetime.datetime(y, mo, d, h, mi, tzinfo=PT))
            except ValueError: pass
    if len(durs) >= 2 and starts:  # on for durs[0] hours, then off for durs[1]: a rotation
        period = datetime.timedelta(hours=durs[0] + durs[1])
        t = min(starts)
        while t < until:
            starts.append(t)
            t += period
    for t in sorted(set(starts)):
        end = t + datetime.timedelta(hours=hours)
        if end >= now - datetime.timedelta(days=1) and t <= until:
            events.append((int(t.timestamp()), hours, key, name, where))
events.sort()

def lstr(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
out = []
out.append("-- Where every item comes from (generated by tools/sources/build.py - don't edit by hand).")
out.append("-- From ForeverDB (github.com/foreverfraddons/forever-db, GPL-3.0; drop counts from Drop Tables,")
out.append("-- github.com/valcheffnet/DropTables, CC BY-SA 4.0) and Wolf's own Forever notes (tools/sources/hand.json).")
out.append("-- FT.SRC[item] = \"kind=...;kind=...\": d drops (npc:chance per 10000), s skinning, o objects and nodes,")
out.append("-- i containers (item:chance), f Merchant's Favor vendors, v vendors, q quest rewards, w world drop from level.")
out.append("-- FT.SRC_N[npc] = \"name|zones|levels|A/H|rank\" (rank: 1 elite, 2 rare elite, 3 boss, 4 rare); FT.SRC_O[object] = \"name|zones\";")
out.append("-- FT.SRC_Q[quest] = \"title|level\".")
out.append("local ADDON, FT = ...")
out.append("FT.SRC_BUILT = %s" % lstr(str(T(D.meta).get("build"))))
out.append("FT.SRC = {")
out.extend("[%d]=%s," % (i, lstr(s)) for i, s in sorted(lines.items()))
out.append("}")
out.append("FT.SRC_N = {")
out.extend("[%d]=%s," % (n, lstr(s)) for n, s in sorted(npcs.items()))
out.append("}")
out.append("FT.SRC_O = {")
out.extend("[%d]=%s," % (n, lstr(s)) for n, s in sorted(objs.items()))
out.append("}")
out.append("FT.SRC_Q = {")
out.extend("[%d]=%s," % (n, lstr(s)) for n, s in sorted(quests.items()))
out.append("}")
out.append("-- Wolf's own notes (tools/sources/hand.json): Forever knowledge, and what no database places")
out.append("FT.SRC_H = {")
out.extend("[%d]=%s," % (i, lstr(t)) for i, t in sorted(notes.items()))
out.append("}")
for key, ids in sorted(lists.items()):
    out.append("FT.SRC_LIST_%s = {%s}" % (key.upper(), ",".join(str(i) for i in ids)))
# the PvP study (v0.51): { id, roles, conf, note } in rank order (its names are the "pvp" list's, in order)
pvp_ids = lists.get("pvp", [])
out.append("FT.SRC_PVP = {")
for n, x in enumerate([x for x in hand.get("pvpStudy", {}).get("items", [])]):
    if n < len(pvp_ids):
        out.append("{%d,%s,%s,%s}," % (pvp_ids[n], lstr(x["roles"]), lstr(x["conf"]), lstr(x["note"])))
out.append("}")
out.append("-- Forever's calendar: { start (unix), hours, kind, name, where }")
out.append("FT.SRC_EVENTS = {")
out.extend("{%d,%d,%s,%s,%s}," % (t, h, lstr(k), lstr(n), lstr(w)) for t, h, k, n, w in events)
out.append("}")
out.append("-- recipes that can't be made in Forever: an item they make or use isn't in the game")
out.append("FT.SRC_DEAD = {" + ",".join("[%d]=true" % r for r in dead) + "}")
out.append("-- Merchant's Favor vendors: npc -> \"A\" (Three Corners, Redridge) or \"H\" (west of the Crossroads, the Barrens)")
out.append("FT.SRC_MF = {" + ",".join("[%d]=%s" % (n, lstr(v)) for n, v in sorted(MF.items())) + "}")
open(OUT, "w", encoding="utf-8").write("\n".join(out) + "\n")

os.makedirs(os.path.dirname(GAPS), exist_ok=True)
with open(GAPS, "w", encoding="utf-8") as g:
    g.write("# Sold on the auction house, no source in ForeverDB, Wolf's recipes or hand.json: %d\n" % len(gaps))
    for i in gaps:
        v = item[i]
        g.write("%d\t%s\tclass %s.%s\n" % (i, v.get(1), v.get(5), v.get(6)))
print("%d notes; %d items placed (%s), %d creatures, %d objects, %d quests, %d dead recipes, %d gaps -> %s (%d KB)" % (
    len(notes), len(lines), dict(kinds), len(npcs), len(objs), len(quests), len(dead), len(gaps), OUT, os.path.getsize(OUT) // 1024))


# ---- the dungeons (v0.55): what a full clear drops on average, from every mob in it ----------------------
# Data/Dungeons.lua: per 5-man dungeon, each item's expected count a clear (thousandths) - all of it and the trash
# only - and the coin. Wolf prices them in game with today's market (or what a vendor pays).
DUNGEONS = {  # map: (name, where the door is, minutes for a full clear of every wing - a rough guide)
    389: ("Ragefire Chasm", "Orgrimmar", 20), 36: ("The Deadmines", "Westfall", 40), 43: ("Wailing Caverns", "The Barrens", 45),
    33: ("Shadowfang Keep", "Silverpine Forest", 35), 48: ("Blackfathom Deeps", "Ashenvale", 40), 34: ("The Stockade", "Stormwind", 25),
    90: ("Gnomeregan", "Dun Morogh", 60), 47: ("Razorfen Kraul", "The Barrens", 45), 189: ("Scarlet Monastery", "Tirisfal Glades", 90),
    129: ("Razorfen Downs", "The Barrens", 45), 70: ("Uldaman", "Badlands", 60), 209: ("Zul'Farrak", "Tanaris", 50),
    349: ("Maraudon", "Desolace", 75), 109: ("Sunken Temple", "Swamp of Sorrows", 60), 230: ("Blackrock Depths", "Blackrock Mountain", 120),
    229: ("Blackrock Spire", "Blackrock Mountain", 90), 429: ("Dire Maul", "Feralas", 120), 289: ("Scholomance", "Western Plaguelands", 75),
    329: ("Stratholme", "Eastern Plaguelands", 90),
}
GD = F.gold if F.gold is not None else D.gold
gold = {int(k): T(v) for k, v in GD.items()} if GD is not None else {}
# coin a kill when no kill was counted: the median of counted mobs of that level and kind (normal / elite)
by = collections.defaultdict(list)
for n, g in gold.items():
    v = T(D.npc[n]) or {}
    if g.get(1) and v.get(3):
        by[(min(int(v[3]), 63), 1 if (v.get(5) or 0) in (1, 2) else 0)].append(g[1])
def coin_guess(lv, elite):
    for d in range(0, 6):
        for l2 in (lv - d, lv + d):
            xs = by.get((l2, elite)) or (by.get((l2, 0)) and [x * 2 for x in by[(l2, 0)]] if elite else None)
            if xs:
                xs = sorted(xs)
                return xs[len(xs) // 2]
    return 0
enc_names = collections.defaultdict(set)
for _, e in D.enc.items():
    e = T(e)
    if e.get(2):
        enc_names[int(e[2])].add(e.get(1))
# every creature's spawns, by map
spawns = collections.defaultdict(dict)   # map -> npc -> count
SP = D.spw
for k, v in SP.items():
    k = str(k)
    if not k.startswith("c"):
        continue
    n = int(k[1:])
    for _, pt in v.items():
        pt = T(pt)
        m = pt.get(1)
        if m in DUNGEONS:
            spawns[m][n] = spawns[m].get(n, 0) + (len(pt) - 1) // 2
want_npcs = set(n for m in spawns.values() for n in m)
loot = collections.defaultdict(list)     # npc -> [(item, chance per 10000)]
DROP = F.drop if F.drop is not None else D.drop
for i, rows in DROP.items():
    i = int(i)
    if not real(i):
        continue
    for npc, chance in pairs_list(rows):
        if npc in want_npcs and item[i].get(5) != 12:   # quest items sell for nothing
            loot[npc].append((i, chance))
dng = []
for m, (name, door, minutes) in sorted(DUNGEONS.items(), key=lambda x: x[1][0]):
    allx, trash, unknown = collections.Counter(), collections.Counter(), set()
    coin = coin_t = mobs = bosses = 0
    lvs = []
    for n, cnt in spawns[m].items():
        v = T(D.npc[n]) or {}
        if not loot.get(n) and n not in gold:
            continue                     # no loot, no coin: a friendly or a decoration
        # a boss: in the encounter list, or one of a kind with a blue-or-better drop at 5% or more (a boss's table)
        boss = v.get(1) in enc_names[m] or (cnt == 1 and any(chance >= 500 and (item.get(i, {}).get(2) or 0) >= 3
                                                             for i, chance in loot.get(n, [])))
        mobs += cnt
        bosses += 1 if boss else 0
        if v.get(3):
            lvs += [int(v[3])] * cnt
        g = gold.get(n, {}).get(1) or coin_guess(int(v.get(3) or 1), 1 if (v.get(5) or 0) in (1, 2) else 0)
        coin += g * cnt
        if not boss:
            coin_t += g * cnt
        for i, chance in loot.get(n, []):
            if chance <= 0:
                unknown.add(i)
                continue
            e = cnt * chance / 10000.0
            allx[i] += e
            if not boss:
                trash[i] += e
    if not mobs:
        continue
    lvs.sort()
    lv = "%d-%d" % (lvs[len(lvs) // 10], lvs[(len(lvs) * 9) // 10]) if lvs else ""
    def enc(c):
        top = [(i, e) for i, e in c.most_common() if e >= 0.005][:110]
        return ",".join("%d:%d" % (i, max(1, round(e * 1000))) for i, e in top)
    dng.append("{n=%s,door=%s,lv=%s,min=%d,mobs=%d,bosses=%d,coin=%d,coinT=%d,items=%s,trash=%s,u=%s}," % (
        lstr(name), lstr(door), lstr(lv), minutes, mobs, bosses, coin, coin_t, lstr(enc(allx)), lstr(enc(trash)),
        lstr(",".join(str(i) for i in sorted(unknown)[:60]))))
DOUT = os.path.join(ROOT, "Data", "Dungeons.lua")
open(DOUT, "w", encoding="utf-8").write("\n".join([
    "-- What a full clear of each 5-man dungeon drops on average (generated by tools/sources/build.py - don't edit by hand).",
    "-- From ForeverDB (spawns, loot tables, coin counts; GPL-3.0, Drop Tables counts CC BY-SA 4.0). items/trash:",
    "-- \"item:thousandths of one a clear\" (trash leaves the bosses out); coin in copper; u: drops of unknown rate;",
    "-- min: a rough full clear of every wing, for a guide - Wolf's sessions measure the real one.",
    "local ADDON, FT = ...",
    "FT.DNG = {"] + dng + ["}"]) + "\n")
print("%d dungeons -> %s (%d KB)" % (len(dng), DOUT, os.path.getsize(DOUT) // 1024))
