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

umap = {int(k): T(v).get(1) for k, v in D.umap.items()}
def zones(key, n=2):
    """the zones a creature (c) or object (o) is found in, most spots first"""
    z = F.spz[key] if F.spz else None
    if z is None:
        return []
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

# ---- the hand table: Forever knowledge the databases don't have -------------------------------------------
hand = json.load(open(HAND)) if os.path.exists(HAND) else {}
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
        npcs[n] = "|".join([v.get(1) or "?", ",".join(zones("c%d" % n)), lv, nfac.get(n, "")])
    return n
def obj_ref(o):
    if o not in objs:
        v = T(D.obj[o]) or {}
        objs[o] = "|".join([v.get(1) or "?", ",".join(zones("o%d" % o, 3))])
    return o
def quest_ref(q):
    if q not in quests:
        v = T(D.quest[q]) or {}
        quests[q] = "%s|%s" % ((v.get(1) or "?").replace("|", "/"), v.get(2) or "")
    return q

def best(rows, ref):
    """the best sources: known chances first, highest first; unknown rates (0) after"""
    rows = [(s, c) for s, c in rows if s]
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
        rest = [n for n in vend if n not in MF]
        if mf: parts.append("f=" + ",".join(str(npc_ref(n)) for n in mf[:2]))
        if rest: parts.append("v=" + ",".join(str(npc_ref(n)) for n in rest[:6]))
    r = [int(x) for x in (T(D.rew[i]) or {}).values()]
    if r: parts.append("q=" + ",".join(str(quest_ref(q)) for q in r[:2]))
    w = D.world[i]
    if w is not None: parts.append("w=%d" % w)
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

def lstr(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
out = []
out.append("-- Where every item comes from (generated by tools/sources/build.py - don't edit by hand).")
out.append("-- From ForeverDB (github.com/foreverfraddons/forever-db, GPL-3.0; drop counts from Drop Tables,")
out.append("-- github.com/valcheffnet/DropTables, CC BY-SA 4.0) and Wolf's own Forever notes (tools/sources/hand.json).")
out.append("-- FT.SRC[item] = \"kind=...;kind=...\": d drops (npc:chance per 10000), s skinning, o objects and nodes,")
out.append("-- i containers (item:chance), f Merchant's Favor vendors, v vendors, q quest rewards, w world drop from level.")
out.append("-- FT.SRC_N[npc] = \"name|zones|levels|A/H\"; FT.SRC_O[object] = \"name|zones\"; FT.SRC_Q[quest] = \"title|level\".")
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
