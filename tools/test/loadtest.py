# Load the addon in the fake WoW, log in, click through everything; print every error.
import sys, os, re
import lupa.lua51 as L51
root = sys.argv[1]
feed = sys.argv[2] if len(sys.argv) > 2 else None
lua = L51.LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'wowmock.lua')).read())
lua.execute(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'layout.lua')).read())
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
# WOLF_TEXT=2: the largest text size
if os.environ.get('WOLF_LOOK') or os.environ.get('WOLF_TEXT'):
    lua.execute('WolfOfBootyBayDB = { settings = { look = "%s", textSize = %s } }' % (os.environ.get('WOLF_LOOK', 'classic'), os.environ.get('WOLF_TEXT', 'nil')))
mem0 = lua.eval('function() collectgarbage("collect") return collectgarbage("count") end')()
load_all()
mem1 = lua.eval('function() collectgarbage("collect") return collectgarbage("count") end')()
print("memory: the addon's files %d KB" % (mem1 - mem0))
lua.execute('''
mock.fire("ADDON_LOADED", "WolfOfBootyBay")
mock.fire("PLAYER_LOGIN")
mock.fire("PLAYER_ENTERING_WORLD", true, false)

mock.run(200, 0.25)
''')
mem2 = lua.eval('function() collectgarbage("collect") return collectgarbage("count") end')()
print("memory: after login %d KB more (prices read, lists made; the test's own data included)" % (mem2 - mem1))
FT = ns
script = r'''
local FT = ...
local function step(name, fn) mock.call("step " .. name, fn) end
collectgarbage("collect")
print(string.format("memory after login: %d KB (the test's world included)", collectgarbage("count")))
step("slash", function() SlashCmdList["WOLFOFBOOTYBAY"]("") end)
mock.run(1)
for _, tab in ipairs({ "today", "market", "make", "you", "signals", "radar", "pvp", "calc", "portfolio", "sessions", "sell", "settings", "craft" }) do
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
-- (v0.57) the farming tracker: a gather starts it quietly, 5 quiet minutes pause it (not counted), a loot goes on,
-- 30 minutes paused ends and keeps it; a tiny one isn't kept; your own session takes over
step("auto session", function()
  LOOT_ITEM_SELF = LOOT_ITEM_SELF or "You receive loot: %s."
  LOOT_ITEM_SELF_MULTIPLE = LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d."
  if FT.Session.Current() then FT.Session.Stop() end
  local herb = "|cffffffff|Hitem:13464::::::::60:::::|h[Golden Sansam]|h|r"
  local n0 = #FT.Session.List()
  mock.fire("CHAT_MSG_LOOT", string.format(LOOT_ITEM_SELF_MULTIPLE, herb, 2))
  local s = FT.Session.Current()
  assert(s and s.auto, "a gather started a farming session")
  FT.UpdateHUD()
  local hud = _G["WolfOfBootyBaySession"]
  assert(not (hud and hud:IsShown()), "nothing on screen")
  for i = 1, 8 do mock.run(60); mock.fire("CHAT_MSG_LOOT", string.format(LOOT_ITEM_SELF, herb)) end
  mock.run(400)
  assert(s.paused and s.idle, "5 quiet minutes: paused")
  local secs = FT.Session.Elapsed(s)
  assert(secs >= 470 and secs <= 500, "the quiet minutes don't count: " .. secs)
  mock.fire("CHAT_MSG_LOOT", string.format(LOOT_ITEM_SELF, herb))
  assert(not s.paused, "a loot: on again")
  mock.run(60); mock.fire("CHAT_MSG_MONEY", "You loot 35 Silver")
  mock.run(2200)
  assert(not FT.Session.Current(), "30 minutes paused: over")
  local kept = FT.Session.List()[1]
  assert(#FT.Session.List() == n0 + 1 and kept.auto and kept.name:find("herbs", 1, true), "kept: " .. tostring(kept and kept.name))
  print("auto session: " .. kept.name .. ", " .. kept.worth .. "c, " .. kept.secs .. "s")
  -- a tiny one: not kept
  mock.fire("CHAT_MSG_LOOT", string.format(LOOT_ITEM_SELF, herb))
  mock.run(2400)
  assert(not FT.Session.Current() and #FT.Session.List() == n0 + 1, "a tiny one isn't kept")
  -- resting in town: no farming session; out again with your own session: it takes over
  IsResting = function() return true end
  mock.fire("CHAT_MSG_LOOT", string.format(LOOT_ITEM_SELF, herb))
  assert(not FT.Session.Current(), "not in town")
  IsResting = function() return false end
  mock.fire("CHAT_MSG_LOOT", string.format(LOOT_ITEM_SELF, herb))
  FT.Session.Start()
  assert(FT.Session.Current() and not FT.Session.Current().auto, "your own session takes over")
  FT.Session.Stop()
  FT.S.autoSession = false
  mock.fire("CHAT_MSG_LOOT", string.format(LOOT_ITEM_SELF, herb))
  assert(not FT.Session.Current(), "off in Settings")
  FT.S.autoSession = true
end)
-- (v0.57) the quiet alerts: newer prices or a newer Wolf - a dot on the minimap button, its menu, a line at the
-- mailbox once an hour
step("alerts", function()
  local C = FT.Companion
  local real = C.FreshReady
  C.FreshReady = function() return true end
  FT.UpdateMinimapDot()
  local mb = _G["WolfOfBootyBayMinimapButton"]
  assert(mb.dot:IsShown(), "fresh prices: the dot")
  local printed = {}
  local realPrint = FT.Print
  FT.Print = function(t) printed[#printed + 1] = t end
  mock.fire("MAIL_SHOW"); mock.run(2)
  mock.fire("MAIL_SHOW"); mock.run(2)
  FT.Print = realPrint
  local said = 0
  for _, t in ipairs(printed) do if t:find("Newer prices", 1, true) then said = said + 1 end end
  assert(said == 1, "once an hour at the mailbox: " .. said)
  FT.ShowMenu(mb)
  C.FreshReady = real
  FT.db.told = FT.db.told or {}
  FT.db.told.version, FT.db.told.versionAt, FT.db.told.again = "9.9", time() - 4 * 86400, nil
  FT.Ver.newest = "v9.9.1"
  printed = {}
  FT.Print = function(t) printed[#printed + 1] = t end
  FT.Ver.RemindAgain(); FT.Ver.RemindAgain()
  FT.Print = realPrint
  assert(#printed == 1 and printed[1]:find("9.9", 1, true), "three days on: once more")
  FT.UpdateMinimapDot()
  assert(mb.dot:IsShown(), "a newer Wolf: the dot")
  print("alerts: dot, mailbox line once, version again once")
  -- (v0.58) the prices companion keeps Wolf up to date: a newer one is a /reload away, or waits for a restart; once
  -- it's in, one line
  local realNote = FT.COMPANION
  FT.COMPANION = { version = "1.1.0", checked = time() - 60, built = time() - 600, t = time() - 900, auto = true }
  assert(FT.Ver.HowToGet("9.9"):find("Reload", 1, true), "the companion brought it: reload")
  FT.COMPANION.pending = "9.9.1"
  assert(FT.Ver.HowToGet("9.9"):find("restart", 1, true), "new files: a restart")
  FT.COMPANION.pending = nil
  FT.COMPANION.updated, FT.COMPANION.updatedAt = FT.VERSION, time() - 300
  FT.db.told.self = nil
  printed = {}
  FT.Print = function(t) printed[#printed + 1] = t end
  FT.Ver.SelfUpdated(); FT.Ver.SelfUpdated()
  FT.Print = realPrint
  assert(#printed == 1 and printed[1]:find("updated it", 1, true), "updated: said once")
  FT.COMPANION.auto = false
  assert(FT.Ver.HowToGet("9.9"):find("CurseForge", 1, true), "no companion updates: CurseForge")
  SlashCmdList.WOLFOFBOOTYBAY("build")
  FT.COMPANION = realNote
  SlashCmdList.WOLFOFBOOTYBAY("build")
  FT.Ver.newest = nil
  FT.db.told.version, FT.db.told.versionAt, FT.db.told.again = nil, nil, nil
  FT.UpdateMinimapDot()
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
step("mail to a bank alt", function()
  -- a bank alt on this side; 200 Thorium Ore and 50g mailed to it
  local altGuid = "Player-1-BANKALT"
  FT.db.chars[altGuid] = { name = "Bankalt", side = FT.sideKey, money = 0 }
  local before, goldBefore = FT.Port.Count(10620), FT.Port.Gold()
  mock.sendItems, mock.sendMoney = { { 10620, 200 } }, 500000
  SendMail("Bankalt", "stuff", "")
  mock.sendItems, mock.sendMoney = {}, 0
  mock.fire("MAIL_SEND_SUCCESS")
  FT.Fire("FT_INVENTORY_CHANGED")
  assert(FT.Port.Count(10620) == before + 200, "mailed ore still counted: " .. FT.Port.Count(10620) .. " before " .. before .. " transit " .. #FT.db.transit)
  assert(FT.Port.Gold() == goldBefore + 500000, "mailed gold still counted")
  -- someone else: leaves
  SendMail("Stranger", "sold", ""); mock.fire("MAIL_SEND_SUCCESS")
  assert(#FT.db.transit == 1, "mail to a stranger isn't on the way")
  -- the alt opens its mailbox: the letter is there, its own reading counts it, the on-the-way entry goes
  local me = FT.charKey
  FT.charKey = altGuid
  mock.inbox = { { sender = FT.db.chars[me].name, money = 500000, items = { { 10620, 200 } } } }
  mock.fire("MAIL_SHOW"); FT.Game.ScanMail()
  FT.charKey = me
  mock.inbox = nil
  FT.Fire("FT_INVENTORY_CHANGED")
  assert(#FT.db.transit == 0, "arrived letter cleared")
  assert(FT.Port.Count(10620) == before + 200, "ore in the alt's mailbox counted once: " .. FT.Port.Count(10620))
  assert(FT.Port.Gold() == goldBefore + 500000, "gold in the alt's mailbox counted once")
  print("mail: ore " .. FT.Port.Count(10620) .. ", gold ok")
  FT.db.chars[altGuid], FT.db.inv[altGuid] = nil, nil
  FT.Fire("FT_INVENTORY_CHANGED")
end)
step("companion", function()
  local C = FT.Companion
  assert(not C.Running(), "no note: not running")
  -- no companion: one pointer after a real visit, once
  FT.db.companionHint, FT.db.companionSeen = nil, nil
  mock.fire("AUCTION_HOUSE_SHOW"); mock.run(60); mock.fire("AUCTION_HOUSE_CLOSED"); mock.run(12)
  assert(FT.db.companionHint, "pointer said")
  -- the note: checked just now; the prices loaded were published 2 hours ago
  local realBuilt, realTime = FT.FEED.built, FT.Feed.Time
  FT.COMPANION = { version = "1.0.0", checked = time() }
  FT.FEED.built = time() - 7200
  FT.Feed.Time = function() return time() - 7300 end
  print("companion: running", tostring(C.Running()), "fresh now", tostring(C.FreshReady()))
  mock.run(17 * 60)
  assert(C.FreshReady(), "fresh after a check")
  mock.fire("AUCTION_HOUSE_SHOW"); mock.run(3)
  FT.UpdateAHPill()
  SetItemRef("addon:WolfOfBootyBay:get", "[Get it]", "LeftButton")
  FT.FEED.built, FT.Feed.Time, FT.COMPANION = realBuilt, realTime, nil
  FT.UpdateAHPill()
end)
step("watchlist groups", function()
  local M = FT.Market
  FT.db.watch, FT.db.watchGroups = {}, {}
  M.Watch(12360); M.Watch(7080)
  local g, n = M.WatchWithMaterials(13510)
  assert(g and n > 0, "the flask and its materials in a group")
  assert(M.GroupOf(13510) == g, "the flask in its group")
  M.NewGroup("Flips"); M.Watch(12360, "Flips")
  assert(select(2, M.GroupOf(12360)), "moved into a group of yours")
  FT.Show("market"); FT.Tabs.market.SetFilter("fav")
  local headers = 0
  local list = FT.Tabs.market.list or nil
  print("watchlist groups: " .. table.concat(M.WatchGroups(), ", ") .. "; flask group " .. g .. ", 7080 in " .. M.GroupOf(7080))
  M.RenameGroup("Flips", "Quick flips")
  assert(M.GroupOf(12360) == "Quick flips", "renamed")
  M.DeleteGroup("Quick flips")
  assert(not select(2, M.GroupOf(12360)) and M.IsWatched(12360), "group gone, item still watched")
  UI = FT.UI
  FT.UI.WatchMenu(13468)
  FT.UI.WatchMenu(13510)
end)
step("ah visit", function()
  -- a visit: Wolf's own purchase and posting, a purchase in another window; then walking away
  mock.fire("AUCTION_HOUSE_SHOW")
  FT.Fire("FT_AH_BOUGHT", 12360, 20, 20 * 30000)
  FT.Fire("FT_AH_POSTED", 7080, 5, 80000)
  mock.fire("COMMODITY_PRICE_UPDATED", 25000, 250000)
  if C_AuctionHouse and C_AuctionHouse.ConfirmCommoditiesPurchase then C_AuctionHouse.ConfirmCommoditiesPurchase(7078, 10) end
  mock.fire("COMMODITY_PURCHASE_SUCCEEDED")
  local v = FT.AHVisit.Current()
  print("ah visit: " .. #v.events .. " events")
  FT.SnipePanel.Get(UIParent):Show()
  for _, view in ipairs({ "visit", "watch", "deals", "past" }) do FT.SnipePanel.SetView(view) end
  -- a watched item with a book under its usual price: a deal
  FT.db.watch[12360] = FT.db.watch[12360] or { added = time() }
  local s = FT.An.Stats(12360)
  local usual = (s.avg and s.fair and math.min(s.avg, s.fair)) or s.fair or s.avg
  FT.Hist.SetBook(12360, { t = time(), levels = { { math.floor(usual * 0.7), 12 }, { math.floor(usual * 0.8), 5 }, { usual, 40 } }, auctions = 3, qty = 57, sellers = 3, source = "live" })
  local d = FT.AHVisit.WatchDeal(12360)
  assert(d and d.n == 17, "17 under usual -15%: " .. tostring(d and d.n))
  FT.ahOpen = true
  FT.Fire("FT_LIVE_UPDATED", 12360)
  FT.ahOpen = false
  mock.fire("AUCTION_HOUSE_CLOSED")
  assert(#FT.AHVisit.Past() >= 1, "the visit kept")
  FT.SnipePanel.SetView("past")
  FT.SnipePanel.Get():Hide()
end)
-- The millisecond test: what the heavy things cost in one go. Over its budget: an error - a hitch you'd feel.
-- The rules: a click answers within 50 ms (it feels instant); what happens on its own while you look (new prices)
-- within two frames (33 ms at 60 fps), and is rare; work spread over frames never past one frame (16 ms).
if os.getenv("WOLF_PROF") then step("profile", function()
  local counts = {}
  local function Hook()
    for lvl = 2, 12 do
      local info = debug.getinfo(lvl, "Sl")
      if not info then break end
      local k = info.short_src:match("[^/]*$") .. ":" .. (info.linedefined or 0)
      counts[k] = (counts[k] or 0) + 1
    end
  end
  if mock.layout.Live then mock.layout.Live(true) end
  debug.sethook(Hook, "", 1000)
  local which = os.getenv("WOLF_PROF")
  if which == "rl" then
    FT.Tabs.market.ClearSelection(); FT.Tabs.market.SetFilter("all")
    counts = {}
    debug.sethook(function()
      local info = debug.getinfo(2, "Sl")
      if info then local k = info.short_src:match("[^/]*$") .. ":" .. (info.currentline or 0); counts[k] = (counts[k] or 0) + 1 end
    end, "", 100)
    for _ = 1, 5 do FT.Tabs.market.RefreshList() end
  elseif which == "ready" then
    debug.sethook()
    FT.Show("market"); FT.Tabs.market.ClearSelection()
    local function Again() FT.Fire("FT_MARKET_READY"); FT.Fire("FT_SCAN_DONE", "feed") end
    Again()
    counts = {}
    debug.sethook(Hook, "", 1000)
    for _ = 1, 5 do Again(); FT.Tabs.market.Refresh() end
  elseif which == "item" then FT.OpenItem(13510) elseif which == "fav" then for _ = 1, 5 do FT.Tabs.market.ClearSelection(); FT.Tabs.market.SetFilter("fav") end else for _ = 1, 5 do FT.Show("market"); FT.Tabs.market.Refresh() end end
  debug.sethook()
  mock.layout.Live(false)
  local arr = {}
  for k, v in pairs(counts) do arr[#arr + 1] = { k, v } end
  table.sort(arr, function(a, b) return a[2] > b[2] end)
  for i = 1, math.min(25, #arr) do print("PROF", arr[i][1], arr[i][2]) end
end) end
step("ms test", function()
  local function T(f) local t0 = os.clock(); f(); return (os.clock() - t0) * 1000 end
  -- the usual cost: the middle of five (one run can catch the computer busy, or the garbage collector)
  local function Worst(f)
    local t = {}
    for i = 1, 5 do collectgarbage("collect"); t[i] = T(f) end
    table.sort(t)
    return t[3]
  end
  local over, lines = {}, {}
  if mock.layout and mock.layout.Live then mock.layout.Live(true) end
  local function Check(name, budget, f)
    local ok, ms = pcall(Worst, f)
    if not ok then over[#over + 1] = name .. " failed: " .. tostring(ms); return end
    lines[#lines + 1] = string.format("%-34s %6.1f ms  (budget %d)", name, ms, budget)
    if ms > budget then over[#over + 1] = string.format("%s %.1f ms > %d", name, ms, budget) end
  end
  for _, key in ipairs({ "today", "market", "signals", "portfolio", "sessions", "radar", "pvp", "calc", "settings" }) do
    Check("open page: " .. key, 50, function() FT.Show(key); if FT.Tabs[key].Refresh then FT.Tabs[key].Refresh() end end)
  end
  Check("open an item (chart, breakdown)", 40, function() FT.OpenItem(13510) end)
  Check("market list: watchlist groups", 25, function() FT.Tabs.market.ClearSelection(); FT.Tabs.market.SetFilter("fav") end)
  Check("market list: rising, then all", 50, function() FT.Tabs.market.SetFilter("up"); FT.Tabs.market.SetFilter("all") end)
  -- new prices while you look: the list one frame, the overview the next (T.RefreshSoft)
  Check("new prices: the list (a frame)", 33, function() FT.Tabs.market.ListChanged(); FT.Tabs.market.RefreshList(true) end)
  Check("new prices: the overview (next)", 16, function() FT.Tabs.market.RefreshRight() end)
  Check("the list again, nothing changed", 8, function() FT.Tabs.market.RefreshList(true) end)
  Check("movers (both ways)", 8, function() FT.Market.Movers(20, "ch1", true); FT.Market.Movers(20, "ch1", false) end)
  Check("portfolio rows", 15, function() FT.Port.Rows() end)
  Check("wolf: moves", 25, function() FT.Eye.Moves(6) end)
  Check("wolf: login note", 35, function() FT.db.eyeSaid = nil; FT.Eye.LoginNote() end)
  Check("futures: consumables", 20, function() FT.Futures.Consumables() end)
  Check("futures: key materials", 20, function() FT.Futures.Materials(10) end)
  Check("craft breakdown (flask)", 10, function() FT.UI.RecipeOf(13510); FT.Craft.Eval(FT.UI.RecipeOf(13510)) end)
  Check("where to farm (window)", 15, function() FT.ShowFarm(4338); _G.WolfOfBootyBayFarm:Hide() end)
  Check("farm tip (looking)", 10, function() FT.Farm.BestTip(42) end)
  Check("when it sells (window)", 15, function() FT.ShowWhenSells(12360); _G.WolfOfBootyBayWhenSells:Hide() end)
  local ah = FT.SnipePanel.Get(UIParent)
  ah:SetSize(800, 440); ah:Show()
  for _, view in ipairs({ "visit", "watch", "deals", "past" }) do
    Check("ah tab: " .. view, 20, function() FT.SnipePanel.SetView(view) end)
  end
  ah:Hide()
  -- the jobs spread over frames, run again now with the garbage collector paused (this test's world is far bigger
  -- than the game's, and its collection pauses would be counted as the addon's): their longest frame
  collectgarbage("collect")
  collectgarbage("stop")
  FT.perf = {}
  FT.Market.Rebuild()
  FT.An.LearnKinds(true)
  FT.Deals.Build()
  if FT.Craft.ProfitCrafts then FT.Craft.ProfitCrafts() end
  FT.Market.PrepareMovers()
  mock.run(40)
  collectgarbage("restart")
  collectgarbage("collect")
  for k, v in pairs(FT.perf or {}) do
    if (v.worst or 0) > 0 then lines[#lines + 1] = string.format("%-34s %6.1f ms  (longest frame of %d)", "job: " .. k, v.worst, v.frames or 1) end
    -- a job spread over frames: none past a frame (16 ms). A task done at once, later, is timed once here (one
    -- busy moment of this computer shows): two frames at most - the redraw it usually is is timed above
    local cap = k:find("^delayed:") and 40 or 16
    if (v.worst or 0) > cap then over[#over + 1] = string.format("job %s: a %.1f ms frame (budget %d)", k, v.worst, cap) end
  end
  table.sort(lines)
  for _, l in ipairs(lines) do print("MS " .. l) end
  for _, o in ipairs(over) do print("MS OVER " .. o) end
  if mock.layout and mock.layout.Live then mock.layout.Live(false) end
  assert(#over == 0, #over .. " over budget: " .. table.concat(over, "; "))
end)
step("nothing loose on the screen", function()
  -- frames made by the pages' code with no parent end up on UIParent: they'd stay when the window closes
  local loose = {}
  local function TextIn(f, depth)
    if f.__text and f.__text ~= "" then return f.__text end
    if depth > 2 then return nil end
    for _, k in ipairs(f.__kids or {}) do local t = TextIn(k, depth + 1) if t then return t end end
  end
  for _, f in ipairs(UIParent.__kids or {}) do
    if f.__kind == "Button" and not f.__name then
      local t = TextIn(f, 0)
      if t then loose[#loose + 1] = t end
    end
  end
  for _, t in ipairs(loose) do print("LOOSE button on the screen: " .. t) end
  assert(#loose == 0, #loose .. " buttons on the screen with no window")
end)
-- farming: the farm log from loot windows, the spots for your level, the window, the tip, Wowhead links
step("farm", function()
  local F = FT.Farm
  FT.db.farm, FT.db.farmTip = nil, nil
  assert(F.WowheadURL("item", 4338) == "https://www.wowhead.com/forever/item=4338", F.WowheadURL("item", 4338))
  assert(F.WowheadURL("search", "Arathi Highlands") == "https://www.wowhead.com/forever/search?q=Arathi%20Highlands")
  assert(F.KindOf(4338) == "cloth" and F.KindOf(3858) == "ore" and F.IsRaw(14047))
  -- level 42: Stranglethorn / Badlands first for mageweave, not Zul'Farrak (44+) nor Arathi (36-40)
  local spots = F.Spots(4338, 42)
  print("mageweave at 42: " .. spots[1].zone .. ", " .. spots[2].zone .. ", " .. spots[3].zone)
  assert(spots[1].fit == 0, "the first spot fits level 42")
  local names = F.ForYou(4338, 42, 3)
  assert(#names == 3, "three zones for 42")
  -- 12 corpses of one mob in Arathi: 9 mageweave (5 corpses had 1, 2 had 2) and one corpse skinned twice
  mock.zone = "Arathi Highlands"
  local t0 = mock.now
  for k = 1, 12 do
    local guid = "Creature-0-1-2-3-2588-" .. string.format("%08X", t0 % 100000 * 100 + k) -- new corpses each run
    mock.target = { guid = guid, name = "Syndicate Prowler", level = 38 }
    mock.loot = {}
    if k <= 5 then mock.loot[1] = { id = 4338, qty = 1, sources = { guid, 1 } }
    elseif k <= 7 then mock.loot[1] = { id = 4338, qty = 2, sources = { guid, 2 } }
    else mock.loot[1] = { id = 4306, qty = 1, sources = { guid, 1 } } end
    mock.fire("LOOT_READY", true)
    mock.fire("LOOT_CLOSED")
    if k == 12 then -- skinned: the same corpse again
      mock.loot = { { id = 4234, qty = 1, sources = { guid, 1 } } }
      mock.fire("LOOT_READY", true)
      mock.fire("LOOT_CLOSED")
    end
    mock.now = mock.now + 30
  end
  mock.target, mock.loot = nil, {}
  local mobs = F.Mobs(4338)
  assert(#mobs == 1 and mobs[1].corpses == 12 and mobs[1].n == 9, "12 corpses, 9 mageweave: " .. tostring(mobs[1] and mobs[1].corpses) .. "/" .. tostring(mobs[1] and mobs[1].n))
  assert(mobs[1].name == "Syndicate Prowler" and mobs[1].lv == 38)
  local z = FT.db.farm.zones["Arathi Highlands"]
  print(string.format("farm log: Arathi %d corpses, %d s looting, mageweave %d", z.corpses, z.secs, z.items[4338] or 0))
  assert(z.corpses == 12 and z.secs >= 300)
  local y = F.ZoneFor("Arathi Highlands", 4338)
  assert(y and y.perHour > 0, "your mageweave an hour in Arathi")
  -- the window, at level 42 and at 60
  for _, lv in ipairs({ 42, 60 }) do
    mock.level = lv
    FT.ShowFarm(4338)
    local d = _G.WolfOfBootyBayFarm
    mock.layout.Settle(d)
    local found, texts = mock.layout.Overlaps(d)
    for _, o in ipairs(found) do print(string.format("OVERLAP [where to farm @%d] %q x %q  (%dx%d px)", lv, o[1].text:sub(1, 50), o[2].text:sub(1, 50), o[3], o[4])) end
    for _, t in ipairs(texts) do if t.cut then print(string.format("CUT [where to farm @%d] %q", lv, t.text:sub(1, 80))) end end
    local m = d.model
    print(string.format("where to farm @%d: %s | %s | %d other spots | %s | %dpx tall", lv, m.card.k or "?", m.card.big or "?", #m.others,
      (m.mine or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), d:GetHeight()))
    assert(m.card.k and m.card.big, "one answer first")
    assert(m.mine and m.mine:find("12", 1, true), "your loot in one line: " .. tostring(m.mine))
    assert(d:GetHeight() < 420, "as tall as what it says: " .. d:GetHeight())
    d:Hide()
  end
  mock.level = 60
  -- (v0.56) the three kinds: ore (zones and the skill), a world epic (not a farm), a pattern you can target
  local function chipsText(m) local t = {} for _, c in ipairs(m.card.chips) do t[#t + 1] = c[1] end return table.concat(t, " | ") end
  FT.ShowFarm(3858)
  local mo = _G.WolfOfBootyBayFarm.model
  assert(chipsText(mo):find("Mining 175", 1, true) or (mo.card.meta or ""):find("Mining", 1, true), "ore shows its Mining: " .. chipsText(mo))
  for _, id in ipairs({ 1168, 252892 }) do
    FT.ShowFarm(id)
    local d = _G.WolfOfBootyBayFarm
    mock.layout.Settle(d)
    local found, texts = mock.layout.Overlaps(d)
    for _, o in ipairs(found) do print(string.format("OVERLAP [where to farm %d] %q x %q  (%dx%d px)", id, o[1].text:sub(1, 50), o[2].text:sub(1, 50), o[3], o[4])) end
    for _, t in ipairs(texts) do if t.cut then print(string.format("CUT [where to farm %d] %q", id, t.text:sub(1, 80))) end end
    local m = d.model
    print(string.format("where to farm %d: %s | %s | %s", id, m.card.k, m.card.big, chipsText(m)))
    if id == 1168 then
      assert(m.world and m.card.k:find("WORLD", 1, true), "a world epic: not a farm")
    else
      assert(m.card.big == "Gordok Ogre-Mage" or m.card.big == "Gordok Mage-Lord", "Dawn Armor: the ogres")
    end
  end
  _G.WolfOfBootyBayFarm:Hide()
  -- the tip: mageweave up this week, selling every day, at 42
  local r = FT.Market.Row(4338)
  if r then
    local ch7, price = r.ch7, r.price
    r.ch7, r.price = 0.34, r.price or 12000
    local real = FT.Sales.Rate
    FT.Sales.Rate = function(id) if id == 4338 then return { perDay = 400, sold = 2800, hours = 168 } end return real(id) end
    mock.level = 42
    -- no professions seen: cloth only (the real feed's herbs may be up more)
    local c = FT.db.chars[FT.charKey]
    local profs = c.profs
    c.profs = nil
    local t = F.BestTip(42)
    assert(t and FT.FarmSpots[t.id].kind ~= "herb" and FT.FarmSpots[t.id].kind ~= "ore", "no gathering tip without the profession")
    c.profs = { Herbalism = 100 }
    local t2 = F.BestTip(42)
    assert(not (t2 and FT.FarmSpots[t2.id].kind == "herb" and FT.FarmSpots[t2.id].skill > 100), "no herb above your skill")
    c.profs = profs
    print("farm tip: " .. F.TipText(t, 42):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H[^|]*|h", ""):gsub("|h", ""))
    FT.db.farmTip = nil
    local said = F.MaybeTip()
    assert(said, "said once")
    assert(not F.MaybeTip(), "not twice in two hours")
    FT.Sales.Rate, r.ch7, r.price = real, ch7, price
    mock.level = 60
  else
    print("farm tip: no mageweave row in this feed")
  end
  -- Best crafts from mageweave: both orders, and nothing overlapping
  FT.ShowBestUse(4338)
  local bw = _G.WolfOfBootyBayBestUse
  local first = bw.list.items[1] and bw.list.items[1].recipe.output
  bw.sortBy = "sells"
  FT.ShowBestUse(4338)
  local top = bw.list.items[1]
  print(string.format("best crafts from mageweave: %d products; most per one %s, best seller %s (%s a day)", #bw.list.items,
    FT.ItemText(first or 0):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), FT.ItemText(top.recipe.output):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), tostring(top.perDay and math.floor(top.perDay))))
  for i = 2, #bw.list.items do
    local a, b = bw.list.items[i - 1], bw.list.items[i]
    local va = (a.each and a.perDay) and a.each * a.need * a.perDay or -1
    local vb = (b.each and b.perDay) and b.each * b.need * b.perDay or -1
    assert(va >= vb, "best sellers in order")
  end
  mock.layout.Settle(bw)
  local bf, bt = mock.layout.Overlaps(bw)
  for _, o in ipairs(bf) do print(string.format("OVERLAP [best crafts] %q x %q  (%dx%d px)", o[1].text:sub(1, 50), o[2].text:sub(1, 50), o[3], o[4])) end
  for _, t in ipairs(bt) do if t.cut then print(string.format("CUT [best crafts] %q", t.text:sub(1, 80))) end end
  bw.sortBy = "each"
  bw:Hide()
  -- v0.42: the watch menu has no Wowhead and no Where to farm (the item page has them), and has Long hold
  local shown
  local realMenu = FT.ShowMenu
  FT.ShowMenu = function(_, items) shown = items end
  FT.UI.WatchMenu(4338, UIParent)
  FT.ShowMenu = realMenu
  local labels = {}
  for _, it in ipairs(shown or {}) do labels[#labels + 1] = it[1] end
  local all = table.concat(labels, "|")
  assert(not all:find("Wowhead", 1, true) and not all:find("Where to farm", 1, true) and all:find("Long hold", 1, true), all)
end)
-- the sell / hold model: its trendline, the raids ahead, an endgame material in a young economy
step("sell model", function()
  local An = FT.An
  -- 20 days climbing 2% a day: on its line
  local daily, today = {}, FT.Day()
  for k = 1, 20 do daily[k] = { day = today - 21 + k, c = math.floor(10000 * 1.02 ^ k), o = 1, h = 1, l = 1 } end
  local tr = An.TrendLine(daily, today, math.floor(10000 * 1.02 ^ 21))
  print(string.format("trend: %+.1f%% a week, r2 %.2f, above %+.1f%%, band %.0f%%, climbing %s", tr.perWeek * 100, tr.r2, tr.above * 100, tr.band * 100, tostring(tr.climbing)))
  assert(tr.climbing and math.abs(tr.above) < 0.03)
  -- where each item stands
  assert(An.Lifecycle(14047) == "endgame", "runecloth: endgame")
  assert(An.Lifecycle(2589) == "leveling", "linen: leveling")
  assert(An.Lifecycle(12363) == "endgame", "arcane crystal: endgame")
  -- the raids pull on arcane crystals: through Arcanite Bar into the Lionheart Helm on the pre-raid list
  local dem = FT.Futures.DemandAhead(12363)
  print("arcane crystal demand: " .. tostring(dem and FT.ItemText(dem.into)) .. ", raids in " .. tostring(dem and dem.days) .. " days")
  assert(dem and dem.days and dem.days > 4, "the raids ahead pull on arcane crystals")
  -- a made-up item high above its average, to see each rule decide
  local function S(over)
    local s = { id = 999001, price = 14000, avg = 10000, dev = 0.4, rsi = 60, days = 14, span = 20, avgN = 10,
      behavior = {}, closes = {}, daily = daily, fair = 14000 }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
  end
  local realDem, realLife, realEnough = FT.Futures.DemandAhead, An.Lifecycle, nil
  FT.Futures.DemandAhead = function() return nil end
  An.Lifecycle = function() return nil end
  local k, _, why = An.SellSignal(S())
  print("plain high: " .. k .. " - " .. tostring(why))
  local k1, _, w1 = An.SellSignal(S({ trend = { climbing = true, perWeek = 0.15, r2 = 0.9, n = 20, above = 0.02, band = 0.08 } }))
  print("on its climb: " .. k1 .. " - " .. w1)
  assert(k1 == "HOLD", "on its climb: hold")
  local k2, _, w2 = An.SellSignal(S({ trend = { climbing = true, perWeek = 0.15, r2 = 0.9, n = 20, above = 0.2, band = 0.08 } }))
  print("over its climb: " .. k2 .. " - " .. w2)
  assert(k2 == "TRIM", "over its climb: a third")
  local k3 = An.SellSignal(S({ dropped = true, trend = { climbing = true, perWeek = 0.15, r2 = 0.9, n = 20, above = 0.02, band = 0.08 } }))
  assert(k3 == "SELL", "a climb that cracks: sell")
  FT.Futures.DemandAhead = function() return { into = 12640, n = 1, days = 12, t = time() + 12 * 86400, name = "raids" } end
  local k4, _, w4 = An.SellSignal(S())
  print("raids ahead: " .. k4 .. " - " .. w4)
  assert(k4 == "HOLD")
  FT.Futures.DemandAhead = function() return { into = 12640, n = 1, days = 3, t = time() + 3 * 86400, name = "raids" } end
  local k5, _, w5 = An.SellSignal(S())
  print("raid week: " .. k5 .. " - " .. w5)
  assert(k5 == "SELL")
  FT.Futures.DemandAhead = function() return nil end
  An.Lifecycle = function() return "endgame" end
  local k6, _, w6 = An.SellSignal(S())
  print("endgame, young economy: " .. k6 .. " - " .. w6)
  assert(k6 == "TRIM")
  An.Lifecycle = function() return "leveling" end
  local k7, _, w7 = An.SellSignal(S())
  print("leveling: " .. k7 .. " - " .. w7)
  assert(k7 == "SELL")
  FT.Futures.DemandAhead, An.Lifecycle = realDem, realLife
  -- the new rules are graded like the others: holding was right when it didn't fall
  assert(An.Right("trend", 100, 110) == true and An.Right("demand", 100, 90) == false and An.Right("endgame", 100, 98) == true)
end)
step("when it sells", function()
  -- a feed line with prices by the hour: 4% under its usual 3-5 UTC, 5% over 18-20
  local h = FT.Feed.House()
  local rawLine = h.hourRaw[12360]
  local injected = false
  if rawLine and not rawLine:find("/.*/.*/") then
    injected = true
    local tp = {}
    for u = 0, 23 do tp[u + 1] = (u >= 3 and u <= 5) and "qo" or ((u >= 18 and u <= 20) and "t6" or "rs") end -- 960 / 1050 / 1000
    local lp = {}
    for k = 1, 48 do lp[k] = "1kw" end
    h.hourRaw[12360] = rawLine .. "/" .. table.concat(lp, ",") .. "/" .. table.concat(tp, ",")
  end
  local hp = FT.Feed.Hourly(12360)
  -- (a feed with no hourly lines at all: nothing to read; a live feed's own line may not have five looks an hour yet)
  if rawLine and injected then
    assert(hp.todPrice, "prices by the hour read")
    local lo, hi = 9, 0
    for u = 0, 23 do if hp.todPrice[u] then lo, hi = math.min(lo, hp.todPrice[u]), math.max(hi, hp.todPrice[u]) end end
    assert(math.abs(lo - 0.96) < 0.001 and math.abs(hi - 1.05) < 0.001, lo .. " " .. hi)
    assert(hp.hours[48].p == tonumber("1kw", 36), "the last hours' prices")
  end
  local hr = FT.Feed.Hourly(12360)
  print("hourly: " .. tostring(hr and #hr.hours) .. " hours")
  FT.ShowWhenSells(12360)
  local d = _G.WolfOfBootyBayWhenSells
  if d then
    -- v0.42: the three answers first (sell, buy, the busiest day)
    for i, r in ipairs(d.answers) do print("when it sells " .. i .. ": " .. tostring(r.text.__text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    assert(not injected or tostring(d.answers[2].text.__text):find("cheapest"), "the window says when to buy")
    assert(d:GetHeight() < 400 or (FT.db.ui and FT.db.ui.whenCharts), "the charts only on request")
    if FT.Feed.Hourly(12360) then
      FT.db.ui = FT.db.ui or {}; FT.db.ui.whenCharts = true; FT.ShowWhenSells(12360)
      assert(d.tod:IsShown() and d:GetHeight() > 600, "Show the charts shows them")
      FT.db.ui.whenCharts = nil; FT.ShowWhenSells(12360)
    end
    mock.layout.Settle(d)
    local found, texts = mock.layout.Overlaps(d)
    for _, o in ipairs(found) do print(string.format("OVERLAP [when it sells] %q x %q  (%dx%d px)", o[1].text:sub(1, 50), o[2].text:sub(1, 50), o[3], o[4])) end
    for _, t in ipairs(texts) do if t.cut then print(string.format("CUT [when it sells] %q", t.text:sub(1, 80))) end end
    d:Hide()
  end
  FT.ShowWhenSells(13510) -- no hourly line: the note instead
  if d then d:Hide() end
end)
step("craft breakdown", function()
  -- the flask: no character of yours knows it, the game's recipe; and a craft of yours
  local inv = FT.db.inv[FT.charKey]
  for _, id in ipairs({ 13510, 18405 }) do
    FT.OpenItem(id)
    local r, known = FT.UI.RecipeOf(id)
    print("breakdown " .. id .. ": recipe " .. tostring(r and r.name) .. ", known " .. tostring(known))
    local panel
    local function find(f) if f.advice and f.sum then panel = f return end for _, k in ipairs(f.__kids or {}) do if not panel then find(k) end end end
    find(WolfOfBootyBayFrame)
    if panel then
      print("  " .. tostring(panel.who.__text))
      for _, sline in ipairs(panel.sum) do print("  " .. tostring(sline.label.__text) .. ": " .. tostring(sline.value.__text)) end
      print("  advice: " .. tostring(panel.advice.__text):gsub("\n", " | "))
      print("  shown " .. tostring(panel.__shown) .. ", height " .. tostring(panel.__h))
    end
  end
end)
step("wolf notes", function()
  -- a big position and a watched item; their prices "last time" lower: the note says what moved
  local inv = FT.db.inv[FT.charKey]
  local keep = inv.bags[12360]
  inv.bags[12360] = 200
  FT.db.watch[13468] = FT.db.watch[13468] or { added = time() }
  FT.Fire("FT_INVENTORY_CHANGED"); FT.Port.Holdings()
  FT.db.eyePrices = nil
  FT.Eye.Remember()
  for id, b in pairs(FT.db.eyePrices) do b.p = math.floor(b.p * 0.8) end
  FT.db.eyeSaid = nil
  FT.Eye.LoginNote()
  local after = 0
  for _ in pairs(FT.db.eyePrices) do after = after + 1 end
  assert(after > 0, "prices remembered")
  -- nothing moved since: the steady line
  FT.Eye.LoginNote()
  FT.Eye.AfterScan()
  inv.bags[12360] = keep
  FT.db.watch[13468] = nil
  FT.Fire("FT_INVENTORY_CHANGED")
end)
step("layout", function()
  -- every page with things in it (a gatherer holding the key materials), and texts that draw over each other
  local inv = FT.db.inv[FT.charKey]
  local held = {}
  for i, x in ipairs(FT.Futures.Materials(10)) do held[x.id] = inv.bags[x.id]; inv.bags[x.id] = 1234 * i end
  FT.Fire("FT_INVENTORY_CHANGED"); FT.Port.Holdings()
  local seen = {}
  local total, cuts = 0, 0
  FT.S.showCraft = true
  local pages = {
    { "today", "today" },
    { "make: raid prep", "radar", function() FT.ShowSub("make", "raid") end },
    { "you: sessions", "sessions", function() FT.ShowSub("you", "sessions") end },
    { "you: holdings, liquid", "portfolio", function() FT.ShowSub("you", "portfolio"); FT.Tabs.portfolio.donutBox.seg.buttons[3].onClick() end },
    { "you: holdings, bank only", "portfolio", function() FT.Tabs.portfolio.donutBox.seg.buttons[2].onClick(); FT.Tabs.portfolio.worth:Pick("bank") end },
    { "you: holdings, on the AH", "portfolio", function() FT.Tabs.portfolio.worth:Pick("ah") end },
    { "you: holdings, what it is", "portfolio", function()
        -- (v0.57) no ring: the total, then each part's gold and share, biggest first, with its top items
        local T = FT.Tabs.portfolio
        T.worth:Pick(nil); T.donutBox.seg.buttons[1].onClick()
        local parts = T.worth.parts
        assert(#parts >= 2, "parts of your worth: " .. #parts)
        local share = 0
        for i, pt in ipairs(parts) do
          share = share + pt.share
          if i > 1 then assert(pt.value <= parts[i - 1].value or parts[i].key == "rest", "biggest first") end
        end
        assert(math.abs(share - 1) < 0.01, "shares add up: " .. share)
        local r = T.donutBox.parts[1]
        assert(r.val.__text and r.val.__text ~= "" and r.top.fitText and r.top.fitText ~= "", "a part shows its gold and top items")
        local names = {}
        for _, pt in ipairs(parts) do names[#names + 1] = string.format("%s %d%%", pt.label, math.floor(pt.share * 100 + 0.5)) end
        print("worth by what: " .. table.concat(names, ", "))
    end },
    { "market", "market" }, { "market item", "market", function() FT.OpenItem(12363) end },
    { "market item: two-line verdict", "market", function()
      -- v0.43: a long reason takes two lines; When it sells starts below it
      realCall = realCall or FT.An.Call
      FT.An.Call = function(...)
        local c = realCall(...)
        local x = {}
        for k, v in pairs(c) do x[k] = v end
        x.text = "Cheaper than usual (-34%), but dips like this kept falling for days on end: wait for it to settle first"
        x.conf = x.conf or "likely"
        return x
      end
      FT.OpenItem(12363)
    end },
    { "market item: a flask", "market", function() if realCall then FT.An.Call = realCall end; FT.OpenItem(13510) end },
    { "market item: a raw mat", "market", function() FT.OpenItem(4338) end },
    { "market: watchlist", "market", function() FT.Tabs.market.ClearSelection(); FT.Tabs.market.SetFilter("fav") end },
    { "market item: a craft of yours", "market", function() FT.OpenItem(18405) end },
    { "money: make", "signals", function() FT.Tabs.signals.SetView("make") end },
    { "money: farm", "signals", function() FT.Tabs.signals.SetView("farm") end },
    { "money: craft", "signals", function() FT.Tabs.signals.SetView("craft") end },
    { "portfolio", "portfolio", function() FT.Tabs.portfolio.SetView("portfolio") end },
    { "portfolio: sell", "portfolio", function() FT.Tabs.portfolio.SetView("sell") end },
    { "portfolio: chars", "portfolio", function() FT.Tabs.portfolio.SetView("chars") end },
    { "sessions", "sessions" },
    { "craft", "craft", function() if FT.Tabs.craft and FT.Tabs.craft.SetView then FT.Tabs.craft.SetView("recipes") end end },
    { "craft queue", "craft", function() if FT.Tabs.craft and FT.Tabs.craft.SetView then FT.Tabs.craft.SetView("queue") end end },
    -- v0.50
    { "craft: level it up", "craft", function() FT.Tabs.craft.SetView("level") end },
    { "craft: worth learning", "craft", function()
      local c = FT.db.chars[FT.charKey]
      c.profs = c.profs or { Alchemy = 280, Tailoring = 250, Engineering = 260, Blacksmithing = 270, Leatherworking = 260 }
      FT.Tabs.craft.SetView("learn")
    end },
    { "craft again", "craft", function() FT.Tabs.craft.SetView("recipes") end },
    { "make: raids", "radar", function() FT.ShowSub("make", "raid") end },
    { "make: pvp", "pvp", function() FT.ShowSub("make", "pvp") end },
    { "money: farm next week", "signals", function()
      FT.ShowSub("make", "farm")
      FT.Ahead.Lists()
      mock.run(20, 0.05)
      local f = FT.Tabs.signals
      for _, b in ipairs(f.farmKindBar and f.farmKindBar.buttons or {}) do if b.value == "next" then b.onClick() end end
    end },
    { "money: farm drops", "signals", function()
      local f = FT.Tabs.signals
      for _, b in ipairs(f.farmKindBar and f.farmKindBar.buttons or {}) do if b.value == "drops" then b.onClick() end end
      FT.Drops.List(); mock.run(60, 0.05); f.RefreshFarm()
      local rows = f.DropRows()
      assert(rows and #rows > 0, "drops listed: " .. tostring(rows and #rows))
      print("drops: " .. #rows .. ", top " .. (FT.Name(rows[1].id) or "?") .. " | " .. (rows[1].reason or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
      for _, x in ipairs(rows) do
        assert(FT.Drops.Killable(x.drop.who), "no world boss, raid, summoned or 61+ mob: " .. tostring(x.drop.who.name))
        assert(not FT.Drops.World(x.id) or x.drop.chance >= 200, "no world drops: " .. tostring(FT.Name(x.id)))
      end
    end },
    { "money: drops per hour", "signals", function()
      local f = FT.Tabs.signals
      f.RefreshFarm()
      local bar = FT.Tabs.signals
      for _, b in ipairs((bar.farmKindBar and bar.farmKindBar:GetParent().sort or {}).buttons or {}) do if b.value == "hour" then b.onClick() end end
      local rows = f.DropRows()
      assert(rows[1] and rows[1].drop.perHour, "per hour: the known rates first")
    end },
    { "money: dungeons", "signals", function()
      local f = FT.Tabs.signals
      for _, b in ipairs(f.farmKindBar and f.farmKindBar.buttons or {}) do if b.value == "dungeons" then b.onClick() end end
      local rows = f.DungeonRows()
      assert(#rows >= 15, "the dungeons: " .. #rows)
      local d = rows[1].dungeonInfo
      assert(d.steady > d.coin and d.each == d.steady / 5, "a run: steady loot and coin, split five ways; rare drops apart")
      print("dungeons: best " .. d.name .. " " .. math.floor(d.each / 10000) .. "g each a clear, " .. math.floor(d.hour / 10000) .. "g an hour each")
    end },
    { "money: dungeons, the trash", "signals", function()
      local view = FT.Tabs.signals.farmKindBar:GetParent()
      for _, b in ipairs(view.trash.buttons) do if b.value == "trash" then b.onClick() end end
    end },
    { "money: dungeons, solo", "signals", function()
      -- (v0.57) solo: the whole run's loot, slower, only well under your level; hard ones marked and below
      local f = FT.Tabs.signals
      local view = f.farmKindBar:GetParent()
      for _, b in ipairs(view.trash.buttons) do if b.value == "solo" then b.onClick() end end
      local rows = f.DungeonRows()
      assert(#rows >= 5, "solo dungeons at 60: " .. #rows)
      local d = rows[1].dungeonInfo
      assert(d.solo and d.each == d.steady and not d.hardSolo, "solo: all the loot is yours")
      for _, r in ipairs(rows) do assert(r.dungeonInfo.solo) end
      local hard = 0
      for _, r in ipairs(rows) do if r.dungeonInfo.hardSolo then hard = hard + 1 end end
      print(string.format("solo dungeons: %d (%d hard), best %s %dg a run, ~%d min", #rows, hard, d.name, math.floor(d.each / 10000), d.min))
      assert(view.hint.__text and view.hint.__text:find("hard", 1, true), "the caveat: it's hard")
      for _, b in ipairs(view.trash.buttons) do if b.value == "full" then b.onClick() end end
    end },
    { "money: a dungeon's drops", "signals", function()
      local f = FT.Tabs.signals
      local view = f.farmKindBar:GetParent()
      local rows = f.DungeonRows()
      -- a click on a dungeon: Drops, that dungeon only
      local name = rows[1].dungeonInfo.name
      local click = view.list.opts and view.list.opts.onClick
      if click then click(rows[1], "LeftButton") end
      for _, b in ipairs(view.trash.buttons) do if b.value == "full" then b.onClick() end end
      print("a dungeon's drops: " .. name)
    end },
    { "money: farm again", "signals", function()
      local f = FT.Tabs.signals
      for _, b in ipairs(f.farmKindBar and f.farmKindBar.buttons or {}) do if b.value == "all" then b.onClick() end end
    end },
    { "today: a day picked", "today", function()
      local TT = FT.Tabs.today
      TT.FillComing()
      for _, dd in ipairs(TT.coming.days) do if #dd.events > 0 then TT.coming.picked = dd.t break end end
      TT.FillComing()
    end },
    { "calculator", "calc", function() FT.ShowCalc(12363, "sell"); FT.Tabs.calc.qty:SetValue("500"); FT.Tabs.calc.Log(); FT.Tabs.calc.Update() end },
    { "calculator: buying", "calc", function() FT.ShowCalc(12363, "buy") end },
    { "today: four weeks", "today", function() local c = FT.Tabs.today.coming; c.picked = nil; c.weeks = 4; FT.Tabs.today.FillComing() end },
    { "today again", "today", function() local c = FT.Tabs.today.coming; c.picked, c.weeks, c.from = nil, 1, nil; FT.Tabs.today.FillComing() end },
    { "futures", "radar", function() FT.Tabs.radar.SetSection("consumables") end },
    { "futures: gear", "radar", function() FT.Tabs.radar.SetSection("gear") end },
    { "settings", "settings" },
    { "settings: all", "settings", function() FT.S.showAdvanced = true; FT.Tabs.settings.Layout() end },
  }
  for _, size in ipairs({ "min", "std", "max" }) do
  FT.SetWindowSize(size)
  for _, pg in ipairs(pages) do
    local key = pg[1] .. " @" .. size
    FT.Show(pg[2])
    if pg[3] then pg[3]() end
    if FT.Tabs[pg[2]] and FT.Tabs[pg[2]].Refresh then FT.Tabs[pg[2]].Refresh() end
    mock.layout.Settle(WolfOfBootyBayFrame)
    if FT.Tabs[pg[2]] and FT.Tabs[pg[2]].Refresh then FT.Tabs[pg[2]].Refresh() end
    mock.run(1)
    mock.layout.Settle(WolfOfBootyBayFrame)
    local found, texts = mock.layout.Overlaps(WolfOfBootyBayFrame)
    for _, t in ipairs(texts) do
      if t.out and not seen["out|" .. t.text] then
        seen["out|" .. t.text] = true
        cuts = cuts + 1
        local r, pr = t.ink, mock.layout.Rect(t.f.__parent)
        print(string.format("OUT [%s] %q runs past its frame (%d..%d in %d..%d)  in %s", key, t.text:sub(1, 60), r[1], r[2], pr[1], pr[2], mock.layout.Where(t.f)))
      end
      if t.spill and not seen["spill|" .. t.text] then
        seen["spill|" .. t.text] = true
        cuts = cuts + 1
        print(string.format("SPILL [%s] %q hangs out of its row  in %s", key, t.text:sub(1, 60), mock.layout.Where(t.f)))
      end
      if t.cut and not seen["cut|" .. t.text] then
        seen["cut|" .. t.text] = true
        cuts = cuts + 1
        if cuts <= 40 then
          local r = mock.layout.Rect(t.f)
          print(string.format("CUT [%s] %q  box %d, text %d, size %s  in %s", key, t.text:sub(1, 70), r[2] - r[1], mock.layout.TextWidth(t.f), tostring(t.f.__fsize), mock.layout.Where(t.f)))
        end
      end
    end
    for _, o in ipairs(found) do
      local k = o[1].text .. "|" .. o[2].text
      if not seen[k] then
        seen[k] = true
        total = total + 1
        if total <= 60 then
          print(string.format("OVERLAP [%s] %q x %q  (%dx%d px)  in %s", key, o[1].text:sub(1, 50), o[2].text:sub(1, 50), o[3], o[4], mock.layout.Where(o[1].f)))
          if os.getenv and os.getenv("WOLF_DEBUG") then
            for z = 1, 2 do local r = o[z].ink; print(string.format("    %q ink l%d r%d t%d b%d size %s", o[z].text:sub(1, 30), r[1], r[2], r[3], r[4], tostring(o[z].f.__fsize))) end
          end
        end
      end
    end
  end
  FT.S.showAdvanced = false
  FT.Tabs.market.SetFilter("all")
  FT.Tabs.radar.SetSection("consumables")
  end
  -- the auction house's Wolf tab, each view
  local ah = FT.SnipePanel.Get(UIParent)
  ah:ClearAllPoints(); ah:SetPoint("CENTER"); ah:SetSize(800, 440); ah:Show()
  mock.fire("AUCTION_HOUSE_SHOW")
  FT.Fire("FT_AH_BOUGHT", 12360, 20, 20 * 30000)
  FT.Fire("FT_AH_POSTED", 7080, 5, 80000)
  for _, view in ipairs({ "visit", "watch", "deals", "past" }) do
    FT.SnipePanel.SetView(view)
    mock.layout.Settle(ah)
    local found, texts = mock.layout.Overlaps(ah)
    for _, o in ipairs(found) do
      total = total + 1
      print(string.format("OVERLAP [ah tab: %s] %q x %q  (%dx%d px)", view, o[1].text:sub(1, 50), o[2].text:sub(1, 50), o[3], o[4]))
    end
    for _, t in ipairs(texts) do
      if t.cut then cuts = cuts + 1; local r = mock.layout.Rect(t.f); print(string.format("CUT [ah tab: %s] %q  box %d text %d", view, t.text:sub(1, 90), r[2] - r[1], mock.layout.TextWidth(t.f))) end
      if t.spill then cuts = cuts + 1; print(string.format("SPILL [ah tab: %s] %q", view, t.text:sub(1, 60))) end
    end
  end
  mock.fire("AUCTION_HOUSE_CLOSED")
  ah:Hide()
  -- (v0.52: the item window is gone: an item opens on the Market page)
  FT.ShowItemWindow(13510)
  assert(FT.Tabs.market.Selected() == 13510, "an item opens on Market")
  -- the craft window with its recipe line (v0.43): a merchant's recipe, on the auction house
  do
    local r = FT.Craft.AllRecipes()[1]
    for _, x in ipairs(FT.Craft.AllRecipes()) do if x.name and #x.name > 20 then r = x break end end
    local had = FT.RECIPE_ITEMS
    FT.RECIPE_ITEMS = { [r.name:lower()] = { 13510 } }
    FT.db.recipeVendors = { [13510] = { n = "Kylanna Windwhisper", z = "Ashenvale", p = 40000, l = true, t = time(), by = "Sarge" } }
    FT.ShowCraft(r)
    local win = _G["WolfOfBootyBayCraft"]
    mock.layout.Settle(win)
    local found, texts = mock.layout.Overlaps(win)
    for _, o in ipairs(found) do
      total = total + 1
      print(string.format("OVERLAP [craft window] %q x %q  (%dx%d px)", o[1].text:sub(1, 50), o[2].text:sub(1, 50), o[3], o[4]))
    end
    for _, t in ipairs(texts) do
      if t.cut then cuts = cuts + 1; local rr = mock.layout.Rect(t.f); print(string.format("CUT [craft window] %q  box %d text %d", t.text:sub(1, 120), rr[2] - rr[1], mock.layout.TextWidth(t.f))) end
      if t.spill then cuts = cuts + 1; print(string.format("SPILL [craft window] %q", t.text:sub(1, 60))) end
    end
    print("craft window checked: " .. #texts .. " texts")
    win:Hide()
    FT.RECIPE_ITEMS, FT.db.recipeVendors = had, nil
  end
  FT.SetWindowSize("min")
  print("layout: " .. total .. " overlapping text pairs, " .. cuts .. " texts cut short")
  for id, n in pairs(held) do inv.bags[id] = n end
  FT.Fire("FT_INVENTORY_CHANGED")
end)
step("open item", function() FT.OpenItem(12363) end)
mock.run(1)
step("best use", function() FT.ShowBestUse(12359) end)
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
step("radar shown", function()
  FT.Show("radar")
  -- (v0.51: the old Radar's own list is gone; its calendar stays)
  assert(not FT.Radar.Build, "no Radar list worked out for nothing")
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
-- the Wolf network: what we send after a scan, and what we take from others (the junk guard holds an odd price)
step("network", function()
  local N = FT.Net
  FT.db.netSent = nil -- (the reload's pass: what the first one sent is remembered)
  FT.S.net, FT.S.netDeals = true, true -- (the settings step before clicks every box)
  -- a live price comes after a scan: newer than the hourly prices (the test's clock starts before the test feed)
  mock.now = math.max(mock.now, (FT.Feed.Time() or 0), (FT.Hist.LastScan("full") or 0), (FT.ScanTime() or 0)) + 600
  local realGuild = IsInGuild
  IsInGuild = function() return true end
  local id
  for _, r in ipairs(FT.Market.Rows() or {}) do if r.price and r.price > 1000 then id = r.id break end end
  assert(id, "an item with a price")
  local n = N.SendLive(time())
  assert(n > 0 and N.Queued() > 0, "changed prices are queued: " .. tostring(n))
  -- 400 a round, the busiest first: the next rounds the rest, then nothing (the same prices aren't said twice)
  local rounds = 1
  while N.SendLive(time()) > 0 and rounds < 30 do rounds = rounds + 1 end
  assert(rounds < 30 and N.SendLive(time()) == 0, "the same prices aren't said twice")
  local enc = FT.Hist.Enc
  local function Msg(sender, ...) mock.fire("CHAT_MSG_ADDON", "WOLFNET1", table.concat({ ... }, "\t"), "GUILD", sender) end
  local wire = enc(time() + ((GetServerTime and GetServerTime() or time()) - time()))
  -- a sane new price (10% over what it usually is): taken at once
  local st = FT.An.Stats(id)
  local usual = st.fair or st.avg or FT.Price(id)
  local want = math.floor(usual * 1.1)
  Msg("Friend-Realm", "L", "1", FT.houseKey, wire, enc(id) .. "," .. enc(want))
  local after, _, src = FT.Price(id)
  assert(src == "peer" and math.abs(after - want) <= 2, "a live price is taken: " .. tostring(want) .. " -> " .. tostring(after) .. " " .. tostring(src))
  -- ten times what we know: held; a second user agrees: taken
  local known = FT.An.Stats(id).fair or FT.An.Stats(id).avg or after
  Msg("Friend-Realm", "L", "1", FT.houseKey, wire, enc(id) .. "," .. enc(math.floor(known * 10)))
  local held = FT.Price(id)
  assert(math.abs(held - known * 10) > known, "an odd price waits")
  Msg("Other-Realm", "L", "1", FT.houseKey, wire, enc(id) .. "," .. enc(math.floor(known * 10.3)))
  local agreed = FT.Price(id)
  assert(math.abs(agreed - known * 10.15) <= known * 0.2, "two users agree: taken " .. tostring(agreed))
  -- a joke: dropped
  assert(N.Guard(id, known * 100, "X", time()) == "drop", "100x is dropped")
  -- farm rates, sales, deals
  Msg("Friend-Realm", "F", "1", enc(4440), "Southsea Pirate", enc(40), enc(id) .. ":" .. enc(14))
  Msg("Other-Realm", "F", "1", enc(4440), "Southsea Pirate", enc(20), enc(id) .. ":" .. enc(6))
  local ft = N.FarmText(id)
  assert(ft and ft:find("0.33") and ft:find("60"), "pooled farm rate: " .. tostring(ft))
  Msg("Friend-Realm", "S", "1", FT.houseKey, enc(id), enc(2000), enc(5), wire)
  assert(N.SoldText(id) and N.SoldText(id):find("5"), "a sale heard")
  -- (the reload's pass has the first pass's addon still listening in this fake game: count what the second call adds)
  local said = #mock.prints
  Msg("Friend-Realm", "G", "1", FT.houseKey, enc(id), enc(900), enc(25))
  local afterFirst = #mock.prints
  Msg("Friend-Realm", "G", "1", FT.houseKey, enc(id), enc(900), enc(25))
  assert(afterFirst > said and mock.prints[afterFirst]:find("25% under usual", 1, true), "a deal call says it")
  assert(#mock.prints == afterFirst, "the same deal again: nothing more")
  -- another auction house's: nothing
  Msg("Friend-Realm", "S", "1", "otherhouse", enc(id + 1), enc(2000), enc(5), wire)
  assert(not N.SoldText(id + 1), "another house's sale isn't taken")
  print("network: sent " .. n .. " changed prices; " .. ft:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "; " .. N.SoldText(id))
  IsInGuild = realGuild
end)
-- v0.43: opens on Today, search from any page, what you pick up, where a recipe comes from
step("v0.43", function()
  -- opened: Today, whatever page was last
  FT.Show("market"); WolfOfBootyBayFrame:Hide(); FT.Toggle()
  assert(FT.currentTab == "today", "opens on Today: " .. tostring(FT.currentTab))
  -- the top search: typing on Today takes you to Market with it
  local qs = FT.MainRefs.search
  assert(qs and qs:IsShown(), "the top search shows on Today")
  qs:SetText("thor")
  qs:GetScript("OnTextChanged")(qs, true)
  assert(FT.currentTab == "market", "typing opens Market: " .. tostring(FT.currentTab))
  assert(FT.Tabs.market.searchBox:GetText() == "thor", "Market's box has it: " .. tostring(FT.Tabs.market.searchBox:GetText()))
  assert(not qs:IsShown(), "the top search hides on Market")
  FT.Show("today")
  assert(qs:IsShown(), "and comes back elsewhere")
  -- Market: an item, then "< Market" back to its home (the overview); the tab itself opens on the home
  FT.OpenItem(12363)
  local ov, iv = FT.Tabs.market.Views()
  assert(iv:IsShown() and not ov:IsShown() and iv.back, "an item page with a way back")
  local click = iv.back:GetScript("OnClick")
  if click then click(iv.back, "LeftButton") else FT.Tabs.market.Home() end
  assert(ov:IsShown() and not iv:IsShown() and FT.Tabs.market.Selected() == nil, "back on the market's home")
  FT.OpenItem(12363)
  FT.Show("today")
  FT.Tabs.market.Home(); FT.SelectTab("market")
  assert(ov:IsShown(), "the Market tab opens on its home")
  -- picked up: ten more of something priced, at today's price; Today says it
  local P = FT.Port
  P.TrackPlay()
  local id
  for i, x in pairs(FT.db.inv[FT.charKey].bags) do
    local st = FT.An.Stats(i)
    if st and st.price and st.price > 100 then id = i break end
  end
  assert(id, "a priced item in the bags")
  local before = P.Played()
  local bags = FT.db.inv[FT.charKey].bags
  bags[id] = bags[id] + 10
  FT.Fire("FT_INVENTORY_CHANGED")
  P.Snapshot()
  local got = P.Played() - before
  local want = math.floor(10 * FT.An.Stats(id).price)
  assert(math.abs(got - want) <= 1, "picked up " .. got .. ", want " .. want)
  FT.Tabs.today.FillWorth()
  local since = FT.Tabs.today.since.__text or ""
  assert(since:find("picked up today", 1, true), "Today says it: " .. since)
  bags[id] = bags[id] - 10
  FT.Fire("FT_INVENTORY_CHANGED")
  P.Snapshot()
  -- the worth line on the first days: 14 days of what you hold
  print("today worth: " .. tostring(FT.Tabs.today.worth.__text) .. " | " .. tostring(FT.Tabs.today.update.__text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    .. " | " .. since:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. " | " .. tostring(FT.Tabs.today.span.__text))
  -- a recipe: from a trainer, from a merchant someone in the guild saw, on the auction house
  local r
  for _, x in ipairs(FT.Craft.AllRecipes()) do if x.name then r = x break end end
  local had = FT.RECIPE_ITEMS
  FT.RECIPE_ITEMS = {}
  assert(FT.Craft.RecipeSource(r).trainer, "no recipe item: a trainer")
  FT.RECIPE_ITEMS = { [r.name:lower()] = { 13510 } }
  FT.db.recipeVendors = nil
  local realGuild, realInstant = IsInGuild, FT.GetItemInfoInstant
  IsInGuild = function() return true end
  -- (the test's stand-in recipe item is a flask: the game would say it's a recipe)
  FT.GetItemInfoInstant = function(i) if i == 13510 then return i, nil, nil, nil, nil, 9, 2 end return realInstant(i) end
  local enc = FT.Hist.Enc
  mock.fire("CHAT_MSG_ADDON", "WOLFNET1", table.concat({ "V", "1", FT.houseKey, enc(13510), "Kylanna", "Ashenvale", enc(40000), "1" }, "\t"), "GUILD", "Sarge-Realm")
  IsInGuild, FT.GetItemInfoInstant = realGuild, realInstant
  local src = FT.Craft.RecipeSource(r)
  assert(src.vendor and src.vendor.n == "Kylanna" and src.vendor.l and src.vendor.by == "Sarge", "a merchant heard from the network")
  assert(src.ah and src.ah.id == 13510, "its price on the auction house")
  FT.ShowCraft(r)
  local line = WolfOfBootyBayCraft.recipe.text.__text or ""
  assert(line:find("Kylanna", 1, true), "the craft window says where: " .. line)
  print("recipe line: " .. line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  WolfOfBootyBayCraft:Hide()
  -- without the recipe data: no line
  FT.RECIPE_ITEMS = nil
  assert(FT.Craft.RecipeSource(r) == nil, "no recipe data: nothing said")
  FT.RECIPE_ITEMS, FT.db.recipeVendors = had, nil
end)
-- v0.50: where things come from, Coming up, the calendar and the best-moves card, the uniform bar, the
-- reminder, the calculator, Level it up and Worth learning, the version line
step("v0.50", function()
  local W = FT.Where
  -- Cured Rugged Hide: made (with salt on a timer), not farmed; Rugged Leather: farmed
  assert(FT.Craft.ByOutputAll(15407), "Cured Rugged Hide is crafted")
  assert(not W.Farmable(15407), "Cured Rugged Hide isn't farmed")
  local d = FT.Craft.TimerOf(15409)
  assert(d == 3, "Refined Deeprock Salt: every 3 days, got " .. tostring(d))
  assert(W.Farmable(8170), "Rugged Leather is farmed")
  local lines = W.Lines(8170, 6)
  assert(#lines > 0, "Rugged Leather says where")
  print("rugged leather: " .. lines[1]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  -- every traded item has a source (the build's gap list is empty) - spot check a few on the market
  local none = 0
  for i, r in ipairs(FT.Market.Rows() or {}) do
    if i > 400 then break end
    if not (FT.SRC[r.id] or (FT.SRC_H and FT.SRC_H[r.id]) or FT.Craft.ByOutputAll(r.id)) then none = none + 1 end
  end
  print("market rows without a source (first 400): " .. none)
  -- the vendor floor: a vendor reagent over its vendor price
  local v = FT.VendorBuy(3371)
  assert(v and FT.VendorFloor(3371, v * 3) == v, "the vendor floor")
  assert(FT.VendorFloor(3371, math.max(1, v - 1)) == nil, "cheaper on the AH: no floor")

  -- the network's nodes and chests: an O message, pooled into the loot line
  local enc = FT.Hist.Enc
  local realGuild = IsInGuild
  IsInGuild = function() return true end
  mock.fire("CHAT_MSG_ADDON", "WOLFNET1", table.concat({ "O", "1", enc(176584), "Felwood", enc(12), enc(13463) .. ":" .. enc(20) }, "\t"), "GUILD", "Sarge-Realm")
  assert(FT.db.netObj and next(FT.db.netObj), "the nodes are pooled")

  -- the version line: once per new version, then quiet - from the network (the version rides on every message)
  -- and from the price file
  FT.db.told = {}
  local said = #mock.prints
  mock.fire("CHAT_MSG_ADDON", "WOLFNET1", table.concat({ "S", "1", "otherhouse", enc(1), enc(1), enc(1), enc(1), "v0.98" }, "\t"), "GUILD", "Sarge-Realm")
  assert(#mock.prints == said + 1 and mock.prints[#mock.prints]:find("v0.98", 1, true), "a newer version heard: one line")
  mock.fire("CHAT_MSG_ADDON", "WOLFNET1", table.concat({ "S", "1", "otherhouse", enc(1), enc(1), enc(1), enc(1), "v0.98" }, "\t"), "GUILD", "Kev-Realm")
  mock.fire("CHAT_MSG_ADDON", "WOLFNET1", table.concat({ "S", "1", "otherhouse", enc(1), enc(1), enc(1), enc(1), "v0.5" }, "\t"), "GUILD", "Kev-Realm")
  assert(#mock.prints == said + 1, "the same version again, or an older one: quiet")
  local feedRel = FT.FEED.release
  FT.FEED.release = "0.98.202612010000"
  FT.Ver.Remind()
  assert(#mock.prints == said + 1, "the price file's same version: quiet")
  FT.FEED.release = "0.99.202612020000"
  FT.Ver.Remind(); FT.Ver.Remind()
  assert(#mock.prints == said + 2 and mock.prints[#mock.prints]:find("v0.99", 1, true), "a newer one from the price file: one line")
  FT.FEED.release = feedRel
  -- ours goes with every message
  local sent = {}
  local realSend = C_ChatInfo.SendAddonMessage
  C_ChatInfo.SendAddonMessage = function(prefix, text) if prefix == "WOLFNET1" then sent[#sent + 1] = text end return true end
  FT.Net.Deal(12363, 100, -0.4)
  mock.run(5, 0.5)
  C_ChatInfo.SendAddonMessage = realSend
  IsInGuild = realGuild
  for _, t in ipairs(sent) do assert(t:find("\tv0%.9$"), "the version rides along: " .. t) end
  assert(#sent > 0, "a message went out")
  print("network messages with the version: " .. #sent)

  -- the calendar: the Darkmoon Faire in Mulgore from Dec 7, 2026; a battleground holiday week each week
  local t0 = time({ year = 2026, month = 12, day = 1, hour = 12 })
  local ev = FT.Ahead.Events(14, t0)
  local faire, bg
  for _, e in ipairs(ev) do
    if e.kind == "faire" then faire = e end
    if e.kind == "bg" then bg = e end
  end
  assert(faire and (faire.where or ""):find("Mulgore", 1, true) and date("%d", faire.t) == "07", "the Faire: Mulgore, Dec 7")
  assert(bg, "a battleground's holiday week")
  -- the reminder: the day before, once
  FT.db.reminded = {}
  said = #mock.prints
  FT.Ahead.Remind(faire.t - 20 * 3600)
  FT.Ahead.Remind(faire.t - 19 * 3600)
  local faireLines = 0
  for i = said + 1, #mock.prints do if mock.prints[i]:find("Coming up tomorrow", 1, true) and mock.prints[i]:find("Darkmoon", 1, true) then faireLines = faireLines + 1 end end
  assert(faireLines == 1, "the Faire's reminder, once: " .. faireLines)

  -- Coming up: the calls (how sure, never under 40%), the page and Today's calendar
  local l = FT.Ahead.Lists()
  for _ = 1, 40 do
    if l then break end
    mock.run(5, 0.05)
    l = FT.Ahead.Lists()
  end
  assert(l, "next week's calls are worked out")
  for _, r in ipairs(l.farms) do assert(r.call.sure >= 40 and r.call.sure <= 100, "how sure: " .. r.call.sure) end
  print(string.format("coming up: %d farms, %d raids, %d pvp", #l.farms, #l.raids, #l.pvp))
  -- (v0.51) Coming up came apart: Raids, PvP, Farm it's Next week
  FT.ShowSub("make", "pvp")
  assert(FT.currentTab == "pvp", "Make gold > PvP")
  local pv = FT.Futures.PvP()
  assert(#pv >= 15 and pv[1].roles and pv[1].conf, "the PvP study's list: " .. #pv)
  print("pvp: " .. #pv .. " items, first " .. FT.ItemText(pv[1].id):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. ", " .. #FT.Futures.PvPMaterials(10) .. " materials; " .. FT.Futures.PvPHeadline())
  FT.ShowSub("make", "raid")
  assert(FT.currentTab == "radar", "Make gold > Raids")
  FT.Show("today")
  local TT = FT.Tabs.today
  TT.FillComing()
  assert(TT.coming.days[1].day.__text == "Today", "the calendar starts today")
  local withEvent
  for _, dd in ipairs(TT.coming.days) do if #dd.events > 0 then withEvent = dd break end end
  if withEvent then
    withEvent:GetScript("OnClick")(withEvent)
    assert(TT.coming.picked == withEvent.t, "a day picked")
    withEvent:GetScript("OnClick")(withEvent)
    assert(TT.coming.picked == nil, "and unpicked")
  end
  TT.FillMoves()
  print("best moves card: " .. #TT.moves.list.items .. " rows" .. (TT.moves.list.items[1] and (", first " .. tostring(TT.moves.list.items[1].kind)) or ""))

  -- the uniform bar: the same spot on every Make gold and You page
  local function Vis(f)
    while f do
      if f.__shown == false then return false end
      if f == UIParent then return true end
      f = f.__parent
    end
    return true
  end
  for _, g in ipairs({ "make", "you" }) do
    local at
    for _, e in ipairs(FT.GROUPS[g]) do
      FT.ShowSub(g, e[1])
      for _, bar in ipairs(FT.GroupBarsOf(g)) do
        if Vis(bar) then
          local r = mock.layout.Rect(bar)
          if at then
            assert(math.abs(r[1] - at[1]) <= 1 and math.abs(r[3] - at[3]) <= 1,
              string.format("%s > %s: the bar at %d,%d, not %d,%d", g, e[1], r[1], r[3], at[1], at[3]))
          else at = r end
        end
      end
    end
  end

  -- the calculator
  local C = FT.Calc
  assert(C.ParseMoney("12g 50s") == 125000 and C.ParseMoney("1.5") == 15000 and C.ParseMoney("75s") == 7500 and C.ParseMoney("x") == nil, "prices typed")
  local b = C.Buy(12363, 5)
  assert(b and b.total > 0 and b.got >= 1, "buying walks the listings")
  local x = C.Sell(12363, 5)
  assert(x and x.take == x.gross - x.cut and x.cut == math.floor(x.gross * FT.Cut() + 0.5), "selling: take home after the cut")
  -- (v0.51) the Calculator page and its cheat sheet
  FT.db.calcSheet = nil
  FT.ShowCalc(12363, "sell")
  local CT = FT.Tabs.calc
  assert(FT.currentTab == "calc" and (CT.lines[1].__text or ""):find("take home", 1, true), "the calculator page, selling")
  print("calc: " .. (CT.lines[1].__text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  CT.qty:SetValue("500")
  CT.Log()
  FT.ShowCalc(12363, "buy")
  CT.Log()
  -- no item: plain sums
  CT.item:SetValue(""); CT.FindItem("")
  FT.ShowCalc(nil, "buy")
  CT.each:SetValue("12g 50s"); CT.qty:SetValue("4")
  local plain = CT.Sum()
  assert(plain.total == 500000, "4 at 12g 50s: " .. tostring(plain.total))
  CT.Log()
  assert(#FT.db.calcSheet == 3 and FT.db.calcSheet[1].total == 500000, "the cheat sheet keeps the sums, newest first")
  assert(CT.FindItem(FT.Name(12363) or "x") == 12363, "an item by its name")
  local w = CT.wipe:GetScript("OnClick")
  w(CT.wipe); assert(#FT.db.calcSheet == 3, "one click on Wipe only asks")
  w(CT.wipe); assert(#FT.db.calcSheet == 0, "the second wipes it")
  CT.Log()
  CT.each:SetValue(""); CT.qty:SetValue("")
  -- (v0.54) the item box suggests as you type; a pick fills it
  local nm = FT.Name(12363) or ""
  local ids = CT.Suggest(nm)
  local has = false
  for _, id in ipairs(ids) do if id == 12363 then has = true end end
  assert(#ids >= 1 and #ids <= 8 and has, "suggestions for '" .. nm .. "': " .. #ids)
  assert(#CT.Suggest("x") == 0, "one letter: no list yet")
  CT.item:SetValue(nm:sub(1, 5)); CT.ShowSuggest(CT.Suggest(nm:sub(1, 5)))
  assert(CT.sugg:IsShown(), "the list opens under the box")
  CT.PickItem(12363)
  assert(not CT.sugg:IsShown() and CT.Sum().id == 12363 and CT.item:GetText() == nm, "a pick fills the box and closes the list")
  -- (v0.54) buying walks your last scan's listings at today's price when a newer price came since
  local lvb, lp, lpt = C.Levels(12363)
  local raw = FT.Hist.Book(12363)
  if lvb and lp and lpt and raw and raw.t and lpt > raw.t + 1800 and math.abs(lp - raw.levels[1][1]) / raw.levels[1][1] > 0.01 then
    assert(lvb.shifted and lvb.levels[1][1] == lp, "the listings shifted to today's price")
  end
  print("calc listings: " .. (lvb and lvb.shifted and "shifted to today's price" or "as scanned"))

  -- Level it up and Worth learning (the test's recipes are another character's: this one gets a copy, and skills)
  local ks = {}
  for k, profs in pairs(FT.db.recipes) do ks[#ks + 1] = tostring(k) .. ":" .. tostring(FT.db.chars[k] and FT.db.chars[k].side) end
  print("recipes of: " .. table.concat(ks, ", ") .. " me " .. tostring(FT.charKey) .. " side " .. tostring(FT.sideKey))
  local hadRecipes = FT.db.recipes[FT.charKey]
  if not hadRecipes then
    FT.db.recipes[FT.charKey] = { Alchemy = { scanned = time(), name = "Alchemy", list = {
      { name = "Major Healing Potion", output = 13446, outputQty = 1, reagents = { { itemID = 13464, qty = 2 }, { itemID = 13465, qty = 1 }, { itemID = 8925, qty = 1 } } } } } }
    FT.Fire("FT_RECIPES_CHANGED")
  end
  FT.db.chars[FT.charKey].profs = FT.db.chars[FT.charKey].profs or { Alchemy = 280, Tailoring = 250, Engineering = 260, Blacksmithing = 270, Leatherworking = 260, Enchanting = 270, Cooking = 250 }
  local mine = FT.db.recipes[FT.charKey]
  local marked
  for _, data in pairs(mine or {}) do
    for _, r in ipairs(data.list or {}) do if not marked then r.diff = "optimal"; marked = r end end
  end
  local lv = FT.Craft.LevelUp("all")
  local wl = FT.Craft.WorthLearning("all")
  print("level it up: " .. (lv and #lv or "nil") .. " rows; worth learning: " .. #wl .. (wl[1] and (", first " .. FT.Craft.LearnText(wl[1]):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) or ""))
  assert(lv and #lv >= 1, "Level it up lists the orange recipe")
  FT.SelectTab("craft")
  FT.Tabs.craft.SetView("level")
  FT.Tabs.craft.SetView("learn")
  FT.Tabs.craft.SetView("recipes")
  if marked then marked.diff = nil end
  if not hadRecipes then FT.db.recipes[FT.charKey] = nil; FT.Fire("FT_RECIPES_CHANGED") end
end)
-- v0.51: how to learn it, truer sources, the craft window's last row, the small tracker, Make gold apart, the
-- calendar's jumps, the undercut check and what to post tonight
step("v0.51", function()
  local W = FT.Where
  local function Plain(x) return (x or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
  -- Thorium Widget: made, so no Where to get it; its Craft it section leads with the recipe
  assert(#W.Lines(15994, 6) == 0, "Thorium Widget: no target dummy, no drops under 5%")
  local r = FT.UI.RecipeOf(15994)
  local rt = Plain(FT.Tabs.market.RecipeText(r, false))
  assert(rt:find("^Recipe: ") and (rt:find("trainer", 1, true) or rt:find("vendor", 1, true) or rt:find("drops", 1, true)), "the recipe line: " .. rt)
  print("thorium widget: " .. rt)
  -- Thornstone Sledgehammer, BoE gear: the world drop first
  local realInstant = FT.GetItemInfoInstant
  FT.GetItemInfoInstant = function(i) if i == 1722 then return i, nil, nil, nil, nil, 2, 4 end return realInstant(i) end
  local tl = W.Lines(1722, 6)
  FT.GetItemInfoInstant = realInstant
  assert(tl[1] and Plain(tl[1]):find("^World drop"), "gear: the world drop first: " .. Plain(tl[1] or "none"))
  for _, l in ipairs(tl) do assert(not Plain(l):find("Chest"), "no chest for gear with a drop: " .. Plain(l)) end
  -- vendors that aren't in the world aren't vendors (Jimmy McWeaksauce on Thorium Headed Arrow)
  for _, l in ipairs(W.Lines(18042, 6)) do assert(not l:find("McWeaksauce", 1, true), "no test vendors") end
  -- a boss's instance: Ragnaros, Molten Core
  assert((FT.SRC_N[11502] or ""):find("Molten Core", 1, true), "Ragnaros is in Molten Core")
  -- the item page with a long source line: no "..." (it wraps), and the hover has it whole
  FT.OpenItem(264011)
  mock.run(1)

  -- the craft window: the last row's answer sits beside its label
  local rr = FT.UI.RecipeOf(13446)
  if rr then
    FT.ShowCraft(rr)
    local d = WolfOfBootyBayCraft
    for _, pair in ipairs(d.sum) do assert(pair[1]:GetParent() == pair[2]:GetParent(), "label and answer on one row") end
    d:Hide()
  end

  -- the folded session tracker: no "Session", pause and stop on it, narrower
  FT.S.sessionPanel = true
  FT.Session.Start()
  FT.db.ui = FT.db.ui or {}
  FT.db.ui.hudFolded = true
  FT.UpdateHUD()
  local h = WolfOfBootyBaySession
  assert(h and h:IsShown(), "the tracker shows")
  assert(not (h.title.__text or ""):find("Session", 1, true), "no Session in it: " .. tostring(h.title.__text))
  assert(h.miniPause:IsShown() and h.miniStop:IsShown(), "pause and stop when folded")
  assert(h:GetWidth() <= 180, "folded, it's narrow: " .. h:GetWidth())
  assert(h.miniPause:GetWidth() >= 20, "a pause button you can hit")
  assert(h.miniPause:GetWidth() == h.miniStop:GetWidth() and h.miniStop:GetWidth() == h.fold:GetWidth()
    and h.miniPause:GetHeight() == h.fold:GetHeight(), "fold, pause and stop: one size")
  print("folded tracker: " .. h:GetWidth() .. " x " .. h:GetHeight())
  h.miniPause:GetScript("OnClick")(h.miniPause)
  assert(FT.Session.Current().paused, "pause from the folded tracker")
  h.miniPause:GetScript("OnClick")(h.miniPause)
  FT.db.ui.hudFolded = nil
  FT.UpdateHUD()
  assert(not h.miniPause:IsShown() and h:GetWidth() == 260, "unfolded: as before")
  FT.Session.Stop()

  -- Make gold: Flip it, Craft it, Farm it, Raids, PvP (Coming up came apart)
  local keys = {}
  for _, e in ipairs(FT.GROUPS.make) do keys[#keys + 1] = e[1] end
  assert(table.concat(keys, ",") == "make,craft,farm,raid,pvp", "Make gold's sections: " .. table.concat(keys, ","))
  assert(not FT.Tabs.coming, "no Coming up page")

  -- the calendar: a battleground week's tag jumps to PvP; All of it shows four weeks
  FT.Show("today")
  local TT = FT.Tabs.today
  local c = TT.coming
  c.weeks, c.from, c.picked = 1, nil, nil
  TT.FillComing()
  local bgDay
  for _, dd in ipairs(c.days) do
    if dd:IsShown() and dd.events and dd.events[1] and dd.events[1].kind == "bg" then bgDay = dd break end
  end
  if bgDay then
    bgDay.evBtn:GetScript("OnClick")(bgDay.evBtn)
    assert(FT.currentTab == "pvp", "a battleground week's tag opens PvP: " .. tostring(FT.currentTab))
    FT.Show("today")
  end
  c.all:GetScript("OnClick")(c.all)
  assert(c.weeks == 4 and c.days[28]:IsShown() and not c.list:IsShown(), "All of it: four weeks")
  c.all:GetScript("OnClick")(c.all)
  assert(c.weeks == 1 and not c.days[8]:IsShown() and c.list:IsShown(), "and back to this week")

  -- the undercut check and what to post tonight: one row each, on top of your best moves
  local realList, realUnder = FT.Owned.List, FT.Owned.Undercut
  FT.Owned.List = function() return { { itemID = 12363, unit = 50000, qty = 5 }, { itemID = 13446, unit = 9000, qty = 2 } } end
  FT.Owned.Undercut = function(a) if a.itemID == 12363 then return 48000 end end
  local u = TT.Undercuts()
  assert(u and u.id == 12363 and u.label == "UNDERCUT", "the undercut row")
  TT.FillMoves()
  local found
  for _, m in ipairs(TT.moves.list.items) do if m.label == "UNDERCUT" then found = true end end
  assert(found, "the undercut row is in your best moves")
  FT.Owned.List, FT.Owned.Undercut = realList, realUnder
  local realWhen, realRows = FT.WhenSummary, FT.Port.Rows
  local hour = tonumber(date("%H"))
  FT.Port.Rows = function() return { { id = 12363, value = 900000, signal = "SELL" } } end
  FT.WhenSummary = function() return { timed = true, sellAt = (hour + 3) % 24, sell = "later" } end
  local pt = TT.PostTonight()
  assert(pt and pt.id == 12363 and pt.label == "POST", "what to post tonight")
  print("post tonight: " .. Plain(pt.what) .. " | undercut: " .. Plain(u.what))
  FT.WhenSummary = function() return { timed = true, sellAt = (hour + 12) % 24, sell = "later" } end
  assert(not TT.PostTonight(), "not in the next few hours: no row")
  FT.WhenSummary, FT.Port.Rows = realWhen, realRows
  TT.FillMoves()
end)
-- v0.52: compact by default (sizes in Settings), Today about you, the market's own lists, lighter
step("v0.52", function()
  assert(FT.S.windowSize == "min" or FT.S.windowSize == nil or FT.Compact(), "compact by default")
  FT.SetWindowSize("max"); assert(FT.WindowMaximized(), "full screen from Settings")
  FT.SetWindowSize("min"); assert(FT.Compact(), "and back to compact")
  -- Today: your movers, while you were away
  local TT = FT.Tabs.today
  FT.Show("today")
  local mv = TT.YourMovers()
  for _, x in ipairs(mv) do assert(x.gold and x.ch1 and math.abs(x.ch1) >= 0.02, "a mover of yours") end
  FT.Journal.Add("S", 12363, 3, 150000, 7500, time() - 60)
  FT.Journal.Add("X", 13446, 2, 0, 0, time() - 60)
  local away, sold = TT.Away()
  local kinds = {}
  for _, x in ipairs(away) do kinds[x.id] = true end
  assert(kinds[12363] and kinds[13446] and sold >= 142500, "while you were away: the sale and what came back")
  print(string.format("today: %d movers of yours, %d while away (+%s sold)", #mv, #away, FT.Money(sold, "gold")))
  -- Market's home: most traded, Market Makers, each pair on a switch
  FT.Tabs.market.Home(); FT.SelectTab("market")
  local mt = FT.Market.MostTraded(20)
  for _ = 1, 60 do if mt then break end; mock.run(5, 0.05); mt = FT.Market.MostTraded(20) end
  -- (by this step the test's market is a handful of made-up items: the list can be short)
  assert(mt ~= nil, "most traded is worked out")
  print("most traded: " .. #mt)
  for i = 2, #mt do assert(mt[i - 1].gold >= mt[i].gold, "most gold a day first") end
  local ov = FT.Tabs.market.Views()
  ov.whoSeg.buttons[1].onClick()
  assert(ov.traded:IsShown() and not ov.makers:IsShown(), "Most traded on its switch")
  ov.whoSeg.buttons[2].onClick()
  assert(ov.makers:IsShown() and not ov.traded:IsShown(), "Market Makers on its switch")
  ov.whoSeg.buttons[1].onClick()
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
