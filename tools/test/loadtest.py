# Load the addon in the fake WoW, log in, click through everything; print every error.
import sys, os, re
import lupa.lua51 as L51
root = sys.argv[1]
feed = sys.argv[2] if len(sys.argv) > 2 else None
lua = L51.LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'wowmock.lua')).read())
G = lua.globals()
toc = [l.strip().replace('\\', '/') for l in open(os.path.join(root, 'WolfOfBootyBay.toc')) if l.strip() and not l.startswith('#')]
ns = lua.eval('{}')
loader = lua.eval('''function(src, name, ns)
  local f, e = loadstring(src, "@" .. name)
  if not f then mock.err("load " .. name, e) return end
  mock.call("run " .. name, f, "WolfOfBootyBay", ns)
end''')
def load_all(db_lua=None):
    if db_lua: lua.execute(db_lua)
    for f in toc:
        path = os.path.join(root, f)
        if f == 'Data/Feed.lua' and feed: path = feed
        loader(open(path, encoding='utf-8').read(), f, ns)
    return ns
lua.execute('''
Auctionator = {
  Constants = { SCAN_DAY_0 = time({ year = 2020, month = 1, day = 1, hour = 0 }) },
  Database = { db = { ["2770"] = { m = 1000, h = { ["2518"] = 1100, ["2519"] = 1050 }, l = { ["2518"] = 1000 }, a = { ["2518"] = 5 } } },
    SetPrice = function() end },
  EventBus = { Register = function(_, listener, names) mock.atrListener = listener end },
  FullScan = { Events = { ScanStart = "fs_start", ScanComplete = "fs_done", ScanFailed = "fs_fail" } },
  IncrementalScan = { Events = { ScanStart = "is_start", ScanComplete = "is_done", ScanFailed = "is_fail" } },
  Search = { GroupResultsForDB = function() end },
}
''')
load_all()
lua.execute('''
mock.fire("ADDON_LOADED", "WolfOfBootyBay")
mock.fire("PLAYER_LOGIN")
mock.fire("PLAYER_ENTERING_WORLD", true, false)
mock.run(70, 0.25)
''')
FT = ns
script = r'''
local FT = ...
local function step(name, fn) mock.call("step " .. name, fn) end
step("slash", function() SlashCmdList["WOLFOFBOOTYBAY"]("") end)
mock.run(1)
for _, tab in ipairs({ "market", "signals", "portfolio", "sell", "settings", "craft" }) do
  step("tab " .. tab, function() FT.Show(tab) end)
  mock.run(1)
end
for _, v in ipairs({ "make", "craft", "farm", "HOUSES", "sell" }) do
  step("money view " .. v, function() FT.Show("signals"); FT.Tabs.signals.SetView(v) end)
  mock.run(0.5)
end
for _, v in ipairs({ "portfolio", "sell", "chars", "journal" }) do
  step("portfolio view " .. v, function() FT.Show("portfolio"); FT.Tabs.portfolio.SetView(v) end)
  mock.run(0.5)
end
step("settings all", function() FT.S.showAdvanced = true; FT.Show("settings"); FT.Tabs.settings.Layout(); FT.S.showAdvanced = false; FT.Tabs.settings.Layout() end)
mock.run(1)
step("overview moves", function()
  FT.Show("market"); FT.Tabs.market.ShowOverview(); FT.Tabs.market.FillMoves()
  local ids = {}
  for id in pairs(FT.Feed.House().items) do ids[#ids + 1] = id; if #ids >= 8 then break end end
  local syms = {}
  for _, id in ipairs(ids) do syms[#syms + 1] = FT.Symbol(id) end
  print("symbols: " .. table.concat(syms, " "))
end)
step("craft for profit", function()
  local t0 = os.clock()
  FT.Craft.ProfitCrafts()
end)
mock.run(40)
step("craft list", function()
  local list = FT.Craft.ProfitCrafts()
  print("profitable crafts:", list and #list, list and list[1] and (list[1].recipe.name .. " +" .. math.floor(list[1].profit) .. " x" .. string.format("%.1f", list[1].perDay) .. "/day"))
  if list and list[1] then FT.ShowCraft(list[1].recipe) end
  FT.Show("signals"); FT.Tabs.signals.SetView("craft")
end)
mock.run(1)
step("disenchant", function()
  FT.db.chars[FT.charKey].enchanting = 300
  -- mock items: class 4 when id % 5 == 0, quality 1 from GetItemInfo; make some green gear
  local real = GetItemInfo
  GetItemInfo = function(id) local a, b, q, l = real(id) if type(id) == "number" and id % 5 == 0 then return a, b, 2, 45 + (id % 15) end return real(id) end
  local n, v = 0, nil
  for id in pairs(FT.Feed.House().items) do
    if id % 5 == 0 then local x = FT.Enchant.Value(id) if x then n = n + 1; v = v or x end end
  end
  local deals = FT.Enchant.Deals()
  print("disenchantable priced:", n, "first value:", v and math.floor(v), "DE deals:", #deals, deals[1] and math.floor(deals[1].profit))
  FT.Show("signals"); FT.Tabs.signals.SetView("make")
  GameTooltip:ClearLines(); mock.tdp(GameTooltip, { id = deals[1] and deals[1].id or 10 })
  print("tooltip gear: " .. table.concat(GameTooltip.__lines or {}, " // "))
  GetItemInfo = real
end)
mock.run(1)
step("open item", function() FT.OpenItem(12363) end)
mock.run(1)
step("best use", function() FT.ShowBestUse(12359) end)
step("toast", function() FT.S.alertPopup = true; FT.Toast(12363, "test", "TO THE MOON", "up"); FT.S.alertPopup = false end)
mock.run(10)
step("signals", function()
  local n, kinds = 0, {}
  local fh = FT.Feed.House()
  for id in pairs(fh and fh.items or {}) do
    local s = FT.An.Stats(id)
    local k = FT.An.SellSignal(s); kinds[k] = (kinds[k] or 0) + 1
    local b = FT.An.BuySignal(s); kinds["buy:" .. b] = (kinds["buy:" .. b] or 0) + 1
    n = n + 1
    if n >= 3000 then break end
  end
  local out = {}
  for k, v in pairs(kinds) do out[#out + 1] = k .. "=" .. v end
  table.sort(out)
  print("signals over " .. n .. " items: " .. table.concat(out, " "))
end)
step("AH open", function() mock.fire("AUCTION_HOUSE_SHOW") end)
mock.run(3)
step("auctionator scan", function()
  local res = {}
  for i = 1, 50 do res[#res + 1] = { itemKey = { itemID = 3000 + (i % 30), itemLevel = i, itemSuffix = 0 }, minPrice = 500 + i, totalQuantity = 3 } end
  mock.atrListener:ReceiveEvent(Auctionator.IncrementalScan.Events.ScanStart)
  mock.atrListener:ReceiveEvent(Auctionator.IncrementalScan.Events.ScanComplete, res)
end)
mock.run(5)
step("auctionator start scan", function()
  Auctionator.State = { IncrementalScanFrameRef = { InitiateScan = function() mock.atrStarted = true end } }
  print("our button starts Auctionator's scan:", FT.Atr.StartScan(function() print("fallback ran") end), mock.atrStarted)
end)
mock.run(3)
step("auctionator daily", function()
  local d = FT.Atr.Daily(2770)
  local n = 0; for _ in pairs(d or {}) do n = n + 1 end
  print("auctionator days for 2770:", n)
end)
step("AH close", function() mock.fire("AUCTION_HOUSE_CLOSED") end)
mock.run(3)
step("tour", function() if FT.Tour and FT.Tour.Start then FT.Tour.Start() end end)
mock.run(2)
step("our summary scan", function()
  local sum = FT.Scanner.NewSummary()
  local res = {}
  for i = 1, 400 do res[#res + 1] = { itemKey = { itemID = 2770 + i, itemLevel = 0, itemSuffix = 0 }, minPrice = 1000 + i * 37, totalQuantity = 5 + i % 9 } end
  FT.Scanner.AddBrowse(sum, res)
  mock.ahOpen = true
  FT.Scanner.SaveSummary(sum, time(), "full", function(n) print("summary scan saved", n) end)
end)
mock.run(5)
step("our full scan with sellers", function()
  local acc = FT.Scanner.NewAcc()
  for i = 1, 300 do
    local id = 2770 + (i % 60)
    FT.Scanner.Add(acc, id, 20, 20 * (5000 + id), (i % 3 == 0) and "Bigwhale" or ("Seller" .. i))
  end
  FT.Scanner.SaveFull(acc, time(), "full", function(n) print("full scan saved", n) end)
end)
mock.run(8)
step("makers", function()
  local list = FT.Whales.Makers()
  print("market makers:", #list, list[1] and list[1].n, list[1] and list[1].value)
  local w = FT.Whales.Of(2771)
  print("whale of 2771:", w and w.n, w and w.s)
end)
step("views shown", function()
  FT.Show("signals"); FT.Tabs.signals.SetView("farm")
  print("farm view list rows set:", FT.Tabs.signals.SetView ~= nil)
end)
step("feed parse", function()
  local e = FT.Feed.House().items[25]
  print("feed item 25: price", e.p, "qty", e.q, "auctions", e.n, "sold7d", e.sold, "rate/day", FT.Feed.Rate(25) and FT.Feed.Rate(25).perDay)
  local d = FT.Feed.Daily(25)
  local days = {}; for k in pairs(d) do days[#days + 1] = k end; table.sort(days)
  print("feed item 25 days (ours):", days[1], "..", days[#days], "today", FT.Day(), "count", #days)
  print("house", FT.Feed.HouseID(), "neutral", FT.Feed.HouseID("neutral"), "cut here", FT.Cut and FT.Cut(FT.house), "cut neutral", FT.Cut and FT.Cut("neutral"))
end)
step("tooltips", function()
  local fh = FT.Feed.House()
  local ids = {}
  for id in pairs(fh.items) do ids[#ids + 1] = id; if #ids >= 300 then break end end
  ids[#ids + 1] = 4234; ids[#ids + 1] = 12359
  local t0 = os.clock()
  for _, id in ipairs(ids) do GameTooltip:ClearLines(); mock.tdp(GameTooltip, { id = id }) end
  local first = (os.clock() - t0) * 1000
  t0 = os.clock()
  for r = 1, 20 do for _, id in ipairs(ids) do GameTooltip:ClearLines(); mock.tdp(GameTooltip, { id = id }) end end
  local again = (os.clock() - t0) * 1000 / 20
  print(string.format("tooltips: %d items, first %.1f ms (%.2f each), refresh %.2f ms (%.3f each)", #ids, first, first / #ids, again, again / #ids))
  GameTooltip:ClearLines(); mock.tdp(GameTooltip, { id = 4234 })
  print("tooltip Heavy Leather: " .. table.concat(GameTooltip.__lines or {}, " // "))
  mock.combat = true
  GameTooltip:ClearLines(); mock.tdp(GameTooltip, { id = 99999 })
  print("tooltip in combat, never seen: " .. #(GameTooltip.__lines or {}) .. " lines")
  mock.combat = false
end)
step("auctionator last scan", function()
  AUCTIONATOR_SAVEDVARS = { TimeOfLastBrowseScan = time() - 600 }
  local db = Auctionator.Database.db
  local day = tostring(FT.Day(time() - 600))
  for i = 1, 200 do db[tostring(5000 + i)] = { m = 1000 + i, h = { [day] = 1000 + i }, a = { [day] = 3 } } end
  print("atr debug:", FT.Atr.On(), FT.Atr.LastScanTime(), FT.Atr.DB() ~= nil, FT.house, FT.Hist.HasScan(time() - 600))
  print("took from Auctionator:", FT.Atr.TakeLatest(true))
  FT.UpdateAHPill()
end)
mock.run(5)
step("timing", function()
  local fh = FT.Feed.House()
  local ids = {}
  for id in pairs(fh.items) do ids[#ids + 1] = id end
  local t0 = os.clock()
  for i = 1, math.min(#ids, 2000) do FT.Hist.Daily(ids[i], 60) end
  local t1 = os.clock()
  for i = 1, math.min(#ids, 2000) do FT.An.Behavior(FT.Hist.Daily(ids[i], 60), ids[i]) end
  local t2 = os.clock()
  print(string.format("Hist.Daily %.2f ms/item, Behavior+Daily %.2f ms/item, %d items in feed", (t1 - t0) / 2000 * 1000, (t2 - t1) / 2000 * 1000, #ids))
  t0 = os.clock()
  for i = 1, 50 do FT.Craft.BestUse(ids[i]) end
  FT.Craft.BestUse(4234)
  print(string.format("BestUse(Heavy Leather) %.1f ms", (os.clock() - t0) * 1000))
end)
step("learn kinds", function() FT.An.LearnKinds(true) end)
mock.run(30)
step("learned", function()
  local l = FT.db.learned and FT.db.learned[FT.houseKey]
  local n = 0; for _ in pairs(l and l.kinds or {}) do n = n + 1 end
  print("kinds learned:", n)
end)
step("logout", function() mock.fire("PLAYER_LOGOUT") end)
'''
lua.execute('return function(...) ' + script + ' end')(FT)
# a /reload: the same saved data, every file again
print("=== reload with saved data ===")
ns = lua.eval('{}')
load_all()
lua.execute('''
mock.fire("ADDON_LOADED", "WolfOfBootyBay")
mock.fire("PLAYER_LOGIN")
mock.fire("PLAYER_ENTERING_WORLD", false, true)
mock.run(70, 0.25)
''')
lua.execute('return function(...) ' + script + ' end')(ns)
errs = list(lua.eval('mock.errors').values())
seen = set()
for e in errs:
    key = e.split('\n')[0]
    if key in seen: continue
    seen.add(key)
    print('ERROR', e[:1500]); print('---')
print(len(errs), 'errors,', len(seen), 'distinct')
prints = list(lua.eval('mock.prints').values())
print('chat lines:', len(prints))
for p in prints[:25]: print('  chat:', re.sub(r'\|c\w{8}|\|r|\|H[^|]*\|h|\|h', '', p)[:200])
