-- Wolf of Booty Bay (built on ForeverTrading): texts. English is the key. With "Plain English" on (Settings >
-- General, the default) the trader terms are swapped for plain words: the table below, applied once at start.
-- Every other text shows as written in the code.
local ADDON, FT = ...

local L = setmetatable({}, { __index = function(_, k) return k end })
FT.L = L

-- original text -> what Plain English shows instead
local plain = {}
FT.PLAIN = plain

function FT.ApplyLocale(words)
    if words ~= "trader" then
        for k, v in pairs(plain) do rawset(L, k, v) end
    end
end
