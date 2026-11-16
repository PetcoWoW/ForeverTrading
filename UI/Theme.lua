-- ForeverTrading: the look and the basic pieces every window uses. Three styles (Settings > General):
-- dark (an exchange terminal at night, the default), light (the same by day) and classic (the game's own look).
local ADDON, FT = ...

local UI = {}
FT.UI = UI

UI.C = {
    bg0 = { 0.043, 0.051, 0.063 },   -- window
    bg1 = { 0.071, 0.082, 0.102 },   -- panels
    bg2 = { 0.098, 0.114, 0.141 },   -- raised: inputs, rows on hover
    bg3 = { 0.137, 0.157, 0.192 },   -- pressed, selected
    line = { 0.157, 0.180, 0.220 },  -- borders and grid
    text = { 0.918, 0.925, 0.937 },
    muted = { 0.518, 0.557, 0.612 },
    dim = { 0.369, 0.400, 0.451 },
    up = { 0.055, 0.796, 0.506 },
    down = { 0.965, 0.275, 0.365 },
    accent = { 0.941, 0.725, 0.043 },
    blue = { 0.231, 0.510, 0.965 },
    purple = { 0.655, 0.545, 0.980 },
    black = { 0, 0, 0 },
}
local C = UI.C

-- the other styles: the same names, other colours
local THEMES = {
    light = {
        bg0 = { 0.957, 0.961, 0.969 }, bg1 = { 1, 1, 1 }, bg2 = { 0.937, 0.945, 0.957 }, bg3 = { 0.890, 0.902, 0.922 },
        line = { 0.851, 0.863, 0.886 }, text = { 0.118, 0.137, 0.161 }, muted = { 0.420, 0.459, 0.522 },
        dim = { 0.600, 0.635, 0.686 }, up = { 0.012, 0.620, 0.408 }, down = { 0.812, 0.188, 0.290 },
        accent = { 0.780, 0.565, 0.0 }, blue = { 0.145, 0.388, 0.922 }, purple = { 0.486, 0.227, 0.929 },
    },
    classic = {
        bg0 = { 0.035, 0.032, 0.030 }, bg1 = { 0.075, 0.068, 0.060 }, bg2 = { 0.135, 0.118, 0.095 },
        bg3 = { 0.200, 0.170, 0.125 }, line = { 0.420, 0.345, 0.205 }, text = { 1.0, 0.953, 0.855 },
        muted = { 0.800, 0.725, 0.560 }, dim = { 0.560, 0.505, 0.400 }, up = { 0.118, 1.0, 0.118 },
        down = { 1.0, 0.200, 0.200 }, accent = { 1.0, 0.820, 0.0 }, blue = { 0.400, 0.620, 1.0 },
        purple = { 0.640, 0.210, 0.930 },
    },
}
UI.theme = "dark"
UI.INSET = 1 -- how far the window's content keeps from its edge

local function Hex(c)
    return string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- once, when the saved settings are known, before any window is built
function UI.ApplyTheme()
    local name = FT.S and FT.S.theme or "dark"
    local palette = THEMES[name]
    if not palette then name = "dark" end
    for k, v in pairs(palette or {}) do C[k] = v end
    UI.theme = name
    UI.INSET = (name == "classic") and 4 or 1
    -- the colours of coloured text follow
    for k in pairs(FT.HEX) do
        if C[k] then FT.HEX[k] = Hex(C[k]) end
    end
end
FT.On("FT_DB_READY", function() UI.ApplyTheme() end)

function UI.RGB(name)
    local c = C[name] or C.text
    return c[1], c[2], c[3]
end

---------------------------------------------------------------------------
-- Font: Noto Sans when Mastercraft brings it (it has Cyrillic and looks modern), else the game's own
---------------------------------------------------------------------------
UI.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function AddonLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    return IsAddOnLoaded and IsAddOnLoaded(name)
end

function UI.ResolveFont()
    if UI.fontResolved then return end
    UI.fontResolved = true
    local candidates = {}
    -- classic: the game's own Friz Quadrata - when it has the letters of the language we show
    if UI.theme == "classic" and (FT.Lang() ~= "ru" or GetLocale() == "ruRU") and STANDARD_TEXT_FONT then
        candidates[#candidates + 1] = STANDARD_TEXT_FONT
    end
    if AddonLoaded("Mastercraft") then
        candidates[#candidates + 1] = "Interface\\AddOns\\Mastercraft\\media\\NotoSans-Regular.ttf"
    end
    candidates[#candidates + 1] = "Fonts\\ARIALN.TTF"
    local probe = UIParent:CreateFontString(nil, "OVERLAY")
    for _, path in ipairs(candidates) do
        local ok, res = pcall(probe.SetFont, probe, path, 12, "")
        if ok and res ~= false then
            UI.FONT = path
            break
        end
    end
    probe:Hide()
end

---------------------------------------------------------------------------
-- Primitives
---------------------------------------------------------------------------
function UI.Tex(parent, layer, color, alpha, sub)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
    local c = type(color) == "table" and color or C[color or "bg1"]
    t:SetColorTexture(c[1], c[2], c[3], alpha or 1)
    return t
end

function UI.SetTexColor(tex, color, alpha)
    local c = type(color) == "table" and color or C[color] or C.text
    tex:SetColorTexture(c[1], c[2], c[3], alpha or 1)
end

-- vertical or horizontal fade from (color, a1) to (color, a2)
function UI.Gradient(tex, orientation, color, a1, a2, color2)
    local c1 = type(color) == "table" and color or C[color]
    local c2 = color2 and (type(color2) == "table" and color2 or C[color2]) or c1
    tex:SetColorTexture(1, 1, 1, 1)
    if CreateColor and tex.SetGradient then
        local ok = pcall(tex.SetGradient, tex, orientation, CreateColor(c1[1], c1[2], c1[3], a1),
            CreateColor(c2[1], c2[2], c2[3], a2))
        if ok then return end
    end
    if tex.SetGradientAlpha then
        local ok = pcall(tex.SetGradientAlpha, tex, orientation, c1[1], c1[2], c1[3], a1, c2[1], c2[2], c2[3], a2)
        if ok then return end
    end
    tex:SetColorTexture(c1[1], c1[2], c1[3], (a1 + a2) / 2)
end

function UI.Fill(frame, color, alpha)
    local t = UI.Tex(frame, "BACKGROUND", color, alpha, -8)
    t:SetAllPoints()
    frame.bg = t
    return t
end

-- 1px border of four textures
function UI.Border(frame, color, alpha)
    local b = {}
    for i = 1, 4 do b[i] = UI.Tex(frame, "BORDER", color or "line", alpha or 1) end
    b[1]:SetPoint("TOPLEFT"); b[1]:SetPoint("TOPRIGHT"); b[1]:SetHeight(1)
    b[2]:SetPoint("BOTTOMLEFT"); b[2]:SetPoint("BOTTOMRIGHT"); b[2]:SetHeight(1)
    b[3]:SetPoint("TOPLEFT"); b[3]:SetPoint("BOTTOMLEFT"); b[3]:SetWidth(1)
    b[4]:SetPoint("TOPRIGHT"); b[4]:SetPoint("BOTTOMRIGHT"); b[4]:SetWidth(1)
    frame.border = b
    function frame:SetBorderColor(c, a)
        for i = 1, 4 do UI.SetTexColor(b[i], c, a) end
    end
    return b
end

-- the edge of the game's tooltips, for the classic style
local CLASSIC_EDGE = { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } }

-- frame with the classic style's edge; false when the style or the client doesn't do it
function UI.ClassicEdge(f, color, edge)
    if UI.theme ~= "classic" or not f.SetBackdrop then return false end
    f:SetBackdrop(edge or CLASSIC_EDGE)
    local c = type(color) == "table" and color or C[color or "line"]
    f:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    function f:SetBorderColor(col, a)
        local cc = type(col) == "table" and col or C[col] or C.line
        self:SetBackdropBorderColor(cc[1], cc[2], cc[3], a or 1)
    end
    return true
end

-- a template that can carry the classic style's edge
function UI.EdgeTemplate()
    return (UI.theme == "classic" and BackdropTemplateMixin) and "BackdropTemplate" or nil
end

function UI.Panel(parent, color, border)
    local f = CreateFrame("Frame", nil, parent, border ~= false and UI.EdgeTemplate() or nil)
    UI.Fill(f, color or "bg1")
    if border ~= false then
        if UI.ClassicEdge(f, border or "line") then
            -- the fill inside the edge
            f.bg:ClearAllPoints()
            f.bg:SetPoint("TOPLEFT", 3, -3)
            f.bg:SetPoint("BOTTOMRIGHT", -3, 3)
        else
            UI.Border(f, border or "line")
        end
    end
    return f
end

-- horizontal / vertical 1px line
function UI.HLine(parent, color, alpha)
    local t = UI.Tex(parent, "BORDER", color or "line", alpha or 1)
    t:SetHeight(1)
    return t
end

function UI.VLine(parent, color, alpha)
    local t = UI.Tex(parent, "BORDER", color or "line", alpha or 1)
    t:SetWidth(1)
    return t
end

function UI.Text(parent, size, color, justify, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(UI.FONT, size or 12, "")
    local c = type(color) == "table" and color or C[color or "text"]
    fs:SetTextColor(c[1], c[2], c[3], 1)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("MIDDLE")
    fs:SetShadowColor(0, 0, 0, 0.6)
    -- a dark shadow only reads well on a dark background
    if UI.theme == "light" then fs:SetShadowOffset(0, 0) else fs:SetShadowOffset(1, -1) end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
end

function UI.SetTextColor(fs, color)
    local c = type(color) == "table" and color or C[color] or C.text
    fs:SetTextColor(c[1], c[2], c[3], 1)
end

-- item icon with a thin dark frame and the inner 8% of the art (the game's icons have a border baked in)
function UI.Icon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local bg = UI.Tex(f, "BACKGROUND", "black", 0.6)
    bg:SetAllPoints()
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", 1, -1)
    f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    function f:SetItem(itemID)
        local _, _, icon = FT.Item(itemID)
        self.tex:SetTexture(icon or 134400)
    end
    function f:SetIcon(icon)
        self.tex:SetTexture(icon or 134400)
    end
    return f
end

-- a line between two points of a frame (CreateLine where the client has it, else a dotted trail)
function UI.NewLine(parent, layer)
    if parent.CreateLine then
        local l = parent:CreateLine(nil, layer or "ARTWORK")
        l.isLine = true
        l.owner = parent
        return l
    end
    return { parent = parent, dots = {}, layer = layer, isLine = false }
end

function UI.PlaceLine(l, x1, y1, x2, y2, thickness, color, alpha)
    local c = type(color) == "table" and color or C[color] or C.text
    if l.isLine then
        l:SetStartPoint("BOTTOMLEFT", l.owner, x1, y1)
        l:SetEndPoint("BOTTOMLEFT", l.owner, x2, y2)
        l:SetThickness(thickness or 1)
        l:SetColorTexture(c[1], c[2], c[3], alpha or 1)
        l:Show()
        return
    end
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    local n = math.max(1, math.floor(len / 2))
    for i = 1, n do
        local d = l.dots[i]
        if not d then
            d = l.parent:CreateTexture(nil, l.layer or "ARTWORK")
            l.dots[i] = d
        end
        d:SetColorTexture(c[1], c[2], c[3], alpha or 1)
        d:SetSize(thickness or 1, thickness or 1)
        d:ClearAllPoints()
        d:SetPoint("CENTER", l.parent, "BOTTOMLEFT", x1 + dx * i / n, y1 + dy * i / n)
        d:Show()
    end
    for i = n + 1, #l.dots do l.dots[i]:Hide() end
end

function UI.HideLine(l)
    if l.isLine then
        l:Hide()
    else
        for _, d in ipairs(l.dots) do d:Hide() end
    end
end

-- a small chevron of two lines ("down", "up", "right", "left")
function UI.Chevron(parent, size, color)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size or 8, size or 8)
    f.a, f.b = UI.NewLine(f, "OVERLAY"), UI.NewLine(f, "OVERLAY")
    function f:SetDir(dir, c)
        local s = self:GetWidth()
        local h = s / 2
        c = c or color or "muted"
        if dir == "up" then
            UI.PlaceLine(self.a, 0, h * 0.5, h, h * 1.5, 1.5, c)
            UI.PlaceLine(self.b, h, h * 1.5, s, h * 0.5, 1.5, c)
        elseif dir == "right" then
            UI.PlaceLine(self.a, h * 0.5, s, h * 1.5, h, 1.5, c)
            UI.PlaceLine(self.b, h * 1.5, h, h * 0.5, 0, 1.5, c)
        elseif dir == "left" then
            UI.PlaceLine(self.a, h * 1.5, s, h * 0.5, h, 1.5, c)
            UI.PlaceLine(self.b, h * 0.5, h, h * 1.5, 0, 1.5, c)
        else
            UI.PlaceLine(self.a, 0, h * 1.5, h, h * 0.5, 1.5, c)
            UI.PlaceLine(self.b, h, h * 0.5, s, h * 1.5, 1.5, c)
        end
    end
    f:SetDir("down")
    return f
end

-- pool of textures / font strings / lines that a widget redraws often
function UI.Pool(owner, make)
    local pool = { items = {}, used = 0 }
    function pool:Get()
        self.used = self.used + 1
        local it = self.items[self.used]
        if not it then
            it = make(owner)
            self.items[self.used] = it
        end
        return it
    end
    function pool:Reset()
        self.used = 0
    end
    function pool:HideRest()
        for i = self.used + 1, #self.items do
            local it = self.items[i]
            if it.isLine == false then UI.HideLine(it) else it:Hide() end
        end
    end
    return pool
end
