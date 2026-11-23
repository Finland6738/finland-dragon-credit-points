-- UpgradeAdvisor: the upgrade badge of this player for an item (docs/ANALISI.md §5.1, §6, M5-2, rewritten by M7-5c). Lua
-- 5.1, no frames. It puts together what lives apart: the guild's rules (the section `upgrade`, read from the ledger this
-- client holds), the season's item-level band (the one the master looter's session carries, Net/Protocol.lua `ib`, else
-- the open season of this client's ledger), the player's declared specs (MS1 = main-spec, MS2 = off-spec:
-- Domain/Roster.lua; without a declaration the spec played now is the main-spec and there is no off-spec badge) and the
-- game: the item, and the gear the player wore during the fight (Adapters/GearSnapshot.lua; the gear worn now when there
-- is no snapshot of that boss). Domain/UpgradeScore.lua gives the tier. The popup draws the badge, the response carries it
-- to the master looter (Net/Protocol.lua SRESP `vd` / `eq`), the master looter's table shows it. It never changes the winner.
--
-- Advisor.For(itemID)  advice = { ms = result, os = result | nil, specs = { ms = specID | nil, os = specID | nil },
--                      autoPass (every badge says "cannot use it" and the rules ask for the preselection),
--                      snapshot (true: compared with the gear of the fight), band = { min, max } | nil,
--                      equipped = { "item:..." } (the worn pieces the item was compared with),
--                      wire = { vd = { m = packed, o = packed | nil }, eq = { ... }, cg = evidence | nil } (what the
--                      response carries; cg = the roll-cheating evidence of M7-5d, Advisor.Evidence) },
--                      or nil and a code: DISABLED (the rules turn the badge off), NO_CLASS, UNKNOWN, NOT_LOADED. The
--                      answer is kept until the gear, the snapshot, the spec, the band, the ledger or the rules change; an
--                      item whose data is not loaded is not kept (the popup asks for it and redraws).
-- Advisor.Badge(advice) the result the popup shows: the main-spec one, or the off-spec one when only that one is usable.
-- Advisor.Text(u) / Tone(u) / Lines(u) the words of a result `u` (an Evaluate result or UpgradeScore.Unpack's), from the
--                      locale: the badge text ("Medium upgrade · ilvl +13"), the badge tone and the tooltip lines.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local Advisor = {}
ns.UpgradeAdvisor, ns.modules.UpgradeAdvisor = Advisor, Advisor

local type, ipairs, pairs = type, ipairs, pairs

Advisor.MAX_LINKS = 4      -- worn pieces a response names
Advisor.generation = 0     -- raised when the equipment, the snapshot or the spec change
Advisor.ctx = nil          -- the context of the current generation and ledger
Advisor.cache = {}         -- [itemID] = { ctx, advice }

local function me() return ns.GuildRanks and ns.GuildRanks.Me() or nil end

-- Forgets what was computed (the next call reads the game again).
function Advisor.Reset()
	Advisor.generation = Advisor.generation + 1
	Advisor.ctx, Advisor.cache = nil, {}
end

---------------------------------------------------------------------------------------------------------------------
-- The context: rules, band, gear, character and declared specs

local function ledger()
	local NC = ns.NightController
	return NC and NC:Ledger() or nil
end

local function view()
	local PS = ns.Protocol and ns.Protocol.Session
	return PS and PS.view or nil
end

-- The band in force: the session's (the master looter's ledger), else the open season of this client's ledger.
local function bandOf(L, v)
	local U = ns.UpgradeScore
	if v and v.band then return U.Band(v.band) end
	local season = L and ns.Season and ns.Season.Current(L)
	return season and U.Band(season.band) or nil
end

local function sameBand(a, b)
	if a == nil or b == nil then return a == b end
	return a.min == b.min and a.max == b.max
end

local function context()
	local L = ledger()
	local count = L and ns.Ledger.Count(L) or -1
	local v = view()
	local encounter = v and v.e or nil
	local snap = ns.GearSnapshot and ns.GearSnapshot.Current(encounter) or nil
	local band = bandOf(L, v)
	local ctx = Advisor.ctx
	if ctx and ctx.generation == Advisor.generation and ctx.ledger == L and ctx.count == count and ctx.snap == snap
		and sameBand(ctx.band, band) then
		return ctx
	end
	ctx = { generation = Advisor.generation, ledger = L, count = count, snap = snap, band = band }
	ctx.rules = (L and ns.Rules and ns.Rules.Current(L).upgrade) or ns.UpgradeScore.DefaultRules()
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

-- The worn pieces of the context (read once): the snapshot of the fight, else the gear worn now. A worn piece the client
-- has not loaded yet is asked for; the badge is computed again when it arrives.
local function worn(ctx)
	if not ctx.equipped then
		if ctx.snap then
			ctx.equipped, ctx.links = ns.Inventory.FromLinks(ctx.snap.links)
		else
			ctx.equipped, ctx.links = ns.Inventory.Equipped()
		end
		for _, piece in pairs(ctx.equipped) do
			if piece.quality == nil and ns.ItemCache then
				ns.ItemCache.Get(piece.itemID, function()
					Advisor.Reset()
					if ns.Bus then ns.Bus:Emit("UPGRADE_ADVICE_CHANGED") end
				end)
			end
		end
	end
	return ctx.equipped
end

---------------------------------------------------------------------------------------------------------------------
-- The badge

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

-- The roll-cheating evidence of M7-5d (Domain/Cheat.lua ReadGear): for each slot the item was compared with, the item
-- level in the fight (the snapshot; only when there is one) and now (0 = empty), the item ids, and x = 1 when the compared
-- piece does not fit the main spec (Inventory.Piece with its specs, UpgradeScore.CanUse); then `h`, the main-spec badge
-- without those pieces. A piece not loaded yet leaves its level out. nil when there is nothing to say.
function Advisor.Evidence(ctx, piece, ms, opts)
	local U, Cheat = ns.UpgradeScore, ns.Cheat
	if not Cheat or type(ms) ~= "table" or type(ms.slots) ~= "table" or #ms.slots == 0 then return nil end
	local nowEq = ctx.snap and ns.Inventory.Equipped() or ctx.equipped
	local fit, g, unfit = {}, {}, false
	for slot, p in pairs(ctx.equipped) do fit[slot] = p end
	for i, slot in ipairs(ms.slots) do
		if i > Cheat.MAX_SLOTS then break end
		local compared, now = ctx.equipped[slot], nowEq[slot]
		local e = { s = slot, fi = compared and compared.itemID or nil, ni = now and now.itemID or nil }
		if ctx.snap then e.f = compared and compared.level or (compared == nil and 0 or nil) end
		e.n = now and now.level or (now == nil and 0 or nil)
		if compared and compared.link then
			local full = ns.Inventory.Piece(compared.link, { classID = ctx.player.classID, classFile = ctx.class })
			if full and U.CanUse(full, ctx.class, ctx.ms) == false then
				e.x, fit[slot], unfit = 1, nil, true
			end
		end
		g[#g + 1] = e
	end
	local cg = { g = g }
	if unfit then cg.h = U.Pack(U.Evaluate(piece, fit, { class = ctx.class, spec = ctx.ms }, opts)) end
	return Cheat.ReadGear(cg)
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
	local U = ns.UpgradeScore
	local opts = { band = ctx.band }
	local ms = U.Evaluate(piece, equipped, { class = ctx.class, spec = ctx.ms }, opts)
	local os = ctx.os and U.Evaluate(piece, equipped, { class = ctx.class, spec = ctx.os }, opts) or nil
	local results = { ms, os }
	local links = wornLinks(ctx, results)
	local advice = {
		ms = ms, os = os, specs = { ms = ctx.ms, os = ctx.os }, snapshot = ctx.snap ~= nil, band = ctx.band,
		autoPass = ctx.rules.autoPass == true and ms.usable == false and (os == nil or os.usable == false),
		equipped = links,
		wire = { vd = { m = U.Pack(ms), o = os and U.Pack(os) or nil }, eq = links,
			cg = Advisor.Evidence(ctx, piece, ms, opts) },
	}
	Advisor.cache[itemID] = { ctx = ctx, advice = advice }
	return advice
end

-- The result the popup shows: main-spec, or off-spec when only the off-spec can use the item.
function Advisor.Badge(advice)
	if type(advice) ~= "table" or not advice.ms then return nil end
	if advice.ms.usable == false and advice.os and advice.os.usable ~= false then return advice.os, "os" end
	return advice.ms, "ms"
end

-- The specs the badges are computed for: main-spec, off-spec | nil (the declared ones, else the one played now).
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

-- The badge: "Medium upgrade · ilvl +13", "Major upgrade · empty slot", "No upgrade · ilvl -4", "Not usable".
function Advisor.Text(u)
	if type(u) ~= "table" then return "" end
	if u.usable == false then return ns.Reasons.Text("VERDICT", "UNUSABLE") end
	local text = ns.Reasons.Text("VERDICT", u.verdict)
	if u.verdict ~= "NOT_COMPARABLE" then
		if u.code == "EMPTY_SLOT" then
			text = text .. " · " .. L()["UPG_EMPTY_SLOT"]
		elseif u.ilvlDelta then
			text = text .. " · " .. L()["UPG_ILVL"]:format(("%+.0f"):format(u.ilvlDelta))
		end
	end
	return text
end

local TONES = { MAJOR = "ok", MEDIUM = "accent", MINOR = "accent", NONE = "neutral", NOT_COMPARABLE = "neutral" }

-- The badge tone of a result (Widgets.BADGE_TONES).
function Advisor.Tone(u)
	if type(u) ~= "table" then return "neutral" end
	if u.usable == false then return "warn" end
	return TONES[u.verdict] or "neutral"
end

-- The order of the master looter's column: major first.
Advisor.ORDER = { MAJOR = 1, MEDIUM = 2, MINOR = 3, NONE = 4, NOT_COMPARABLE = 5 }

-- The tooltip lines of a result for a spec ("MS" = Main-spec, "OS" = Off-spec): the badge, why when it is not usable or
-- not comparable, and how the tier is read.
function Advisor.Lines(u, response)
	local lines = {}
	if type(u) ~= "table" then return lines end
	lines[1] = ns.Reasons.Text("RESPONSE", response or "MS") .. ": " .. Advisor.Text(u)
	if u.code and u.code ~= "EMPTY_SLOT" and ns.Reasons.Key("UPGRADE", u.code) then
		lines[#lines + 1] = ns.Reasons.Text("UPGRADE", u.code)
	end
	for _, note in ipairs(u.notes or {}) do
		if (note == "OLD_SEASON" or note == "ITEM_OLD_SEASON") and ns.Reasons.Key("UPGRADE", note) then
			lines[#lines + 1] = ns.Reasons.Text("UPGRADE", note)
		end
	end
	return lines
end

---------------------------------------------------------------------------------------------------------------------
-- Events: the gear, the snapshot and the spec change what an item is worth

local function changed()
	Advisor.Reset()
	if ns.Bus then ns.Bus:Emit("UPGRADE_ADVICE_CHANGED") end
end

if ns.Bus then ns.Bus:On("GEAR_SNAPSHOT_TAKEN", changed, Advisor) end

if ns.addon and CreateFrame then
	ns.addon.UpgradeAdvisor = Advisor   -- also reachable from tests
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	frame:SetScript("OnEvent", changed)
end
