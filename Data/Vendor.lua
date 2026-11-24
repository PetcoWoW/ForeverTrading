-- Wolf of Booty Bay (built on ForeverTrading): what crafting materials cost at a vendor.
-- 1. what a merchant really charged you (recorded when you visit one: Sources/Game.lua)
-- 2. what Mastercraft recorded the same way
-- 3. for the common vendor-sold reagents below: an estimate from the item's sell price (vendors sell
--    for about four times what they pay)
local ADDON, FT = ...

local VENDOR_REAGENTS = {
    -- threads
    [2320] = true, [2321] = true, [4291] = true, [8343] = true, [14341] = true,
    -- vials
    [3371] = true, [3372] = true, [8925] = true, [18256] = true,
    -- flux, rods, wood, stock, coal, ink
    [2880] = true, [3466] = true, [18567] = true, [6217] = true, [4470] = true, [11291] = true,
    [4399] = true, [4400] = true, [3857] = true, [10647] = true, [10648] = true,
    -- dyes and bleach
    [2324] = true, [2604] = true, [2605] = true, [4340] = true, [4341] = true, [4342] = true,
    [6260] = true, [6261] = true, [10290] = true,
    -- salt, spices, drinks used in cooking
    [4289] = true, [2678] = true, [2692] = true, [3713] = true, [2665] = true, [159] = true,
    [1179] = true, [2596] = true, [17194] = true, [17196] = true,
    -- poisons (the poison supplier): Dust of Decay, Essence of Pain, Deathweed, Essence of Agony,
    -- Dust of Deterioration
    [2928] = true, [2930] = true, [5173] = true, [8923] = true, [8924] = true,
}
FT.VENDOR_REAGENTS = VENDOR_REAGENTS

-- price per item at a vendor, and how sure we are ("seen" / "estimate")
function FT.VendorBuy(itemID)
    if not itemID then return nil end
    local own = FT.db and FT.db.vendor[itemID]
    if own then return own, "seen" end
    if VENDOR_REAGENTS[itemID] then
        local _, _, _, sellPrice = FT.Item(itemID)
        if sellPrice and sellPrice > 0 then return sellPrice * 4, "estimate" end
    end
    return nil
end

-- what a vendor pays you for one
function FT.VendorSell(itemID)
    local _, _, _, sellPrice = FT.Item(itemID)
    if sellPrice and sellPrice > 0 then return sellPrice end
    return nil
end
