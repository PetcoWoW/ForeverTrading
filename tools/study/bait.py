import pickle, re, collections
S = pickle.load(open('/tmp/study.pkl','rb')); T = pickle.load(open('/tmp/cdb.pkl','rb'))
price, world = S['price'], S['world_items']
items = {r[0]: dict(zip(T['item_template']['cols'], r)) for r in T['item_template']['rows']}
ct = {r[0]: dict(zip(T['creature_template']['cols'], r)) for r in T['creature_template']['rows']}
src = open('/home/claude/forevertrading/Data/Sources.lua').read()
body = src[src.index('FT.SRC = {'):src.index('FT.SRC_N = {')]
SRC = {int(m.group(1)): dict(p.split('=',1) for p in m.group(2).split(';') if '=' in p) for m in re.finditer(r'\[(\d+)\]="([^"]*)"', body)}
nb = src[src.index('FT.SRC_N = {'):src.index('FT.SRC_O = {')]
NPC = {int(m.group(1)): m.group(2).split('|') for m in re.finditer(r'\[(\d+)\]="([^"]*)"', nb)}
RAID = {"Molten Core","Blackwing Lair","Onyxia's Lair","Zul'Gurub","Ruins of Ahn'Qiraj","Temple of Ahn'Qiraj","Naxxramas","Alterac Valley","Warsong Gulch","Arathi Basin"}
STAPLE = {(7,5),(7,6),(7,7),(7,9)}
rows = []
for i, s in SRC.items():
    p = price.get(i)
    if not p or p < 10000 or 'd' not in s: continue
    it = items.get(i, {})
    if (it.get('class'), it.get('subclass')) in STAPLE: continue
    best = None; ndrop = 0
    for e in s['d'].split(','):
        n, c = e.split(':'); n, c = int(n), int(c or 0); ndrop += 1
        v = NPC.get(n)
        if not v: continue
        if len(v) > 4 and v[4] == '3': continue
        if any(z in RAID for z in v[1].split(',')): continue
        if not best or c > best[1]: best = (n, c, v)
    if not best: continue
    rows.append((p, i, best, s, ndrop))
rows.sort(key=lambda r: -r[0])
print("Wolf's Drops today: %d items; the top 40 by price:" % len(rows))
cls = collections.Counter(); out = []
for p, i, (n, c, v), s, nd in rows[:40]:
    it = items.get(i, {})
    lv = v[2]; top = int((lv or '0').split('-')[-1] or 0)
    why = []
    if i in world or 'w' in s: why.append('WORLD')
    if top >= 62: why.append('UNKILLABLE-LV')
    if c == 0: why.append('RATE?')
    elif c >= 500 and (i in world or 'w' in s): why.append('RATE-SUSPECT')
    if it.get('bonding') == 1: why.append('BOP')
    if not why: why.append('ok')
    for w in why: cls[w] += 1
    print("%7dg  %-34s q%s  %-26s %-18s lv %-6s %5s  %s" % (p//10000, (it.get('name') or str(i))[:34], it.get('quality'), v[0][:26], (v[1] or '')[:18], lv, ('%.2f%%' % (c/100)) if c else '?', ' '.join(why)))
print(cls)
# over the whole list
allc = collections.Counter()
for p, i, (n, c, v), s, nd in rows:
    w = (i in world or 'w' in s)
    allc['world' if w else 'specific'] += 1
print('whole list:', allc)
