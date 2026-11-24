-- The readiness tab and the notify button (M8-3, ADR 0010, docs/ANALISI.md §4.2): Domain/ReadinessNotice.lua (the words, the
-- grouping, the 255-byte split), App/ReadinessNotifier.lua (permission, cooldown, the queue behind a boss fight or the chat
-- lockdown, the log; on the network simulator), UI/ReadinessPanel.lua over Roster > Readiness, and the readiness page of the
-- rules form (Domain/RuleFields.lua, UI/Windows/RulesForm.lua).
local function N() return FDCP.ReadinessNotice end
local function R() return FDCP.Readiness end
local function RF() return FDCP.RuleFields end

local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end

-- The English words of the notice, as the locale keys give them (the Domain module takes them as a table).
local function words()
	local T_ = function(key) return FDCP.Locale.Text("enUS", key) end
	return {
		raid = T_("READY_NOTICE_RAID"), raidUnknown = T_("READY_NOTICE_RAID_UNKNOWN"), whisper = T_("READY_NOTICE_WHISPER"),
		group = T_("READY_NOTICE_GROUP"), enchant = T_("READY_PART_ENCHANT"), item = T_("READY_PART_ITEM"),
		slot = function(n) return T_("READY_SLOT_" .. n) end, cat = function(c) return T_("READY_CAT_" .. c) end,
	}
end

-- A row of the table, as App/ReadinessCheck.lua gives it.
local function row(name, status, enchants, items, reason)
	return { name = name, status = status, reason = reason, result = { status = status, enchants = enchants or {}, items = items or {} } }
end
local function miss(slot) return { slot = slot, status = "MISSING" } end
local function item(cat, status, have, need) return { cat = cat, status = status, have = have, need = need } end

describe("the words of the notice", function()
	it("a whisper names exactly what is missing and where", function()
		local r = row("Aurel-" .. REALM, "MISSING", { miss(10), miss(15) },
			{ item("POTION", "WARN", 1, 2), item("FLASK", "MISSING", 0, 1) })
		local lines = N().Whisper(r, words())
		deepEq(lines, { "[FDCP] Missing: enchant hands, back; potions 1/2; flask 0/1" })
	end)

	it("what could not be read is not listed, and a raider with nothing readable to list gets no whisper", function()
		local r = row("Bryn", "WARN", { { slot = 9, status = "UNKNOWN" } }, { item("FOOD", "UNKNOWN", nil, 5) })
		isNil(N().Whisper(r, words()))
		local r2 = row("Corin", "MISSING", { { slot = 9, status = "UNKNOWN" }, miss(5) }, { item("FOOD", "UNKNOWN", nil, 5) })
		deepEq(N().Whisper(r2, words()), { "[FDCP] Missing: enchant chest" })
		local rows = { r, r2, row("Dara", "UNKNOWN", nil, nil, "NO_ADDON"), row("Edda", "OK") }
		deepEq(N().Recipients(rows)[1].name, "Corin")
		eq(#N().Recipients(rows), 1)
	end)

	it("splits a long whisper over lines of at most 255 bytes, no part cut", function()
		local items = {}
		for i = 1, 40 do items[i] = item("POTION", "MISSING", 0, 2) end
		local w = words()
		w.cat = function() return "elixir of the very long name" end
		local lines = N().Whisper(row("Aurel", "MISSING", {}, items), w)
		truthy(#lines > 1, "one line is not enough")
		local parts = 0
		for _, line in ipairs(lines) do
			truthy(#line <= 255, "a line has " .. #line .. " bytes")
			truthy(line:find("^%[FDCP%] Missing: "))
			for _ in line:gmatch("elixir of the very long name 0/2") do parts = parts + 1 end
		end
		eq(parts, 40)
	end)

	it("counts the raiders by status and writes the /raid summary with the names grouped by what they lack", function()
		local rows = {
			row("Aurel-" .. REALM, "MISSING", { miss(9) }, { item("POTION", "MISSING", 0, 2) }),
			row("Bryn-" .. REALM, "MISSING", { miss(9) }, {}),
			row("Corin-" .. REALM, "WARN", {}, { item("POTION", "WARN", 1, 2) }),
			row("Dara-" .. REALM, "MISSING", {}, { item("POTION", "MISSING", 0, 2) }),
			row("Edda-" .. REALM, "UNKNOWN", nil, nil, "NO_ADDON"), row("Fenn-" .. REALM, "OK"),
		}
		deepEq(N().Counts(rows), { missing = 3, low = 1, unknown = 1, total = 6, whispers = 4 })
		local lines = N().Raid(rows, words())
		eq(lines[1], "[FDCP] Readiness: 3 missing, 1 low, 1 unknown. Check your whispers.")
		eq(lines[2], "[FDCP] potions: Aurel, Corin, Dara", "the most lacked first")
		eq(lines[3], "[FDCP] enchant wrist: Aurel, Bryn")
		eq(#lines, 3)
		rows[5] = row("Edda", "OK")
		eq(N().Raid(rows, words())[1], "[FDCP] Readiness: 3 missing, 1 low. Check your whispers.", "no unknown, no mention")
	end)

	it("splits the names of a group over lines of at most 255 bytes", function()
		local rows = {}
		for i = 1, 40 do rows[i] = row(string.format("Raider%02d-%s", i, REALM), "MISSING", { miss(9) }) end
		local lines = N().Raid(rows, words())
		truthy(#lines >= 2)
		local seen = 0
		for i, line in ipairs(lines) do
			truthy(#line <= 255, "a line has " .. #line)
			if i > 1 then for _ in line:gmatch("Raider%d%d") do seen = seen + 1 end end
		end
		eq(seen, 40)
		-- and only the most lacked things are named: a raider lacking twenty things never fills the channel
		local many = {}
		for i = 1, 11 do many[i] = miss(({ 1, 3, 5, 7, 8, 9, 10, 15, 16, 17, 18 })[i]) end
		local capped = N().Raid({ row("Aurel", "MISSING", many) }, words())
		eq(#capped, 1 + N().GROUPS_MAX)
	end)

	it("nobody to write to is NOBODY", function()
		local lines, code = N().Raid({ row("Aurel", "OK"), row("Bryn", "UNKNOWN", nil, nil, "OFFLINE") }, words())
		isNil(lines); eq(code, "NOBODY")
		local plan, why = N().Plan({}, words())
		isNil(plan); eq(why, "NOBODY")
	end)

	it("the guild's wording wins, and {list} {name} {missing} {low} {unknown} fill in; a text without {list} ends with it", function()
		local rows = { row("Aurel-" .. REALM, "MISSING", { miss(9) }), row("Bryn-" .. REALM, "UNKNOWN", nil, nil, "NO_ANSWER") }
		local texts = { raid = "{missing}/{low}/{unknown} of {total}", whisper = "{name}, bring" }
		eq(N().Raid(rows, words(), texts)[1], "[FDCP] 1/0/1 of 2")
		deepEq(N().Whisper(rows[1], words(), texts), { "[FDCP] Aurel, bring enchant wrist" })
		texts.whisper = "{name}: {list}!"
		deepEq(N().Whisper(rows[1], words(), texts), { "[FDCP] Aurel: enchant wrist!" })
		texts.whisper = ""
		deepEq(N().Whisper(rows[1], words(), texts), { "[FDCP] Missing: enchant wrist" }, "empty = the default")
		-- a chat escape never leaves
		texts.whisper = "a|cffff0000b {list}"
		falsy(N().Whisper(rows[1], words(), texts)[1]:find("|", 1, true))
	end)

	it("builds the whole plan and counts its messages", function()
		local rows = { row("Aurel-" .. REALM, "MISSING", { miss(9) }), row("Bryn-" .. REALM, "WARN", {}, { item("FOOD", "WARN", 2, 5) }) }
		local plan = N().Plan(rows, words())
		eq(#plan.whispers, 2)
		eq(plan.whispers[2].name, "Bryn-" .. REALM)
		deepEq(plan.whispers[2].lines, { "[FDCP] Missing: food 2/5" })
		eq(N().Size(plan), #plan.raid + 2)
	end)

	it("every text exists in both languages and carries the placeholders", function()
		for _, lang in ipairs({ "enUS", "itIT" }) do
			local function T_(k) return FDCP.Locale.Text(lang, k) end
			contains(T_("READY_NOTICE_RAID"), "{missing}"); contains(T_("READY_NOTICE_RAID"), "{low}")
			contains(T_("READY_NOTICE_RAID_UNKNOWN"), "{unknown}")
			contains(T_("READY_NOTICE_WHISPER"), "{list}")
			contains(T_("READY_NOTICE_GROUP"), "{what}"); contains(T_("READY_NOTICE_GROUP"), "{names}")
			contains(T_("READY_PART_ENCHANT"), "{slots}")
			for _, k in ipairs({ "{cat}", "{have}", "{need}" }) do contains(T_("READY_PART_ITEM"), k) end
			for _, slot in ipairs(FDCP.ReadinessData.SLOTS) do truthy(T_("READY_SLOT_" .. slot) ~= "READY_SLOT_" .. slot) end
			for _, c in ipairs(FDCP.ReadinessData.CATEGORIES) do truthy(T_("READY_CAT_" .. c.code) ~= "READY_CAT_" .. c.code) end
		end
	end)
end)

describe("the wording in the rules", function()
	it("is part of the defaults, validated and left out of the ledger while it is the default", function()
		local d = R().DefaultConfig()
		deepEq(d.texts, { raid = "", whisper = "" })
		truthy(R().ValidateConfig(d))
		d.texts.raid = ("x"):rep(121)
		d.texts.whisper = "a|b"
		local ok, problems = R().ValidateConfig(d)
		falsy(ok)
		deepEq(problems, { "texts.raid", "texts.whisper" })
		d.texts = nil
		falsy(R().ValidateConfig(d))
		-- an older rules table without it is filled with the defaults
		local old = FDCP.Rules.DefaultConfig()
		old.readiness.texts = nil
		deepEq(FDCP.Rules.WithDefaults(old).readiness.texts, { raid = "", whisper = "" })
		isNil(FDCP.Rules.Stored(FDCP.Rules.DefaultConfig()).readiness)
	end)

	it("a requirement list says what each category needs of a raider", function()
		local needs = R().Needs(R().DefaultConfig(), { class = "HUNTER" })
		eq(needs.AMMO, 1000); eq(needs.WATER, 10); eq(needs.FOOD, 5)
		local rogue = R().Needs(R().DefaultConfig(), { class = "ROGUE" })
		isNil(rogue.AMMO); isNil(rogue.WATER); eq(rogue.POTION, 2)
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The readiness page of the rules form

describe("the readiness fields of the rules", function()
	it("read the defaults and write them back unchanged", function()
		local rules = FDCP.Rules.DefaultConfig()
		local fields = RF().Page("readiness")
		eq(#fields, 24)
		for _, f in ipairs(fields) do
			local v = RF().Get(rules, f)
			truthy(v ~= nil, f.id)
			for _, key in ipairs(f.keys) do truthy(FDCP.L[key] ~= key, key .. " has a text") end
			truthy(RF().Set(rules, f, v), f.id)
		end
		deepEq(FDCP.Rules.Diff(rules, FDCP.Rules.DefaultConfig()), {})
		eq(RF().Get(rules, RF().Field("readiness.slot.9")), true)
		eq(RF().Get(rules, RF().Field("readiness.slot.1")), false)
		eq(RF().Get(rules, RF().Field("readiness.need.POTION")), 2)
		eq(RF().Get(rules, RF().Field("readiness.filter.WATER")), true)
		eq(RF().Get(rules, RF().Field("readiness.filter.AMMO")), true)
		eq(RF().PageOfCode("readiness.needs.2.min"), "readiness")
	end)

	it("a slot switch adds or removes the requirement, keeping the hunter's ranged scope and the order of the sheet", function()
		local rules = FDCP.Rules.DefaultConfig()
		local head, ranged = RF().Field("readiness.slot.1"), RF().Field("readiness.slot.18")
		RF().Set(rules, head, true)
		eq(rules.readiness.slots[1].slot, 1, "head goes first, as on the character sheet")
		RF().Set(rules, ranged, false)
		for _, r in ipairs(rules.readiness.slots) do truthy(r.slot ~= 18) end
		RF().Set(rules, ranged, true)
		local last = rules.readiness.slots[#rules.readiness.slots]
		eq(last.slot, 18); deepEq(last.classes, { "HUNTER" })
		truthy(FDCP.Rules.Validate(rules))
	end)

	it("a minimum and a filter change one requirement and keep every other filter", function()
		local rules = FDCP.Rules.DefaultConfig()
		rules.readiness.needs[4].roles = { "TANK" }         -- POTION for the tanks only: the form keeps it
		RF().Set(rules, RF().Field("readiness.need.POTION"), 6)
		eq(rules.readiness.needs[4].min, 6); deepEq(rules.readiness.needs[4].roles, { "TANK" })
		RF().Set(rules, RF().Field("readiness.need.FLASK"), 0)
		eq(RF().Get(rules, RF().Field("readiness.need.FLASK")), 0)
		truthy(FDCP.Rules.Validate(rules))
		-- the mana filter and the hunter filter
		RF().Set(rules, RF().Field("readiness.filter.WATER"), false)
		isNil(rules.readiness.needs[3].mana)
		RF().Set(rules, RF().Field("readiness.filter.WATER"), true)
		eq(rules.readiness.needs[3].mana, true)
		RF().Set(rules, RF().Field("readiness.filter.AMMO"), false)
		isNil(rules.readiness.needs[6].classes)
		RF().Set(rules, RF().Field("readiness.filter.AMMO"), true)
		deepEq(rules.readiness.needs[6].classes, { "HUNTER" })
		-- a category the rules never had is added with its default filter
		rules.readiness.needs = {}
		RF().Set(rules, RF().Field("readiness.need.AMMO"), 500)
		deepEq(rules.readiness.needs, { { classes = { "HUNTER" }, cat = "AMMO", min = 500 } })
		truthy(FDCP.Rules.Validate(rules))
		-- numbers typed are checked
		local f = RF().Field("readiness.need.AMMO")
		isNil(RF().Parse(f, "-1")); isNil(RF().Parse(f, "10001")); eq(RF().Parse(f, "2000"), 2000)
	end)
end)

local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }

local function click(b) b:GetScript("OnClick")(b) end

describe("the readiness page of the Settings tab", function()
	before_boot(function(Mock)
		Mock.guild.Set({ name = "Keepers", ranks = RANKS, myRank = 0, members = { { name = "Aurel", rank = 0 } } })
	end)

	it("lists the page, edits a slot and a minimum and saves them through the controller", function()
		local L = FDCP.Ledger.New()
		FDCP.NightController:Bind(L)
		Mock.Advance(3)
		Mock.Slash("/fdcp")
		FDCP.MainWindow:SelectTab("settings")
		FDCP.SettingsWindow.root.sub:Select("rules")
		local form = FDCP.SettingsWindow.rules
		form.list:Select("readiness")
		eq(form.page, "readiness"); eq(#form.fields, 24)
		local function rowOf(id)
			for i, f in ipairs(form.fields) do if f.id == id then return form.rows[i] end end
			error("no field " .. id)
		end
		rowOf("readiness.slot.1").switch:SetOn(true)
		rowOf("readiness.need.POTION").edit:SetText("4")
		Mock.TypeInto(rowOf("readiness.need.POTION").edit.edit, "4")
		Mock.TypeInto(rowOf("readiness.texts.whisper").edit.edit, "bring {list}")
		click(form.card.save)
		local rules = FDCP.Rules.Current(L)
		eq(rules.readiness.slots[1].slot, 1)
		eq(FDCP.ReadinessCheck:Rules().needs[4].min, 4)
		eq(rules.readiness.texts.whisper, "bring {list}")
		eq(form.card.message:GetText(), "Saved.")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The notify button on the network simulator

local function link(id, enchant, name)
	return "|cffa335ee|Hitem:" .. id .. ":" .. (enchant or "") .. ":::::::60:::::|h[" .. (name or "Item") .. "]|h|r"
end

local NAMES = { "Gm", "Aurel", "Bryn", "Corin", "Dara", "Edda" }
local RANKS_OF = { Aurel = 1, Bryn = 3, Corin = 3, Dara = 3, Edda = 3, Gm = 0 }

local function guildFor(name)
	return function(M)
		local members = {}
		for _, n in ipairs(NAMES) do
			if n ~= name then members[#members + 1] = { name = n, rank = RANKS_OF[n], class = "WARRIOR", online = true } end
		end
		M.guild.Set({ name = "Dragon", members = members, myRank = RANKS_OF[name] })
	end
end

-- Bryn is ready; Corin lacks a wrist enchant and potions; Dara a priest without water.
local function gear(M, name)
	if name == "Dara" then M.player.classFile, M.player.classId = "PRIEST", 5 end
	local wrist = name == "Corin" and 0 or 1885
	M.items.Add{ id = 22009, link = link(22009, wrist, "Bracers"), equipLoc = "INVTYPE_WRIST", classID = 4, subclassID = 4 }
	M.items.equipped = { [9] = link(22009, wrist, "Bracers") }
	M.items.counts = { [20452] = 5, [8932] = 20, [13446] = name == "Corin" and 0 or 5, [13510] = 1 }
	if name ~= "Dara" then M.items.counts[8079] = 20 end
	M.auras.buffs = { { spellId = 17626 } }
end

local function client(net, name, opts)
	opts = opts or {}
	local base = guildFor(name)
	return net:Client(name, { setup = function(M)
		base(M); gear(M, name)
		if opts.locale then M.player.locale = opts.locale end
	end })
end

-- Aurel (an officer) has asked the raid and the answers are in.
local function scenario(opts)
	local net = Sim.new{ realm = REALM, step = 0.5 }
	local c = {}
	for _, n in ipairs({ "Aurel", "Bryn", "Corin", "Dara" }) do c[n] = client(net, n, n == "Aurel" and opts or nil) end
	net:Raid({ "Aurel", "Bryn", "Corin", "Dara", "Edda" })
	net:Advance(5)
	truthy(c.Aurel.addon().AddonCheck:Request())
	assert(c.Aurel.addon().ReadinessCheck:Request())
	net:Advance(5)
	return net, c
end

local function chat(c, chatType)
	local out = {}
	for _, m in ipairs(c.Mock.chat.messages) do
		if chatType == nil or m.chatType == chatType then out[#out + 1] = m end
	end
	return out
end

describe("the notify button", function()
	it("writes the /raid summary and one whisper to each raider who lacks something, then logs it", function()
		local net, c = scenario()
		local notifier = c.Aurel.addon().ReadinessNotifier
		local plan = assert(notifier:Preview())
		eq(plan.counts.whispers, 2)
		local entry = assert(notifier:Send())
		eq(entry.raid, 4); eq(entry.whispers, 2)
		net:Advance(5)
		local raid = chat(c.Aurel, "RAID")
		eq(#raid, 4)
		eq(raid[1].message, "[FDCP] Readiness: 2 missing, 0 low, 1 unknown. Check your whispers.")
		eq(raid[2].message, "[FDCP] enchant wrist: Corin")
		eq(raid[3].message, "[FDCP] potions: Corin")
		eq(raid[4].message, "[FDCP] water: Dara")
		local whispers = chat(c.Aurel, "WHISPER")
		eq(#whispers, 2)
		eq(whispers[1].target, full("Corin")); eq(whispers[1].message, "[FDCP] Missing: enchant wrist; potions 0/2")
		eq(whispers[2].target, full("Dara")); eq(whispers[2].message, "[FDCP] Missing: water 0/10")
		-- the log: one entry, names only in the character's data, never in the debug log; nothing in the ledger
		local h = notifier:History()
		eq(#h, 1); eq(h[1].sent, 6); eq(h[1].failed, 0); eq(h[1].whispers, 2)
		deepEq(h[1].names, { full("Corin"), full("Dara") })
		for _, e in ipairs(c.Aurel.addon().Log.Entries()) do
			for _, a in ipairs(e.args) do
				if type(a) == "string" then falsy(a:find("Corin", 1, true), "a name reached the log") end
			end
		end
		isNil(c.Aurel.addon().Config.char.readiness)
	end)

	it("the messages leave one by one, PACE seconds apart", function()
		local net, c = scenario()
		local notifier = c.Aurel.addon().ReadinessNotifier
		assert(notifier:Send())
		eq(#chat(c.Aurel), 1, "the first goes at the click")
		truthy(notifier:Busy())
		net:Advance(0.5)
		eq(#chat(c.Aurel), 2)
		local _, code = notifier:Send()
		eq(code, "BUSY")
		net:Advance(5)
		eq(#chat(c.Aurel), 6)
		falsy(notifier:Busy())
	end)

	it("one notice every `notice.minutes` minutes; a night opening clears the wait", function()
		local net, c = scenario()
		local notifier = c.Aurel.addon().ReadinessNotifier
		assert(notifier:Send())
		net:Advance(5)
		local entry, code, wait = notifier:Send()
		isNil(entry); eq(code, "THROTTLED")
		truthy(wait > 250 and wait <= 300, "5 minutes by default: " .. tostring(wait))
		eq(#chat(c.Aurel), 6)
		net:Advance(300)
		truthy(notifier:Send(), "after the minutes")
		net:Advance(5)
		eq(#chat(c.Aurel), 12)
		eq(#notifier:History(), 2)
		-- a night opens: the wait is gone
		c.Aurel.addon().Bus:Emit("NIGHT_OPENED")
		eq(notifier:Wait(), 0)
	end)

	it("is refused for a raider, outside a raid, before any check and when nobody lacks anything", function()
		local net, c = scenario()
		local _, code = c.Bryn.addon().ReadinessNotifier:Send()
		eq(code, "RANK_TOO_LOW")
		net:Raid({})
		net:Advance(3)
		_, code = c.Aurel.addon().ReadinessNotifier:Send()
		eq(code, "NOT_IN_RAID")
		local net2 = Sim.new{ realm = REALM, step = 0.5 }
		local a = client(net2, "Aurel")
		net2:Raid({ "Aurel", "Bryn" })
		net2:Advance(5)
		_, code = a.addon().ReadinessNotifier:Send()
		eq(code, "NO_CHECK")
		assert(a.addon().ReadinessCheck:Request())
		net2:Advance(3)
		_, code = a.addon().ReadinessNotifier:Send()
		eq(code, "NOBODY", "Aurel is ready and Bryn has no addon: nobody to write to")
		eq(#chat(a), 0)
	end)

	it("waits behind a boss fight and leaves after it", function()
		local net, c = scenario()
		local notifier = c.Aurel.addon().ReadinessNotifier
		net:Encounter(601, "Boss", "start")
		local entry = assert(notifier:Send())
		truthy(entry.queued)
		net:Advance(10)
		eq(#chat(c.Aurel), 0, "nothing during the fight")
		truthy(notifier:Busy())
		net:Encounter(601, "Boss", "kill")
		net:Advance(5)
		eq(#chat(c.Aurel), 6)
		local h = notifier:History()
		eq(#h, 1); truthy(h[1].queued); eq(h[1].sent, 6)
	end)

	it("waits behind the chat lockdown and leaves when it ends", function()
		local net, c = scenario()
		local notifier = c.Aurel.addon().ReadinessNotifier
		net:Lockdown(true)
		truthy(assert(notifier:Send()).queued)
		net:Advance(6)
		eq(#chat(c.Aurel), 0)
		net:Lockdown(false)
		net:Advance(8)
		eq(#chat(c.Aurel), 6)
		falsy(notifier:Busy())
	end)

	it("a notice that waited too long is dropped, logged as expired, and the player can ask again", function()
		local net, c = scenario()
		local notifier = c.Aurel.addon().ReadinessNotifier
		net:Encounter(601, "Boss", "start")
		assert(notifier:Send())
		net:Advance(notifier.QUEUE_MAX + 10)
		falsy(notifier:Busy())
		eq(#chat(c.Aurel), 0)
		truthy(notifier:History()[1].expired)
		net:Encounter(601, "Boss", "kill")
		net:Advance(2)
		eq(#chat(c.Aurel), 0, "stale: nothing leaves")
	end)

	it("leaving the raid drops a waiting notice", function()
		local net, c = scenario()
		local notifier = c.Aurel.addon().ReadinessNotifier
		net:Lockdown(true)
		assert(notifier:Send())
		net:Raid({})
		net:Advance(3)
		falsy(notifier:Busy())
		net:Lockdown(false)
		net:Advance(5)
		eq(#chat(c.Aurel), 0)
	end)

	it("a game that refuses the first message does not spend the click", function()
		local net, c = scenario()
		local notifier = c.Aurel.addon().ReadinessNotifier
		local send = c.Aurel.addon().Compat.Chat.Send
		c.Aurel.addon().Compat.Chat.Send = function() return false end
		local entry, code = notifier:Send()
		isNil(entry); eq(code, "SEND_FAILED")
		c.Aurel.addon().Compat.Chat.Send = send
		eq(notifier:Wait(), 0)
		truthy(notifier:Send())
	end)

	it("writes in the language of the player who clicks, with the guild's wording when the rules carry one", function()
		local net, c = scenario({ locale = "itIT" })
		local notifier = c.Aurel.addon().ReadinessNotifier
		assert(notifier:Send())
		net:Advance(5)
		local whispers = chat(c.Aurel, "WHISPER")
		eq(whispers[1].message, "[FDCP] Ti manca: incantamento polsi; pozioni 0/2")
		eq(chat(c.Aurel, "RAID")[1].message, "[FDCP] Preparazione: 2 con mancanze, 0 con scorte basse, 1 ignoti. Controllate i sussurri.")
		-- the guild's wording
		local net2, c2 = scenario()
		local n2 = c2.Aurel.addon().ReadinessNotifier
		local rules = c2.Aurel.addon().Readiness.DefaultConfig()
		rules.texts.whisper = "{name}, fix: {list}"
		c2.Aurel.addon().ReadinessCheck.Rules = function() return rules end
		assert(n2:Send())
		net2:Advance(5)
		eq(chat(c2.Aurel, "WHISPER")[1].message, "[FDCP] Corin, fix: enchant wrist; potions 0/2")
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- The tab

local function snap(class, opts)
	opts = opts or {}
	local slots = { [5] = "YES", [8] = "YES", [9] = opts.wrist or "YES", [10] = "YES", [15] = "YES", [16] = "YES" }
	return { class = class, slots = slots, buffs = { WELL_FED = true, FLASK = true }, buffsKnown = true,
		counts = { FOOD_BUFF = 3, FOOD = 20, WATER = 20, POTION = opts.potions or 5, FLASK = 2, AMMO = 2000, PET_FOOD = 20 } }
end

local function raidWith(names, myRank)
	local members = {}
	for i, n in ipairs(names) do members[i] = { name = n, class = "WARRIOR" } end
	Mock.guild.Set{ name = "Dragons", ranks = RANKS, myRank = myRank, members = { { name = "Aurel", rank = myRank }, { name = "Bryn", rank = 3 } } }
	Mock.group.Set{ raid = true, members = members }
	Mock.Advance(3)
end

local function open()
	Mock.Slash("/fdcp")
	FDCP.MainWindow:SelectTab("roster")
	FDCP.RosterWindow:Refresh()
	return FDCP.ReadinessPanel
end

-- The player's own snapshot comes back at once from the mock client's empty bags (everything missing): a ready one replaces it.
local function selfReady()
	FDCP.Bus:Emit("READINESS_REPLY", snap("WARRIOR"), full("Aurel"), FDCP.ReadinessCheck.request.q)
end

local function cells(panel, i)
	local rows = panel.root.table:VisibleRows()
	local r = rows[i]
	local out = {}
	for ci, fs in ipairs(r.cells) do out[ci] = fs:GetText() end
	return out
end

describe("the readiness tab", function()
	before_boot(function(M) M.player.name, M.player.realm = "Aurel", REALM end)

	it("is there for who may ask the raid and for nobody else", function()
		raidWith({ "Bryn", "Corin" }, 1)
		local panel = open()
		local seg = FDCP.RosterWindow.root.sub
		truthy(seg.buttons.readiness:IsShown())
		truthy(FDCP.RosterWindow:SelectSub("readiness"))
		truthy(FDCP.RosterWindow.root.panes.readiness:IsShown())
		-- the right goes away: the sub-tab goes away and the pane is left
		FDCP.ReadinessCheck.CanManage = function() return false, "RANK_TOO_LOW" end
		FDCP.RosterWindow:Refresh()
		falsy(seg.buttons.readiness:IsShown())
		eq(FDCP.RosterWindow:ActiveSub(), "pool")
		truthy(panel.root.empty:GetText():find("officers"))
	end)

	it("outside a raid says so and keeps the buttons off", function()
		Mock.guild.Set{ name = "Dragons", ranks = RANKS, myRank = 1, members = { { name = "Aurel", rank = 1 } } }
		Mock.Advance(3)
		local panel = open()
		FDCP.RosterWindow:SelectSub("readiness")
		panel:Refresh()
		eq(panel.root.empty:GetText(), "Join a raid group to check its readiness.")
		falsy(panel.root.ask:IsEnabled()); falsy(panel.root.notify:IsEnabled())
	end)

	it("one row per raid member: the worst first, the missing enchants named, each category with have/need, the reasons", function()
		raidWith({ "Bryn", "Corin", "Dara", "Edda" }, 1)
		local panel = open()
		FDCP.RosterWindow:SelectSub("readiness")
		local rc = FDCP.ReadinessCheck
		eq(panel.root.message:GetText(), "Press Check to ask every raider for their enchants and consumables.")
		click(panel.root.ask)
		eq(panel.root.message:GetText(), "Asked the raid: the answers arrive in a few seconds.")
		local q = rc.request.q
		selfReady()
		FDCP.Bus:Emit("READINESS_REPLY", snap("WARRIOR"), full("Bryn"), q)
		FDCP.Bus:Emit("READINESS_REPLY", snap("WARRIOR", { wrist = "NO", potions = 1 }), full("Corin"), q)
		FDCP.Bus:Emit("READINESS_REPLY", snap("MAGE", { potions = 0 }), full("Dara"), q)
		local rows = panel.root.table:VisibleRows()
		eq(#rows, 5, "the player is in the raid too")
		-- Corin and Dara are MISSING, Edda waits (UNKNOWN), Aurel and Bryn are OK
		local first, second = cells(panel, 1), cells(panel, 2)
		eq(first[1], "Corin"); eq(first[2], "Missing"); eq(first[3], "wrist")
		eq(second[1], "Dara")
		-- category cells: potions 1/2 for Corin (WARN counts as a category cell), OK elsewhere, "-" where not required
		local order = panel.CATEGORIES
		local function cell(i, cat) for ci, c in ipairs(order) do if c == cat then return cells(panel, i)[3 + ci] end end end
		eq(cell(1, "POTION"), "1/2")
		eq(cell(1, "FLASK"), "OK")
		eq(cell(1, "AMMO"), "-", "a warrior needs no ammunition")
		eq(cell(2, "POTION"), "0/2")
		eq(cell(2, "WATER"), "OK")
		-- the summary and the counts
		eq(panel.root.summary:GetText(), "2 ok · 0 warn · 2 missing · 1 unknown")
		eq(panel.root.counts:GetText(), "4/5 answered")
		-- a row without an answer shows why
		local silent
		for i = 1, #rows do if cells(panel, i)[1] == "Edda" then silent = cells(panel, i) end end
		eq(silent[2], "Unknown"); eq(silent[3], "waiting for an answer")
		Mock.Advance(rc.TIMEOUT + 1)
		for i = 1, #rows do if cells(panel, i)[1] == "Edda" then silent = cells(panel, i) end end
		eq(silent[3], "no answer")
	end)

	it("refreshes at every answer and counts the wait of the Check button down", function()
		raidWith({ "Bryn" }, 1)
		local panel = open()
		FDCP.RosterWindow:SelectSub("readiness")
		click(panel.root.ask)
		eq(panel.root.ask.label:GetText(), "Check (30s)")
		falsy(panel.root.ask:IsEnabled())
		click(panel.root.ask)
		Mock.Advance(10)
		eq(panel.root.ask.label:GetText(), "Check (20s)")
		Mock.Advance(21)
		eq(panel.root.ask.label:GetText(), "Check the raid")
		truthy(panel.root.ask:IsEnabled())
		FDCP.Bus:Emit("READINESS_REPLY", snap("WARRIOR"), full("Bryn"), FDCP.ReadinessCheck.request.q)
		eq(panel.root.counts:GetText(), "2/2 answered", "the player's own snapshot and Bryn's")
	end)

	it("the refusal codes become messages", function()
		local E = FDCP.ReadinessPanel.ErrorText
		eq(E("TOO_SOON", 12.2), "Wait 13 more seconds before asking again.")
		eq(E("THROTTLED", 40), "Wait 40 more seconds before the next notice.")
		eq(E("NOT_IN_RAID"), "You are not in a raid group.")
		eq(E("RANK_TOO_LOW"), "Your guild rank cannot do this.")
		eq(E("DISABLED"), "The readiness check is turned off in the rules.")
		eq(E("ODD"), "Not possible now (ODD).")
	end)

	it("Notify asks first, then sends; Cancel sends nothing; the button shows the wait", function()
		raidWith({ "Bryn", "Corin" }, 1)
		local panel = open()
		FDCP.RosterWindow:SelectSub("readiness")
		click(panel.root.notify)
		eq(panel.root.message:GetText(), "Check the raid first.")
		click(panel.root.ask)
		local q = FDCP.ReadinessCheck.request.q
		selfReady()
		FDCP.Bus:Emit("READINESS_REPLY", snap("WARRIOR"), full("Bryn"), q)
		FDCP.Bus:Emit("READINESS_REPLY", snap("WARRIOR", { wrist = "NO" }), full("Corin"), q)
		click(panel.root.notify)
		truthy(panel.root.confirm:IsShown())
		eq(panel.root.confirm.text:GetText(), "Write 2 lines in /raid and whisper 1 players?")
		eq(#Mock.chat.messages, 0, "nothing before the confirmation")
		click(panel.root.confirm.no)
		falsy(panel.root.confirm:IsShown())
		eq(#Mock.chat.messages, 0)
		click(panel.root.notify)
		click(panel.root.confirm.yes)
		falsy(panel.root.confirm:IsShown())
		eq(panel.root.message:GetText(), "Notice on its way: 2 lines in /raid, 1 whispers.")
		Mock.Advance(3)
		eq(#Mock.chat.messages, 3)
		eq(Mock.chat.messages[3].message, "[FDCP] Missing: enchant wrist")
		eq(Mock.chat.messages[3].target, full("Corin"))
		eq(panel.root.notify.label:GetText(), "Notify (297s)")
		falsy(panel.root.notify:IsEnabled())
		click(panel.root.notify)
		eq(panel.root.message:GetText(), "Wait 297 more seconds before the next notice.")
	end)

	it("during a boss fight the confirmed notice waits and says so", function()
		raidWith({ "Bryn", "Corin" }, 1)
		local panel = open()
		FDCP.RosterWindow:SelectSub("readiness")
		click(panel.root.ask)
		selfReady()
		FDCP.Bus:Emit("READINESS_REPLY", snap("WARRIOR", { wrist = "NO" }), full("Corin"), FDCP.ReadinessCheck.request.q)
		Mock.encounter.Start(601, "Boss")
		click(panel.root.notify)
		click(panel.root.confirm.yes)
		eq(panel.root.message:GetText(), "The chat is busy: 2 lines in /raid and 1 whispers will leave after it.")
		eq(#Mock.chat.messages, 0)
		Mock.encounter.End(601, "Boss", true)
		Mock.Advance(4)
		eq(#Mock.chat.messages, 3)
	end)
end)

describe("the readiness tab for a plain raider", function()
	before_boot(function(M) M.player.name, M.player.realm = "Aurel", REALM end)

	it("is not shown to a rank without the permission", function()
		raidWith({ "Bryn", "Corin" }, 3)
		open()
		falsy(FDCP.RosterWindow.root.sub.buttons.readiness:IsShown())
		local q, code = FDCP.ReadinessCheck:Request()
		isNil(q); eq(code, "RANK_TOO_LOW")
		local entry, why = FDCP.ReadinessNotifier:Send()
		isNil(entry); eq(why, "RANK_TOO_LOW")
	end)
end)
