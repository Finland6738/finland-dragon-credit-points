-- Theme: the tokens of docs/specs/ui-style.md §2 in three themes, the registry of tinted regions, font objects, the Px()
-- helper and the 9-slice shapes (M1-7). Lua 5.1; UI only, no game data.
-- * Every texture is white; a region that shows a token registers itself (Theme.Tint / Theme.Text / Theme.Call) and
--   Theme.Apply recolours all of them without /reload. The registry has weak keys: a region that is gone costs nothing.
-- * A font that fails to load falls back to the game's font (SetFont answers false); "Font: game" forces the fallback.
local ADDON_NAME, ns = ...
ns = ns or {}

local Theme = {}
ns.Theme = Theme
if ns.addon then ns.addon.Theme = Theme end   -- also reachable from tests

local Assets = ns.Assets

-- --- tokens ------------------------------------------------------------------------------------------------------------

local function hex(s)
	return { tonumber(s:sub(2, 3), 16) / 255, tonumber(s:sub(4, 5), 16) / 255, tonumber(s:sub(6, 7), 16) / 255, 1 }
end
local function rgba(r, g, b, a) return { r / 255, g / 255, b / 255, a } end

-- Token names, in the order of the spec's table. Every theme defines every one of them (tests check the parity).
Theme.TOKENS = { "bg", "surface-1", "surface-2", "surface-3", "raised", "border-subtle", "border", "border-strong",
	"text-1", "text-2", "text-3", "on-accent", "accent", "accent-hover", "accent-text", "accent-2", "neon", "neon-core",
	"ok", "warn", "err", "highlight", "scrim", "grad-1", "grad-2", "grad-3", "grad-4" }

local function lightBorders(r, g, b) return rgba(r, g, b, .07), rgba(r, g, b, .13), rgba(r, g, b, .24) end

Theme.themes = {
	nebula = {
		name = "Nebula", dark = true,
		bg = hex("#0B0612"), ["surface-1"] = hex("#110A1A"), ["surface-2"] = hex("#170F22"), ["surface-3"] = hex("#1E142C"),
		raised = hex("#2A1D3B"),
		["border-subtle"] = rgba(243, 238, 247, .08), border = rgba(243, 238, 247, .14), ["border-strong"] = rgba(243, 238, 247, .26),
		["text-1"] = hex("#F3EEF7"), ["text-2"] = hex("#C3B8D1"), ["text-3"] = hex("#9A8FAB"),
		["on-accent"] = hex("#1A0710"), accent = hex("#FC7E46"), ["accent-hover"] = hex("#FDA877"), ["accent-text"] = hex("#FC8C46"),
		["accent-2"] = hex("#EE4662"), neon = hex("#C45BC4"), ["neon-core"] = hex("#9A2A9A"),
		ok = hex("#46C28F"), warn = hex("#F2B33D"), err = hex("#FF6369"),
		highlight = rgba(255, 255, 255, .06), scrim = rgba(5, 2, 10, .72),
		["grad-1"] = hex("#FC8C46"), ["grad-2"] = hex("#EE4662"), ["grad-3"] = hex("#9A2A9A"), ["grad-4"] = hex("#702AA8"),
	},
	aurora = {
		name = "Aurora", dark = false,
		bg = hex("#F5F8FA"), ["surface-1"] = hex("#FFFFFF"), ["surface-2"] = hex("#EAF0F4"), ["surface-3"] = hex("#E1E9EF"),
		raised = hex("#FFFFFF"),
		["text-1"] = hex("#0B1B2B"), ["text-2"] = hex("#3C4E60"), ["text-3"] = hex("#526476"),
		["on-accent"] = hex("#FFFFFF"), accent = hex("#0054B6"), ["accent-hover"] = hex("#003F8A"), ["accent-text"] = hex("#0054B6"),
		["accent-2"] = hex("#00766C"), neon = hex("#008F84"), ["neon-core"] = hex("#009A9A"),   -- the site's #00A89A darkened to 3:1 on the light surface (M7-1)
		ok = hex("#1B7A50"), warn = hex("#8F5B00"), err = hex("#C0262D"),
		highlight = rgba(255, 255, 255, .6), scrim = rgba(11, 27, 43, .45),
		["grad-1"] = hex("#0054B6"), ["grad-2"] = hex("#007EA8"), ["grad-3"] = hex("#00A89A"), ["grad-4"] = hex("#70C446"),
	},
	drago = {
		name = "Drago", dark = true,
		bg = hex("#071715"), ["surface-1"] = hex("#0E2422"), ["surface-2"] = hex("#16332F"), ["surface-3"] = hex("#1B3D38"),
		raised = hex("#22443F"),
		["border-subtle"] = rgba(230, 239, 233, .08), border = rgba(230, 239, 233, .14), ["border-strong"] = rgba(230, 239, 233, .26),
		["text-1"] = hex("#E6EFE9"), ["text-2"] = hex("#C2D3CD"), ["text-3"] = hex("#9FB5AE"),
		["on-accent"] = hex("#2A1E00"), accent = hex("#E9B949"), ["accent-hover"] = hex("#F2CD6E"), ["accent-text"] = hex("#E9B949"),
		["accent-2"] = hex("#3E9E5F"), neon = hex("#B8E86A"), ["neon-core"] = hex("#6FA83A"),
		ok = hex("#5BC17F"), warn = hex("#F2B33D"), err = hex("#FF6B5E"),
		highlight = rgba(255, 255, 255, .06), scrim = rgba(2, 10, 9, .72),
		["grad-1"] = hex("#E9B949"), ["grad-2"] = hex("#B8E86A"), ["grad-3"] = hex("#3E9E5F"), ["grad-4"] = hex("#1F6F5A"),
	},
}
do
	local a = Theme.themes.aurora
	a["border-subtle"], a.border, a["border-strong"] = lightBorders(11, 27, 43)
end

Theme.ORDER = { "nebula", "aurora", "drago" }
Theme.DEFAULT = "nebula"

function Theme.Has(id) return Theme.themes[id] ~= nil end
function Theme.List() return Theme.ORDER end
function Theme.Name(id) return Theme.themes[id] and Theme.themes[id].name or id end

local current = Theme.DEFAULT
function Theme.Current() return current end
function Theme.IsDark() return Theme.themes[current].dark end

-- The colour of a token in the current theme (or of `themeId`): r, g, b, a. An unknown token is magenta, so a typo shows.
function Theme.Color(token, themeId)
	local c = (Theme.themes[themeId or current] or Theme.themes[Theme.DEFAULT])[token]
	if not c then return 1, 0, 1, 1 end
	return c[1], c[2], c[3], c[4]
end

-- --- the registry of tinted regions -----------------------------------------------------------------------------------

-- region -> list of { kind, token, extra }. Weak keys: a destroyed or collected region drops out by itself.
local registry = setmetatable({}, { __mode = "k" })

local function applyOne(region, entry)
	local kind = entry.kind
	if kind == "vertex" then
		local r, g, b, a = Theme.Color(entry.token)
		region:SetVertexColor(r, g, b, (a or 1) * (entry.alpha or 1))
	elseif kind == "color" then
		local r, g, b, a = Theme.Color(entry.token)
		region:SetColorTexture(r, g, b, (a or 1) * (entry.alpha or 1))
	elseif kind == "text" then
		local r, g, b, a = Theme.Color(entry.token)
		region:SetTextColor(r, g, b, a or 1)
	elseif kind == "rgb" then
		region:SetTextColor(entry.r, entry.g, entry.b, 1)   -- a colour of the game (item quality), not of a theme
	elseif kind == "class" then
		if Theme.IsDark() then
			region:SetTextColor(entry.r, entry.g, entry.b, 1)   -- the class colour on a dark surface
		else
			local r, g, b, a = Theme.Color("text-1")            -- on a light surface only the square is coloured
			region:SetTextColor(r, g, b, a or 1)
		end
	elseif kind == "fn" then
		entry.fn(region, current)
	end
end

-- The colour of a text is one thing: a token ("text"), a class colour ("class") or a game colour ("rgb"); setting one
-- replaces the others, so a pooled row that is filled again never keeps the colour of its previous data.
local TEXT_COLOUR = { text = true, class = true, rgb = true }

local function add(region, entry)
	local list = registry[region]
	if not list then list = {}; registry[region] = list end
	-- one entry per kind: registering again replaces the token (a button that changes style)
	for i, e in ipairs(list) do
		if e.kind ~= "fn" and (e.kind == entry.kind or (TEXT_COLOUR[e.kind] and TEXT_COLOUR[entry.kind])) then
			list[i] = entry; applyOne(region, entry); return region
		end
	end
	list[#list + 1] = entry
	applyOne(region, entry)
	return region
end

-- A white texture shows `token` through SetVertexColor; `alpha` multiplies the token's own alpha.
function Theme.Tint(region, token, alpha) return add(region, { kind = "vertex", token = token, alpha = alpha }) end
-- A solid-colour texture (SetColorTexture) in `token`.
function Theme.Fill(region, token, alpha) return add(region, { kind = "color", token = token, alpha = alpha }) end
-- A FontString (or font object) coloured with `token`.
function Theme.Text(region, token) return add(region, { kind = "text", token = token }) end
-- A FontString in a colour of the game (r, g, b in 0..1): the item quality, the class of a player. It survives Apply.
function Theme.TextRGB(region, r, g, b) return add(region, { kind = "rgb", r = r, g = g, b = b }) end
-- A player's name: the class colour on the dark themes, text-1 on the light one (the square next to it carries the colour).
function Theme.ClassText(region, r, g, b) return add(region, { kind = "class", r = r, g = g, b = b }) end
-- A free function fn(region, themeId) that sets whatever a token cannot (a gradient, a blend mode); runs now and on Apply.
function Theme.Call(region, fn) return add(region, { kind = "fn", fn = fn }) end

function Theme.Count()
	local n = 0
	for _ in pairs(registry) do n = n + 1 end
	return n
end

-- The two preferences of the Settings (docs/specs/ui-style.md §5: "Neon effects", "Animations"). Both are on by default;
-- a client without a database (the first frames of a load) answers the default.
local function preference(name)
	local cfg = ns.Config
	if cfg and cfg.db then
		local v = cfg:Get(name)
		if v ~= nil then return v and true or false end
	end
	return true
end
function Theme.EffectsOn() return preference("effects") end
function Theme.AnimationsOn() return preference("animations") end

-- A soft glow of Media/glow_s or glow_l behind `parent`, white and tinted with `token`. Dark themes add it to the picture
-- (blend mode ADD, the site's neon); the light theme draws it as an ordinary soft shadow at half strength. It is hidden
-- with the "Neon effects" preference off. opts: layer, alpha. Returns the texture; the caller anchors it.
function Theme.Glow(parent, key, token, opts)
	opts = opts or {}
	local tex = Theme.Slice(parent, key, token, opts.layer or "BACKGROUND", opts.alpha or 0.4)   -- no token: the caller tints it
	tex._glow = true
	Theme.Call(tex, function(region, id)
		local dark = Theme.themes[id].dark
		if region.SetBlendMode then region:SetBlendMode(dark and "ADD" or "BLEND") end
		region:SetShown(Theme.EffectsOn() and region._want ~= false)
		region._additive = dark
	end)
	return tex
end

-- Shows or hides a glow on purpose (the one neon element of a view): it still disappears with "Neon effects" off.
function Theme.GlowShow(tex, shown)
	tex._want = shown and true or false
	tex:SetShown(tex._want and Theme.EffectsOn())
end

-- A text glow for the one display title of a view: a coloured shadow of the font, dark themes and effects on only.
function Theme.TextGlow(fs, token)
	Theme.Call(fs, function(region, id)
		local on = Theme.themes[id].dark and Theme.EffectsOn()
		local r, g, b = Theme.Color(token or "accent", id)
		if region.SetShadowColor then region:SetShadowColor(r, g, b, on and 0.55 or 0) end
		if region.SetShadowOffset then region:SetShadowOffset(0, on and -1 or 0) end
		region._glowing = on
	end)
end

-- Switches the theme and recolours every registered region. Returns true when the theme exists.
function Theme.Apply(id)
	if id ~= nil then
		if not Theme.themes[id] then return false end
		current = id
	end
	for region, list in pairs(registry) do
		for _, entry in ipairs(list) do
			local ok, err = pcall(applyOne, region, entry)
			if not ok and ns.Log then ns.Log.warn("Theme", "APPLY_FAILED", ns.Log.Plain(tostring(err):sub(1, 60))) end
		end
	end
	if ns.Bus then ns.Bus:Emit("THEME_CHANGED", current) end
	return true
end

-- Reads the saved theme (profile) and applies it; called when the window is built and when the profile changes.
function Theme.Load()
	local id = ns.Config and ns.Config.db and ns.Config:Get("theme") or Theme.DEFAULT
	if not Theme.themes[id] then id = Theme.DEFAULT end
	return Theme.Apply(id)
end

-- Saves and applies a theme. Returns ok, error code (the Config codes).
function Theme.Set(id)
	if not Theme.themes[id] then return false, "BAD_VALUE" end
	if ns.Config and ns.Config.db then
		local ok, err = ns.Config:Set("theme", id)
		if not ok then return false, err end
	end
	Theme.Apply(id)
	return true
end

-- --- Px and snapping ---------------------------------------------------------------------------------------------------

-- One physical pixel in UI units of `frame` (UIParent by default): lines of 1 px stay sharp at any UI scale.
function Theme.PixelSize(frame)
	frame = frame or UIParent
	local scale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
	local physical
	if GetPhysicalScreenSize then
		local ok, _, h = pcall(GetPhysicalScreenSize)
		if ok and type(h) == "number" and h > 0 then physical = h end
	end
	if not scale or scale <= 0 then scale = 1 end
	return (768 / (physical or 768)) / scale
end

function Theme.Px(n, frame) return (n or 1) * Theme.PixelSize(frame) end

-- Turns off the engine's pixel snapping for a texture (thin lines at fractional scales); each call is guarded.
function Theme.Crisp(texture)
	if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
	if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
	return texture
end

-- --- fonts -------------------------------------------------------------------------------------------------------------

-- Font objects: id -> { font = key of Assets.fonts, size, token }. Names are FDCPFont<Id>.
Theme.fontSpecs = {
	Display = { "display", 22 }, DisplaySmall = { "display", 15 },
	H1 = { "textSemiBold", 16 }, H2 = { "textSemiBold", 14 },
	Body = { "text", 13 }, BodyMedium = { "textMedium", 13 }, Small = { "text", 11 },
	Eyebrow = { "textMedium", 11 }, Th = { "textSemiBold", 10 }, Tab = { "textMedium", 14 }, Button = { "textMedium", 13 },
	Mono = { "mono", 13 }, MonoMedium = { "monoMedium", 13 }, MonoSmall = { "mono", 11 },
}
Theme.fontStatus = {}   -- id -> "addon" | "game"
Theme.fontObjects = {}  -- id -> font object

local function gameFontPath(key)
	if key == "FRIZQT" then return _G.UNIT_NAME_FONT or "Fonts\\FRIZQT__.TTF" end
	return _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

-- Builds or refreshes every font object. `source` is "addon" (the files of Media/Fonts) or "game"; a file that does not
-- load falls back to the game font for that object. Returns the number of objects that use the game font.
function Theme.SetupFonts(source)
	source = source or (ns.Config and ns.Config.db and ns.Config:Get("fontSource")) or "addon"
	local fallbacks = 0
	for id, spec in pairs(Theme.fontSpecs) do
		local asset = Assets.fonts[spec[1]]
		local obj = Theme.fontObjects[id]
		if not obj then
			obj = CreateFont("FDCPFont" .. id)
			Theme.fontObjects[id] = obj
		end
		local ok = false
		if source ~= "game" then ok = obj:SetFont(asset.path, spec[2], "") and true or false end
		if not ok then
			obj:SetFont(gameFontPath(asset.fallback), spec[2], "")
			Theme.fontStatus[id] = "game"
			fallbacks = fallbacks + 1
		else
			Theme.fontStatus[id] = "addon"
		end
	end
	return fallbacks
end

function Theme.Font(id) return Theme.fontObjects[id] or Theme.fontObjects.Body end
function Theme.FontName(id) return "FDCPFont" .. id end

-- A FontString of `parent` in font `id` and colour `token` (registered).
function Theme.NewText(parent, id, token, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	if Theme.fontObjects[id] then fs:SetFontObject(Theme.fontObjects[id]) end
	Theme.Text(fs, token or "text-1")
	return fs
end

-- --- shapes: 9-slice fills, rings, shadows and glows --------------------------------------------------------------------

local SLICE_STRETCHED = (Enum and Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched) or 0

-- A 9-slice texture of the Media sheet `key` on `parent`: white, tinted with `token`.
function Theme.Slice(parent, key, token, layer, alpha)
	local a = Assets.textures[key]
	local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
	tex:SetTexture(a.path)
	if a.slice and tex.SetTextureSliceMargins then
		tex:SetTextureSliceMargins(a.slice, a.slice, a.slice, a.slice)
		if tex.SetTextureSliceMode then tex:SetTextureSliceMode(SLICE_STRETCHED) end
	end
	Theme.Crisp(tex)
	tex._asset = key
	if token then Theme.Tint(tex, token, alpha) end
	return tex
end

local RADII = { [8] = true, [12] = true, [18] = true }

-- Fill + 1 px ring (+ optional shadow) behind `frame`: returns the table of the regions. opts: radius (8|12|18),
-- fill token, border token, shadow (bool), shadowAlpha.
function Theme.Panel(frame, opts)
	opts = opts or {}
	local r = RADII[opts.radius] and opts.radius or 12
	local p = {}
	if opts.shadow then
		p.shadow = Theme.Slice(frame, "shadow", "scrim", "BACKGROUND", opts.shadowAlpha or 0.6)
		p.shadow:SetPoint("TOPLEFT", frame, "TOPLEFT", -24, 16)
		p.shadow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 24, -32)
		Theme.Call(p.shadow, function(region) region:SetShown(Theme.EffectsOn()) end)   -- "Neon effects: off" is flat
	end
	if opts.fill ~= false then
		p.fill = Theme.Slice(frame, "rr_fill_" .. r, opts.fill or "surface-1", "BACKGROUND")
		p.fill:SetAllPoints(frame)
	end
	if opts.border ~= false then
		p.ring = Theme.Slice(frame, "rr_ring_" .. r, opts.border or "border", "BORDER")
		p.ring:SetAllPoints(frame)
	end
	if opts.highlight then
		-- "on the dark the depth comes from the light": a 1 px line of `highlight` along the top edge, inside the corners
		p.highlight = frame:CreateTexture(nil, "BORDER", nil, 1)
		Theme.Fill(p.highlight, "highlight")
		Theme.Crisp(p.highlight)
		p.highlight:SetPoint("TOPLEFT", frame, "TOPLEFT", r, -1)
		p.highlight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -r, -1)
		p.highlight:SetHeight(Theme.Px(1, frame))
	end
	return p
end

-- Rebuild what the preferences decide when one changes (or the profile does): glows, shadows, text glow.
if ns.Bus then
	local function refresh(_, name)
		if name == nil or name == "effects" then Theme.Apply() end
	end
	ns.Bus:On("CONFIG_CHANGED", refresh, Theme)
	ns.Bus:On("CONFIG_PROFILE_CHANGED", function() Theme.Load() end, Theme)
end

-- The probes of /fdcp debug (docs/specs/ui-style.md §7): what the client answered. Nothing here is a verdict: the owner
-- reads the lines in game.
function Theme.Probes()
	local res = {}
	res.scrollBox = _G.CreateScrollBoxListLinearView ~= nil and _G.ScrollUtil ~= nil
	res.dataProvider = _G.CreateDataProvider ~= nil
	local probe = Theme.probeFrame
	if not probe and CreateFrame then
		probe = CreateFrame("Frame")
		Theme.probeFrame = probe
		probe:Hide()
	end
	local tex = probe and probe:CreateTexture(nil, "BACKGROUND")
	res.slicing = tex ~= nil and tex.SetTextureSliceMargins ~= nil
	res.addBlend = tex ~= nil and tex.SetBlendMode ~= nil
	res.spriteSheet = tex ~= nil and tex.SetSpriteSheetCell ~= nil
	res.pixel = Theme.PixelSize()
	res.scale = UIParent and UIParent:GetEffectiveScale() or 1
	local refused = 0
	if tex then
		for _, a in pairs(Assets.textures) do
			if tex:SetTexture(a.path) == false then refused = refused + 1 end
		end
	end
	res.texturesRefused = refused
	return res
end
