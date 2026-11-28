# Wolf's farm study: value per kill for every mob, open-world grind spots, dungeon trash, gray drops, and why
# Drops' "Priciest" is bait. Data: cMaNGOS classic-db (loot tables, vendor prices, coin, spawns, respawns; GPL-3.0),
# ForeverDB (Forever's zones and new loot), Wolf's price file (Forever's market).
import pickle, re, sys, os, json, collections, statistics, math
sys.path.insert(0, '/tmp/forever-db/tools')
from lupa import LuaRuntime

T = pickle.load(open('/tmp/cdb.pkl', 'rb'))
def rows(name):
    cols = T[name]['cols']
    for r in T[name]['rows']:
        yield dict(zip(cols, r))

items = {r['entry']: r for r in rows('item_template')}
ctpl = {r['entry']: r for r in rows('creature_template')}
loot = collections.defaultdict(list)
for r in rows('creature_loot_template'): loot[r['entry']].append(r)
ref = collections.defaultdict(list)
for r in rows('reference_loot_template'): ref[r['entry']].append(r)
EV_T = pickle.load(open('/tmp/cdb_events.pkl', 'rb'))
event_guids = set(r[0] for r in EV_T['game_event_creature']['rows'])   # holiday and war-effort spawns
spawns = collections.defaultdict(list)    # npc -> [(map, x, y, respawn)]
for r in rows('creature'):
    if r['guid'] in event_guids: continue
    spawns[r['id']].append((r['map'], r['position_x'], r['position_y'], r['spawntimesecsmin'] or 300))

# ---- Forever's market: the price file of the newest release (median over the realms) --------------------------
feed = open(sys.argv[1]).read()
def dec(s): return int(s, 36) if s else None
px, sold = collections.defaultdict(list), collections.defaultdict(list)
for data in re.findall(r'data = "([^"]*)"', feed):
    for m in re.finditer(r'(\d+)=([^;]*);', data):
        f = m.group(2).split(',')
        p = dec(f[0]) if f and f[0] else None
        if p:
            px[int(m.group(1))].append(p)
            if len(f) > 3 and f[3]: sold[int(m.group(1))].append(dec(f[3]) or 0)
price = {i: statistics.median(v) for i, v in px.items()}
perday = {i: statistics.median(v) for i, v in sold.items()}   # 'sold' = sold over the feed's days? used as a liquidity hint only

# ---- ForeverDB: zones, ranks, Forever's own drops ---------------------------------------------------------------
lua = LuaRuntime(unpack_returned_tuples=True)
for folder in ('ForeverDB', 'ForeverDB_Full'):
    d = os.path.join('/tmp/forever-db', folder)
    for fn in sorted(os.listdir(d)):
        if fn.endswith('.lua'): lua.execute(open(os.path.join(d, fn), encoding='utf-8').read())
G = lua.globals(); D, F = G.ForeverDB, G.ForeverDBFull
def lt(v): return {k: lt(x) for k, x in v.items()} if hasattr(v, 'items') else v
umap = {int(k): lt(v).get(1) for k, v in D.umap.items()}
def zone_of(npc):
    z = F.spz['c%d' % npc] if F.spz else None
    if z is None: return None
    best = max(((len(lt(p) or {}), umap.get(int(m))) for m, p in z.items()), default=(0, None))
    return best[1]

# ---- what a kill is worth (cMaNGOS loot rules) -----------------------------------------------------------------
GROUP_SHARE = 0.95
def worth(i):
    """(value to you, kind): grays/whites and BoP at the vendor; tradeable greens+ at the market (after the cut)
    when it sells, else the vendor"""
    it = items.get(i)
    if not it: return 0, 'none'
    if it['class'] == 12: return 0, 'quest'
    v = it['sellprice'] or 0
    q = it['quality']
    if q == 0: return v, 'gray'
    if q == 1 and i not in price: return v, 'white'
    if it['bonding'] == 1: return v, 'bop'
    p = price.get(i)
    if p:
        return max(v, p * GROUP_SHARE), ('white' if q == 1 else 'market')
    return v, ('white' if q == 1 else 'vendor-only')

memo = {}
def ev(entries, depth=0, key=None):
    """expected value of one roll of a loot template: {kind: copper}"""
    if key is not None and key in memo: return memo[key]
    out = collections.Counter()
    if depth > 6: return out
    groups = collections.defaultdict(list)
    for e in entries:
        ch = e['chanceorquestchance']
        if ch < 0: continue                     # a quest drop
        if e['mincountorref'] < 0:              # a reference: rolled maxcount times
            sub = ev(ref[-e['mincountorref']], depth + 1, ('r', -e['mincountorref']))
            p = (ch or 100) / 100.0
            for k, v in sub.items(): out[k] += v * p * (e['maxcount'] or 1)
            continue
        if e['groupid']:
            groups[e['groupid']].append(e)
            continue
        v, kind = worth(e['item'])
        n = ((e['mincountorref'] or 1) + (e['maxcount'] or 1)) / 2.0
        if kind == 'market' and ch < 5 and v >= 20000: kind = 'jackpot'
        out[kind] += v * n * ch / 100.0
    for g, es in groups.items():
        expl = [e for e in es if e['chanceorquestchance'] > 0]
        eq = [e for e in es if e['chanceorquestchance'] == 0]
        left = max(0.0, 100 - sum(e['chanceorquestchance'] for e in expl))
        for e in es:
            if e['mincountorref'] < 0: continue
            ch = e['chanceorquestchance'] if e['chanceorquestchance'] > 0 else (left / len(eq) if eq else 0)
            v, kind = worth(e['item'])
            n = ((e['mincountorref'] or 1) + (e['maxcount'] or 1)) / 2.0
            if kind == 'market' and ch < 5 and v >= 20000: kind = 'jackpot'
            out[kind] += v * n * ch / 100.0
    if key is not None: memo[key] = out
    return out

# which reference pools are world drops: referenced by many different creatures
ref_users = collections.Counter()
for npc, es in loot.items():
    for e in es:
        if e['mincountorref'] < 0: ref_users[-e['mincountorref']] += 1
pool_items = collections.defaultdict(set)
def walk_ref(r, top, depth=0):
    if depth > 5: return
    for e in ref[r]:
        if e['mincountorref'] < 0: walk_ref(-e['mincountorref'], top, depth + 1)
        else: pool_items[top].add(e['item'])
for r in ref: walk_ref(r, r)
world_items = set()
for r, n in ref_users.items():
    if n >= 15: world_items |= pool_items[r]

OPEN = {0: 'Eastern Kingdoms', 1: 'Kalimdor'}
DUNGEON = {389: 'Ragefire Chasm', 36: 'The Deadmines', 43: 'Wailing Caverns', 33: 'Shadowfang Keep', 48: 'Blackfathom Deeps',
    34: 'The Stockade', 90: 'Gnomeregan', 47: 'Razorfen Kraul', 189: 'Scarlet Monastery', 129: 'Razorfen Downs', 70: 'Uldaman',
    209: "Zul'Farrak", 349: 'Maraudon', 109: 'Sunken Temple', 230: 'Blackrock Depths', 229: 'Blackrock Spire', 429: 'Dire Maul',
    289: 'Scholomance', 329: 'Stratholme'}
BAD_NAME = re.compile(r'(?i)guard|peacekeeper|trigger|\(|dummy|totem|invisible|spirit healer|ward\b|bunny|target')
mobs = []
for npc, c in ctpl.items():
    sp = spawns.get(npc)
    if not sp or c['npcflags'] or c['creaturetype'] == 8 or c['rank'] == 3 or BAD_NAME.search(c['name'] or ''): continue
    if (c['minlevel'] or 0) > 61: continue
    v = ev(loot.get(c['lootid'] or 0, []), key=('c', c['lootid'])) if c['lootid'] else collections.Counter()
    coin = ((c['minlootgold'] or 0) + (c['maxlootgold'] or 0)) / 2.0
    if not v and not coin: continue
    maps = collections.Counter(s[0] for s in sp)
    m = maps.most_common(1)[0][0]
    n_sp = maps[m]
    resp = statistics.median(s[3] for s in sp if s[0] == m)
    elite = c['rank'] in (1, 2)
    kills = 30 if elite else 90                    # kills an hour, solo at level (a rough, steady pace)
    cap = n_sp * 3600 / max(resp, 60)              # what the spawns give an hour
    kph = min(kills, cap)
    total = sum(v.values()) + coin
    steady = total - v.get('jackpot', 0)
    mobs.append(dict(steady=steady, steadyHour=steady * kph, rare=c['rank'] in (2, 4), npc=npc, name=c['name'], lv=(c['minlevel'], c['maxlevel']), elite=elite, map=m, n=n_sp, resp=resp,
        coin=coin, loot=dict(v), kill=total, kph=kph, hour=total * kph, zone=zone_of(npc) or OPEN.get(m) or DUNGEON.get(m)))
pickle.dump(dict(mobs=mobs, world_items=world_items, price=price, perday=perday), open('/tmp/study.pkl', 'wb'))
print('mobs valued:', len(mobs), ' world-drop items:', len(world_items), ' priced items:', len(price))
