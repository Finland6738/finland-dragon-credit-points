-- Permissions (M2-5): permission -> lowest rank index (docs/ANALISI.md §3.9), config.rules and config.permissions fixed
-- at the Guild Master, the table as PERMISSIONS_CHANGED events, and the trust gate of the ledger: an event is accepted
-- only if its author had the required rank when it was written, a config event only from the GM; ranks are indexes,
-- so renaming a rank changes nothing. Pure domain code: the rank history stands in for the guild roster.
local function Lg() return FDCP.Ledger end
local function P() return FDCP.Permissions end

local GM, OFFICER, RAIDER, OUTSIDER = "Aurel-Camelot", "Bryn-Camelot", "Corin-Camelot", "Dara-Camelot"
local PACK = { { id = 409, size = 40 } }

-- A loaded roster: Aurel GM, Bryn officer (1), Corin raider (3), all seen at ts 0.
local function roster()
	local h = P().NewHistory()
	P().RecordRank(h, GM, 0, 0)
	P().RecordRank(h, OFFICER, 1, 0)
	P().RecordRank(h, RAIDER, 3, 0)
	h.loaded = true
	return h
end

local function event(author, seq, ts, typ, payload, season)
	return { id = author .. ":" .. seq, author = author, seq = seq, ts = ts, type = typ, v = 1,
		payload = payload or {}, season = season }
end

local function award(author, seq, ts)
	return event(author, seq, ts, "ITEM_AWARDED", { member = "Corin", item = 19000 + ts, cost = 1 }, "S1")
end

local function adjust(author, seq, ts)
	return event(author, seq, ts, "CREDITS_ADJUSTED", { member = "Corin", delta = -1, reason = "MANUAL_FIX" }, "S1")
end

local function codes(list)
	local out = {}
	for _, r in ipairs(list) do out[#out + 1] = r.id .. "=" .. r.code end
	table.sort(out)
	return out
end

local function shuffled(list, seed)
	local out, state = {}, seed
	for i, v in ipairs(list) do out[i] = v end
	for i = #out, 2, -1 do
		state = (state * 1103515245 + 12345) % 2147483648
		local j = (math.floor(state / 65536) % i) + 1
		out[i], out[j] = out[j], out[i]
	end
	return out
end

describe("the permission table", function()
	it("the preset of §3.9: GM only for config, seasons and credit corrections, officers for the rest", function()
		local t = P().DefaultTable()
		eq(#P().LIST, 12)
		for _, p in ipairs(P().LIST) do notNil(t[p]) end
		eq(t["config.rules"], 0); eq(t["config.permissions"], 0)
		eq(t["season.manage"], 0); eq(t["credits.adjust"], 0)
		for _, p in ipairs({ "night.run", "award.confirm", "council.member", "roster.manage", "export.public",
			"view.attendance", "raid.addonCheck", "progress.edit" }) do
			eq(t[p], P().OFFICER, p)
		end
		truthy(P().Validate(t))
	end)

	it("a lower rank index holds everything a higher one holds", function()
		truthy(P().Can(0, "config.rules")); truthy(P().Can(0, "night.run")); truthy(P().Can(0, "credits.adjust"))
		truthy(P().Can(1, "night.run")); falsy(P().Can(1, "credits.adjust")); falsy(P().Can(1, "season.manage"))
		falsy(P().Can(2, "night.run"))
		falsy(P().Can(1.5, "night.run")); falsy(P().Can(-1, "night.run")); falsy(P().Can(10, "night.run"))
		falsy(P().Can(0, "loot.everything"))
		local of = P().Of(1)
		truthy(of["night.run"]); isNil(of["config.rules"])
	end)

	it("the GM may lower credits.adjust to the officers, never the config permissions", function()
		local t = P().DefaultTable()
		t["credits.adjust"] = 1
		truthy(P().Can(1, "credits.adjust", t))
		t["config.rules"] = 1
		falsy(P().Can(1, "config.rules", t))   -- fixed: the table cannot lower it
		local ok, problems = P().Validate(t)
		falsy(ok); deepEq(problems, { "fixed:config.rules" })
	end)

	it("refuses unknown permissions and ranks that do not exist", function()
		local ok, problems = P().Validate({ ["night.run"] = 10, ["loot.all"] = 1, ["export.public"] = 1.5,
			["config.permissions"] = 2 })
		falsy(ok)
		deepEq(problems, { "export.public", "fixed:config.permissions", "night.run", "unknown:loot.all" })
		ok, problems = P().Validate("all")
		falsy(ok); deepEq(problems, { "table" })
		truthy(P().Validate({}))
	end)

	it("a partial table takes the preset for the rest", function()
		local t = P().Normalize({ ["export.public"] = 4, ["config.rules"] = 3, bogus = 1 })
		eq(t["export.public"], 4); eq(t["config.rules"], 0); eq(t["night.run"], 1); isNil(t.bogus)
	end)

	it("every ledger type needs a permission", function()
		for typ in pairs(Lg().TYPES) do
			truthy(P().IsPermission(P().EVENT_PERMISSION[typ]), typ)
		end
		eq(P().EVENT_PERMISSION.CONFIG_CHANGED, "config.rules")
		eq(P().EVENT_PERMISSION.PERMISSIONS_CHANGED, "config.permissions")
		eq(P().EVENT_PERMISSION.SEASON_OPENED, "season.manage")
		eq(P().EVENT_PERMISSION.ITEM_AWARDED, "night.run")
		eq(P().EVENT_PERMISSION.MEMBER_JOINED, "roster.manage")
	end)
end)

describe("the trust gate", function()
	it("refuses events from an author without the rank", function()
		local L = Lg().New()
		local gate = P().Gate(roster())
		local r = Lg().Merge(L, { award(OFFICER, 1, 10), award(RAIDER, 1, 11),
			event(OFFICER, 2, 12, "SEASON_OPENED", { instances = PACK, startCredits = 0 }, "S2"),
			adjust(OFFICER, 3, 13) }, gate)
		eq(r.added, 1)
		deepEq(codes(r.refused), { OFFICER .. ":2=RANK_TOO_LOW", OFFICER .. ":3=RANK_TOO_LOW",
			RAIDER .. ":1=RANK_TOO_LOW" })
		notNil(Lg().Get(L, OFFICER .. ":1")); isNil(Lg().Get(L, RAIDER .. ":1"))
		-- A refused event leaves a hole, so a later sync asks for it again.
		deepEq(Lg().Gaps(L), {})
		eq(Lg().Heads(L)[OFFICER], 1)
	end)

	it("Append refuses with the same codes", function()
		local L = Lg().New()
		local gate = P().Gate(roster())
		local e, code = Lg().Append(L, { author = RAIDER, ts = 1, season = "S1", type = "ITEM_AWARDED",
			payload = { member = "Corin", item = 19001, cost = 1 } }, gate)
		isNil(e); eq(code, "RANK_TOO_LOW")
		notNil(Lg().Append(L, { author = OFFICER, ts = 1, season = "S1", type = "ITEM_AWARDED",
			payload = { member = "Corin", item = 19001, cost = 1 } }, gate))
		eq(Lg().Count(L), 1)
	end)

	it("refuses a config event from anyone but the GM", function()
		local L = Lg().New()
		local gate = P().Gate(roster())
		local e, code = FDCP.Rules.Change(L, { author = OFFICER, ts = 1, rules = { session = { awardMode = "auto" } } }, gate)
		isNil(e); eq(code, "NOT_GM")
		e, code = P().Change(L, { author = OFFICER, ts = 1, table = { ["credits.adjust"] = 1 } }, gate)
		isNil(e); eq(code, "NOT_GM")
		local rules = FDCP.Rules.DefaultConfig()
		rules.cost.matrix.weapon[4] = 0
		local r = Lg().Merge(L, {
			event(OFFICER, 1, 2, "CONFIG_CHANGED", { rules = rules }),
			event(RAIDER, 1, 3, "PERMISSIONS_CHANGED", { table = { ["night.run"] = 3 } }),
		}, gate)
		eq(r.added, 0)
		deepEq(codes(r.refused), { OFFICER .. ":1=NOT_GM", RAIDER .. ":1=NOT_GM" })
		eq(FDCP.Rules.Current(L).cost.matrix.weapon[4], 2)
		notNil(FDCP.Rules.Change(L, { author = GM, ts = 4, rules = rules }, gate))
		notNil(P().Change(L, { author = GM, ts = 5, table = { ["credits.adjust"] = 1 } }, gate))
		eq(FDCP.Rules.Current(L).cost.matrix.weapon[4], 0)
	end)

	it("a table that tries to open the config to officers is not even valid", function()
		local L = Lg().New()
		local r = Lg().Merge(L, { event(GM, 1, 1, "PERMISSIONS_CHANGED", { table = { ["config.rules"] = 1 } }) },
			P().Gate(roster()))
		deepEq(r.invalid, { "payload:table" })
		local e, code = P().Change(L, { author = GM, ts = 1, table = { ["config.permissions"] = 1 } })
		isNil(e); eq(code, "TABLE:fixed:config.permissions")
	end)

	it("uses the rank the author had when the event was written", function()
		local h = roster()
		P().RecordRank(h, OFFICER, 3, 100)   -- demoted at 100
		P().RecordRank(h, RAIDER, 1, 100)    -- promoted at 100
		local L = Lg().New()
		local r = Lg().Merge(L, { award(OFFICER, 1, 50), award(OFFICER, 2, 150), award(RAIDER, 1, 50),
			award(RAIDER, 2, 150) }, P().Gate(h))
		eq(r.added, 2)
		deepEq(codes(r.refused), { OFFICER .. ":2=RANK_TOO_LOW", RAIDER .. ":1=RANK_TOO_LOW" })
	end)

	it("a GM change hands the config power over; the old GM's changes stay valid", function()
		local h = roster()
		P().RecordRank(h, GM, 1, 100)
		P().RecordRank(h, OFFICER, 0, 100)   -- Bryn is the GM from 100
		local L = Lg().New()
		local function cfg(author, seq, ts, cost)
			local rules = FDCP.Rules.DefaultConfig()
			rules.cost.matrix.weapon[4] = cost
			return event(author, seq, ts, "CONFIG_CHANGED", { rules = rules })
		end
		local r = Lg().Merge(L, { cfg(GM, 1, 10, 3), cfg(OFFICER, 1, 50, 4), cfg(OFFICER, 2, 150, 5),
			cfg(GM, 2, 160, 6) }, P().Gate(h))
		eq(r.added, 2)
		deepEq(codes(r.refused), { GM .. ":2=NOT_GM", OFFICER .. ":1=NOT_GM" })
		eq(FDCP.Rules.Current(L).cost.matrix.weapon[4], 5)
	end)

	it("uses the permissions in force when the event was written, whatever the arrival order", function()
		local lowered = event(GM, 1, 100, "PERMISSIONS_CHANGED", { table = P().Normalize({ ["credits.adjust"] = 1 }) })
		local early, late = adjust(OFFICER, 1, 50), adjust(OFFICER, 2, 150)
		for seed = 1, 6 do
			local L = Lg().New()
			local r = Lg().Merge(L, shuffled({ lowered, early, late }, seed), P().Gate(roster()))
			eq(r.added, 2, "seed " .. seed)
			deepEq(codes(r.refused), { OFFICER .. ":1=RANK_TOO_LOW" })
			eq(Lg().Credits(L, "S1").Corin, -1)
		end
	end)

	it("in a night, the master looter's corrections need night.run; outside, credits.adjust", function()
		local L = Lg().New()
		local gate = P().Gate(roster())
		local r = Lg().Merge(L, {
			event(OFFICER, 1, 10, "NIGHT_OPENED", { date = "2026-11-12", instanceID = 409, size = 40, difficulty = "normal" }, "S1"),
			award(OFFICER, 2, 11),
			adjust(OFFICER, 3, 12),
			event(OFFICER, 4, 13, "AWARD_VOIDED", { ref = OFFICER .. ":2", reason = "WRONG_WINNER" }, "S1"),
			event(OFFICER, 5, 20, "NIGHT_CLOSED", {}, "S1"),
			adjust(OFFICER, 6, 30),
			adjust(OFFICER, 7, 12, nil),
		}, gate)
		eq(r.added, 6)
		deepEq(codes(r.refused), { OFFICER .. ":6=RANK_TOO_LOW" })
		eq(P().Required(L, adjust(OFFICER, 8, 15)), "night.run")
		eq(P().Required(L, adjust(OFFICER, 8, 25)), "credits.adjust")
		eq(P().Required(L, adjust(OFFICER, 8, 5)), "credits.adjust")
		local other = adjust(OFFICER, 8, 15); other.season = "S2"
		eq(P().Required(L, other), "credits.adjust")   -- the night is of another season
	end)

	it("an unknown type of a newer addon needs the loosest writing permission", function()
		local L = Lg().New()
		local future = event(OFFICER, 1, 1, "LOOT_TRADED", {}, "S1")
		eq(P().Required(L, future), "night.run")   -- rank 1, the loosest; ties go to the first name
		local r = Lg().Merge(L, { future, event(RAIDER, 1, 1, "LOOT_TRADED", {}, "S1") }, P().Gate(roster()))
		eq(r.added, 1); deepEq(codes(r.refused), { RAIDER .. ":1=RANK_TOO_LOW" })
	end)

	it("waits while the roster is not loaded, then decides", function()
		local h = roster()
		h.loaded = false
		local L = Lg().New()
		local r = Lg().Merge(L, { award(OFFICER, 1, 1), award(RAIDER, 1, 2) }, P().Gate(h))
		eq(r.added, 0); eq(#r.pending, 2); deepEq(r.refused, {})
		eq(Lg().Count(L), 0)
		local e, code = Lg().Append(L, { author = OFFICER, ts = 3, season = "S1", type = "ITEM_AWARDED",
			payload = { member = "Corin", item = 19003, cost = 1 } }, P().Gate(h))
		isNil(e); eq(code, "PENDING")
		h.loaded = true
		r = Lg().Merge(L, r.pending, P().Gate(h))
		eq(r.added, 1); deepEq(codes(r.refused), { RAIDER .. ":1=RANK_TOO_LOW" })
	end)

	it("refuses an author who is not in the guild", function()
		local h = roster()
		P().RecordRank(h, RAIDER, false, 100)   -- left the guild at 100
		local L = Lg().New()
		local r = Lg().Merge(L, { award(OUTSIDER, 1, 1), award(OFFICER, 1, 2) }, P().Gate(h))
		eq(r.added, 1); deepEq(codes(r.refused), { OUTSIDER .. ":1=NOT_IN_GUILD" })
		eq(P().RankAt(h, RAIDER, 50), 3); eq(P().RankAt(h, RAIDER, 150), false)
	end)

	it("an event already stored is a duplicate, not a new decision", function()
		local L = Lg().New()
		local a = award(OFFICER, 1, 1)
		eq(Lg().Merge(L, { a }, P().Gate(roster())).added, 1)
		local refuseAll = { accept = function() return false, "RANK_TOO_LOW" end }
		local r = Lg().Merge(L, { a }, refuseAll)
		eq(r.duplicate, 1); deepEq(r.refused, {})
	end)

	it("takes a rankOf function as well as a history", function()
		local L = Lg().New()
		local gate = P().Gate(function(author) return author == GM and 0 or 5 end)
		eq(Lg().Merge(L, { award(GM, 1, 1), award(OFFICER, 1, 1) }, gate).added, 1)
	end)

	it("the writers of seasons and members pass the gate on", function()
		local L = Lg().New()
		local gate = P().Gate(roster())
		local e, code = FDCP.Season.Open(L, { author = OFFICER, ts = 1, season = "S1", instances = PACK }, nil, gate)
		isNil(e); eq(code, "RANK_TOO_LOW")
		assert(FDCP.Season.Open(L, { author = GM, ts = 2, season = "S1", instances = PACK }, nil, gate))
		e, code = FDCP.Members.Join(L, { author = RAIDER, ts = 3, season = "S1", member = "Corin" }, nil, gate)
		isNil(e); eq(code, "RANK_TOO_LOW")
		assert(FDCP.Members.Join(L, { author = OFFICER, ts = 4, season = "S1", member = "Corin" }, nil, gate))
		e, code = FDCP.Members.LinkAlt(L, { author = RAIDER, ts = 5, season = "S1", alt = "Corinalt", main = "Corin" }, gate)
		isNil(e); eq(code, "RANK_TOO_LOW")
		e, code = FDCP.Season.Close(L, { author = OFFICER, ts = 6, season = "S1" }, gate)
		isNil(e); eq(code, "RANK_TOO_LOW")
		assert(FDCP.Season.Close(L, { author = GM, ts = 7, season = "S1" }, gate))
	end)

	it("without a gate the ledger stores every valid event, as before", function()
		local L = Lg().New()
		eq(Lg().Merge(L, { award(RAIDER, 1, 1), award(OUTSIDER, 1, 1) }).added, 2)
	end)
end)

describe("ranks are indexes, not names", function()
	it("renamed ranks change nothing", function()
		local names = { "Guild Master", "Officer", "Veteran", "Raider" }
		local renamed = { "Drago", "Custode", "Veterano", "Predone" }
		eq(P().RanksChanged(names, renamed), "RENAMED")
		local events = { award(OFFICER, 1, 1), award(RAIDER, 1, 2),
			event(GM, 1, 3, "PERMISSIONS_CHANGED", { table = { ["night.run"] = 3 } }), award(RAIDER, 2, 4) }
		local A, B = Lg().New(), Lg().New()
		local ra = Lg().Merge(A, events, P().Gate(roster()))
		-- The same roster after the rename: the history holds indexes, so the gate decides the same.
		local rb = Lg().Merge(B, events, P().Gate(roster()))
		deepEq(codes(ra.refused), codes(rb.refused))
		eq(ra.added, 3); deepEq(codes(ra.refused), { RAIDER .. ":1=RANK_TOO_LOW" })
		deepEq(P().Current(A), P().Current(B))
	end)

	it("reordered, removed or added ranks are reported to the GM", function()
		local names = { "GM", "Officer", "Veteran", "Raider" }
		isNil(P().RanksChanged(names, { "GM", "Officer", "Veteran", "Raider" }))
		eq(P().RanksChanged(names, { "GM", "Veteran", "Officer", "Raider" }), "REORDERED")
		eq(P().RanksChanged(names, { "GM", "Officer", "Raider" }), "REMOVED")
		eq(P().RanksChanged(names, { "GM", "Officer", "Veteran", "Raider", "Trial" }), "ADDED")
		isNil(P().RanksChanged(nil, names))
	end)

	it("lists the permissions that point at a rank that no longer exists", function()
		local t = P().Normalize({ ["export.public"] = 3, ["view.attendance"] = 4 })
		deepEq(P().CheckRanks(t, 4), { "view.attendance" })
		deepEq(P().CheckRanks(t, 3), { "export.public", "view.attendance" })
		deepEq(P().CheckRanks(t, 10), {})
	end)
end)

describe("the rank history", function()
	it("stores only changes and answers for any time", function()
		local h = P().NewHistory()
		isNil(P().RankAt(h, OFFICER, 1))   -- not loaded yet
		truthy(P().RecordRank(h, OFFICER, 2, 10))
		falsy(P().RecordRank(h, OFFICER, 2, 20))
		truthy(P().RecordRank(h, OFFICER, 1, 30))
		falsy(P().RecordRank(h, OFFICER, 12, 40))   -- not a rank
		eq(#h.members[OFFICER], 2)
		h.loaded = true
		eq(P().RankAt(h, OFFICER, 5), 2)    -- older than every record: the first one seen
		eq(P().RankAt(h, OFFICER, 10), 2); eq(P().RankAt(h, OFFICER, 29), 2)
		eq(P().RankAt(h, OFFICER, 30), 1); eq(P().RankAt(h, OFFICER, 99), 1)
		eq(P().RankAt(h, "Nobody", 1), false)
		isNil(P().RankAt(nil, OFFICER, 1))
	end)
end)

describe("the permissions in the ledger", function()
	it("are the preset until the GM writes them", function()
		local L = Lg().New()
		local t, from = P().Current(L)
		deepEq(t, P().DefaultTable()); isNil(from)
	end)

	it("PERMISSIONS_CHANGED stores the whole table", function()
		local L = Lg().New()
		local e = assert(P().Change(L, { author = GM, ts = 1, table = { ["credits.adjust"] = 1 } }))
		eq(e.type, "PERMISSIONS_CHANGED"); isNil(e.season)
		deepEq(e.payload.table, P().Normalize({ ["credits.adjust"] = 1 }))
		local t, from = P().Current(L)
		eq(t["credits.adjust"], 1); eq(from, e.id)
		eq(P().Current(L, e)["credits.adjust"], 0)
		local same, code = P().Change(L, { author = GM, ts = 2, table = { ["credits.adjust"] = 1 } })
		isNil(same); eq(code, "UNCHANGED")
		same, code = P().Change(L, "table")
		isNil(same); eq(code, "event")
	end)

	it("need an explicit confirmation while a season is open", function()
		local L = Lg().New()
		assert(FDCP.Season.Open(L, { author = GM, ts = 1, season = "S1", instances = PACK }))
		local e, code = P().Change(L, { author = GM, ts = 2, table = { ["export.public"] = 3 } })
		isNil(e); eq(code, "CONFIRM_REQUIRED")
		e = assert(P().Change(L, { author = GM, ts = 3, table = { ["export.public"] = 3 }, confirmed = true }))
		eq(e.payload.confirmed, true)
	end)
end)
