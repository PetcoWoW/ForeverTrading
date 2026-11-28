import pickle, collections
S = pickle.load(open('/tmp/study.pkl','rb'))
mobs = S['mobs']
def g(c): return '%.1fg' % (c/10000)
OPEN = {0, 1}
def brk(lv): return min(60, (lv // 10) * 10)
print("== Open world: best STEADY gold an hour by level band (solo, ~90 kills/h normal, 30 elite, capped by spawns) ==")
by = collections.defaultdict(list)
for m in mobs:
    if m['map'] in OPEN and m['n'] >= 6:            # a spot: at least 6 of it in the world
        by[brk(m['lv'][0])].append(m)
for b in sorted(by):
    print("-- level %d-%d --" % (b, b + 9))
    for m in sorted([m for m in by[b] if not m['rare']], key=lambda m: -m['steadyHour'])[:7]:
        L = m['loot']; tot = m['kill'] or 1
        parts = 'coin %d%% gray %d%% white %d%% market %d%% | jackpot +%s/h' % (100*m['coin']/tot, 100*L.get('gray',0)/tot, 100*L.get('white',0)/tot, 100*L.get('market',0)/tot, g(L.get('jackpot',0)*m['kph']))
        print("  %-28s %-22s lv %2d-%-2d %s n=%3d  %s/kill  %s/h  (%s)" % (m['name'][:28], (m['zone'] or '?')[:22], m['lv'][0], m['lv'][1], 'E' if m['elite'] else ' ', m['n'], g(m['steady']), g(m['steadyHour']), parts))
# gray share overall at 50+
tot = collections.Counter(); 
for m in mobs:
    if m['map'] in OPEN and m['lv'][0] >= 50:
        for k, v in m['loot'].items(): tot[k] += v
        tot['coin'] += m['coin']
s = sum(tot.values()); print("\nWhere a level 50+ open-world kill's value comes from:", {k: '%d%%' % (100*v/s) for k, v in tot.most_common()})
