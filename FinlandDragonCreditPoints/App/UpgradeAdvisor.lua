-- UpgradeAdvisor: the upgrade verdicts of this player for an item (docs/ANALISI.md §5.1, §6, M5-2). Lua 5.1, no frames.
-- It puts together the three things that live apart: the guild's rules (the section `upgrade`, read from the ledger this
-- client holds), the player's declared specs (MS1 = main-spec, MS2 = off-spec: Domain/Roster.lua; without a declaration
-- the spec the character plays now is the main-spec and there is no off-spec verdict) and the game (Adapters/Inventory.lua:
-- the item, the worn pieces, the stats), and gives them to Domain/UpgradeScore.lua twice: once with the MS1 weights for
-- Main-spec, once with the MS2 weights for Off-spec. The popup draws the result, the response carries it to the master
-- looter (Net/Protocol.lua SRESP `vd` / `eq`), the master looter's table shows it.
--
-- Advisor.For(itemID)  advice = { ms = result, os = result | nil, specs = { ms = specID | nil, os = specID | nil },
--                      autoPass (every verdict says "cannot use it" and the rules ask for the preselection),
--                      personal = { ms = bool, os = bool } (the verdict used the player's own weights, M5-3),
--                      equipped = { "item:..." } (the worn pieces the item was compared with),
--                      wire = { vd = { m = packed, o = packed | nil }, eq = { ... } } (what the response carries) },
--                      or nil and a code: DISABLED (the rules turn the verdicts off), NO_CLASS, UNKNOWN, NOT_LOADED. The
--                      answer is kept until the equipment, the spec, the ledger or the rules change; an item whose data
--                      is not loaded is not kept (the popup asks for it and redraws).
-- Advisor.Text(u) / Tone(u) / Lines(u) the words of a verdict `u` (an Evaluate result or UpgradeScore.Unpack's), from the
--                      locale: the chip text, the badge tone and the tooltip lines. No sentence is written in code.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Advisor = {}
ns.UpgradeAdvisor, ns.modules.UpgradeAdvisor = Advisor, Advisor

local type, ipairs, tostring = type, ipairs, tostring

Advisor.MAX_LINKS = 4      -- worn pieces a response names
Advisor.generation = 0     -- raised when the equipment or the spec change
Advisor.ctx = nil          -- the context of the current generation and ledger
Advisor.cache = {}         -- [itemID] = { ctx, advice }

local function me() return ns.GuildRanks and ns.GuildRanks.Me() or nil end

-- Forgets what was computed (the next call reads the game again).
function Advisor.Reset()
	Advisor.generation = Advisor.generation + 1
	Advisor.ctx, Advisor.cache = nil, {}
end

---------------------------------------------------------------------------------------------------------------------
-- The context: rules, character and declared specs (rebuilt when the ledger or the equipment change)

local function ledger()
	local NC = ns.NightController
	return NC and NC:Ledger() or nil
end

local function context()
	local L = ledger()
	local count = L and ns.Ledger.Count(L) or -1
	local ctx = Advisor.ctx
	if ctx and ctx.generation == Advisor.generation and ctx.ledger == L and ctx.count == count then return ctx end
	ctx = { generation = Advisor.generation, ledger = L, count = count }
	ctx.rules = (L and ns.Rules and ns.Rules.Current(L).upgrade) or ns.UpgradeScore.DefaultRules()
	ctx.config = ns.UpgradeScore.ConfigFromRules(ctx.rules)
	ctx.player = ns.Inventory.Player()
	-- the declared specs of this character (a main of the pool; an alt or an undeclared player plays the active spec)
	local decl
	local season = L and ns.Season and ns.Season.Current(L)
	if season and ns.Roster and me() then decl = ns.Roster.Get(L, season.id, me()) end
	local class = ctx.player.class or (decl and decl.class)
	local function ofClass(spec)
		local info = ns.Specs and ns.Specs.Get(spec)
		return spec ~= nil and (info == nil or info.class == class) and spec or nil
	end
	ctx.class = class
	ctx.ms = decl and ofClass(decl.ms1) or ctx.player.spec
	ctx.os = decl and ofClass(decl.ms2) or nil
	if ctx.os == ctx.ms then ctx.os = nil end
	Advisor.ctx = ctx
	return ctx
end

-- The worn pieces of the current generation (read once).
local function worn(ctx)
	if not ctx.equipped then ctx.equipped, ctx.links = ns.Inventory.Equipped() end
	return ctx.equipped
end

---------------------------------------------------------------------------------------------------------------------
-- The verdicts

local function wornLinks(ctx, results)
	local out, seen = {}, {}
	for _, r in ipairs(results) do
		for _, slot in ipairs(r.slots or {}) do
			local piece = ctx.equipped[slot]
			if piece and not seen[piece.link] and #out < Advisor.MAX_LINKS then
				seen[piece.link] = true
				out[#out + 1] = piece.link
			end
		end
	end
	return out
end

function Advisor.For(itemID)
	local ctx = context()
	if not ctx.rules.enabled then return nil, "DISABLED" end
	if not ctx.class then return nil, "NO_CLASS" end
	local hit = Advisor.cache[itemID]
	if hit and hit.ctx == ctx then return hit.advice end
	local piece, why = ns.Inventory.Piece(itemID, { classID = ctx.player.classID, classFile = ctx.class })
	if not piece then return nil, why end
	local equipped = worn(ctx)
	ns.Inventory.Fill(piece, equipped)
	local U = ns.UpgradeScore
	-- the player's own weights for a spec (M5-3), when they imported and turned them on; else the defaults
	local PU = ns.PersonalUpgrade
	local msWeights = PU and PU.WeightsFor(ctx.ms)
	local osWeights = ctx.os and PU and PU.WeightsFor(ctx.os) or nil
	local ms = U.Evaluate(piece, equipped, { class = ctx.class, spec = ctx.ms, weights = msWeights }, ctx.config)
	local os = ctx.os and U.Evaluate(piece, equipped, { class = ctx.class, spec = ctx.os, weights = osWeights }, ctx.config) or nil
	local results = { ms, os }
	local links = wornLinks(ctx, results)
	local advice = {
		ms = ms, os = os, specs = { ms = ctx.ms, os = ctx.os },
		personal = { ms = msWeights ~= nil, os = osWeights ~= nil },   -- compared on the player's own weights
		autoPass = ctx.rules.autoPass == true and ms.usable == false and (os == nil or os.usable == false),
		equipped = links,
		wire = { vd = { m = U.Pack(ms), o = os and U.Pack(os) or nil }, eq = links },
	}
	Advisor.cache[itemID] = { ctx = ctx, advice = advice }
	return advice
end

-- The specs the verdicts are computed for: main-spec, off-spec | nil (the declared ones, else the one played now).
function Advisor.Specs()
	local ctx = context()
	return ctx.ms, ctx.os
end

-- The worn pieces' names for a tooltip: "Helm of Embers". An item the client has not loaded yet is asked for and left out.
function Advisor.EquippedNames(links)
	local out = {}
	for _, link in ipairs(links or {}) do
		local id = ns.ItemCache and ns.ItemCache.IdFromLink(link)
		local entry = id and ns.ItemCache.Get(id)   -- loaded now, or asked for: the next hover has the name
		if entry and entry.name then out[#out + 1] = entry.name end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- The words

local function L() return ns.L end

local function percent(pct)
	local text = ("%+.1f%%"):format(pct * 100):gsub("%.", L()["UPG_DECIMAL"])
	return text
end
Advisor.Percent = percent

-- The chip of a verdict: "Big upgrade +7.4% · ilvl +6".
function Advisor.Text(u)
	if type(u) ~= "table" then return "" end
	if u.usable == false then return ns.Reasons.Text("VERDICT", "UNUSABLE") end
	local text = ns.Reasons.Text("VERDICT", u.verdict)
	if u.verdict == "BIG" or u.verdict == "SMALL" or u.verdict == "NONE" then
		if u.pct then text = text .. " " .. percent(u.pct) end
		if u.ilvlDelta then text = text .. " · " .. L()["UPG_ILVL"]:format(("%+.0f"):format(u.ilvlDelta)) end
	end
	return text
end

local TONES = { BIG = "ok", SMALL = "accent", NONE = "neutral", NOT_COMPARABLE = "neutral" }

-- The badge tone of a verdict (Widgets.BADGE_TONES).
function Advisor.Tone(u)
	if type(u) ~= "table" then return "neutral" end
	if u.usable == false then return "warn" end
	return TONES[u.verdict] or "neutral"
end

-- The tooltip lines of a verdict for a spec ("main" = Main-spec, "off" = Off-spec): the chip, why when it is not
-- usable or not comparable, and what the comparison was made on.
function Advisor.Lines(u, response)
	local lines = {}
	if type(u) ~= "table" then return lines end
	lines[1] = ns.Reasons.Text("RESPONSE", response or "MS") .. ": " .. Advisor.Text(u)
	if u.code and ns.Reasons.Key("UPGRADE", u.code) then lines[#lines + 1] = ns.Reasons.Text("UPGRADE", u.code) end
	if u.basis == "ILVL" then lines[#lines + 1] = L()["UPG_BASIS_ILVL"]
	elseif u.basis == "STATS" then lines[#lines + 1] = L()["UPG_BASIS_STATS"] end
	return lines
end

---------------------------------------------------------------------------------------------------------------------
-- Events: the equipment and the spec change what an item is worth

if ns.addon and CreateFrame then
	ns.addon.UpgradeAdvisor = Advisor   -- also reachable from tests
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	frame:SetScript("OnEvent", function()
		Advisor.Reset()
		if ns.Bus then ns.Bus:Emit("UPGRADE_ADVICE_CHANGED") end
	end)
end
