-- Export (M6-3): the credits table as Discord text, CSV and JSON (Domain/Export.lua, pure) and the History › Export pane.
-- The exports are deterministic and match the golden files of Tests/golden/ (English and Italian formats).
local function Lg() return FDCP.Ledger end
local function Sn() return FDCP.Season end
local function R() return FDCP.Roster end
local function Nt() return FDCP.Nights end
local function E() return FDCP.Export end
local function NC() return FDCP.NightController end
local function RC() return FDCP.RosterController end
local function HW() return FDCP.HistoryWindow end
local function XW() return FDCP.ExportWindow end

local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }
local REALM = "TestRealm"
local function full(n) return n .. "-" .. REALM end

local function guild(rank)
	return function(M)
		M.guild.Set({ name = "Keepers", ranks = RANKS, myRank = rank or 1, members = {
			{ name = "Aurel", rank = 0 }, { name = "Bryn", rank = 1 }, { name = "Corin", rank = 3 },
		} })
	end
end

-- name, spec, faction
local POOL = {
	{ "Aurel", 73, "Horde" },     -- Protection Warrior (tank)
	{ "Bryn", 65, "Horde" },      -- Holy Paladin (healer)
	{ "Corin", 105, "Horde" },    -- Restoration Druid (healer)
	{ "Dara", 63, "Horde" },      -- Fire Mage (dps)
	{ "Édda", 258, "Horde" },     -- Shadow Priest (dps), an accent in the name
	{ "Fenn", 70, "Alliance" },   -- Retribution Paladin: the other faction
}

local function award(L, author, ts, member, cost)
	return assert(Lg().Append(L, { author = author, ts = ts, season = "S1", type = "ITEM_AWARDED",
		payload = { target = "member", member = full(member), item = 100 + ts, cost = cost, reasons = {}, flags = {} } }))
end

-- Season S1, five Horde mains and one Alliance, two nights (2026-10-14 and 2026-10-21) with a lineup and a bench (the
-- attendance, which no export may carry), a voided award and an adjustment.
local function ledger()
	local L = Lg().New()
	local A, B = full("Aurel"), full("Bryn")
	assert(Sn().Open(L, { author = A, ts = 1, season = "S1", label = "Season 1", instances = { { id = 409, size = 40 } } }))
	for i, p in ipairs(POOL) do
		assert(R().Join(L, { author = B, ts = 1 + i, season = "S1", member = full(p[1]), faction = p[3], ms1 = p[2] }))
	end
	assert(Nt().Open(L, { author = A, ts = 20, season = "S1", date = "2026-10-14", instanceID = 409, difficulty = "normal" }))
	assert(Nt().SetLineup(L, { author = A, ts = 21, season = "S1", raid = { full("Aurel"), full("Bryn") }, bench = { full("Dara") } }))
	award(L, A, 22, "Bryn", 1)
	award(L, A, 23, "Corin", 2)
	award(L, A, 24, "Corin", 1)
	local voided = award(L, A, 25, "Édda", 2)
	assert(Lg().Append(L, { author = A, ts = 26, season = "S1", type = "AWARD_VOIDED", payload = { ref = voided.id, reason = "MISTAKE" } }))
	assert(Nt().Close(L, { author = A, ts = 30, season = "S1" }))
	assert(Nt().Open(L, { author = A, ts = 40, season = "S1", date = "2026-10-21", instanceID = 409, difficulty = "normal" }))
	award(L, A, 41, "Aurel", 1)
	award(L, A, 42, "Fenn", 2)
	assert(Lg().Append(L, { author = A, ts = 43, season = "S1", type = "CREDITS_ADJUSTED",
		payload = { member = full("Dara"), delta = 1.5, reason = "CORRECTION" } }))
	assert(Nt().Close(L, { author = A, ts = 50, season = "S1" }))
	return L
end

-- The guild's language: separators, date pattern, class and role names and the labels, from the locale of that language.
local function fmtFor(lang)
	local function T(k) return FDCP.Locale.Text(lang, k) end
	return {
		decimal = T("NUMBER_DECIMAL"), group = T("NUMBER_GROUP"), date = T("DATE_LONG"),
		className = function(c) return T("CLASS_" .. c) end,
		roleName = function(c) return T("ROLE_" .. c) end,
		labels = { rank = T("EXPORT_COL_RANK"), member = T("EXPORT_COL_MEMBER"), class = T("EXPORT_COL_CLASS"),
			role = T("EXPORT_COL_ROLE"), credits = T("EXPORT_COL_CREDITS"), title = T("EXPORT_TITLE"),
			updated = T("EXPORT_UPDATED"), part = T("EXPORT_PART_LINE") },
	}
end

local function golden(name, text)
	eq(text, Golden(name), name)
end

describe("the data of an export", function()
	it("is the Credits tab's table: queue order, the guild's faction, voids out, no attendance", function()
		local d = assert(E().Data(ledger(), "S1", { faction = "Horde" }))
		eq(d.label, "Season 1"); eq(d.updated, "2026-10-21")
		deepEq(d.nights, { "2026-10-14", "2026-10-21" })
		eq(#d.rows, 5, "the Horde's playing mains only")
		local by = {}
		for i, r in ipairs(d.rows) do eq(r.rank, i); by[r.member] = r end
		eq(by.Bryn.total, 1)    -- lowest credits first in the queue: spent 1 at 0 start credits
		eq(by.Corin.total, 3); deepEq(by.Corin.perNight, { 3, 0 })
		eq(by["Édda"].total, 0, "the voided award leaves no trace")
		eq(by.Dara.total, 1.5, "an adjustment is in the total only"); deepEq(by.Dara.perNight, { 0, 0 })
		eq(by.Aurel.class, "WARRIOR"); eq(by.Aurel.role, "TANK")
		isNil(by.Fenn)
	end)

	it("carries no attendance: no lineup, bench or presence anywhere in the data or in the texts", function()
		local L = ledger()
		local d = E().Data(L, "S1", { faction = "Horde" })
		local allowed = { rank = true, member = true, class = true, role = true, total = true, perNight = true }
		for _, r in ipairs(d.rows) do for k in pairs(r) do truthy(allowed[k], "unexpected field " .. k) end end
		for _, k in ipairs({ "discord", "csv", "json" }) do
			for _, text in ipairs(E().Build(L, "S1", k, fmtFor("enUS"), { faction = "Horde" })) do
				falsy(text:lower():find("bench", 1, true)); falsy(text:lower():find("lineup", 1, true))
				falsy(text:lower():find("attend", 1, true)); falsy(text:find("TestRealm", 1, true), "no realm in a public export")
			end
		end
	end)

	it("refuses an unknown season and an unknown kind", function()
		local L = ledger()
		eq(select(2, E().Data(L, "S9")), "SEASON_UNKNOWN")
		eq(select(2, E().Build(L, "S9", "csv", fmtFor("enUS"))), "SEASON_UNKNOWN")
		eq(select(2, E().Build(L, "S1", "xml", fmtFor("enUS"))), "EXPORT_KIND_UNKNOWN")
	end)
end)

describe("numbers and dates", function()
	it("use the decimal mark, the thousands separator and the date pattern of the language", function()
		local en, it = fmtFor("enUS"), fmtFor("itIT")
		eq(E().Number(1.5, en), "1.5"); eq(E().Number(1.5, it), "1,5")
		eq(E().Number(1234567.25, en), "1,234,567.25"); eq(E().Number(1234567.25, it), "1.234.567,25")
		eq(E().Number(-2, en), "-2"); eq(E().Number(0.1 + 0.2, en), "0.3", "rounded to two decimals")
		eq(E().Number(100, en), "100"); eq(E().Number(1000, it), "1.000")
		eq(E().Date("2026-10-21", en.date), "10/21/2026"); eq(E().Date("2026-10-21", it.date), "21/10/2026")
		eq(E().Date("nonsense", it.date), "nonsense")
	end)
end)

describe("the exports match the golden files", function()
	local function build(kind, lang)
		return E().Build(ledger(), "S1", kind, fmtFor(lang), { faction = "Horde" })
	end

	it("Discord, in English and in Italian", function()
		local en, it = build("discord", "enUS"), build("discord", "itIT")
		eq(#en, 1)
		golden("export_discord_enUS.txt", en[1])
		golden("export_discord_itIT.txt", it[1])
	end)

	it("CSV: a comma in English, a semicolon and decimal comma in Italian", function()
		golden("export_csv_enUS.csv", build("csv", "enUS")[1])
		golden("export_csv_itIT.csv", build("csv", "itIT")[1])
	end)

	it("JSON: ISO dates and decimal points whatever the language", function()
		local en, it = build("json", "enUS")[1], build("json", "itIT")[1]
		eq(en, it)
		golden("export_json.json", en)
	end)

	it("is deterministic: the same ledger gives the same bytes", function()
		for _, k in ipairs({ "discord", "csv", "json" }) do
			deepEq(build(k, "enUS"), build(k, "enUS"))
		end
	end)
end)

describe("a long Discord table", function()
	it("goes in several messages under the limit, each with its own code block and the column line", function()
		local L = Lg().New()
		local A = full("Aurel")
		assert(Sn().Open(L, { author = A, ts = 1, season = "S1", label = "Big", instances = { { id = 409, size = 40 } } }))
		for i = 1, 120 do
			assert(R().Join(L, { author = A, ts = 1 + i, season = "S1", member = full("Player" .. i), faction = "Horde", ms1 = 63 }))
		end
		local msgs = E().Build(L, "S1", "discord", fmtFor("enUS"), { faction = "Horde" })
		truthy(#msgs >= 2)
		local rows = 0
		for i, m in ipairs(msgs) do
			truthy(#m <= 2000, "message " .. i .. " is " .. #m)
			truthy(m:find("^%*%*") == (i == 1 and 1 or nil), "the title only in the first")
			truthy(m:find("```\n#", 1, true) or m:find("```\n ", 1, true), "the column line opens every block")
			eq(select(2, m:gsub("```", "")), 2)
			contains(m, ("(part %d/%d)"):format(i, #msgs))
			for _ in m:gmatch("Player%d+") do rows = rows + 1 end
		end
		eq(rows, 120, "every member is in exactly one message")
	end)
end)

describe("the Export sub-tab", function()
	local function open(rank)
		local L = ledger()
		NC():Bind(L)
		Mock.Advance(3)
		RC().faction = "Horde"
		Mock.Slash("/fdcp")
		FDCP.MainWindow:SelectTab("history")
		HW():Refresh()
		HW().root.sub:Select("export")
		return L
	end

	describe("an officer", function()
		before_boot(guild(1))

		it("sees the Discord text selected-ready, switches to CSV and JSON, and cannot edit the text", function()
			open()
			truthy(HW().root.panes.export:IsShown())
			eq(XW().kind, "discord")
			contains(XW().edit:GetText(), "Season 1")
			contains(XW().edit:GetText(), "Bryn")
			XW().seg:Select("csv")
			contains(XW().edit:GetText(), "Corin")
			falsy(XW().edit:GetText():find("```", 1, true))
			XW().seg:Select("json")
			contains(XW().edit:GetText(), '"season": "S1"')
			local text = XW().text
			XW().edit:SetText("tampered")
			Mock.RunScript(XW().edit, "OnTextChanged", true)
			eq(XW().edit:GetText(), text, "an edit by hand is put back")
			XW():SelectAll()
			truthy(XW().edit._highlighted, "everything is selected for Ctrl+C")
		end)

		it("follows the season shown and the guild's language", function()
			open()
			XW().seg:Select("csv")
			contains(XW().edit:GetText(), "10/14/2026")
		end)
	end)

	describe("a raider", function()
		before_boot(guild(3))

		it("is told the rank is too low and gets no text, and a forced call is refused", function()
			open()
			eq(XW().edit:GetText(), "")
			falsy(XW().field:IsShown())
			contains(XW().message:GetText(), "rank")
			local texts, why = XW().Generate("discord", "S1")
			isNil(texts); eq(why, "RANK_TOO_LOW")
		end)
	end)
end)
