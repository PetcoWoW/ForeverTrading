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
    muted = { 0.600, 0.635, 0.690 },
    dim = { 0.455, 0.490, 0.545 },
    up = { 0.055, 0.796, 0.506 },
    down = { 0.965, 0.275, 0.365 },
    accent = { 0.941, 0.725, 0.043 },
    blue = { 0.231, 0.510, 0.965 },
    purple = { 0.655, 0.545, 0.980 },
    black = { 0, 0, 0 },
    -- a row under the mouse, a chosen row (with its alpha: UI.SEL_A)
    hl = { 0.098, 0.114, 0.141 },
    sel = { 0.941, 0.725, 0.043 },
}
local C = UI.C
UI.SEL_A = 0.07

-- the other styles: the same names, other colours
local THEMES = {
    light = {
        bg0 = { 0.925, 0.933, 0.945 }, bg1 = { 1, 1, 1 }, bg2 = { 0.906, 0.918, 0.933 }, bg3 = { 0.827, 0.843, 0.867 },
        line = { 0.765, 0.784, 0.816 }, text = { 0.098, 0.114, 0.137 }, muted = { 0.337, 0.373, 0.427 },
        dim = { 0.494, 0.529, 0.584 }, up = { 0.012, 0.580, 0.380 }, down = { 0.780, 0.165, 0.267 },
        hl = { 0.800, 0.820, 0.855 }, sel = { 0.984, 0.851, 0.490 },
        accent = { 0.780, 0.565, 0.0 }, blue = { 0.145, 0.388, 0.922 }, purple = { 0.486, 0.227, 0.929 },
    },
    classic = {
        hl = { 0.135, 0.118, 0.095 }, sel = { 1.0, 0.820, 0.0 },
        bg0 = { 0.035, 0.032, 0.030 }, bg1 = { 0.075, 0.068, 0.060 }, bg2 = { 0.135, 0.118, 0.095 },
        bg3 = { 0.200, 0.170, 0.125 }, line = { 0.420, 0.345, 0.205 }, text = { 1.0, 0.953, 0.855 },
        muted = { 0.800, 0.725, 0.560 }, dim = { 0.560, 0.505, 0.400 }, up = { 0.118, 1.0, 0.118 },
        down = { 1.0, 0.200, 0.200 }, accent = { 1.0, 0.820, 0.0 }, blue = { 0.400, 0.620, 1.0 },
        purple = { 0.640, 0.210, 0.930 },
    },
}
UI.theme = "dark"
UI.INSET = 1 -- how far the window's content keeps from its edge

-- the height of a control when none is given
UI.H, UI.HS = 24, 20
function UI.ControlH(h)
    return h or UI.H
end

-- A faint tint (a chosen row, a badge, a tinted button) shows on a dark background; on white it is gone: the light
-- style makes it stronger
function UI.Alpha(a)
    if UI.theme == "light" and a and a > 0 and a < 0.35 then return math.min(0.4, a * 2.2) end
    return a
end

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
    -- the chosen row: a faint gold on dark, a solid light gold on white
    UI.SEL_A = (name == "light") and 1 or 0.07
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
    t:SetColorTexture(c[1], c[2], c[3], UI.Alpha(alpha or 1))
    return t
end

function UI.SetTexColor(tex, color, alpha)
    local c = type(color) == "table" and color or C[color] or C.text
    if tex.isRound then
        tex:SetColor(c, alpha)
    elseif tex.tinted then
        tex:SetVertexColor(c[1], c[2], c[3], UI.Alpha(alpha or 1))
    else
        tex:SetColorTexture(c[1], c[2], c[3], UI.Alpha(alpha or 1))
    end
end

---------------------------------------------------------------------------
-- Slightly rounded corners (in the classic style too: its windows and panels keep the game's edges, the rounded
-- fill hides under them). A rounded rectangle is its
-- rounded corners - quarters of a disc (media\round.tga) - and up to three bands between them; a rounded border
-- is quarters of a ring (media\ringN.tga: 1 wide at radius N) and four lines. The radius shrinks to fit a small
-- rectangle. corners: "all" (the default), "top", "bottom", "left", "right", "none" (square).
---------------------------------------------------------------------------
UI.RADIUS = 3
local WHITE = "Interface\\Buttons\\WHITE8X8"
local DISC = FT.MEDIA .. "round.tga"
local QUARTER = {
    TOPLEFT = { 0, 0.5, 0, 0.5 }, TOPRIGHT = { 0.5, 1, 0, 0.5 },
    BOTTOMLEFT = { 0, 0.5, 0.5, 1 }, BOTTOMRIGHT = { 0.5, 1, 0.5, 1 },
}
local CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local SETS = {
    all = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true },
    top = { TOPLEFT = true, TOPRIGHT = true }, bottom = { BOTTOMLEFT = true, BOTTOMRIGHT = true },
    left = { TOPLEFT = true, BOTTOMLEFT = true }, right = { TOPRIGHT = true, BOTTOMRIGHT = true },
}

function UI.Rounded()
    return UI.RADIUS > 0
end

local function Ring(r)
    if r <= 1 then return DISC end
    return FT.MEDIA .. "ring" .. math.min(r, 6) .. ".tga"
end

-- the radius of a rectangle w x h with these corners rounded (two rounded corners on a side share it)
local function Fit(set, w, h, want)
    local r = want or UI.RADIUS
    local cols = ((set.TOPLEFT or set.BOTTOMLEFT) and 1 or 0) + ((set.TOPRIGHT or set.BOTTOMRIGHT) and 1 or 0)
    local rows = ((set.TOPLEFT or set.TOPRIGHT) and 1 or 0) + ((set.BOTTOMLEFT or set.BOTTOMRIGHT) and 1 or 0)
    if w and w > 0 and cols > 0 then r = math.min(r, math.floor(w / cols)) end
    if h and h > 0 and rows > 0 then r = math.min(r, math.floor(h / rows)) end
    return math.max(0, r)
end

-- a rounded rectangle: used like a texture (points, shown, colour through UI.SetTexColor)
local Round = {}
Round.__index = Round

function Round:Layout()
    local b, s = self.base, self.set
    local r = Fit(s, b:GetWidth(), b:GetHeight(), self.want)
    if r == self.r then return end
    self.r = r
    local tl, tr = s.TOPLEFT and r or 0, s.TOPRIGHT and r or 0
    local bl, br = s.BOTTOMLEFT and r or 0, s.BOTTOMRIGHT and r or 0
    local top, bottom = math.max(tl, tr), math.max(bl, br)
    for _, t in pairs(self.corners) do
        if r > 0 then t:SetSize(r, r) end
        self.vis[t] = r > 0
    end
    self.top:ClearAllPoints()
    self.top:SetPoint("TOPLEFT", b, "TOPLEFT", tl, 0)
    self.top:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", -tr, -top)
    self.vis[self.top] = top > 0
    self.bottom:ClearAllPoints()
    self.bottom:SetPoint("TOPLEFT", b, "BOTTOMLEFT", bl, bottom)
    self.bottom:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -br, 0)
    self.vis[self.bottom] = bottom > 0
    self.mid:ClearAllPoints()
    self.mid:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -top)
    self.mid:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, bottom)
    self:SetShown(self.shown)
end

-- its place changed: laid out now, and again once the game has placed it
function Round:Relayout()
    self.r = nil
    self:Layout()
    C_Timer.After(0, function()
        self.r = nil
        self:Layout()
    end)
end

function Round:SetColor(color, alpha)
    local c = type(color) == "table" and color or C[color] or C.text
    alpha = UI.Alpha(alpha or 1)
    for _, t in ipairs(self.parts) do t:SetVertexColor(c[1], c[2], c[3], alpha) end
end
function Round:SetColorTexture(r, g, b, a) self:SetColor({ r, g, b }, a) end
function Round:SetVertexColor(r, g, b, a) self:SetColor({ r, g, b }, a) end
-- (never an explicit nil to the game: SetAllPoints(nil) is the whole screen, not the parent)
function Round:SetAllPoints(rel)
    self.base:SetAllPoints(rel or self.parent)
    self:Relayout()
end
function Round:SetPoint(...)
    self.base:SetPoint(...)
    self:Relayout()
end
function Round:ClearAllPoints() self.base:ClearAllPoints() end
function Round:SetSize(w, h)
    self.base:SetSize(w, h)
    self:Relayout()
end
function Round:SetWidth(w)
    self.base:SetWidth(w)
    self:Relayout()
end
function Round:SetHeight(h)
    self.base:SetHeight(h)
    self:Relayout()
end
function Round:GetWidth() return self.base:GetWidth() end
function Round:GetHeight() return self.base:GetHeight() end
function Round:SetShown(on)
    self.shown = on and true or false
    for _, t in ipairs(self.parts) do t:SetShown(self.shown and self.vis[t] ~= false) end
end
function Round:Show() self:SetShown(true) end
function Round:Hide() self:SetShown(false) end
function Round:IsShown() return self.shown end
function Round:IsVisible() return self.shown and self.base:IsVisible() end
function Round:SetAlpha(a)
    for _, t in ipairs(self.parts) do t:SetAlpha(a) end
end
function Round:SetDrawLayer(layer, sub)
    self.base:SetDrawLayer(layer, sub)
    for _, t in ipairs(self.parts) do t:SetDrawLayer(layer, sub) end
end

-- like UI.Tex, slightly rounded (radius: `radius`, else UI.RADIUS); square in the classic style or with "none"
function UI.RoundTex(parent, layer, color, alpha, sub, corners, radius)
    local set = SETS[corners or "all"]
    if not (UI.Rounded() and set) then return UI.Tex(parent, layer, color, alpha, sub) end
    local o = setmetatable({ isRound = true, parent = parent, set = set, want = radius, parts = {}, corners = {},
        vis = {}, shown = true }, Round)
    layer = layer or "ARTWORK"
    -- the rectangle itself: where the pieces go (never drawn)
    o.base = parent:CreateTexture(nil, layer, nil, sub)
    o.base:SetColorTexture(0, 0, 0, 0)
    local function Piece(file)
        local t = parent:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(file)
        o.parts[#o.parts + 1] = t
        return t
    end
    for _, key in ipairs(CORNERS) do
        if set[key] then
            local t = Piece(DISC)
            t:SetTexCoord(unpack(QUARTER[key]))
            t:SetPoint(key, o.base, key)
            o.corners[key] = t
        end
    end
    o.top, o.bottom, o.mid = Piece(WHITE), Piece(WHITE), Piece(WHITE)
    o:SetColor(color or "bg1", alpha)
    -- the frame it fills changes size: the radius follows
    if parent.HookScript then parent:HookScript("OnSizeChanged", function() o:Layout() end) end
    return o
end

-- a small round dot (a status light)
function UI.Dot(parent, size, color, alpha, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(DISC)
    t:SetSize(size or 7, size or 7)
    t.tinted = true
    UI.SetTexColor(t, color or "dim", alpha)
    return t
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

function UI.Fill(frame, color, alpha, corners, radius)
    local t = UI.RoundTex(frame, "BACKGROUND", color, alpha, -8, corners, radius)
    t:SetAllPoints()
    frame.bg = t
    return t
end

-- 1px border, slightly rounded (see UI.RoundTex; "none": square)
function UI.Border(frame, color, alpha, corners, radius)
    local set = SETS[corners or "all"]
    if UI.Rounded() and set then
        local lines, rings, all = {}, {}, {}
        for i = 1, 4 do
            lines[i] = frame:CreateTexture(nil, "BORDER")
            lines[i]:SetTexture(WHITE)
            all[#all + 1] = lines[i]
        end
        for _, key in ipairs(CORNERS) do
            if set[key] then
                rings[key] = frame:CreateTexture(nil, "BORDER")
                all[#all + 1] = rings[key]
            end
        end
        local lastR
        local function Layout()
            local r = Fit(set, frame:GetWidth(), frame:GetHeight(), radius)
            if r == lastR then return end
            lastR = r
            local tl, tr = set.TOPLEFT and r or 0, set.TOPRIGHT and r or 0
            local bl, br = set.BOTTOMLEFT and r or 0, set.BOTTOMRIGHT and r or 0
            local top, bottom, left, right = lines[1], lines[2], lines[3], lines[4]
            top:ClearAllPoints(); top:SetPoint("TOPLEFT", tl, 0); top:SetPoint("TOPRIGHT", -tr, 0); top:SetHeight(1)
            bottom:ClearAllPoints(); bottom:SetPoint("BOTTOMLEFT", bl, 0); bottom:SetPoint("BOTTOMRIGHT", -br, 0); bottom:SetHeight(1)
            left:ClearAllPoints(); left:SetPoint("TOPLEFT", 0, -tl); left:SetPoint("BOTTOMLEFT", 0, bl); left:SetWidth(1)
            right:ClearAllPoints(); right:SetPoint("TOPRIGHT", 0, -tr); right:SetPoint("BOTTOMRIGHT", 0, br); right:SetWidth(1)
            for key, t in pairs(rings) do
                t:SetTexture(Ring(r))
                t:SetTexCoord(unpack(QUARTER[key]))
                t:ClearAllPoints()
                t:SetPoint(key)
                if r > 0 then t:SetSize(r, r) end
                t:SetShown(r > 0)
            end
        end
        frame.border = all
        function frame:SetBorderColor(c, a)
            local cc = type(c) == "table" and c or C[c] or C.line
            a = UI.Alpha(a or 1)
            for _, t in ipairs(all) do t:SetVertexColor(cc[1], cc[2], cc[3], a) end
        end
        frame:SetBorderColor(color or "line", alpha or 1)
        Layout()
        if frame.HookScript then frame:HookScript("OnSizeChanged", Layout) end
        C_Timer.After(0, function()
            lastR = nil
            Layout()
        end)
        return all
    end
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

-- a filled frame with a border (border false: none), slightly rounded
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

-- a gear drawn with lines (Settings), in the style's colours: a ring and eight teeth
function UI.Gear(parent, size, color)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.lines = {}
    function f:SetColor(c, alpha)
        local s = self:GetWidth()
        local cx, cy = s / 2, s / 2
        local ring, tip = s * 0.27, s * 0.47
        local i = 0
        local function Line(x1, y1, x2, y2, w)
            i = i + 1
            local l = self.lines[i]
            if not l then
                l = UI.NewLine(self, "OVERLAY")
                self.lines[i] = l
            end
            UI.PlaceLine(l, x1, y1, x2, y2, w, c, alpha or 1)
        end
        local n = 18
        for k = 0, n - 1 do
            local a1, a2 = k / n * 2 * math.pi, (k + 1) / n * 2 * math.pi
            Line(cx + ring * math.cos(a1), cy + ring * math.sin(a1), cx + ring * math.cos(a2), cy + ring * math.sin(a2), s * 0.13)
        end
        for k = 0, 7 do
            local a = (k + 0.5) / 8 * 2 * math.pi
            Line(cx + ring * math.cos(a), cy + ring * math.sin(a), cx + tip * math.cos(a), cy + tip * math.sin(a), s * 0.17)
        end
    end
    f:SetColor(color or "muted")
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
