-- Import, backup and end-of-season compaction (M6-7, docs/ANALISI.md §7, §8.3, §11): the configuration string, the full
-- backup and its restore (a merge, audited), the archive of a season and its compaction (every total, the attendance and
-- the audit stay), the tombstones in the officers' sync, and the History › Backup pane.
local function Lg() return FDCP.Ledger end
local function B() return FDCP.Backup end
local function BS() return FDCP.BackupService end
local function Sn() return FDCP.Season end
local function N() return FDCP.Nights end
local function R() return FDCP.Roster end
local function Ru() return FDCP.Rules end
local function NC() return FDCP.NightController end

local GM, OFFICER = "Testchar-TestRealm", "Bryn-TestRealm"
local PACK = { { id = 531, size = 10 } }
local TANK, HEALER, DPS = 73, 257, 72

local function copy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = copy(x) end
	return c
end

local function count(L, t)
	local n = 0
	for _, e in pairs(L.events) do if t == nil or e.type == t then n = n + 1 end end
	return n
end

-- A season of the ten-player raid: 12 members, `nights` nights with a lineup (10 play, 2 sit out, the bench turns), three
-- kills each followed by a swap (four lineup events a night, as the group changes during a real night), an award each, a void
-- and a manual adjustment, the bench effect "bonus" in the rules; closed when `close`.
local function season(nights, close)
	local L = Lg().New()
	local ts = 1
	local function t() ts = ts + 1; return ts end
	assert(Sn().Open(L, { author = GM, ts = t(), season = "S1", label = "Tier 1", instances = PACK }))
	local rules = Ru().Current(L)
	rules.bench.creditEffect, rules.bench.creditAmount = "bonus", 1
	assert(Ru().Change(L, { author = GM, ts = t(), rules = rules, confirmed = true }))
	local names = {}
	for i = 1, 12 do
		local spec = i <= 2 and TANK or i <= 5 and HEALER or DPS
		names[i] = ("Member%02d-TestRealm"):format(i)
		assert(R().Join(L, { author = OFFICER, ts = t(), season = "S1", member = names[i], faction = "Horde", ms1 = spec }))
	end
	local awards = {}
	for n = 1, nights do
		assert(N().Open(L, { author = OFFICER, ts = t(), season = "S1", date = ("2026-10-%02d"):format(n), instanceID = 531,
			difficulty = "normal", faction = "Horde" }))
		local raid, bench = {}, {}
		for i = 1, 12 do
			local out = (i + n) % 6 == 0
			if out then bench[#bench + 1] = names[i] elseif #raid < 10 then raid[#raid + 1] = names[i] end
		end
		assert(N().SetLineup(L, { author = OFFICER, ts = t(), season = "S1", raid = raid, bench = bench }))
		local inRaid, onBench = raid[#raid], bench[1]
		for k = 1, 3 do
			assert(N().Kill(L, { author = OFFICER, ts = t(), season = "S1", encounterID = 700 + n * 10 + k, difficulty = 14 }))
			-- one swap after each kill
			assert(N().SetLineup(L, { author = OFFICER, ts = t(), season = "S1", raid = { onBench }, bench = { inRaid } }))
			inRaid, onBench = onBench, inRaid
		end
		local e = assert(Lg().Append(L, { author = OFFICER, ts = t(), season = "S1", type = "ITEM_AWARDED",
			payload = { member = raid[(n % #raid) + 1], item = 19000 + n, cost = 1 + (n % 2) * 0.5, response = "MS" } }))
		awards[#awards + 1] = e
		assert(N().Close(L, { author = OFFICER, ts = t(), season = "S1" }))
	end
	assert(Lg().Append(L, { author = GM, ts = t(), season = "S1", type = "AWARD_VOIDED",
		payload = { ref = awards[1].id, reason = "WRONG_ITEM" } }))
	assert(Lg().Append(L, { author = GM, ts = t(), season = "S1", type = "CREDITS_ADJUSTED",
		payload = { member = names[3], delta = 2, reason = "CORRECTION" } }))
	if close then assert(Sn().Close(L, { author = GM, ts = t(), season = "S1" })) end
	return L, names, t
end

-- What a compaction must keep: the credits (with and without the bench effect), the attendance, the audit.
local function totals(L)
	local att = N().Attendance(L, "S1")
	local nights = {}
	for _, rec in ipairs(att.nights) do nights[#nights + 1] = { id = rec.night.id, played = rec.played, benched = rec.benched } end
	local audit = {}
	for _, a in ipairs(FDCP.History.Audit(L, "S1")) do
		if a.kind ~= "COMPACTED" then audit[#audit + 1] = { kind = a.kind, id = a.id } end
	end
	return { credits = Lg().Credits(L, "S1"), full = Lg().Credits(L, "S1", { full = true }), queue = FDCP.Rotation.Credits(L, "S1"),
		members = att.members, nights = nights, audit = audit, played = N().Played(L, "S1"),
		bench = FDCP.Rotation.Counts(L, "S1") }
end

describe("the full backup", function()
	it("restored into an empty ledger gives the same ledger", function()
		local L = season(4, true)
		local text = assert(BS().Encode(B().Full(L, { ts = 99, by = GM })))
		truthy(text:find("^!FDCP:BAK:1:"))
		local data = assert(BS().Decode(text))
		local L2 = Lg().New()
		local report = assert(B().Restore(L2, data))
		eq(report.added, count(L))
		deepEq(L2.events, L.events)
		deepEq(L2.heads, L.heads)
		deepEq(Lg().Credits(L2, "S1"), Lg().Credits(L, "S1"))
	end)

	it("is a merge: twice changes nothing, an older backup removes nothing, a changed event is not overwritten", function()
		local L, names, t = season(2, false)
		local old = B().Full(L)
		assert(Lg().Append(L, { author = GM, ts = t(), season = "S1", type = "CREDITS_ADJUSTED",
			payload = { member = names[1], delta = -1, reason = "CORRECTION" } }))
		local n = count(L)
		local r = assert(B().Restore(L, old))
		eq(r.added, 0); eq(count(L), n, "nothing removed")
		local forged = copy(old)
		forged.events[#forged.events].payload = { member = names[2], delta = 9, reason = "CORRECTION" }
		forged.events[#forged.events].type = "CREDITS_ADJUSTED"
		local r2 = assert(B().Restore(L, forged))
		eq(r2.added, 0); eq(#r2.conflict, 1, "the stored event wins")
	end)

	it("a damaged or foreign string is refused with a reason", function()
		local L = season(1, false)
		local text = BS().Encode(B().Full(L))
		local _, why = BS().Decode("hello"); eq(why, "FORMAT")
		_, why = BS().Decode(""); eq(why, "EMPTY")
		_, why = BS().Decode(text, { CFG = true }); eq(why, "KIND")
		_, why = BS().Decode((text:gsub("^!FDCP:BAK:1:", "!FDCP:BAK:9:"))); eq(why, "NEWER")
		_, why = BS().Decode(text:sub(1, 40) .. "AAAA" .. text:sub(45)); truthy(why == "DECODE" or why:find("^INVALID"), why)
		local spaced = text:sub(1, 30) .. "\n  " .. text:sub(31)
		truthy(BS().Decode(spaced), "a wrapped string still reads")
	end)
end)

describe("the end-of-season compaction", function()
	it("keeps every total, the attendance and the audit of the season, and shrinks the saved data", function()
		local L = season(6, true)
		local before = totals(L)
		local lineups, n, seen = count(L, "LINEUP_CHANGED"), count(L), Lg().Seen(L)
		local size = B().Size(L).bytes
		eq(lineups, 24)
		local e, removed = assert(B().Compact(L, { author = GM, ts = 10000, season = "S1" }))
		eq(removed, 24)
		eq(e.type, "LEDGER_COMPACTED")
		eq(count(L, "LINEUP_CHANGED"), 0)
		eq(count(L), n + 1 - 24)
		eq(Lg().Seen(L), seen + 1, "the compacted events still count")
		eq(Lg().GoneCount(L), 24)
		truthy(B().Size(L).bytes < size, ("smaller: %d -> %d"):format(size, B().Size(L).bytes))
		local after = totals(L)
		deepEq(after.credits, before.credits)
		deepEq(after.full, before.full)
		deepEq(after.queue, before.queue, "the bench effect reads the kept attendance")
		deepEq(after.members, before.members)
		deepEq(after.nights, before.nights)
		deepEq(after.played, before.played)
		deepEq(after.bench, before.bench)
		deepEq(after.audit, before.audit)
		local audit = FDCP.History.Audit(L, "S1")
		local found
		for _, a in ipairs(audit) do if a.kind == "COMPACTED" then found = a end end
		truthy(found); eq(found.removed, 24); eq(found.author, GM)
		-- a night's lineup is the summary: who played and who sat out
		local night = N().List(L, "S1")[2]
		local lists = N().Lists(N().Lineup(L, night.id))
		local rec = N().Attendance(L, "S1", { night = night.id }).nights[1]
		local played = {}
		for name in pairs(rec.played) do played[#played + 1] = name end
		table.sort(played)
		deepEq(lists.raid, played)
		-- a snapshot taken after the compaction gives the same credits
		Lg().TakeSnapshot(L, 10001)
		deepEq(Lg().Credits(L, "S1"), before.credits)
	end)

	it("refuses an open season, a second time and a season with nothing to compact", function()
		local L = season(2, false)
		local e, why = B().Compact(L, { author = GM, ts = 9000, season = "S1" })
		isNil(e); eq(why, "SEASON_OPEN")
		_, why = B().Compact(L, { author = GM, ts = 9000, season = "S9" }); eq(why, "SEASON_UNKNOWN")
		assert(Sn().Close(L, { author = GM, ts = 9001, season = "S1" }))
		assert(B().Compact(L, { author = GM, ts = 9002, season = "S1" }))
		_, why = B().Compact(L, { author = GM, ts = 9003, season = "S1" }); eq(why, "ALREADY_COMPACTED")
		local L2 = Lg().New()
		assert(Sn().Open(L2, { author = GM, ts = 1, season = "S1", instances = PACK }))
		assert(Sn().Close(L2, { author = GM, ts = 2, season = "S1" }))
		_, why = B().Compact(L2, { author = GM, ts = 3, season = "S1" }); eq(why, "NOTHING_TO_COMPACT")
	end)

	it("a compacted event never comes back: merges and new writes are dropped as tombstones", function()
		local L = season(3, true)
		local peer = copy(L)
		assert(B().Compact(L, { author = GM, ts = 9000, season = "S1" }))
		local r = assert(Lg().Merge(L, Lg().Sorted(peer)))
		eq(r.added, 0); eq(r.compacted, 12, "dropped as tombstones"); eq(count(L, "LINEUP_CHANGED"), 0)
		-- a peer still holding the lineups takes the compaction and compacts too: the two converge
		local r2 = assert(Lg().Merge(peer, Lg().Since(L, Lg().Heads(peer))))
		eq(r2.added, 1)
		eq(count(peer, "LINEUP_CHANGED"), 0)
		deepEq(peer.events, L.events)
		deepEq(peer.heads, L.heads)
		deepEq(peer.gone, L.gone)
		-- a lineup of the compacted season cannot be written again
		local _, why = Lg().Append(L, { author = OFFICER, ts = 9999, season = "S1", type = "LINEUP_CHANGED",
			payload = { night = N().List(L, "S1")[1].id, raid = { "Member01-TestRealm" } } })
		eq(why, "SEASON_COMPACTED")
	end)

	it("a ledger behind takes the tombstones of the seqs it lacks and its heads catch up", function()
		local L = season(3, true)
		assert(B().Compact(L, { author = GM, ts = 9000, season = "S1" }))
		local late = Lg().New()
		assert(Lg().Merge(late, Lg().Sorted(L)))
		truthy((late.heads[OFFICER] or 0) < L.heads[OFFICER], "the compacted seqs are holes")
		for author, top in pairs(L.heads) do
			for _, g in ipairs(Lg().GoneRanges(L, author, 1, top)) do Lg().MarkGone(late, author, g[1], g[2], g[3]) end
		end
		deepEq(late.heads, L.heads)
		deepEq(late.gone, L.gone)
		-- a tombstone for a season that is not compacted here, or for a present event, changes nothing
		eq(Lg().MarkGone(late, OFFICER, 1, 1, "S1"), 0)
		eq(Lg().MarkGone(Lg().New(), OFFICER, 1, 3, "S1"), 0)
	end)

	it("the archive keeps every event of the season, and a backup after the compaction keeps the tombstones", function()
		local L = season(3, true)
		local arc = assert(B().Archive(L, "S1", { ts = 5, by = GM }))
		local lineups = 0
		for _, e in ipairs(arc.events) do if e.type == "LINEUP_CHANGED" then lineups = lineups + 1 end end
		eq(lineups, 12)
		local text = assert(BS().Encode(arc))
		truthy(text:find("^!FDCP:ARC:1:"))
		assert(B().Compact(L, { author = GM, ts = 9000, season = "S1" }))
		local data = assert(BS().Decode(BS().Encode(B().Full(L))))
		local L2 = Lg().New()
		assert(B().Restore(L2, data))
		deepEq(L2.events, L.events)
		deepEq(L2.heads, L.heads)
		deepEq(L2.gone, L.gone)
		-- the archive restored into an empty ledger brings the season back whole
		local L3 = Lg().New()
		assert(B().Restore(L3, assert(BS().Decode(text))))
		eq(count(L3, "LINEUP_CHANGED"), 12)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The service and the pane, on the mock client

local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider" }
local function guild(myRank)
	return function(Mock)
		Mock.guild.Set({ name = "Keepers", ranks = RANKS, myRank = myRank, members = {
			{ name = "Bryn", rank = 1 }, { name = "Corin", rank = 3 },
		} })
	end
end

local function bound(L)
	NC():Bind(L)
	Mock.Advance(3)
	return L
end

local function click(b) b:GetScript("OnClick")(b) end

describe("the configuration string", function()
	before_boot(guild(0))

	it("goes to another guild without the guild's own values, and the Guild Master imports it with a confirmation", function()
		local L = season(1, false)
		local rules = Ru().Current(L)
		rules.cost.multipliers = rules.cost.multipliers or {}
		rules.session.rollSeconds = 45
		rules.council.members = { "Bryn-TestRealm" }
		rules.site.factionName = "Keepers"
		assert(Ru().Change(L, { author = GM, ts = 500, rules = rules, confirmed = true }))
		local text = assert(BS().Encode(B().Config(L)))
		truthy(text:find("^!FDCP:CFG:1:"))
		local shared = assert(BS().Decode(text))
		deepEq(shared.rules.council.members, {}, "the names stay home")
		eq(shared.rules.site.factionName, Ru().DefaultConfig().site.factionName)
		-- another guild, with its own council and site name
		local other = bound(Lg().New())
		local mine = Ru().DefaultConfig()
		mine.council.members = { "Corin-TestRealm" }
		mine.site.factionName = "Others"
		assert(Ru().Change(other, { author = GM, ts = 1, rules = mine }))
		local preview = assert(BS():PreviewConfig(text))
		truthy(#preview.changes > 0)
		local e, why = BS():ImportConfig(text)
		isNil(e); eq(why, "CONFIRM_REQUIRED")
		e = assert(BS():ImportConfig(text, { confirmed = true }))
		eq(e.type, "CONFIG_CHANGED"); eq(e.author, GM)
		local now = Ru().Current(other)
		eq(now.session.rollSeconds, 45)
		deepEq(now.council.members, { "Corin-TestRealm" }, "the importing guild keeps its council")
		eq(now.site.factionName, "Others")
		_, why = BS():ImportConfig(text, { confirmed = true }); eq(why, "UNCHANGED")
		_, why = BS():ImportConfig("!FDCP:CFG:1:@@@", { confirmed = true }); eq(why, "FORMAT")
	end)
end)

describe("the configuration string for an officer", function()
	before_boot(guild(1))

	it("is exported by anybody but a config import by anyone but the Guild Master is refused", function()
		local L = bound(season(1, false))
		local text = assert(BS():ExportConfig())
		local n = count(L)
		local e, why = BS():ImportConfig(text, { confirmed = true })
		isNil(e); eq(why, "NOT_GM")
		eq(count(L), n, "nothing written")
		-- a CONFIG_CHANGED forged by an officer is refused by the gate too
		local rules = Ru().Current(L); rules.session.rollSeconds = 50
		local _, why2 = Ru().Change(L, { author = NC():Me(), ts = 9, rules = rules, confirmed = true }, FDCP.PermissionService:Gate())
		eq(why2, "NOT_GM")
		-- an officer makes backups and archives, but restores and compacts nothing
		truthy(BS():BackupText())
		local _, w3 = BS():Restore(BS():BackupText(), { confirmed = true }); eq(w3, "RANK_TOO_LOW")
		local _, w4 = BS():Compact("S1", { confirmed = true, confirmedAgain = true }); eq(w4, "RANK_TOO_LOW")
	end)
end)

describe("restore and compaction from the service", function()
	before_boot(guild(0))

	it("a restore needs a confirmation, adds what is missing and is written in the audit", function()
		local src = season(2, true)
		local text = assert(BS().Encode(B().Full(src, { by = GM })))
		local L = bound(Lg().New())
		local preview = assert(BS():PreviewRestore(text))
		eq(preview.events, count(src)); eq(preview.new, count(src))
		local r, why = BS():Restore(text)
		isNil(r); eq(why, "CONFIRM_REQUIRED")
		eq(count(L), 0)
		r = assert(BS():Restore(text, { confirmed = true }))
		eq(r.added, count(src))
		eq(count(L, "LEDGER_RESTORED"), 1)
		deepEq(Lg().Credits(L, "S1"), Lg().Credits(src, "S1"))
		local found
		for _, a in ipairs(FDCP.History.Audit(L, "S1")) do if a.kind == "RESTORED" then found = a end end
		truthy(found); eq(found.added, count(src)); eq(found.author, NC():Me())
		eq(FDCP.AuditWindow.Line(found), "Testchar: restored a backup (" .. count(src) .. " events added)")
	end)

	it("a compaction needs the archive first and two confirmations", function()
		local L = bound(season(3, true))
		local _, why = BS():Compact("S1", { confirmed = true, confirmedAgain = true })
		eq(why, "ARCHIVE_FIRST")
		assert(BS():ArchiveText("S1"))
		_, why = BS():Compact("S1", { confirmed = true }); eq(why, "CONFIRM_REQUIRED")
		eq(count(L, "LINEUP_CHANGED"), 12)
		eq(assert(BS():Compact("S1", { confirmed = true, confirmedAgain = true })), 12)
		eq(count(L, "LINEUP_CHANGED"), 0)
		eq(count(L, "LEDGER_COMPACTED"), 1)
		local lines = BS():SizeLines()
		truthy(lines[1]:find("compacted 12 %(seasons: S1%)"), lines[1])
		truthy(table.concat(FDCP:DebugSectionLines(), "\n"):find("Ledger size:"), "in /fdcp debug")
	end)

	it("the Backup pane: generate, import, restore and compact, each asking first", function()
		local L = bound(season(2, true))
		Mock.Slash("/fdcp")
		FDCP.MainWindow:SelectTab("history")
		FDCP.HistoryWindow:ShowSub("backup")
		local W = FDCP.BackupWindow
		W:SetMode("config")
		truthy(W.apply:IsShown(), "the Guild Master imports")
		click(W.generate)
		truthy(W.edit:GetText():find("^!FDCP:CFG:1:"))
		click(W.apply)
		eq(W.message:GetText(), "These settings are already the guild's: nothing to import.")
		W.edit:SetText("nonsense")
		click(W.apply)
		eq(W.message:GetText(), "This is not an FDCP string.")
		-- archive and compact
		W:SetMode("archive")
		truthy(W.compact:IsShown())
		W.seasons:Select("S1")
		click(W.compact)
		eq(W.message:GetText(), "Generate the season's archive and save it first.")
		click(W.generate)
		truthy(W.edit:GetText():find("^!FDCP:ARC:1:"))
		click(W.compact)
		truthy(W.dialog:IsShown())
		click(W.dialog.confirm)
		eq(W.dialog.title:GetText(), "Last check")
		eq(count(L, "LEDGER_COMPACTED"), 0, "nothing before the second confirmation")
		click(W.dialog.cancel)
		eq(count(L, "LEDGER_COMPACTED"), 0)
		click(W.compact); click(W.dialog.confirm); click(W.dialog.confirm)
		eq(count(L, "LEDGER_COMPACTED"), 1)
		eq(W.message:GetText(), "Season Tier 1 compacted: 8 events removed.")
		-- backup and restore
		W:SetMode("backup")
		click(W.generate)
		local text = W.edit:GetText()
		truthy(text:find("^!FDCP:BAK:1:"))
		click(W.apply)
		truthy(W.dialog:IsShown())
		eq(count(L, "LEDGER_RESTORED"), 0)
		click(W.dialog.confirm)
		eq(count(L, "LEDGER_RESTORED"), 1)
		eq(W.message:GetText(), "Restored: 0 events added (0 not accepted or waiting).")
	end)
end)

describe("the Backup pane for a member", function()
	before_boot(guild(3))

	it("shows the settings string only, without any button that writes", function()
		bound(season(1, true))
		Mock.Slash("/fdcp")
		FDCP.MainWindow:SelectTab("history")
		FDCP.HistoryWindow:ShowSub("backup")
		local W = FDCP.BackupWindow
		W:SetMode("config")
		falsy(W.apply:IsShown())
		click(W.generate)
		truthy(W.edit:GetText():find("^!FDCP:CFG:1:"))
		W:SetMode("backup")
		falsy(W.apply:IsShown()); falsy(W.generate:IsShown())
		local _, why = BS():BackupText(); eq(why, "RANK_TOO_LOW")
		W:SetMode("archive")
		falsy(W.compact:IsShown())
	end)
end)
