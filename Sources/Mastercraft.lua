-- ForeverTrading: Mastercraft link.
-- Mastercraft keeps (in its saved data, MastercraftDB) the recipes every character knows with their
-- materials, its own auction house scan with how many are listed at each price, and what every
-- character holds. ForeverTrading only reads it: its scans go into our history, its recipes and holdings
-- cover the alts ForeverTrading hasn't seen yet. Settings > Sources can turn it off.
local ADDON, FT = ...

local MC = {}
FT.MC = MC

-- installed and allowed in Settings
function MC.Loaded()
    return type(MastercraftDB) == "table" and not (FT.S and FT.S.useMastercraft == false)
end

local function SameSide(c)
    if type(c) ~= "table" then return false end
    if c.realm and FT.ServerOf(c.realm) ~= FT.ServerOf(GetRealmName()) then return false end
    if c.faction and c.faction ~= UnitFactionGroup("player") then return false end
    return true
end

-- characters of this server and faction: guid -> Mastercraft's character record
function MC.Chars()
    local out = {}
    local db = MastercraftDB
    if not (type(db) == "table" and type(db.chars) == "table") then return out end
    for guid, c in pairs(db.chars) do
        if SameSide(c) then out[guid] = c end
    end
    return out
end

-- fn(guid, profession, recipe, char) for every learned recipe of this side's characters.
-- recipe = { name, icon, output = itemID, outputQty, reagents = { { itemID, qty } }, cooldown, diff }
function MC.EachRecipe(fn)
    local db = MastercraftDB
    if not (type(db) == "table" and type(db.recipes) == "table") then return end
    local chars = MC.Chars()
    for guid, profs in pairs(db.recipes) do
        local c = chars[guid]
        if c and type(profs) == "table" then
            for prof, data in pairs(profs) do
                if type(data) == "table" and type(data.list) == "table" then
                    for _, r in ipairs(data.list) do
                        if type(r) == "table" and r.learned ~= false then fn(guid, prof, r, c) end
                    end
                end
            end
        end
    end
end

-- Mastercraft's price book for this server and faction
function MC.Book()
    local db = MastercraftDB
    if not (type(db) == "table" and type(db.prices) == "table") then return nil end
    local faction = UnitFactionGroup("player") or ""
    local book = db.prices[FT.SideKey()] or db.prices[(GetRealmName() or "") .. "-" .. faction]
    if type(book) == "table" then return book end
    -- a key written another way, but only of this server and faction (never another server's prices)
    local myServer = FT.ServerOf(GetRealmName())
    local best
    for key, b in pairs(db.prices) do
        if type(key) == "string" and type(b) == "table" and key:sub(-#faction - 1) == "-" .. faction then
            local prefix = key:sub(1, -#faction - 2)
            if prefix == myServer or FT.ServerOf(prefix) == myServer then
                if not best or (b.lastScan or 0) > (best.lastScan or 0) then best = b end
            end
        end
    end
    return best
end

-- price, time seen, listed (nil = unknown), tiers ({ {price, qty}, ... } cheapest first)
function MC.Price(itemID)
    local book = MC.Book()
    local e = book and type(book.items) == "table" and book.items[itemID]
    if type(e) ~= "table" or type(e.p) ~= "number" or e.p <= 0 or e.gone then return nil end
    local listed = e.n
    if not listed and type(e.tiers) == "table" then
        listed = 0
        for _, tier in ipairs(e.tiers) do listed = listed + (tier[2] or 0) end
    end
    return e.p, e.t, listed, e.tiers
end

function MC.LastScan()
    local book = MC.Book()
    return book and book.lastScan or nil
end

-- fn(guid, char, inv) for this side's characters; inv = { bags = {[id]=n}, bank = {...}, mail = {...} }
function MC.EachInventory(fn)
    local db = MastercraftDB
    if not (type(db) == "table" and type(db.inv) == "table") then return end
    local chars = MC.Chars()
    for guid, inv in pairs(db.inv) do
        if chars[guid] and type(inv) == "table" then fn(guid, chars[guid], inv) end
    end
end

---------------------------------------------------------------------------
-- Mastercraft's scans go into our price history too
---------------------------------------------------------------------------
function MC.Import()
    local book = MC.Book()
    if not (book and type(book.items) == "table") then return 0 end
    local meta = FT.R().meta
    local last = meta.mcImport or 0
    local newest, count = last, 0
    for itemID, e in pairs(book.items) do
        if type(itemID) == "number" and type(e) == "table" and type(e.t) == "number" and e.t > last
            and type(e.p) == "number" and e.p > 0 and not e.gone then
            local _, _, listed, tiers = MC.Price(itemID)
            FT.Hist.Observe(itemID, e.p, listed, nil, e.t, "mastercraft")
            local have = FT.Hist.Book(itemID)
            if type(tiers) == "table" and #tiers > 0 and not (have and (have.t or 0) >= e.t) then
                local levels = {}
                for _, tier in ipairs(tiers) do
                    if tier[1] and tier[2] then levels[#levels + 1] = { tier[1], tier[2], 0 } end
                end
                FT.Hist.SetBook(itemID, { t = e.t, levels = levels, qty = listed, source = "mastercraft" })
            end
            count = count + 1
            if e.t > newest then newest = e.t end
        end
    end
    meta.mcImport = newest
    if count > 0 then
        FT.Debug("Mastercraft prices imported:", count)
        FT.Fire("FT_PRICES_CHANGED", "mastercraft")
    end
    return count
end

local watching
FT.On("FT_READY", function()
    if MC.Loaded() then
        C_Timer.After(2, MC.Import)
        FT.Fire("FT_SOURCES_CHANGED")
    end
end)
FT.On("AUCTION_HOUSE_SHOW", function()
    if not MC.Loaded() or watching then return end
    -- Mastercraft scans while the auction house is open: look for new prices now and then
    watching = C_Timer.NewTicker(8, function() MC.Import() end)
end)
FT.On("AUCTION_HOUSE_CLOSED", function()
    if watching then
        watching:Cancel()
        watching = nil
    end
    if MC.Loaded() then C_Timer.After(1, MC.Import) end
end)
