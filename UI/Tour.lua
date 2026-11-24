-- Wolf of Booty Bay (built on ForeverTrading): the tour - step by step over the real window: everything but the part a step is about is
-- dimmed, the part is ringed, and a note beside it says what it is and does (Back, Next, Esc to end). A step
-- whose part isn't on the screen (the compact window has no order book) is passed over. Offered on a first
-- install; again any time: Settings > About, /wolf tour.
local ADDON, FT = ...
local UI = FT.UI
local L = FT.L

local TR = {}
FT.Tour = TR

local PAD = 6       -- the ring around a part
local NOTE_W = 320

local function Tab(key) return FT.Tabs[key] end

-- { title, text, tab (opened first), prep (a view first), target (the part) } - made when the tour first runs:
-- the language is applied at start, after the files are read (a table made with them would keep the English)
local STEPS
local function MakeSteps() return {
    { title = L["The pages"],
      text = L["Market: the prices and charts of every item. Craft: what your recipes cost and bring. Signals: what to do now. Portfolio: what all you own is worth. Selling: post from your bags and watch your auctions."],
      target = function() return FT.MainRefs and FT.MainRefs.nav end },
    { title = L["The auction house"],
      text = L["Green while you are at an auctioneer: the item you have open is searched again every few seconds, and you can buy, post and cancel right here. Click: the game's own auction house window."],
      target = function() return FT.MainRefs and FT.MainRefs.pill end },
    { title = L["Which auction house"],
      text = L["Your faction's or Blackwater, the neutral one: each keeps its own prices. Talking to an auctioneer picks its house; a click shows the other one's prices (at an auctioneer: offline there). The pencil: this auctioneer is of the other house."],
      target = function() return FT.MainRefs and FT.MainRefs.house end },
    { title = L["Scan and exchange"],
      text = L["Full scan: the prices of the whole market in a couple of minutes (at an auctioneer). Exchange: fresh prices from Wolf of Booty Bay users in your guild and group, anywhere."],
      target = function() return FT.MainRefs and FT.MainRefs.scan end },
    { title = L["Terminal"], tab = "market",
      text = L["Search any item. Click one: its price, chart and what to do. Right-click: watchlist."],
      target = function() return Tab("market").listPanel end },
    { title = L["Item windows"], tab = "market",
      -- an item open on the Market (the first of the list when none is): its More button
      prep = function()
          local M = Tab("market")
          if not M.Selected() then
              local rows = FT.Market.Rows()
              if rows and rows[1] then M.Select(rows[1].id) end
          end
      end,
      text = L["More: the item in a window of its own - up to four at once, two items side by side. Each window has its own auction house (its chip) and a compact mode with the charts alone."],
      target = function() return Tab("market").more end },
    { title = L["The order book"], tab = "market",
      text = L["Every listing by price, how many, by how many sellers. Click a price: how many to buy; Buy: at an auctioneer, at the server's exact price."],
      target = function() return Tab("market").book end },
    { title = L["Craft"], tab = "craft", craft = true, prep = function() Tab("craft").SetView("recipes") end,
      text = L["What each recipe costs with its cheapest materials (auction house, vendor or crafting it yourself), what it brings, its risks. Queue: the materials to buy for several crafts at once."],
      target = function() return Tab("craft").viewSeg end },
    { title = L["Money"], tab = "signals", prep = function() Tab("signals").SetView("signals") end,
      text = L["What to sell and buy now, and deals: under what a vendor pays, far under the normal price, or cheaper than the other auction house sells it for."],
      target = function() return Tab("signals").viewSeg end },
    { title = L["The carry list"], tab = "signals",
      prep = function()
          local S = Tab("signals")
          S.SetView("deals")
          S.SetDealKind("HOUSES")
      end,
      text = L["Cheaper at one auction house than the other sells it for. A right click on a deal puts it on your carry list: it stays here, and at the other auction house the Sell page shows what you brought and what it cost."],
      target = function() return Tab("signals").dealsKind end },
    { title = L["Sell"], tab = "sell", prep = function() Tab("sell").SetView("bags") end,
      text = L["Your bags at market prices, a copper under the lowest. My auctions: who undercut you."],
      target = function() return Tab("sell").viewSeg end },
    { title = L["Portfolio and journal"], tab = "portfolio", prep = function() Tab("portfolio").SetView("portfolio") end,
      text = L["What everything your characters own is worth. Deals journal: what you really earned, from the auction house's letters."],
      target = function() return Tab("portfolio").viewSeg end },
    { title = L["Settings"],
      text = L["Signal thresholds, the exchange, alerts, your data. In About: What's new, and this tour again (/wolf tour)."],
      target = function() return FT.MainRefs and FT.MainRefs.gear end },
} end

local overlay, shades, ring, note
local step = 0
local placed = false -- the step's part found: from then on the note follows it

-- a frame's place on the screen, in UIParent's units: left, bottom, width, height (nil: not on the screen)
local function Rect(f)
    if not (f and f.IsVisible and f:IsVisible()) then return nil end
    local l, b, w, h = f:GetRect()
    if not (l and w and w > 2 and h > 2) then return nil end
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * s, b * s, w * s, h * s
end

local function Shade(i, x, y, w, h)
    local t = shades[i]
    if w <= 0 or h <= 0 then
        t:Hide()
        return
    end
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    t:SetSize(w, h)
    t:Show()
end

-- everything placed around the part of this step (it follows the window as it moves)
local function Place()
    local s = STEPS[step]
    local l, b, w, h = Rect(s and s.target())
    if not l then return false end
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local x0, y0, x1, y1 = l - PAD, b - PAD, l + w + PAD, b + h + PAD
    Shade(1, 0, y1, W, H - y1)            -- above
    Shade(2, 0, 0, W, y0)                 -- below
    Shade(3, 0, y0, x0, y1 - y0)          -- left
    Shade(4, x1, y0, W - x1, y1 - y0)     -- right
    ring:ClearAllPoints()
    ring:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x0, y0)
    ring:SetSize(x1 - x0, y1 - y0)
    -- the note under the part, else over it; within the screen
    local nh = note:GetHeight()
    local ny = (y0 - 12 - nh > 8) and (y0 - 12 - nh) or math.min(H - nh - 8, y1 + 12)
    local nx = math.max(8, math.min(W - NOTE_W - 8, x0))
    note:ClearAllPoints()
    note:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", nx, ny)
    return true
end

local function Build()
    overlay = CreateFrame("Frame", "WolfOfBootyBayTour", UIParent)
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    overlay:SetAllPoints(UIParent)
    overlay:EnableMouse(true) -- the window under it waits while the tour runs
    overlay:Hide()
    table.insert(UISpecialFrames, "WolfOfBootyBayTour")
    shades = {}
    for i = 1, 4 do
        local t = overlay:CreateTexture(nil, "BACKGROUND")
        t:SetColorTexture(0, 0, 0, 0.55)
        shades[i] = t
    end
    ring = CreateFrame("Frame", nil, overlay)
    UI.Border(ring, "accent")
    note = UI.Panel(overlay, "bg1", "accent")
    note:SetFrameLevel(overlay:GetFrameLevel() + 10)
    note:SetWidth(NOTE_W)
    note.count = UI.Text(note, 10, "dim", "RIGHT")
    note.count:SetPoint("TOPRIGHT", -12, -12)
    note.title = UI.Text(note, 14, "text")
    note.title:SetPoint("TOPLEFT", 14, -12)
    note.title:SetPoint("RIGHT", note.count, "LEFT", -8, 0)
    note.text = UI.Text(note, 11, "muted")
    note.text:SetPoint("TOPLEFT", note.title, "BOTTOMLEFT", 0, -8)
    note.text:SetWidth(NOTE_W - 28)
    if note.text.SetWordWrap then note.text:SetWordWrap(true) end
    note.text:SetJustifyH("LEFT")
    note.next = UI.Button(note, L["Next"], 10, 24, "primary", function() TR.Go(step + 1, 1) end)
    note.next:SetPoint("BOTTOMRIGHT", -12, 12)
    note.back = UI.Button(note, L["Back"], 10, 24, "default", function() TR.Go(step - 1, -1) end)
    note.back:FitText(24)
    note.back:SetPoint("RIGHT", note.next, "LEFT", -8, 0)
    note.skip = UI.Button(note, L["End the tour"], 10, 24, "default", function() overlay:Hide() end)
    note.skip:FitText(16)
    note.skip:SetPoint("BOTTOMLEFT", 8, 12)
    -- it follows the window (moved, resized, a page laid out)
    local acc = 0
    overlay:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.1 then return end
        acc = 0
        -- the part gone from the screen (the window made compact, say): on to the next step
        if placed and not Place() then TR.Go(step + 1, 1) end
    end)
    overlay:SetScript("OnHide", function()
        if FT.db then FT.db.tourDone = true end
        if step > 0 then
            step = 0
            FT.Print(L["The tour is over. Again: Settings > About, or /wolf tour."])
        end
    end)
end

-- step i (dir: which way to pass over a step whose part isn't on the screen)
function TR.Go(i, dir)
    if i < 1 then i, dir = 1, 1 end
    if i > #STEPS then
        overlay:Hide()
        return
    end
    local s = STEPS[i]
    step, placed = i, false
    if s.tab then FT.Show(s.tab) end
    if s.prep then pcall(s.prep) end
    note.title:SetText(s.title)
    note.text:SetText(s.text)
    note.count:SetText(i .. " / " .. #STEPS)
    note.back:SetShown(i > 1)
    note.next:SetLabel(i == #STEPS and L["Done"] or L["Next"])
    note.next:FitText(24)
    note:SetHeight(12 + 18 + 8 + math.ceil(note.text:GetStringHeight()) + 14 + 24 + 12)
    -- a page just opened lays out in a moment: then its part is looked for
    for _, t in ipairs(shades) do t:Hide() end
    ring:SetSize(1, 1)
    note:SetAlpha(0)
    C_Timer.After(0.15, function()
        if step ~= i or not overlay:IsShown() then return end
        if Place() then
            placed = true
            note:SetAlpha(1)
        else
            TR.Go(i + (dir or 1), dir or 1)
        end
    end)
end

function TR.Start()
    if InCombatLockdown and InCombatLockdown() then
        FT.Print(L["After the fight: the tour opens the pages of the window."])
        return
    end
    if not overlay then Build() end
    if not STEPS then
        -- the Craft step only when the Craft tab is on
        STEPS = {}
        for _, s in ipairs(MakeSteps()) do
            if not s.craft or FT.S.showCraft then STEPS[#STEPS + 1] = s end
        end
    end
    FT.Show("market")
    if FT.News and FT.News.Hide then FT.News.Hide() end
    overlay:Show()
    TR.Go(1, 1)
end
