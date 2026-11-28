# Reads what the study needs from cMaNGOS classic-db (GPL-3.0) into one pickle.
import sys, pickle, time
sys.path.insert(0, '/tmp/forever-db/tools')
from sqldump import read_tables
t0=time.time()
T = read_tables(['/tmp/cdb/Full_DB/ClassicDB_1_12_1_z2815.sql.gz'],
    {'item_template','creature_template','creature_loot_template','reference_loot_template','creature'})
out={}
for name,tb in T.items():
    cols=tb['cols']; print(name, len(tb['rows']), cols[:40] if name!='creature' else cols)
    out[name]=tb
pickle.dump(out, open('/tmp/cdb.pkl','wb'))
print('took', round(time.time()-t0), 's')
