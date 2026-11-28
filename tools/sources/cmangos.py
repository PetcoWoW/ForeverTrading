"""What Wolf learns from cMaNGOS classic-db (github.com/cmangos/classic-db, GPL-3.0) - v0.56, the farm study.

The 1.12 server database has what ForeverDB doesn't carry: every loot table with its shared pools (world drops),
vendor prices, the coin mobs carry, every spawn point with its respawn, and which spawns only come with an event.
From it, for build.py:
  world_items()   items in a world-drop pool (rolled by 15+ kinds of mob): { item: (lowest level, ~1 in N kills) }
  mob(n)          a mob's farm facts: (spawns, respawn secs, floor copper a kill, { item: expected a kill }) or None
  spawns_in(map)  the spawn points of an instance: [(npc, x, y, z)]
Forever changes things here and there: ForeverDB (and players' recordings) stay first for what drops where.
"""
import collections, os, sys

class CMaNGOS:
    def __init__(self, dump, forever_db):
        sys.path.insert(0, os.path.join(forever_db, "tools"))
        from sqldump import read_tables
        t = read_tables([dump], {"item_template", "creature_template", "creature_loot_template",
                                 "reference_loot_template", "creature", "game_event_creature"})
        def rows(name):
            cols = t[name]["cols"]
            for r in t[name]["rows"]:
                yield dict(zip(cols, r))
        self.items = {r["entry"]: r for r in rows("item_template")}
        self.ctpl = {r["entry"]: r for r in rows("creature_template")}
        self.loot = collections.defaultdict(list)
        for r in rows("creature_loot_template"):
            self.loot[r["entry"]].append(r)
        self.ref = collections.defaultdict(list)
        for r in rows("reference_loot_template"):
            self.ref[r["entry"]].append(r)
        event = set(r["guid"] for r in rows("game_event_creature"))
        self.sp = collections.defaultdict(list)          # npc -> [(map, x, y, z, respawn)]
        for r in rows("creature"):
            if r["guid"] not in event:
                self.sp[r["id"]].append((r["map"], r["position_x"], r["position_y"], r["position_z"], r["spawntimesecsmin"] or 300))
        # the world pools: references rolled by many kinds of mob
        users = collections.defaultdict(set)
        for npc, c in self.ctpl.items():
            for e in self.loot.get(c["lootid"] or 0, []):
                if e["mincountorref"] < 0:
                    users[-e["mincountorref"]].add(npc)
        self.world_refs = set(r for r, u in users.items() if len(u) >= 15)
        self._users = users
        self._memo = {}

    # expected count of each item a roll of a loot template (world pools apart: they're not a farm). cMaNGOS rules:
    # ungrouped entries roll on their own; a group gives one of its entries (explicit chances first, the rest share
    # what's left equally); a reference (negative mincount) rolls another template maxcount times - in a group too
    def counts(self, entries, depth=0, key=None, skip_world=True):
        if key is not None and key in self._memo:
            return self._memo[key]
        out = collections.Counter()
        if depth > 6:
            return out
        def take(e, p):
            if p <= 0:
                return
            if e["mincountorref"] < 0:
                r = -e["mincountorref"]
                if skip_world and r in self.world_refs:
                    return
                sub = self.counts(self.ref[r], depth + 1, ("r", r, skip_world), skip_world)
                k = p * (e["maxcount"] or 1)
                for i, v in sub.items():
                    out[i] += v * k
            else:
                n = ((e["mincountorref"] or 1) + (e["maxcount"] or 1)) / 2.0
                out[e["item"]] += n * p
        groups = collections.defaultdict(list)
        for e in entries:
            if e["chanceorquestchance"] < 0:
                continue                                    # a quest drop
            if e["groupid"]:
                groups[e["groupid"]].append(e)
            else:
                take(e, (e["chanceorquestchance"] or (100 if e["mincountorref"] < 0 else 0)) / 100.0)
        for g, es in groups.items():
            expl = [e for e in es if e["chanceorquestchance"] > 0]
            eq = [e for e in es if e["chanceorquestchance"] == 0]
            left = max(0.0, 100 - sum(e["chanceorquestchance"] for e in expl))
            for e in es:
                ch = e["chanceorquestchance"] if e["chanceorquestchance"] > 0 else (left / len(eq) if eq else 0)
                take(e, ch / 100.0)
        if key is not None:
            self._memo[key] = out
        return out

    def world_items(self):
        """{ item: (lowest level of the mobs that can drop it, ~1 in N kills on a typical one of them) }"""
        pool = collections.defaultdict(set)          # world ref -> items in it (nested pools too)
        def walk(r, top, depth=0):
            if depth > 6:
                return
            for e in self.ref[r]:
                if e["mincountorref"] < 0:
                    walk(-e["mincountorref"], top, depth + 1)
                else:
                    pool[top].add(e["item"])
        for r in self.world_refs:
            walk(r, r)
        per = collections.defaultdict(list)           # item -> [(chance a kill, level)]
        done = set()
        for n, c in self.ctpl.items():
            lid = c["lootid"] or 0
            if not lid or not self.sp.get(n):
                continue
            refs = [-e["mincountorref"] for e in self.loot.get(lid, []) if e["mincountorref"] < 0 and -e["mincountorref"] in self.world_refs]
            if not refs:
                continue
            full = self.counts(self.loot.get(lid, []), key=("full", lid), skip_world=False)
            for r in refs:
                for i in pool[r]:
                    if full.get(i, 0) > 0 and (n, i) not in done:
                        done.add((n, i))
                        per[i].append((full[i], c["minlevel"] or 1))
        out = {}
        for i, xs in per.items():
            ps = sorted(p for p, _ in xs)
            mid = ps[len(ps) // 2]
            out[i] = (min(lv for _, lv in xs), max(1, int(round(1 / mid))))
        return out

    def mob(self, n, priced):
        """(spawns, respawn, floor copper a kill, { item: expected a kill } of what trades) or None: not spawned
        outside events (summoned, event-only or a test mob). priced: the items that trade (their value is worked out
        in game at today's prices); everything else counts at the vendor."""
        c = self.ctpl.get(n)
        sp = self.sp.get(n)
        if not c or not sp:
            return None
        maps = collections.Counter(s[0] for s in sp)
        m = maps.most_common(1)[0][0]
        resp = sorted(s[4] for s in sp if s[0] == m)[len([1 for s in sp if s[0] == m]) // 2]
        coin = ((c["minlootgold"] or 0) + (c["maxlootgold"] or 0)) / 2.0
        floor, trade = coin, {}
        if c["lootid"]:
            for i, k in self.counts(self.loot.get(c["lootid"], []), key=("c", c["lootid"])).items():
                it = self.items.get(i)
                if not it or it["class"] == 12:
                    continue
                if i in priced and it["bonding"] != 1:
                    trade[i] = k
                else:
                    floor += k * (it["sellprice"] or 0)
        return maps[m], int(resp), int(round(floor)), trade

    def spawns_in(self, map_id):
        return [(n, s[1], s[2], s[3]) for n, ss in self.sp.items() for s in ss if s[0] == map_id]
