local _, FT = ...
local L = FT.L

-- Wolf knows you (v0.50): your characters' professions and skill, your level, where you farm - so the calls fit
-- you. A skinning farm for a character with no skinner, a drop from mobs far over your level: not a farm for you.
local M = {}
FT.Me = M

-- your side's characters' professions: { [prof] = best skill }
function M.Profs()
    local out = {}
    for _, c in pairs(FT.db and FT.db.chars or {}) do
        if c.side == FT.sideKey and type(c.profs) == "table" then
            for p, rank in pairs(c.profs) do
                if type(rank) == "number" then out[p] = math.max(out[p] or 0, rank) end
            end
        end
    end
    return out
end

-- this character's professions, else nil (not read yet)
function M.MyProfs()
    local c = FT.charKey and FT.db and FT.db.chars and FT.db.chars[FT.charKey]
    return c and type(c.profs) == "table" and c.profs or nil
end

function M.Has(prof)
    return (M.Profs()[prof] or 0) > 0
end

function M.Level()
    return (UnitLevel and UnitLevel("player")) or 60
end

-- can you farm it? true, or false and why ("needs Skinning", "level 58 mobs"). Nothing known about you yet: yes.
function M.CanFarm(id)
    if not (id and FT.Where) then return true end
    local need = FT.Where.Needs(id)
    if need and next(M.Profs()) and not M.Has(need) then
        return false, string.format(L["needs %s"], L[need] or need)
    end
    local lv = FT.Where.DropLevel(id)
    if lv and lv > M.Level() + 5 then
        return false, string.format(L["level %d mobs"], lv)
    end
    return true
end

-- a line for the Coming up page: what Wolf knows of you ("Jay 60 · Mining 300, Engineering 285")
function M.Text()
    local p = M.Profs()
    local list = {}
    for k, v in pairs(p) do list[#list + 1] = { k, v } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    local bits = {}
    for i = 1, math.min(4, #list) do bits[#bits + 1] = (L[list[i][1]] or list[i][1]) .. " " .. list[i][2] end
    if #bits == 0 then return nil end
    return table.concat(bits, ", ")
end
