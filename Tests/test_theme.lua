-- Theme (M1-7): the tokens of docs/specs/ui-style.md §2 in three themes, WCAG contrast of text on surfaces, the registry
-- of tinted regions and Theme.Apply, fonts with the game fallback, Px, the 9-slice shapes and the assets table.

local function T() return FDCP.Theme end

local function lin(c)
	if c <= 0.03928 then return c / 12.92 end
	return ((c + 0.055) / 1.055) ^ 2.4
end
local function luminance(c) return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3]) end
local function contrast(a, b)
	local la, lb = luminance(a), luminance(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end
local function color(id, token) local t = T().themes[id]; return t[token] end

describe("tokens", function()
	it("three themes, Nebula the default", function()
		deepEq(T().List(), { "nebula", "aurora", "drago" })
		eq(T().DEFAULT, "nebula")
		eq(T().Current(), "nebula")
	end)

	it("every theme defines exactly the tokens of the table", function()
		local expected = {}
		for _, token in ipairs(T().TOKENS) do expected[token] = true end
		for id, t in pairs(T().themes) do
			for token in pairs(expected) do truthy(t[token], id .. " lacks " .. token) end
			for key, value in pairs(t) do
				if type(value) == "table" then truthy(expected[key], id .. " has an unknown token " .. key) end
			end
		end
	end)

	it("every colour is four numbers between 0 and 1", function()
		for id, t in pairs(T().themes) do
			for _, token in ipairs(T().TOKENS) do
				local c = t[token]
				eq(#c, 4, id .. " " .. token)
				for i = 1, 4 do truthy(c[i] >= 0 and c[i] <= 1, id .. " " .. token) end
			end
		end
	end)

	it("keeps the values of the spec for the default theme", function()
		local r, g, b = T().Color("accent", "nebula")
		near(r, 0xFC / 255, 1e-6); near(g, 0x7E / 255, 1e-6); near(b, 0x46 / 255, 1e-6)
		local _, _, _, a = T().Color("border", "nebula")
		near(a, 0.14, 1e-6)
	end)

	it("an unknown token is magenta, so a typo shows", function()
		deepEq({ T().Color("no-such-token") }, { 1, 0, 1, 1 })
	end)
end)

describe("contrast", function()
	local surfaces = { "bg", "surface-1", "surface-2", "surface-3", "raised" }

	it("text-1 and text-2 reach 4.5:1 on every surface of every theme", function()
		for id in pairs(T().themes) do
			for _, s in ipairs(surfaces) do
				for _, text in ipairs({ "text-1", "text-2" }) do
					local ratio = contrast(color(id, text), color(id, s))
					truthy(ratio >= 4.5, ("%s %s on %s = %.2f"):format(id, text, s, ratio))
				end
			end
		end
	end)

	it("text-3 (the muted text) reaches 3:1 and accent-text 4.5:1 on the card surfaces", function()
		for id in pairs(T().themes) do
			for _, s in ipairs({ "bg", "surface-1", "surface-2" }) do
				local r3 = contrast(color(id, "text-3"), color(id, s))
				truthy(r3 >= 3, ("%s text-3 on %s = %.2f"):format(id, s, r3))
				local ra = contrast(color(id, "accent-text"), color(id, s))
				truthy(ra >= 4.5, ("%s accent-text on %s = %.2f"):format(id, s, ra))
			end
		end
	end)

	it("the text of the primary button reaches 4.5:1 on its accent", function()
		for id in pairs(T().themes) do
			local ratio = contrast(color(id, "on-accent"), color(id, "accent"))
			truthy(ratio >= 4.5, ("%s on-accent on accent = %.2f"):format(id, ratio))
		end
	end)

	it("the state colours read on the window background", function()
		for id in pairs(T().themes) do
			for _, token in ipairs({ "ok", "warn", "err" }) do
				local ratio = contrast(color(id, token), color(id, "surface-1"))
				truthy(ratio >= 4.5, ("%s %s = %.2f"):format(id, token, ratio))
			end
		end
	end)
end)

describe("registry", function()
	it("Tint, Fill and Text show the token and Apply recolours without /reload", function()
		local f = CreateFrame("Frame")
		local tex, solid = f:CreateTexture(), f:CreateTexture()
		local fs = f:CreateFontString()
		T().Tint(tex, "accent"); T().Fill(solid, "surface-1"); T().Text(fs, "text-1")
		local r = tex:GetVertexColor()
		near(r, 0xFC / 255, 1e-6)
		truthy(T().Apply("aurora"))
		eq(T().Current(), "aurora")
		r = tex:GetVertexColor()
		near(r, 0, 1e-6)                        -- Aurora's accent #0054B6 has no red
		near(select(1, fs:GetTextColor()), 0x0B / 255, 1e-6)
		near(solid._texture[1], 1, 1e-6)        -- Aurora's surface-1 is white
	end)

	it("an unknown theme changes nothing", function()
		falsy(T().Apply("nope"))
		eq(T().Current(), "nebula")
	end)

	it("registering a region again replaces its token", function()
		local tex = CreateFrame("Frame"):CreateTexture()
		T().Tint(tex, "ok"); T().Tint(tex, "err")
		local r, g = tex:GetVertexColor()
		near(r, 1, 1e-6); near(g, 0x63 / 255, 1e-6)
	end)

	it("Call runs now and on every Apply", function()
		local seen = {}
		T().Call({}, function(_, id) seen[#seen + 1] = id end)
		T().Apply("drago")
		deepEq(seen, { "nebula", "drago" })
	end)

	it("announces THEME_CHANGED on the bus", function()
		local got
		FDCP.Bus:On("THEME_CHANGED", function(_, id) got = id end)
		T().Apply("aurora")
		eq(got, "aurora")
	end)

	it("the registry holds its regions weakly", function()
		collectgarbage(); collectgarbage()
		local n0 = T().Count()
		do
			local stub = { SetVertexColor = function() end }
			T().Tint(stub, "ok")
			eq(T().Count(), n0 + 1)
		end
		collectgarbage(); collectgarbage()
		eq(T().Count(), n0)
	end)
end)

describe("saved theme", function()
	it("Theme.Set saves, applies and survives /reload", function()
		truthy(T().Set("drago"))
		eq(T().Current(), "drago")
		eq(FDCP.Config:Get("theme"), "drago")
		Mock.Reload()
		FDCP.MainWindow:Build()
		eq(FDCP.Theme.Current(), "drago")
	end)

	it("an unknown theme is refused and the setting keeps its value", function()
		local ok, err = T().Set("nope")
		falsy(ok); eq(err, "BAD_VALUE")
		local ok2, err2 = FDCP.Config:Set("theme", "nope")
		falsy(ok2); eq(err2, "BAD_VALUE")
		eq(FDCP.Config:Get("theme"), "nebula")
	end)

	it("/fdcp theme shows and sets the theme in the active language", function()
		Mock.Slash("/fdcp theme")
		contains(table.concat(Mock.PlainOutput(), "\n"), "Theme: Nebula. Available: nebula, aurora, drago.")
		Mock.Slash("/fdcp theme aurora")
		eq(T().Current(), "aurora")
		Mock.Slash("/fdcp theme mauve")
		contains(table.concat(Mock.PlainOutput(), "\n"), "Unknown theme: mauve")
	end)

	it("/fdcp theme speaks Italian", function()
		T().Apply("nebula")
		FDCP.Locale.SetActive("itIT")
		Mock.Slash("/fdcp theme drago")
		contains(table.concat(Mock.PlainOutput(), "\n"), "Tema impostato su Drago.")
	end)
end)

describe("fonts", function()
	it("every font object uses the files of the addon", function()
		eq(T().SetupFonts("addon"), 0)
		for id, spec in pairs(T().fontSpecs) do
			local path = T().Font(id):GetFont()
			contains(path, "Media\\Fonts\\")
			eq(T().fontStatus[id], "addon")
			truthy(spec[2] >= 10)
		end
	end)

	it("falls back to the game font when a file does not load", function()
		Mock.missingFonts[FDCP.Assets.fonts.display.path] = true
		local n = T().SetupFonts("addon")
		truthy(n >= 1)
		eq(T().fontStatus.Display, "game")
		eq(T().fontStatus.Body, "addon")
		local path = T().Font("Display"):GetFont()
		falsy(path:find("Media", 1, true))
	end)

	it("the game fonts can be chosen on purpose", function()
		eq(T().SetupFonts("game"), 14)
		for id in pairs(T().fontSpecs) do eq(T().fontStatus[id], "game") end
	end)

	it("the saved setting decides the source", function()
		FDCP.Config:Set("fontSource", "game")
		T().SetupFonts()
		eq(T().fontStatus.Body, "game")
		local ok, err = FDCP.Config:Set("fontSource", "serif")
		falsy(ok); eq(err, "BAD_VALUE")
	end)
end)

describe("pixels and shapes", function()
	it("Px gives one physical pixel in UI units", function()
		Mock.screen.height = 1080
		UIParent:SetScale(0.5)
		near(T().Px(1), (768 / 1080) / 0.5, 1e-9)
		near(T().Px(2), 2 * (768 / 1080) / 0.5, 1e-9)
		UIParent:SetScale(1)
		Mock.screen.height = 768
		near(T().Px(3), 3, 1e-9)
	end)

	it("Px falls back to the UI scale when the screen size is unknown", function()
		GetPhysicalScreenSize = nil
		UIParent:SetScale(1)
		near(T().Px(1), 1, 1e-9)
	end)

	it("a 9-slice texture has the margin of its radius, no snapping and its token", function()
		local f = CreateFrame("Frame")
		local tex = T().Slice(f, "rr_fill_12", "surface-1")
		deepEq({ tex:GetTextureSliceMargins() }, { 12, 12, 12, 12 })
		eq(tex:GetTexture(), FDCP.Assets.textures.rr_fill_12.path)
		falsy(tex:IsSnappingToPixelGrid())
		eq(tex:GetTexelSnappingBias(), 0)
		near((tex:GetVertexColor()), 0x11 / 255, 1e-6)
	end)

	it("Panel builds fill, ring and optionally a shadow behind a frame", function()
		local f = CreateFrame("Frame")
		local p = T().Panel(f, { radius = 18, shadow = true })
		truthy(p.fill and p.ring and p.shadow)
		eq(p.fill._asset, "rr_fill_18")
		eq(p.ring._asset, "rr_ring_18")
		falsy(T().Panel(CreateFrame("Frame"), { radius = 8 }).shadow)
	end)

	it("the probes answer without an error", function()
		local p = T().Probes()
		eq(type(p.pixel), "number")
		truthy(p.slicing)
		eq(p.texturesRefused, 0)
		Mock.missingTextures[FDCP.Assets.textures.glow_s.path] = true
		eq(T().Probes().texturesRefused, 1)
	end)
end)

describe("assets table", function()
	it("lists every texture with a power-of-two size and every font file", function()
		local A = FDCP.Assets
		for key, t in pairs(A.textures) do
			truthy(t.path:find("^Interface\\AddOns\\FinlandDragonCreditPoints\\Media\\"), key .. " " .. tostring(t.path))
			for _, n in ipairs({ t.w, t.h }) do
				local p = 1
				while p < n do p = p * 2 end
				eq(p, n, key .. " is not a power of two")
			end
			if t.slice then truthy(t.slice * 2 <= math.max(t.w, t.h), key) end
		end
		eq(#A.AllPaths(), 15 + 6)
		local seen = {}
		for _, p in ipairs(A.AllPaths()) do falsy(seen[p], "duplicate " .. p); seen[p] = true end
	end)

	it("icon coordinates follow the sheet", function()
		local A = FDCP.Assets
		local l, r, t, b = A.IconCoords("chevron")
		deepEq({ l, r, t, b }, { 0, 1 / 16, 0, 1 / 16 })
		l, r = A.IconCoords("check")
		near(l, 1 / 16, 1e-9)
		isNil(A.IconCoords("nothing"))
	end)
end)
