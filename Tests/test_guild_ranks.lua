-- Guild ranks and the permission service (M3-1, docs/ANALISI.md §3.9): Adapters/GuildRanks.lua reads the roster through
-- Compat, App/PermissionService.lua keeps the rank history and gates the ledger with it. The mock roster loads
-- asynchronously (Mock.guild.Set{loading = true} ... Mock.guild.Deliver()), as at login in the client.
local function GR() return FDCP.GuildRanks end
local function PS() return FDCP.PermissionService end
local function P() return FDCP.Permissions end
local function Lg() return FDCP.Ledger end

local ME, GM, OFFICER, RAIDER, OUTSIDER = "Testchar-TestRealm", "Aurel-TestRealm", "Bryn-TestRealm", "Corin-TestRealm",
	"Dara-TestRealm"
local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }

-- Aurel GM (an officer when the player is the GM), Bryn officer, Corin raider; the player's rank is `myRank` (default:
-- officer).
local function guild(myRank, extra)
	return function(M)
		local cfg = { name = "Keepers", ranks = RANKS, myRank = myRank or 1, members = {
			{ name = "Aurel", rank = myRank == 0 and 1 or 0 }, { name = "Bryn", rank = 1 }, { name = "Corin", rank = 3 },
		} }
		for k, v in pairs(extra or {}) do cfg[k] = v end
		M.guild.Set(cfg)
	end
end

local function settle() Mock.Advance(2) end   -- the roster request, its answer and the debounced scan

local function now() return GetServerTime() end

local seqs = {}
local function event(author, ts, typ, payload, season)
	seqs[author] = (seqs[author] or 0) + 1
	local seq = seqs[author]
	return { id = author .. ":" .. seq, author = author, seq = seq, ts = ts, type = typ, v = 1, payload = payload or {},
		season = season }
end
local function award(author, ts)
	return event(author, ts, "ITEM_AWARDED", { member = "Corin", item = 19019, cost = 1 }, "S1")
end
local function permissions(author, ts, change)
	local t = P().DefaultTable()
	for k, v in pairs(change or { ["view.attendance"] = 2 }) do t[k] = v end
	return event(author, ts, "PERMISSIONS_CHANGED", { table = t })
end

local function refusedCodes(list)
	local out = {}
	for _, r in ipairs(list) do out[#out + 1] = r.id .. "=" .. r.code end
	table.sort(out)
	return out
end

local function listen(name)
	local seen = {}
	FDCP.Bus:On(name, function(_, ...) seen[#seen + 1] = { ... } end)
	return seen
end

local function output() return table.concat(Mock.PlainOutput(), "\n") end

describe("the adapter", function()
	before_boot(guild(1))

	it("reads the player's rank, the GM, members' ranks and the rank names through Compat", function()
		falsy(GR().SelfIsGM())
		eq(GR().SelfRank(), 1)
		truthy(GR().SelfIsOfficer())
		eq(GR().RankOf("Corin"), 3)
		eq(GR().RankOf("Aurel-TestRealm"), 0)
		isNil(GR().RankOf("Nobody"))
		eq(GR().NumRanks(), 5)
		eq(GR().RankName(1), "Officer")
		deepEq(GR().RankNames(), { "Guild Master", "Officer", "Veteran", "Raider", "Initiate" })
		eq(GR().Me(), ME)
	end)

	it("writes names as Name-Realm with the realm normalized", function()
		eq(GR().FullName("Corin"), "Corin-TestRealm")
		eq(GR().FullName("Corin-Argent Dawn"), "Corin-ArgentDawn")
		eq(GR().FullName("Corin-Quel'Thalas"), "Corin-QuelThalas")
		isNil(GR().FullName("")); isNil(GR().FullName(nil)); isNil(GR().FullName(7))
	end)

	it("a scan gives every member's rank, the GM and the rank names", function()
		local s = GR().Scan()
		eq(s.me, ME); eq(s.myRank, 1); eq(s.gm, GM); truthy(s.complete)
		deepEq(s.members, { [ME] = 1, [GM] = 0, [OFFICER] = 1, [RAIDER] = 3 })
		eq(#s.ranks, 5)
	end)

	it("the GM and a plain member as the game shows them", function()
		Mock.guild.SetMyRank(0)
		truthy(GR().SelfIsGM()); truthy(GR().SelfIsOfficer())
		Mock.guild.SetMyRank(3)
		falsy(GR().SelfIsGM()); falsy(GR().SelfIsOfficer())
	end)

	it("one scan for a burst of roster events", function()
		settle()
		local scans = listen("GUILD_ROSTER_SCANNED")
		for _ = 1, 10 do Mock.Fire("GUILD_ROSTER_UPDATE", false) end
		Mock.Fire("GUILD_RANKS_UPDATE")
		eq(#scans, 0, "debounced")
		settle()
		eq(#scans, 1)
	end)

	it("without a guild there is nothing to scan", function()
		Mock.guild.Leave()
		isNil(GR().Scan())
		falsy(GR().SelfIsGM())
		isNil(GR().SelfRank())
	end)
end)

describe("the roster loads asynchronously", function()
	before_boot(guild(1, { loading = true }))

	it("asks again until the roster comes, then stops", function()
		local asked = 0
		local real = C_GuildInfo.GuildRoster
		C_GuildInfo.GuildRoster = function() asked = asked + 1; return real() end
		Mock.Advance(46)
		eq(asked, 3, "every 15 seconds")
		isNil(GR().Scan())
		falsy(PS():IsReady())
		Mock.guild.Deliver()
		settle()
		truthy(PS():IsReady())
		local before = asked
		Mock.Advance(60)
		eq(asked, before, "no more requests")
	end)

	it("events wait in the queue and are accepted or refused once the roster arrives", function()
		local L = Lg().New()
		local t = now() - 3600
		local ok1, low, out, cfgOfficer, cfgGM = award(OFFICER, t), award(RAIDER, t + 1), award(OUTSIDER, t + 2),
			permissions(OFFICER, t + 3), permissions(GM, t + 4)
		local report = PS():Merge(L, { ok1, low, out, cfgOfficer, cfgGM })
		eq(report.added, 0)
		eq(#report.pending, 5)
		eq(PS():QueueSize(), 5)
		-- the same events again (a resend) are not queued twice
		PS():Merge(L, { ok1, low })
		eq(PS():QueueSize(), 5)
		local ok, code = PS():Can("night.run")
		falsy(ok); eq(code, "PENDING")
		eq(Lg().Count(L), 0)

		local drained = listen("PERMISSIONS_QUEUE_DRAINED")
		local ready = listen("GUILD_RANKS_READY")
		Mock.guild.Deliver()
		settle()
		eq(#ready, 1); eq(ready[1][1], 1, "the player's rank")
		eq(#drained, 1)
		eq(drained[1][1].added, 2)
		deepEq(refusedCodes(drained[1][1].refused), {
			cfgOfficer.id .. "=NOT_GM", low.id .. "=RANK_TOO_LOW", out.id .. "=NOT_IN_GUILD" })
		eq(PS():QueueSize(), 0)
		notNil(Lg().Get(L, ok1.id)); notNil(Lg().Get(L, cfgGM.id))
		isNil(Lg().Get(L, low.id))
		truthy(PS():Can("night.run"))
	end)

	it("after the roster, merges are decided at once", function()
		Mock.guild.Deliver()
		settle()
		local L = Lg().New()
		local report = PS():Merge(L, { award(OFFICER, now()), award(RAIDER, now()) })
		eq(report.added, 1); eq(#report.pending, 0); eq(#report.refused, 1)
		eq(PS():QueueSize(), 0)
	end)

	it("local writes get PENDING while loading", function()
		local L = Lg().New()
		local e, code = Lg().Append(L, { author = ME, ts = now(), type = "ITEM_AWARDED", season = "S1",
			payload = { member = "Corin", item = 19019, cost = 1 } }, PS():Gate())
		isNil(e); eq(code, "PENDING")
	end)

	it("the queue is bounded", function()
		PS().MAX_QUEUE = 3
		local L = Lg().New()
		PS():Merge(L, { award(OFFICER, 1), award(OFFICER, 2), award(OFFICER, 3), award(OFFICER, 4) })
		eq(PS():QueueSize(), 3)
		PS().MAX_QUEUE = 2000
	end)
end)

describe("the Guild Master", function()
	before_boot(guild(1))

	it("only rank index 0 may change the configuration", function()
		settle()
		local ok, code = PS():CanConfigure()
		falsy(ok); eq(code, "NOT_GM")
		truthy(PS():CanConfigure(GM))
		local L = Lg().New()
		local e, why = P().Change(L, { author = ME, ts = now(), table = { ["view.attendance"] = 2 } }, PS():Gate())
		isNil(e); eq(why, "NOT_GM")
		truthy(P().Change(L, { author = GM, ts = now(), table = { ["view.attendance"] = 2 } }, PS():Gate()))
	end)

	it("a GM change hands the config power to the new GM; the old GM's earlier changes stay valid", function()
		settle()
		local changes = listen("GUILD_LEADER_CHANGED")
		local before = now()
		Mock.Advance(60)
		Mock.ClearOutput()
		Mock.guild.SetLeader("Testchar")
		settle()
		eq(#changes, 1)
		deepEq(changes[1], { GM, ME })
		contains(output(), "You are now the Guild Master")
		truthy(PS():CanConfigure())
		falsy(PS():CanConfigure(GM))
		eq(PS():RankAt(GM), 1)

		local after = now() + 10
		local L = Lg().New()
		local oldGM, oldGMLate, newGMEarly, newGM = permissions(GM, before, { ["view.attendance"] = 2 }),
			permissions(GM, after, { ["view.attendance"] = 3 }), permissions(ME, before, { ["view.attendance"] = 4 }),
			permissions(ME, after + 1, { ["export.public"] = 2 })
		local report = PS():Merge(L, { oldGM, oldGMLate, newGMEarly, newGM })
		eq(report.added, 2)
		deepEq(refusedCodes(report.refused), { oldGMLate.id .. "=NOT_GM", newGMEarly.id .. "=NOT_GM" })
		notNil(Lg().Get(L, oldGM.id)); notNil(Lg().Get(L, newGM.id))
	end)

	it("the old GM is told the power has passed", function()
		T.boot(function(M) guild(0)(M) end)
		settle()
		truthy(PS():CanConfigure())
		Mock.ClearOutput()
		Mock.guild.SetLeader("Aurel")
		settle()
		contains(output(), "no longer the Guild Master")
		falsy(PS():CanConfigure())
	end)
end)

describe("rank history", function()
	before_boot(guild(1))

	it("a promotion counts from the moment the roster shows it", function()
		settle()
		local before = now()
		Mock.Advance(60)
		Mock.guild.SetRank("Corin", 1)
		settle()
		local L = Lg().New()
		local early, late = award(RAIDER, before), award(RAIDER, now() + 5)
		local report = PS():Merge(L, { early, late })
		deepEq(refusedCodes(report.refused), { early.id .. "=RANK_TOO_LOW" })
		notNil(Lg().Get(L, late.id))
	end)

	it("a member who left: earlier events stay valid, later ones are refused", function()
		settle()
		local before = now()
		Mock.Advance(60)
		Mock.guild.Remove("Bryn")
		settle()
		eq(PS():RankAt(OFFICER), false)
		local L = Lg().New()
		local early, late = award(OFFICER, before), award(OFFICER, now() + 5)
		local report = PS():Merge(L, { early, late })
		deepEq(refusedCodes(report.refused), { late.id .. "=NOT_IN_GUILD" })
	end)

	it("is saved per guild and waits for this session's roster after a reload", function()
		settle()
		Mock.Advance(60)
		Mock.guild.SetRank("Corin", 2)
		settle()
		Mock.Reload()
		falsy(PS():IsReady(), "not loaded before this session's roster")
		local h = PS():History()
		eq(#h.members[RAIDER], 2, "the promotion was saved")
		settle()
		truthy(PS():IsReady())
		eq(PS():RankAt(RAIDER), 2)
		local saved = FDCP.Config:GuildData().ranks
		eq(saved.leader, GM)
		eq(#saved.rankNames, 5)
	end)

	it("leaving the guild rebinds to an empty, unloaded history", function()
		settle()
		truthy(PS():IsReady())
		Mock.guild.Leave()
		settle()
		falsy(PS():IsReady())
		local ok, code = PS():Can("night.run")
		falsy(ok); eq(code, "PENDING")
	end)
end)

describe("rank reorder and deletion", function()
	before_boot(guild(0))

	it("a reorder is reported to the GM and kept for review", function()
		settle()
		local changed = listen("GUILD_RANKS_CHANGED")
		Mock.ClearOutput()
		Mock.guild.SetRankNames({ [0] = "Guild Master", "Veteran", "Officer", "Raider", "Initiate" }, { [1] = 2, [2] = 1 })
		settle()
		eq(#changed, 1); eq(changed[1][1], "REORDERED")
		contains(output(), "reordered")
		eq(PS():RankReview().code, "REORDERED")
		eq(PS():RankAt(OFFICER), 2, "members followed their rank")
		PS():AcknowledgeRanks()
		isNil(PS():RankReview())
	end)

	it("a rename changes nothing", function()
		settle()
		local changed = listen("GUILD_RANKS_CHANGED")
		Mock.guild.SetRankNames({ [0] = "Guild Master", "Captain", "Veteran", "Raider", "Initiate" })
		settle()
		eq(#changed, 0)
		isNil(PS():RankReview())
	end)

	it("a deletion lists the permissions that point to a rank that is gone", function()
		settle()
		local L = Lg().New()
		truthy(P().Change(L, { author = ME, ts = now(), table = { ["view.attendance"] = 3, ["export.public"] = 4 } },
			PS():Gate()))
		PS():BindLedger(L)
		local changed = listen("GUILD_RANKS_CHANGED")
		Mock.ClearOutput()
		Mock.guild.SetRankNames({ [0] = "Guild Master", "Officer", "Veteran" }, { [3] = 2, [4] = 2 })
		settle()
		eq(changed[1][1], "REMOVED")
		deepEq(changed[1][2], { "export.public", "view.attendance" })
		contains(output(), "export.public, view.attendance")
		PS():BindLedger(nil)
	end)

	it("an officer is not told, the GM is told at the next login", function()
		T.boot(function(M) guild(1)(M) end)
		settle()
		Mock.ClearOutput()
		Mock.guild.SetRankNames({ [0] = "Guild Master", "Officer", "Veteran", "Raider" }, { [4] = 3 })
		settle()
		eq(PS():RankReview().code, "REMOVED")
		eq(output(), "", "the officer sees nothing")
		Mock.guild.SetLeader("Testchar")
		Mock.Reload()
		Mock.ClearOutput()
		settle()
		contains(output(), "removed")
	end)
end)

describe("debug output", function()
	before_boot(guild(1))

	it("shows the roster state and the queue, no names", function()
		local lines = table.concat(FDCP:DebugSectionLines(), "\n")
		contains(lines, "Permissions: roster loading")
		settle()
		lines = table.concat(FDCP:DebugSectionLines(), "\n")
		contains(lines, "Permissions: roster loaded, rank 1, queue 0")
		falsy(lines:find("Testchar", 1, true))
	end)
end)
