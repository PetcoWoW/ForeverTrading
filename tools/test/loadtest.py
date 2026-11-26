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
# WOLF_LOOK=dark: the dark look (the default is classic)
if os.environ.get('WOLF_LOOK'):
    lua.execute('WolfOfBootyBayDB = { settings = { look = "%s" } }' % os.environ['WOLF_LOOK'])
load_all()
lua.execute('''
mock.fire("ADDON_LOADED", "WolfOfBootyBay")
mock.fire("PLAYER_LOGIN")
mock.fire("PLAYER_ENTERING_WORLD", true, false)

mock.run(200, 0.25)
''')
FT = ns
script = r'''
local FT = ...
local function step(name, fn) mock.call("step " .. name, fn) end
step("slash", function() SlashCmdList["WOLFOFBOOTYBAY"]("") end)
mock.run(1)
for _, tab in ipairs({ "market", "signals", "radar", "portfolio", "sessions", "sell", "settings", "craft" }) do
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
  for id in pairs(FT.Feed.House().raw) do ids[#ids + 1] = id; if #ids >= 8 then break end end
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
  local n, v = 0, nil
  for id in pairs(FT.Feed.House().raw) do
    if id % 5 == 0 then local x = FT.Enchant.Value(id) if x then n = n + 1; v = v or x end end
  end
  FT.Enchant.Deals() -- worked out in the background now
  mock.run(20)
  local deals = FT.Enchant.Deals()
  print("disenchantable priced:", n, "first value:", v and math.floor(v), "DE deals:", #deals, deals[1] and math.floor(deals[1].profit))
  FT.Show("signals"); FT.Tabs.signals.SetView("make")
  GameTooltip:ClearLines(); mock.tdp(GameTooltip, { id = deals[1] and deals[1].id or 10 })
  print("tooltip gear: " .. table.concat(GameTooltip.__lines or {}, " // "))
end)
mock.run(1)
-- every "To Auctionator" button, clicked (Make gold's once called a function before it was declared)
step("to auctionator buttons", function()
  FT.Show("signals"); FT.Tabs.signals.SetView("make")
  local n = 0
  for _, f in ipairs(mock.frames) do
    local t = f.label and f.label.GetText and f.label:GetText()
    if t == "To Auctionator" then n = n + 1; mock.click(f) end
  end
  print("to auctionator buttons clicked:", n)
end)
mock.run(1)
step("session", function()
  FT.Session.Start()
  mock.run(120)
  mock.fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:10620::::::::60:::::|h[Thorium Ore]|h|rx3.")
  mock.fire("CHAT_MSG_LOOT", "You receive loot: |cff1eff00|Hitem:12363::::::::60:::::|h[Arcane Crystal]|h|r.")
  mock.fire("CHAT_MSG_LOOT", "Jelly receives loot: |cffffffff|Hitem:10620::::::::60:::::|h[Thorium Ore]|h|r.")
  mock.fire("CHAT_MSG_MONEY", "You loot 1 Gold, 20 Silver")
  mock.run(600, 0.5)
  -- many kinds of loot: the panel scrolls, a row's hover shows then and now, the corner adds rows
  for _, id in ipairs({ 2770, 2771, 2772, 2775, 2776, 3858, 7911, 2838, 7912, 12365, 12364, 12361, 99999901 }) do
    mock.fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:" .. id .. "::::::::60:::::|h[Ore " .. id .. "]|h|r.")
  end
  FT.UpdateHUD()
  local hud = _G["WolfOfBootyBaySession"]
  if hud then
    hud:GetScript("OnMouseWheel")(hud, -1)
    hud:GetScript("OnMouseWheel")(hud, -5)
    local row = hud.rows[1]
    if row and row.item then row:GetScript("OnEnter")(row) end
    print("panel rows:", hud.total, "offset:", hud.offset, "just looted:", hud.just:GetText() or "")
  end
  local sum = FT.Session.Summary()
  print(string.format("session: %d items, worth %d, per hour %s, money %d, %ds, no price %d", #sum.items, sum.worth, tostring(sum.perHour and math.floor(sum.perHour)), sum.money, sum.secs, sum.unpriced or 0))
  print("value check: tooltip price", FT.Price(10620), "session unit", (FT.Session.UnitValue(10620)), "from", FT.PriceFrom(10620))
  FT.Session.Pause(); mock.run(60); FT.Session.Pause()
  FT.ShowMenu(UIParent)
  local mb = _G["WolfOfBootyBayMinimapButton"]
  if mb then mock.click(mb, "RightButton"); mock.click(mb, "LeftButton") end
  FT.Show("portfolio"); FT.Tabs.portfolio.SetView("sessions")
  FT.Session.Stop()
  print("saved sessions:", #FT.Session.List(), FT.Session.List()[1].name)
  FT.Tabs.portfolio.SetView("sessions")
end)
-- a saved session opened: what was found, then and now
step("session details", function()
  FT.Show("sessions")
  local list = FT.Session.List()
  if list[1] then FT.Tabs.sessions.Toggle(list[1]) end
  print("session found:", list[1] and list[1].found and next(list[1].found) and "prices kept" or "none")
  -- right-click: the menu, the rename box, delete
  if list[1] then
    FT.Tabs.sessions.Menu(list[1])
    FT.UI.Confirm({ title = "t", text = "x", input = "old", onOK = function(v) FT.Session.Rename(list[1], v) end })
    local d = _G["WolfOfBootyBayConfirm"]
    if d and d.input then d.input:SetText("Mining run"); d.ok:GetScript("OnClick")(d.ok, "LeftButton") end
    local n = #FT.Session.List()
    print("session renamed:", list[1].name)
    FT.Session.Delete(list[1])
    print("sessions after delete:", n, "->", #FT.Session.List())
  end
end)
step("recap and pings", function()
  FT.Port.Recap()
  FT.Port.SellPings()
  print("week:", tostring(FT.An.WeekText()))
end)
step("share and auctionator", function()
  ChatFrame_OpenChat = function(t) mock.opened = t end
  IsInGuild = function() return true end
  FT.ShareTip(12363)
  print("share:", mock.opened)
  Auctionator.API = { v1 = { CreateShoppingList = function(_, name, terms) mock.list = { name, #terms } end,
    ConvertToSearchString = function(_, t) return '"' .. t.searchString .. '"' end, DeleteShoppingList = function() end } }
  FT.ToAuctionator("Wolf: test", { 10620, 12363, 12363 })
  print("auctionator list:", mock.list and mock.list[1], mock.list and mock.list[2])
end)
step("score", function()
  print("score logged:", pcall(FT.An.ScoreDay))
  local n = 0; for _ in pairs((FT.db.score.pending or {})[FT.houseKey] or {}) do n = n + 1 end
  print("calls written down today:", n)
end)
-- the Portfolio list in groups, with made-up holdings (the fake game has no bags): every row drawn, a group closed
step("portfolio groups", function()
  FT.Show("portfolio"); FT.Tabs.portfolio.SetView("portfolio")
  local P = FT.Tabs.portfolio
  P.rows = {
    { id = 12363, qty = 12, price = 5000, value = 60000, ch7 = 0.1, chars = {}, signal = "SELL", strength = 2 },
    { id = 2770, qty = 120, price = 100, value = 12000, ch7 = -0.05, chars = {}, signal = "HOLD", strength = 3 },
    { id = 13444, qty = 4, price = 3000, value = 12000, ch7 = 0, chars = {}, signal = "FAIR", strength = 1 },
  }
  P.total = 84000
  P.RefreshList()
  FT.db.portClosed = {}
  P.RefreshList()
  -- click a group's header row: it closes (its items leave the list)
  local header
  for _, f in ipairs(mock.frames) do
    if f.item and f.item.header and f.item.toSell ~= nil and f:IsVisible() then header = f break end
  end
  local before = header and header:GetParent() and #(header:GetParent().items or header:GetParent():GetParent().items or {})
  if header then mock.click(header) end
  print("group header click:", header and header.item.key or "no header row", "closed now:", tostring(FT.db.portClosed and FT.db.portClosed[header and header.item.key or "?"]))
  local groups = {}
  for id in pairs({ [12363] = 1, [2770] = 1, [13444] = 1 }) do groups[#groups + 1] = id .. "=" .. FT.Port.Group(id) end
  table.sort(groups)
  print("portfolio groups:", table.concat(groups, " "))
end)
-- the tooltip: our price and call right under Auctionator's lines, above another addon's (bag counts)
step("tooltip under auctionator", function()
  local tt = GameTooltip
  tt:ClearLines()
  tt:AddLine("Arcane Crystal")
  tt:AddDoubleLine("Vendor", "1g")
  tt:AddDoubleLine("Auction", "48g")
  tt:AddLine("Inventory")
  tt:AddDoubleLine("Petco Forever", "Total: 1")
  mock.tdp(tt, { id = 12363 })
  local out = {}
  for i = 1, tt:NumLines() do
    local l, r = _G["GameTooltipTextLeft" .. i], _G["GameTooltipTextRight" .. i]
    out[#out + 1] = (l:GetText() or "") .. ((r:IsShown() and r:GetText() ~= "") and (" | " .. r:GetText()) or "")
  end
  print("tooltip order: " .. table.concat(out, " // "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t", ""))
end)
step("look", function()
  print("look: " .. FT.UI.theme .. ", nav tabs: " .. tostring(FT.MainRefs and FT.MainRefs.nav and #FT.MainRefs.nav.tabs))
end)
step("v0.24 pieces", function()
  local m = FT.NameMatcher("thor ore")
  local hits, named = {}, 0
  for _, r in ipairs(FT.Market.Rows() or {}) do
    if FT.Name(r.id) then named = named + 1 end
    if m(r.id) and #hits < 4 then hits[#hits + 1] = FT.Name(r.id) end
  end
  print("search 'thor ore': " .. table.concat(hits, ", ") .. " (of " .. named .. " named)")
  local realName = FT.Name
  local function Try(name, q) FT.Name = function() return name end; local ok = FT.NameMatcher(q)(1); FT.Name = realName; return ok end
  assert(Try("Thorium Ore", "thor ore") and Try("Thorium Ore", "ore thor") and Try("Thorium Bar", "thor"), "word search")
  assert(not Try("Thorium Bar", "thor ore") and Try("Black Lotus", "lotus bl") and not Try("Thorium Ore", '"thor ore"'), "word search 2")
  print("word search ok")
  FT.Show("market")
  local T = FT.Tabs.market
  T.ToggleFilters(T.filterBtn)
  assert(T.clsDD and T.subDD and T.sortDD, "filter popup dropdowns")
  T.ToggleFilters(T.filterBtn)
  T.RefreshList()
  local farm = FT.Tabs.signals.FarmRows()
  print(string.format("farm: %d rows, top %s: %s each, %.0f a day, you ~%s", #farm, tostring(farm[1] and FT.Name(farm[1].id)),
    tostring(farm[1] and farm[1].price), farm[1] and farm[1].perDay or 0, tostring(farm[1] and math.floor(farm[1].yours))))
  FT.UpdateTicker(); FT.UpdateTicker()
  print("movers up/down: " .. #FT.Market.Movers(20, "ch1", true) .. "/" .. #FT.Market.Movers(20, "ch1", false))
  FT.Show("radar")
  assert(FT.Tabs.radar.sign, "radar sign")
  FT.Show("market")
end)
step("the eye", function()
  LOOT_ITEM_SELF = LOOT_ITEM_SELF or "You receive loot: %s."
  LOOT_ITEM_SELF_MULTIPLE = LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d."
  local printed = {}
  local realPrint = FT.Print
  FT.Print = function(m) printed[#printed + 1] = (tostring(m):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")) end
  local function Show(title)
    print("-- " .. title)
    print("sees: " .. (FT.Eye.ProfileText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
    for i, m in ipairs(FT.Eye.Moves(5)) do
      print(string.format("  %d %s %s  (%s)  why: %s", i, m.label, (m.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")),
        tostring(m.value):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), tostring(m.why)))
    end
  end
  -- a gatherer: herbalism and mining, herbs looted, no recipes
  local me = FT.db.chars[FT.charKey]
  me.profs = { Herbalism = 300, Mining = 285 }
  local herb
  for _, r in ipairs(FT.Market.Rows()) do if r.cls == 7 and r.sub == 9 and r.price then herb = r.id break end end
  if herb then
    for i = 1, 30 do mock.fire("CHAT_MSG_LOOT", string.format(LOOT_ITEM_SELF_MULTIPLE, "|cffffffff|Hitem:" .. herb .. "::::::::|h[Herb]|h|r", 10)) end
  end
  FT.Eye.Profile(); FT.Fire("FT_INVENTORY_CHANGED")
  Show("gatherer")
  -- the login note and the one after the auction house
  FT.db.eyeSaid = nil
  FT.Eye.LoginNote()
  FT.Eye.AfterAH()
  FT.Print = realPrint
  print("chat:"); for _, l in ipairs(printed) do print("  > " .. l) end
  -- the Terminal's cards
  FT.Show("market")
  FT.Tabs.market.ShowOverview()
  -- a crafter: every recipe known by this character, materials for the first profitable one in the bags
  local dbg = {}
  local realDebug = FT.Debug
  FT.Debug = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end dbg[#dbg + 1] = table.concat(t, " ") end
  me.profs = { Alchemy = 300 }
  local list = FT.Craft.ProfitCrafts()
  local pick
  for _, c in ipairs(list or {}) do if c.mode == "sell" and (c.perDay or 0) >= 1 then pick = c break end end
  if pick then
    pick.known = true
    local inv = FT.db.inv[FT.charKey]
    for _, rg in ipairs(pick.recipe.reagents) do inv.bags[rg.itemID] = (inv.bags[rg.itemID] or 0) + (rg.qty or 1) * 12 end
    FT.Fire("FT_INVENTORY_CHANGED"); FT.Port.Holdings()
  end
  FT.Eye.Profile()
  Show("crafter (" .. tostring(pick and FT.Name(pick.id)) .. ")")
  FT.Debug = realDebug
  for _, d in ipairs(dbg) do if d:find("eye:") then print("EYE ERROR " .. d) end end
  me.profs = nil
end)
step("futures", function()
  local function plain(t) return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "g"):gsub("|H.-|h", ""):gsub("|h", "")) end
  local me = FT.db.chars[FT.charKey]
  me.profs = { Herbalism = 300 }
  -- a gatherer with a bank of the top material
  local mats = FT.Futures.Materials(10)
  assert(#mats > 0, "key materials")
  FT.db.inv[FT.charKey].bags[mats[1].id] = 400
  FT.Fire("FT_INVENTORY_CHANGED"); FT.Port.Holdings()
  print("futures: " .. plain(FT.Futures.Headline()))
  for i, x in ipairs(FT.Futures.Consumables()) do
    if i > 6 then break end
    print(string.format("  #%d %s [%s] %s", x.rank, tostring(FT.Name(x.id)), x.move, plain(x.moveText)))
  end
  for i, x in ipairs(FT.Futures.Materials(6)) do
    print(string.format("  mat %s in %d [%s] %s", tostring(FT.Name(x.id)), #x.into, x.move, plain(x.moveText)))
  end
  for i, x in ipairs(FT.Futures.Gear()) do
    if i > 3 then break end
    print(string.format("  gear %s %d specs [%s] %s", tostring(FT.Name(x.id)), x.g.specs, x.move, plain(x.moveText)))
  end
  for i, m in ipairs(FT.Eye.Moves(4)) do print(string.format("  eye %s %s", m.label, plain(m.text))) end
  FT.Show("radar")
  FT.Tabs.radar.Refresh()
  FT.db.inv[FT.charKey].bags[mats[1].id] = nil
  me.profs = nil
  FT.Fire("FT_INVENTORY_CHANGED")
end)
step("open item", function() FT.OpenItem(12363) end)
mock.run(1)
step("best use", function() FT.ShowBestUse(12359) end)
step("toast", function() FT.S.alertPopup = true; FT.Toast(12363, "test", "TO THE MOON", "up"); FT.S.alertPopup = false end)
mock.run(10)
step("signals", function()
  local n, kinds = 0, {}
  local fh = FT.Feed.House()
  for id in pairs(fh and fh.raw or {}) do
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
-- Snipe: the lists after a scan, the panel beside the auction house (no tab library in the fake game), Re-check
step("snipe", function()
  FT.Snipe.Build()
end)
mock.run(30)
step("snipe panel", function()
  local now = FT.Snipe.Now()
  local often = FT.Snipe.Often()
  local p = FT.SnipePanel.Get(UIParent)
  p:SetSize(660, 440); p:Show(); FT.SnipePanel.Refresh()
  FT.SnipePanel.Recheck()
  local by = {}
  for _, x in ipairs(now) do by[x.conf] = (by[x.conf] or 0) + 1 end
  local whys = {}
  for i = 1, math.min(8, #now) do whys[#whys + 1] = now[i].conf .. ": " .. now[i].why .. string.format(" (%.0f%%)", now[i].off * 100) end
  print("snipe reasons: " .. table.concat(whys, " | "))
  print("snipe now:", #now, "safe", by.safe or 0, "good", by.good or 0, "gamble", by.gamble or 0, "often:", #often,
    now[1] and ("first: " .. now[1].id .. " " .. now[1].conf .. " " .. now[1].why) or "")
end)
-- Radar, with made-up daily sales (the release's price file has none yet): one item selling 5x faster lately with
-- its price flat, one slowing down - and what the rising one is made of
step("radar", function()
  local h = FT.Feed.House()
  local today = math.floor(FT.Feed.Time() / 86400)
  h.soldFirst = today - 13
  local function Enc(list) local t = {} for i, v in ipairs(list) do t[i] = string.format("%s", (function(n) local d, out = "0123456789abcdefghijklmnopqrstuvwxyz", "" if n == 0 then return "0" end while n > 0 do local r = n % 36 out = d:sub(r + 1, r + 1) .. out n = math.floor(n / 36) end return out end)(v * 10)) end return table.concat(t, ",") end
  -- a crafted item (a recipe output) rising, a material of nothing slowing
  local rising
  for _, r in ipairs(FT.Craft.AllRecipes() or {}) do if FT.Price(r.output) then rising = r.output break end end
  h.soldRaw = {
    [rising or 12363] = Enc({ 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 20, 22, 25 }),
    [2770] = Enc({ 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 5, 4, 3 }),
  }
  FT.Radar.Build()
end)
mock.run(30)
step("radar shown", function()
  FT.Show("radar")
  local list = FT.Radar.List()
  local parts = {}
  for i, x in ipairs(list) do if i <= 4 then parts[#parts + 1] = x.kind .. "/" .. tostring(x.stage) .. ": " .. FT.Radar.Text(x) end end
  print("radar:", #list, table.concat(parts, " | "))
  print("radar next event:", FT.Radar.Next() and FT.Radar.Next().days or "none")
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
  for id in pairs(fh.raw) do ids[#ids + 1] = id; if #ids >= 300 then break end end
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
  for id in pairs(fh.raw) do ids[#ids + 1] = id end
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
-- how long opening each Money view takes in one go, and what one sales lookup costs
step("page open times", function()
  local function T(f) local t0 = os.clock(); f(); return (os.clock() - t0) * 1000 end
  local a = T(function() FT.Show("signals"); FT.Tabs.signals.SetView("make") end)
  local b = T(function() FT.Tabs.signals.SetView("craft") end)
  local c = T(function() FT.Tabs.signals.SetView("farm") end)
  local ids, n = {}, 0
  for id in pairs(FT.Feed.House().raw) do n = n + 1; ids[n] = id; if n >= 200 then break end end
  local r = T(function() for _, id in ipairs(ids) do FT.Sales.Rate(id) end end)
  local r2 = T(function() for _, id in ipairs(ids) do FT.Sales.Rate(id) end end)
  print(string.format("open ms: make %.1f, craft %.1f, farm %.1f; Sales.Rate x200 first %.1f ms, again %.1f ms", a, b, c, r, r2))
  print("longest frames:", (function()
    local parts = {}
    for k, v in pairs(FT.perf or {}) do if (v.worst or 0) > 8 then parts[#parts + 1] = string.format("%s %.1f", k, v.worst) end end
    table.sort(parts); return table.concat(parts, ", ")
  end)())
end)
step("deal start cost", function()
  local function T(f) local t0 = os.clock(); f(); return (os.clock() - t0) * 1000 end
  local n = 0
  local a = T(function() FT.Hist.EachItem(function() n = n + 1 end) end)
  local b = T(function() if FT.Owned and FT.Owned.List then FT.Owned.List() end end)
  local c = T(function() FT.Deals.Build() end)
  print(string.format("deal start: EachItem %d items %.1f ms, Owned %.1f ms, Build call %.1f ms", n, a, b, c))
end)
mock.run(20)
step("learn kinds", function() FT.An.LearnKinds(true) end)
mock.run(30)
step("learned", function()
  local l = FT.db.learned and FT.db.learned[FT.houseKey]
  local n = 0; for _ in pairs(l and l.kinds or {}) do n = n + 1 end
  print("kinds learned:", n)
  local flips, worked = 0, 0
  for _, k in pairs(l and l.kinds or {}) do flips, worked = flips + (k.flips or 0), worked + (k.flipped or 0) end
  print("replayed flips:", flips, "worked:", worked)
end)
-- the deals after learning (the broker checks), by kind, with their risk and record
step("deals checked", function() FT.Deals.Build() end)
mock.run(40)
step("deals by kind", function()
  local by, risky, rec = {}, 0, 0
  for _, d in ipairs((FT.Deals.List())) do
    by[d.kind] = (by[d.kind] or 0) + 1
    if (d.worst or 0) > 0 then risky = risky + 1 end
    if d.record then rec = rec + 1 end
  end
  local parts = {}
  for k, n in pairs(by) do parts[#parts + 1] = k .. "=" .. n end
  table.sort(parts)
  print("deals:", table.concat(parts, " "), "with a risk:", risky, "with a record:", rec)
  local id = 12363
  local s = FT.An.Stats(id)
  local h, label = FT.An.Health(s)
  local c = FT.An.Call(s, 0)
  print("item 12363:", label, "|", FT.An.TrendWord(s), "|", c.kind, c.text)
end)
step("logout", function() mock.fire("PLAYER_LOGOUT") end)
'''
lua.execute('return function(...) ' + script + ' end')(FT)
# a /reload: the same saved data, every file again - as if the prices loaded last time were an hour older,
# so the reload must say "New prices loaded"
lua.eval('function(FT) for k, v in pairs(FT.db.feedLoaded or {}) do FT.db.feedLoaded[k] = v - 3600 end end')(FT)
print("=== reload with saved data ===")
ns = lua.eval('{}')
load_all()
lua.execute('''
mock.fire("ADDON_LOADED", "WolfOfBootyBay")
mock.fire("PLAYER_LOGIN")
mock.fire("PLAYER_ENTERING_WORLD", false, true)
mock.run(200, 0.25)
''')
lua.execute('return function(...) ' + script + ' end')(ns)
print("feed loaded record:", lua.eval('(function(ns) local s = {}; for k, v in pairs((ns.db and ns.db.feedLoaded) or {}) do s[#s+1] = k .. "=" .. tostring(v) end; return table.concat(s, ",") end)')(ns), "house t:", lua.eval('function(ns) local h = ns.Feed.House(); return h and h.t, ns.Feed.On(), ns.house end')(ns))
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
for p in prints[:60]: print('  chat:', re.sub(r'\|c\w{8}|\|r|\|H[^|]*\|h|\|h', '', p)[:200])
