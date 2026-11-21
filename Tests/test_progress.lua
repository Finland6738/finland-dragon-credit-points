-- Progress (M3-3b): the first kill of every boss per faction of the community site. Data/Instances.lua and
-- Data/Specs.lua are the fixed tables; Domain/Progress.lua is pure (kills inside and outside a night, values entered by
-- hand and their corrections, the faction key); App/ProgressController.lua records a kill outside a night in a guild
-- group and writes PROGRESS_SET for an officer with progress.edit (the mock client drives it, as the game would).
local function Lg() return FDCP.Ledger end
local function Sn() return FDCP.Season end
local function M() return FDCP.Members end
local function N() return FDCP.Nights end
local function P() return FDCP.Permissions end
local function Pr() return FDCP.Progress end
local function I() return FDCP.Instances end
local function Sp() return FDCP.Specs end
local function Ru() return FDCP.Rules end
local function NC() return FDCP.NightController end
local function PC() return FDCP.ProgressController end

local GM, OFFICER, RAIDER = "Aurel-Camelot", "Bryn-Camelot", "Corin-Camelot"
local MC, ONY = 409, 249
local LUCIFRON, MAGMADAR, GEHENNAS, RAGNAROS, ONYXIA = 663, 664, 665, 672, 1084

local function ranks()
	local h = P().NewHistory()
	P().RecordRank(h, GM, 0, 0)
	P().RecordRank(h, OFFICER, 1, 0)
	P().RecordRank(h, RAIDER, 3, 0)
	h.loaded = true
	return h
end

local function gate() return P().Gate(ranks()) end

local function newSeason()
	local L = Lg().New()
	assert(Sn().Open(L, { author = GM, ts = 1, season = "S1", label = "Tier 1",
		instances = { { id = MC, size = 40 }, { id = ONY, size = 40 } } }))
	assert(M().Join(L, { author = OFFICER, ts = 2, season = "S1", member = "Aurel", faction = "Horde" }))
	return L
end

local function kill(L, id, ts, date, extra)
	local d = { author = OFFICER, ts = ts, season = "S1", encounterID = id, difficulty = 14, date = date }
	for k, v in pairs(extra or {}) do d[k] = v end
	return N().Kill(L, d)
end

local function set(L, id, ts, date, faction, author, opts)
	return Pr().Set(L, { author = author or OFFICER, ts = ts, encounterID = id, faction = faction or "Nebulah",
		date = date }, opts)
end

local function dates(firsts)
	local out = {}
	for enc, f in pairs(firsts) do out[enc] = f.date end
	return out
end

---------------------------------------------------------------------------------------------------------------------

describe("the fixed tables", function()
	it("list the site's instances and bosses in the site's order, with English names", function()
		local list = I().LIST
		eq(#list, 2)
		eq(list[1].slug, "mc"); eq(list[1].name, "Molten Core"); eq(list[1].size, 40); eq(list[1].instanceID, MC)
		local names = {}
		for _, b in ipairs(list[1].bosses) do names[#names + 1] = b.name end
		eq(table.concat(names, ","), "Lucifron,Magmadar,Gehennas,Garr,Shazzrah,Baron Geddon,Sulfuron Harbinger,"
			.. "Golemagg,Majordomo Executus,Ragnaros")
		eq(list[2].slug, "ony"); eq(list[2].name, "Onyxia\226\128\153s Lair", "the site's typographic apostrophe")
		eq(#list[2].bosses, 1); eq(list[2].bosses[1].name, "Onyxia")
	end)

	it("find an instance by id and slug, and a boss's instance and position by encounter id", function()
		eq(I().Get(MC).slug, "mc"); eq(I().BySlug("ony").instanceID, ONY)
		isNil(I().Get(9999)); isNil(I().Get("409")); isNil(I().BySlug("bwl"))
		local inst, boss, index = I().OfEncounter(RAGNAROS)
		eq(inst.slug, "mc"); eq(boss.name, "Ragnaros"); eq(index, 10)
		inst, boss, index = I().OfEncounter(ONYXIA)
		eq(inst.slug, "ony"); eq(index, 1)
		isNil(I().OfEncounter(610)); isNil(I().OfEncounter(nil))
		local seen = {}
		for _, i in ipairs(I().LIST) do
			for _, b in ipairs(i.bosses) do
				isNil(seen[b.encounterID], "every encounter id appears once"); seen[b.encounterID] = true
				truthy(type(b.journalID) == "number")
			end
		end
	end)

	it("give every spec of the nine classes a class, an English name and a role, and the site's words", function()
		local classes = {}
		for _, s in ipairs(Sp().LIST) do
			truthy(FDCP.Roster.CLASSES[s.class], s.name); truthy(FDCP.Roster.ROLES[s.role], s.name)
			eq(Sp().Get(s.id), s)
			classes[s.class] = (classes[s.class] or 0) + 1
		end
		for class in pairs(FDCP.Roster.CLASSES) do truthy(classes[class], class) end
		deepEq(Sp().Site(257), { class = "priest", spec = "Holy", role = "healer" })
		deepEq(Sp().Site(73), { class = "warrior", spec = "Protection", role = "tank" })
		deepEq(Sp().Site(260), { class = "rogue", spec = "Combat", role = "dps" })
		isNil(Sp().Site(1)); isNil(Sp().Get("257"))
		eq(#Sp().OfClass("DRUID"), 4)
	end)

	it("plug the spec table into the roster: the class and the role come from the MS1", function()
		eq(FDCP.Roster.SpecInfo, Sp().Get)
		local L = newSeason()
		local e = assert(FDCP.Roster.Join(L, { author = OFFICER, ts = 3, season = "S1", member = "Bryn", ms1 = 257 }))
		eq(e.payload.class, "PRIEST"); eq(e.payload.role, "HEALER")
		local _, code = FDCP.Roster.Join(L, { author = OFFICER, ts = 4, season = "S1", member = "Corin", class = "MAGE",
			ms1 = 257 })
		truthy(code ~= nil, "a priest spec for a mage is refused")
	end)
end)

describe("the faction key", function()
	it("is Nebulah for the Horde and Nebulaa for the Alliance by default, or the name the GM wrote", function()
		local rules = Ru().DefaultConfig()
		eq(rules.site.factionName, "")
		eq(Pr().FactionKey(rules, "Horde"), "Nebulah")
		eq(Pr().FactionKey(rules, "Alliance"), "Nebulaa")
		isNil(Pr().FactionKey(rules, nil))
		rules.site.factionName = "Iron Wolves"
		eq(Pr().FactionKey(rules, "Horde"), "Iron Wolves")
		eq(Pr().FactionKey(nil, "Alliance"), "Nebulaa")
	end)

	it("is checked with the rules: a site key, or empty for the default", function()
		local rules = Ru().DefaultConfig()
		truthy(Ru().Validate(rules))
		for _, bad in ipairs({ "-x", string.rep("a", 33), "a:b", 7, "Ne\"bulah" }) do
			rules.site.factionName = bad
			local ok, problems = Ru().Validate(rules)
			falsy(ok, tostring(bad)); eq(problems[1], "site.factionName")
		end
		rules.site = { factionName = "", colour = "red" }
		local ok, problems = Ru().Validate(rules)
		falsy(ok); eq(problems[1], "site.unknown:colour")
		truthy(Ru().Validate(Ru().WithDefaults({})), "rules written before M3-3b get the empty default")
	end)

	it("is written by the GM with the rules (CONFIG_CHANGED) and read back", function()
		local L = Lg().New()
		local rules = Ru().DefaultConfig()
		rules.site.factionName = "Nebulaa"
		local _, code = Ru().Change(L, { author = OFFICER, ts = 1, rules = rules }, gate())
		eq(code, "NOT_GM")
		assert(Ru().Change(L, { author = GM, ts = 2, rules = rules }, gate()))
		eq(Pr().FactionKey(Ru().Current(L), "Horde"), "Nebulaa")
	end)
end)

describe("first kills", function()
	it("are the oldest kill, inside or outside a night; a later kill never moves the date forward", function()
		local L = newSeason()
		assert(kill(L, LUCIFRON, 50, "2026-11-05"))                    -- outside a night
		assert(N().Open(L, { author = OFFICER, ts = 100, season = "S1", date = "2026-11-12", instanceID = MC,
			difficulty = "normal" }))
		assert(kill(L, LUCIFRON, 200, "2026-11-12"))
		assert(kill(L, MAGMADAR, 210, "2026-11-12"))
		assert(N().Close(L, { author = OFFICER, ts = 300, season = "S1" }))
		assert(kill(L, MAGMADAR, 400, "2026-11-19"))                   -- a later kill, outside a night
		local f = Pr().FirstKills(L, "Nebulah", true)
		deepEq(dates(f), { [LUCIFRON] = "2026-11-05", [MAGMADAR] = "2026-11-12" })
		eq(f[LUCIFRON].source, "KILL"); eq(f[MAGMADAR].source, "KILL")
		-- the order the events arrive in changes nothing
		local R = Lg().New()
		local list = Lg().Sorted(L)
		for i = #list, 1, -1 do Lg().Merge(R, { list[i] }) end
		deepEq(dates(Pr().FirstKills(R, "Nebulah", true)), dates(f))
	end)

	it("a backfill by hand counts when it is older, and a kill without a date is ignored", function()
		local L = newSeason()
		assert(kill(L, LUCIFRON, 50, "2026-11-05"))
		assert(kill(L, GEHENNAS, 60, nil))
		assert(set(L, LUCIFRON, 70, "2026-09-30"))   -- killed before the addon
		assert(set(L, RAGNAROS, 71, "2026-10-15"))   -- never recorded by the addon
		local f = Pr().FirstKills(L, "Nebulah", true)
		deepEq(dates(f), { [LUCIFRON] = "2026-09-30", [RAGNAROS] = "2026-10-15" })
		eq(f[LUCIFRON].source, "SET")
	end)

	it("a correction replaces the earlier value by hand, even later, but never past a recorded kill", function()
		local L = newSeason()
		assert(set(L, RAGNAROS, 10, "2026-10-01"))
		assert(set(L, RAGNAROS, 20, "2026-10-08"))   -- a typo fixed: the date moves forward
		eq(Pr().FirstKills(L, "Nebulah", true)[RAGNAROS].date, "2026-10-08")
		assert(kill(L, RAGNAROS, 30, "2026-10-05"))
		eq(Pr().FirstKills(L, "Nebulah", true)[RAGNAROS].date, "2026-10-05", "the kill is older than the correction")
		assert(set(L, RAGNAROS, 40, "2026-12-01"))
		eq(Pr().FirstKills(L, "Nebulah", true)[RAGNAROS].date, "2026-10-05", "a correction cannot pass a recorded kill")
		assert(set(L, RAGNAROS, 50, "2026-10-05"))
		eq(Pr().FirstKills(L, "Nebulah", true)[RAGNAROS].source, "KILL", "same day: the recorded kill is the proof")
		-- clearing removes what was entered by hand, the kill stays
		assert(Pr().Clear(L, { author = OFFICER, ts = 60, encounterID = RAGNAROS, faction = "Nebulah" }))
		eq(Pr().FirstKills(L, "Nebulah", true)[RAGNAROS].date, "2026-10-05")
		assert(set(L, GEHENNAS, 70, "2026-10-02"))
		assert(Pr().Clear(L, { author = OFFICER, ts = 80, encounterID = GEHENNAS, faction = "Nebulah" }))
		isNil(Pr().FirstKills(L, "Nebulah", true)[GEHENNAS])
		local _, code = Pr().Clear(L, { author = OFFICER, ts = 90, encounterID = GEHENNAS, faction = "Nebulah" })
		eq(code, "NOTHING_TO_CLEAR")
	end)

	it("keeps the factions apart: recorded kills are the guild's own, the other key shows only what was entered", function()
		local L = newSeason()
		assert(kill(L, LUCIFRON, 50, "2026-11-05"))
		assert(set(L, LUCIFRON, 60, "2026-10-20", "Nebulaa"))
		assert(set(L, ONYXIA, 61, "2026-10-21", "Nebulaa"))
		deepEq(dates(Pr().FirstKills(L, "Nebulah", true)), { [LUCIFRON] = "2026-11-05" })
		deepEq(dates(Pr().FirstKills(L, "Nebulaa", false)), { [LUCIFRON] = "2026-10-20", [ONYXIA] = "2026-10-21" })
		deepEq(Pr().Keys(L, "Nebulah"), { "Nebulah", "Nebulaa" })
		assert(set(L, ONYXIA, 62, "2026-10-22", "Iron Wolves"))
		deepEq(Pr().Keys(L, "Nebulah"), { "Nebulah", "Iron Wolves", "Nebulaa" })
		deepEq(Pr().Keys(L, "Keepers"), { "Keepers", "Iron Wolves", "Nebulaa" }, "a custom key has no default partner")
	end)

	it("are counted per instance with the bosses in the site's order", function()
		local L = newSeason()
		assert(kill(L, LUCIFRON, 50, "2026-11-05"))
		assert(kill(L, MAGMADAR, 51, "2026-11-05"))
		assert(kill(L, 610, 52, "2026-11-05"))   -- an encounter the table does not know: in the ledger, not in the tab
		assert(set(L, ONYXIA, 60, "2026-10-21", "Nebulaa"))
		local p = Pr().Build(L, "Nebulah")
		eq(p.own, "Nebulah"); deepEq(p.keys, { "Nebulah", "Nebulaa" })
		eq(#p.instances, 2)
		local mc, ony = p.instances[1], p.instances[2]
		eq(mc.slug, "mc"); eq(mc.total, 10); deepEq(mc.counts, { Nebulah = 2, Nebulaa = 0 })
		eq(mc.bosses[1].name, "Lucifron"); eq(mc.bosses[1].index, 1); eq(mc.bosses[1].first.Nebulah.date, "2026-11-05")
		isNil(mc.bosses[1].first.Nebulaa)
		eq(mc.bosses[3].name, "Gehennas"); isNil(mc.bosses[3].first.Nebulah)
		eq(mc.bosses[1].localName, "Lucifron", "no lookup: the English name")
		eq(ony.total, 1); deepEq(ony.counts, { Nebulah = 0, Nebulaa = 1 })
		local q = Pr().Build(L, "Nebulah", { localName = function(boss, inst)
			if boss then return boss.encounterID == LUCIFRON and "Lucifrone" or nil end
			return inst.slug == "mc" and "Nucleo Fuso" or nil
		end })
		eq(q.instances[1].bosses[1].localName, "Lucifrone"); eq(q.instances[1].bosses[2].localName, "Magmadar")
		eq(q.instances[1].localName, "Nucleo Fuso"); eq(q.instances[2].localName, "Onyxia\226\128\153s Lair")
	end)
end)

describe("entering a first kill by hand", function()
	it("needs a boss of the table, a site key and a date not in the future", function()
		local L = newSeason()
		local _, code = set(L, 610, 10, "2026-10-01")
		eq(code, "UNKNOWN_ENCOUNTER")
		_, code = set(L, LUCIFRON, 10, "2026-10-01", "Neb:ulah")
		eq(code, "faction")
		_, code = set(L, LUCIFRON, 10, "1/10/2026")
		eq(code, "date")
		_, code = Pr().Set(L, { author = OFFICER, ts = 10, encounterID = LUCIFRON, faction = "Nebulah",
			date = "2026-12-01", today = "2026-11-21" })
		eq(code, "FUTURE")
		assert(set(L, LUCIFRON, 10, "2026-10-01"))
		_, code = set(L, LUCIFRON, 11, "2026-10-01")
		eq(code, "UNCHANGED")
		local e = assert(set(L, LUCIFRON, 12, "2026-09-01"))
		eq(e.type, "PROGRESS_SET"); isNil(e.season, "guild-level")
		deepEq(e.payload, { encounterID = LUCIFRON, faction = "Nebulah", date = "2026-09-01" })
	end)

	it("is refused to a member without progress.edit, and the GM can move the permission", function()
		local L = newSeason()
		local _, code = set(L, LUCIFRON, 10, "2026-10-01", nil, RAIDER, gate())
		eq(code, "RANK_TOO_LOW")
		eq(#Lg().Sorted(L, function(e) return e.type == "PROGRESS_SET" end), 0, "nothing written")
		assert(set(L, LUCIFRON, 11, "2026-10-01", nil, OFFICER, gate()))
		-- an event a raider wrote with a modified addon is refused by every other client
		local forged = { id = RAIDER .. ":1", author = RAIDER, seq = 1, ts = 12, type = "PROGRESS_SET", v = 1,
			payload = { encounterID = MAGMADAR, faction = "Nebulah", date = "2026-01-01" } }
		local report = Lg().Merge(L, { forged }, gate())
		eq(report.added, 0); eq(report.refused[1].code, "RANK_TOO_LOW")
		isNil(Pr().FirstKills(L, "Nebulah", true)[MAGMADAR])
		-- the GM keeps it to the GM: the officer is refused from then on
		local t = P().DefaultTable()
		t["progress.edit"] = 0
		assert(P().Change(L, { author = GM, ts = 20, table = t, confirmed = true }, gate()))
		_, code = set(L, MAGMADAR, 30, "2026-10-01", nil, OFFICER, gate())
		eq(code, "RANK_TOO_LOW")
		assert(set(L, MAGMADAR, 31, "2026-10-01", nil, GM, gate()))
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The controller on the mock client

local ME = "Testchar-TestRealm"
local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }
local MOLTEN_CORE = { name = "Molten Core", type = "raid", difficultyID = 14, difficultyName = "Normal", maxPlayers = 40,
	instanceID = MC }
local ONYXIAS_LAIR = { name = "Onyxia's Lair", type = "raid", difficultyID = 14, difficultyName = "Normal",
	maxPlayers = 40, instanceID = ONY }

local function guild(myRank)
	return function(Mock)
		Mock.guild.Set({ name = "Keepers", ranks = RANKS, myRank = myRank or 1, members = {
			{ name = "Aurel", rank = 0 }, { name = "Bryn", rank = 1 }, { name = "Corin", rank = 3 },
		} })
	end
end

local function settle() Mock.Advance(3) end

local function raid(...)
	local members = {}
	for _, n in ipairs({ ... }) do members[#members + 1] = { name = n, inGuild = true } end
	Mock.group.Set({ raid = true, members = members })
end

local function bound()
	local L = Lg().New()
	assert(Sn().Open(L, { author = "Aurel-TestRealm", ts = 1, season = "S1",
		instances = { { id = MC, size = 40 }, { id = ONY, size = 40 } } }))
	for i, n in ipairs({ "Aurel", "Bryn", "Corin" }) do
		assert(M().Join(L, { author = "Bryn-TestRealm", ts = 1 + i, season = "S1", member = n .. "-TestRealm",
			faction = "Horde" }))
	end
	NC():Bind(L)
	Mock.encounter.Set({ instance = MOLTEN_CORE })
	return L
end

local function kills(L) return #Lg().Sorted(L, function(e) return e.type == "ENCOUNTER_KILLED" end) end

describe("Compat for the progress", function()
	it("InGuildParty: true, false, or nil when the client hides it or lacks it", function()
		local G = FDCP.Compat.Group
		falsy(G.InGuildParty()); eq(G.InGuildParty(), false)
		raid("Aurel")
		Mock.group.guildParty = true
		eq(G.InGuildParty(), true)
		Mock.group.guildParty = Mock.SECRET
		isNil(G.InGuildParty())
		local saved = _G.InGuildParty
		_G.InGuildParty = nil
		isNil(G.InGuildParty())
		_G.InGuildParty = saved
	end)

	it("Encounter Journal names: only when the entry is the same encounter or map", function()
		local E = FDCP.Compat.Encounter
		isNil(E.JournalName(1519, LUCIFRON), "the client does not know it")
		Mock.journal.encounters[1519] = { name = "Lucifrone", encounterID = LUCIFRON }
		Mock.journal.encounters[1520] = { name = "Gehennas?", encounterID = GEHENNAS }
		eq(E.JournalName(1519, LUCIFRON), "Lucifrone")
		eq(E.JournalName(1519), "Lucifrone")
		isNil(E.JournalName(1520, MAGMADAR), "another encounter: the English name stays")
		isNil(E.JournalName(nil, LUCIFRON))
		Mock.journal.instances[741] = { name = "Nucleo Fuso", mapID = MC }
		eq(E.JournalInstanceName(741, MC), "Nucleo Fuso")
		isNil(E.JournalInstanceName(741, ONY))
		Mock.journal.encounters[1521] = { name = Mock.SECRET, encounterID = GEHENNAS }
		isNil(E.JournalName(1521, GEHENNAS), "a hidden name is never shown")
	end)
end)

describe("the progress controller", function()
	before_boot(guild(1))

	it("records a first kill outside a night in a guild group, once per boss", function()
		local L = bound()
		settle()
		raid("Aurel", "Bryn")
		Mock.group.guildParty = true
		local seen = {}
		FDCP.Bus:On("PROGRESS_KILL_RECORDED", function(_, e) seen[#seen + 1] = e end)
		Mock.encounter.End(LUCIFRON, "Lucifron", true)
		eq(kills(L), 1); eq(#seen, 1)
		local e = seen[1]
		eq(e.author, ME); eq(e.payload.encounterID, LUCIFRON); isNil(e.payload.night)
		eq(e.payload.date, "2026-01-01"); eq(e.payload.instanceID, MC); eq(e.payload.difficulty, 14)
		Mock.Advance(3600)
		Mock.encounter.End(LUCIFRON, "Lucifron", true)
		eq(kills(L), 1, "a farm kill adds nothing")
		local _, code = PC():OnEncounterEnd({ encounterID = LUCIFRON, success = true })
		eq(code, "ALREADY_KILLED")
		eq(Pr().FirstKills(L, "Nebulah", true)[LUCIFRON].date, "2026-01-01")
		eq(PC():FactionKey(), "Nebulah", "the mock player is Horde")
	end)

	it("writes nothing outside a guild group, outside the table's raids, on a wipe or without a season", function()
		local L = bound()
		settle()
		raid("Aurel", "Bryn")
		Mock.encounter.End(LUCIFRON, "Lucifron", true)
		eq(kills(L), 0, "not a guild group")
		local _, code = PC():OnEncounterEnd({ encounterID = LUCIFRON, success = true })
		eq(code, "NOT_GUILD_GROUP")
		Mock.group.guildParty = true
		Mock.encounter.End(LUCIFRON, "Lucifron", false)
		eq(kills(L), 0, "a wipe")
		Mock.encounter.Set({ instance = { name = "Somewhere", type = "raid", difficultyID = 14, instanceID = 9999 } })
		_, code = PC():OnEncounterEnd({ encounterID = LUCIFRON, success = true })
		eq(code, "NOT_IN_TABLE")
		Mock.encounter.Set({ instance = MOLTEN_CORE })
		assert(Sn().Close(L, { author = "Aurel-TestRealm", ts = 50, season = "S1" }))
		_, code = PC():OnEncounterEnd({ encounterID = LUCIFRON, success = true })
		eq(code, "NO_SEASON")
		eq(kills(L), 0)
	end)

	it("leaves a kill in the night's instance to the night, and records one in another instance", function()
		local L = bound()
		settle()
		raid("Aurel", "Bryn")
		Mock.group.guildParty = true
		local night = assert(NC():Open({}))
		Mock.encounter.End(LUCIFRON, "Lucifron", true)
		eq(kills(L), 1, "written once, by the night")
		eq(N().Kills(L)[1].night, night.id)
		local _, code = PC():OnEncounterEnd({ encounterID = MAGMADAR, success = true })
		eq(code, "IN_NIGHT")
		Mock.encounter.Set({ instance = ONYXIAS_LAIR })
		Mock.encounter.End(ONYXIA, "Onyxia", true)
		eq(kills(L), 2)
		local ony = N().Kills(L, { encounterID = ONYXIA })[1]
		isNil(ony.night); eq(ony.instanceID, ONY)
		local p = assert(PC():Build())
		eq(p.instances[1].counts.Nebulah, 1); eq(p.instances[2].counts.Nebulah, 1)
	end)

	it("a member without the rank writes nothing", function()
		Mock.guild.SetRank("Testchar", 3)
		local L = bound()
		settle()
		raid("Aurel", "Bryn")
		Mock.group.guildParty = true
		Mock.encounter.End(LUCIFRON, "Lucifron", true)
		eq(kills(L), 0)
		local e, code = PC():Set(LUCIFRON, "2025-12-01")
		isNil(e); eq(code, "RANK_TOO_LOW")
		e, code = PC():Clear(LUCIFRON)
		eq(code, "RANK_TOO_LOW")
		eq(Lg().Count(L), 4, "only the season and the pool")
	end)

	it("nothing is written while the guild roster loads", function()
		Mock.guild.Set({ name = "Keepers", ranks = RANKS, myRank = 1, loading = true, members = { { name = "Aurel", rank = 0 } } })
		local L = bound()
		raid("Aurel")
		Mock.group.guildParty = true
		local _, code = PC():OnEncounterEnd({ encounterID = LUCIFRON, success = true })
		eq(code, "PENDING")
		_, code = PC():Set(LUCIFRON, "2025-12-01")
		eq(code, "PENDING")
		eq(kills(L), 0)
	end)

	it("an officer enters, corrects and clears a first kill for either faction key", function()
		local L = bound()
		settle()
		local seen = 0
		FDCP.Bus:On("PROGRESS_CHANGED", function() seen = seen + 1 end)
		local e = assert(PC():Set(RAGNAROS, "2025-12-01"))
		eq(e.author, ME); eq(e.payload.faction, "Nebulah")
		local _, code = PC():Set(RAGNAROS, "2026-02-01")
		eq(code, "FUTURE", "the mock realm's day is 2026-01-01")
		assert(PC():Set(RAGNAROS, "2025-12-08"))
		assert(PC():Set(ONYXIA, "2025-11-30", "Nebulaa"))
		local p = PC():Build()
		eq(p.instances[1].bosses[10].first.Nebulah.date, "2025-12-08")
		eq(p.instances[2].bosses[1].first.Nebulaa.date, "2025-11-30")
		assert(PC():Clear(RAGNAROS))
		isNil(PC():Build().instances[1].bosses[10].first.Nebulah)
		eq(seen, 4)
		_, code = PC():Set(610, "2025-12-01")
		eq(code, "UNKNOWN_ENCOUNTER")
	end)

	it("takes the site key from the rules, and the names from the Encounter Journal when it knows them", function()
		local L = bound()
		settle()
		local rules = Ru().DefaultConfig()
		rules.site.factionName = "Keepers"
		assert(Ru().Change(L, { author = "Aurel-TestRealm", ts = 5, rules = rules, confirmed = true }))
		eq(PC():FactionKey(), "Keepers")
		Mock.journal.encounters[1519] = { name = "Lucifrone", encounterID = LUCIFRON }
		Mock.journal.encounters[1520] = { name = "Wrong", encounterID = 9 }
		Mock.journal.instances[741] = { name = "Nucleo Fuso", mapID = MC }
		local p = PC():Build()
		eq(p.own, "Keepers"); deepEq(p.keys, { "Keepers" })
		eq(p.instances[1].localName, "Nucleo Fuso"); eq(p.instances[1].name, "Molten Core")
		eq(p.instances[1].bosses[1].localName, "Lucifrone"); eq(p.instances[1].bosses[1].name, "Lucifron")
		eq(p.instances[1].bosses[2].localName, "Magmadar", "a journal entry of another encounter is not used")
		eq(p.instances[2].localName, "Onyxia\226\128\153s Lair")
	end)
end)
