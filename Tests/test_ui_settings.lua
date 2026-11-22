-- The Settings tab (M7-2): UI/Windows/Settings.lua and RulesForm.lua over App/SettingsController.lua and Domain/RuleFields.lua.
-- Everybody sees the rules and the permissions; only the Guild Master (rank index 0) changes them, from the window or any other
-- way: a non-GM gets "NOT_GM" before an event is built, and a forged CONFIG_CHANGED / PERMISSIONS_CHANGED that reaches the ledger
-- from a peer is refused by the trust gate. With a season open a change needs the explicit confirmation of the dialog.
local function Lg() return FDCP.Ledger end
local function NC() return FDCP.NightController end
local function SC() return FDCP.SettingsController end
local function SW() return FDCP.SettingsWindow end
local function RF() return FDCP.RuleFields end
local function PS() return FDCP.PermissionService end

local RANKS = { [0] = "Guild Master", "Officer", "Veteran", "Raider", "Initiate" }
local MC = 409

local function guild(myRank)
	return function(Mock)
		Mock.guild.Set({ name = "Keepers", ranks = RANKS, myRank = myRank, members = {
			{ name = "Aurel", rank = 0 }, { name = "Bryn", rank = 1 }, { name = "Corin", rank = 3 },
		} })
	end
end

local function bound()
	local L = Lg().New()
	NC():Bind(L)
	Mock.Advance(3)
	return L
end

local function click(b) b:GetScript("OnClick")(b) end

local function count(L, t)
	local n = 0
	for _, e in pairs(L.events) do if e.type == t then n = n + 1 end end
	return n
end

local function last(L, t)
	local best
	for _, e in pairs(L.events) do
		if e.type == t and (not best or Lg().Before(best, e)) then best = e end
	end
	return best
end

local function open(sub)
	Mock.Slash("/fdcp")
	FDCP.MainWindow:SelectTab("settings")
	SW().root.sub:Select(sub or "personal")
	SW():Refresh()
	return SW().root
end

-- The row of a page of the rules form whose field is `id`.
local function rowOf(form, id)
	for i, f in ipairs(form.fields) do
		if f.id == id then return form.rows[i], f end
	end
	error("no field " .. id)
end

local function openSeason(L)
	assert(FDCP.Season.Open(L, { author = NC():Me(), ts = 1, season = "S1", label = "Season 1",
		instances = { { id = MC, size = 40 } } }))
end

describe("the form of the rules", function()
	before_boot(guild(0))

	it("has a field for every value the guild edits and each one reads and writes the default rules", function()
		local rules = FDCP.Rules.DefaultConfig()
		for _, f in ipairs(RF().LIST) do
			local v = RF().Get(rules, f)
			truthy(v ~= nil, f.id .. " reads")
			for _, key in ipairs(f.keys) do truthy(FDCP.L[key] ~= key, key .. " has a text") end
			truthy(RF().Set(rules, f, v), f.id .. " writes")
		end
		deepEq(FDCP.Rules.Diff(rules, FDCP.Rules.DefaultConfig()), {}, "reading then writing changes nothing")
		truthy(FDCP.Rules.Validate(rules))
	end)

	it("covers every section of the rules, the ones that had no window included", function()
		local seen = {}
		for _, f in ipairs(RF().LIST) do seen[f.path[1]] = true end
		for _, section in ipairs(FDCP.Rules.SECTIONS) do truthy(seen[section], section) end
		for _, page in ipairs(RF().PAGES) do truthy(#RF().Page(page) > 0, page) end
	end)

	it("parses what the player types", function()
		local cost = RF().Field("cost.matrix.weapon.5")
		eq(RF().Parse(cost, "council", "Council"), "council")
		eq(RF().Parse(cost, "Consiglio", "consiglio"), "council")
		eq(RF().Parse(cost, "2,5"), 2.5)
		local n, code = RF().Parse(cost, "abc"); isNil(n); eq(code, "NUMBER")
		n, code = RF().Parse(cost, "-1"); isNil(n); eq(code, "RANGE")
		local roll = RF().Field("session.rollSeconds")
		n, code = RF().Parse(roll, "12.5"); isNil(n); eq(code, "INT")
		n, code = RF().Parse(roll, "2"); isNil(n); eq(code, "RANGE")
		eq(RF().Parse(roll, " 45 "), 45)
		local text = RF().Field("notice.text")
		n, code = RF().Parse(text, ("x"):rep(121)); isNil(n); eq(code, "TEXT")
		deepEq(RF().SplitNames(" Aurel, Bryn ,, "), { "Aurel", "Bryn" })
	end)

	it("keeps a response list and a tie-break as codes", function()
		local rules = FDCP.Rules.DefaultConfig()
		local tie = RF().Field("priority.tieBreak")
		eq(RF().Get(rules, tie), "roll,reroll")
		RF().Set(rules, tie, "")
		deepEq(rules.priority.tieBreak, {})
		truthy(FDCP.Rules.Validate(rules))
		local tmog = RF().Field("priority.responses.TMOG.enabled")
		eq(RF().Get(rules, tmog), false)
		RF().Set(rules, tmog, true)
		isNil(rules.priority.responses.TMOG.enabled, "enabled is the absence of the flag")
		eq(RF().Get(rules, tmog), true)
		truthy(FDCP.Rules.Validate(rules))
		RF().Set(rules, tmog, false)
		eq(rules.priority.responses.TMOG.enabled, false)
	end)
end)

describe("the Settings tab for the Guild Master", function()
	before_boot(guild(0))

	it("has the sub-tabs of the spec in order and opens on Personal", function()
		bound()
		local root = open()
		deepEq(SW().SUBTABS, { "personal", "rules", "permissions", "site", "season" })
		eq(root.sub:Active(), "personal")
		for id, pane in pairs(root.panes) do eq(pane:IsShown(), id == "personal", id) end
		for _, id in ipairs(SW().SUBTABS) do
			truthy(root.sub:Select(id)); truthy(root.panes[id]:IsShown(), id)
		end
	end)

	it("changes the personal preferences without asking anybody", function()
		bound()
		local root = open("personal")
		local c = root.panes.personal.controls
		c.effects:SetOn(false)
		eq(FDCP.Config:Get("effects"), false)
		c.animations:SetOn(false)
		eq(FDCP.Config:Get("animations"), false)
		c.sounds:SetOn(false)
		eq(FDCP.Config:Get("sounds"), false)
		c.theme:Select("aurora")
		eq(FDCP.Config:Get("theme"), "aurora"); eq(FDCP.Theme.Current(), "aurora")
		c.fontSource:Select("game")
		eq(FDCP.Config:Get("fontSource"), "game")
		c.guildLanguage:Select("itIT")
		eq(FDCP.Config:Get("guildLanguage"), "itIT")
		c.language:Select("itIT")
		eq(FDCP.Config:GetLanguage(), "itIT")
		eq(root.panes.personal.card.message:GetText(), "Language set to itIT. Type /reload to apply it.")
		c.language:Select("auto")
		SW():Refresh()
		eq(c.theme:Selected(), "aurora"); eq(c.effects:IsOn(), false)
	end)

	it("resets the popup's place and the sound follows the preference", function()
		bound()
		local root = open("personal")
		FDCP.Config.char.popup = { point = "TOP", x = 5, y = 5, w = 500 }
		click(root.panes.personal.controls.popup)
		isNil(FDCP.Config.char.popup)
		local played = {}
		_G.PlaySound = function(id) played[#played + 1] = id; return 1 end
		truthy(FDCP.MemberLootPopup:Chime(), "plays by default")
		eq(#played, 1)
		FDCP.Config:Set("sounds", false)
		falsy(FDCP.MemberLootPopup:Chime(), "silent when off")
		eq(#played, 1)
	end)

	it("clears the personal wishlist only after a confirmation", function()
		bound()
		local root = open("personal")
		FDCP.PersonalUpgrade.WishAdd(19019)
		SW():Refresh()
		eq(root.panes.personal.card.wishCount:GetText(), "1 items")
		click(root.panes.personal.controls.wishClear)
		truthy(SW().dialog:IsShown())
		eq(#FDCP.PersonalUpgrade.WishList(), 1)
		click(SW().dialog.cancel)
		eq(#FDCP.PersonalUpgrade.WishList(), 1)
		click(root.panes.personal.controls.wishClear)
		click(SW().dialog.confirm)
		eq(#FDCP.PersonalUpgrade.WishList(), 0)
	end)

	it("edits the rules from the form: no season open, the write needs no confirmation", function()
		local L = bound()
		open("rules")
		local form = SW().rules
		eq(form.page, "session"); truthy(form.editable)
		truthy(form.card.save:IsShown())
		local row = rowOf(form, "session.awardMode")
		row.select:Select("council")
		eq(form.card.message:GetText(), "1 changes not saved yet.")
		eq(FDCP.Rules.Current(L).session.awardMode, "confirm", "nothing written yet")
		click(form.card.save)
		eq(count(L, "CONFIG_CHANGED"), 1)
		eq(FDCP.Rules.Current(L).session.awardMode, "council")
		isNil(Lg().Payload(last(L, "CONFIG_CHANGED")).confirmed)
		eq(form.card.message:GetText(), "Saved.")
	end)

	it("a number typed is checked at once; a wrong one never reaches the draft or the ledger", function()
		local L = bound()
		open("rules")
		local form = SW().rules
		local row = rowOf(form, "session.rollSeconds")
		Mock.TypeInto(row.edit.edit, "abc")
		eq(form.card.message:GetText(), "That is not a number.")
		click(form.card.save)
		eq(form.card.message:GetText(), "That is not a number.")
		eq(count(L, "CONFIG_CHANGED"), 0)
		Mock.TypeInto(row.edit.edit, "45")
		click(form.card.save)
		eq(FDCP.Rules.Current(L).session.rollSeconds, 45)
		eq(count(L, "CONFIG_CHANGED"), 1)
	end)

	it("shows the cost matrix in three columns and writes a legendary cell as the council's", function()
		local L = bound()
		open("rules")
		local form = SW().rules
		form.list:Select("costs")
		eq(form.page, "costs"); eq(#form.fields, 22)
		local weapon4 = rowOf(form, "cost.matrix.weapon.4")
		local weapon5 = rowOf(form, "cost.matrix.weapon.5")
		eq(weapon4.edit:GetText(), "2"); eq(weapon5.edit:GetText(), "Council")
		Mock.TypeInto(weapon4.edit.edit, "3")
		Mock.TypeInto(weapon5.edit.edit, "6")
		click(form.card.save)
		local cost = FDCP.Rules.Current(L).cost
		eq(cost.matrix.weapon[4], 3); eq(cost.matrix.weapon[5], 6)
		form.list:Select("multipliers"); form.list:Select("costs")
		eq(weapon5.edit:GetText(), "6")
	end)

	it("edits the wording of the messages, the council, the upgrade rule and the site key", function()
		local L = bound()
		open("rules")
		local form = SW().rules
		form.list:Select("messages")
		Mock.TypeInto(rowOf(form, "notice.text").edit.edit, "Get {addon} at {link}: {names}")
		rowOf(form, "announce.reason").switch:SetOn(false)
		form.list:Select("council")
		Mock.TypeInto(rowOf(form, "council.members").edit.edit, "Aurel-Test, Bryn-Test")
		form.list:Select("upgrade")
		Mock.TypeInto(rowOf(form, "upgrade.bigThreshold").edit.edit, "3")
		click(form.card.save)
		local rules = FDCP.Rules.Current(L)
		eq(rules.notice.text, "Get {addon} at {link}: {names}")
		eq(rules.announce.reason, false)
		deepEq(rules.council.members, { "Aurel-Test", "Bryn-Test" })
		eq(rules.upgrade.bigThreshold, 3)
		eq(count(L, "CONFIG_CHANGED"), 1, "all the pages are one change")
		-- the site page is its own sub-tab
		SW().root.sub:Select("site")
		local site = SW().site
		Mock.TypeInto(rowOf(site, "site.factionName").edit.edit, "Horde")
		click(site.card.save)
		eq(FDCP.Rules.Current(L).site.factionName, "Horde")
	end)

	it("picks who sets the label of a response (M7-2b): suggest by default, and the choice is the Guild Master's alone", function()
		local L = bound()
		open("rules")
		local form = SW().rules
		form.list:Select("priority")
		local row = rowOf(form, "responses.labelMode")
		eq(row.select:Selected(), "suggest")
		eq(row.label:GetText(), "Label of a main-spec response")
		row.select:Select("auto")
		click(form.card.save)
		eq(FDCP.Rules.Current(L).responses.labelMode, "auto")
		eq(count(L, "CONFIG_CHANGED"), 1)
		row.select:Select("manual")
		click(form.card.save)
		eq(FDCP.Rules.Current(L).responses.labelMode, "manual")
	end)

	it("an invalid combination is refused with the field named and the page opened", function()
		local L = bound()
		open("rules")
		local form = SW().rules
		form.list:Select("upgrade")
		Mock.TypeInto(rowOf(form, "upgrade.smallThreshold").edit.edit, "5")   -- above the big threshold
		form.list:Select("session")
		click(form.card.save)
		eq(form.page, "upgrade")
		eq(form.card.message:GetText(), "Not saved: \"Small upgrade from\" is not valid.")
		eq(count(L, "CONFIG_CHANGED"), 0)
	end)

	it("with a season open it asks for the confirmation, lists the changes and keeps it in the ledger", function()
		local L = bound()
		openSeason(L)
		open("rules")
		local form = SW().rules
		rowOf(form, "session.awardMode").select:Select("auto")
		click(form.card.save)
		truthy(SW().dialog:IsShown())
		eq(SW().dialog.title:GetText(), "Change the rules of a season in progress?")
		truthy(SW().dialog.body:GetText():find("Award", 1, true))
		eq(count(L, "CONFIG_CHANGED"), 0, "nothing written before the confirmation")
		click(SW().dialog.cancel)
		eq(count(L, "CONFIG_CHANGED"), 0)
		falsy(SW().dialog:IsShown())
		click(form.card.save)
		click(SW().dialog.confirm)
		eq(count(L, "CONFIG_CHANGED"), 1)
		eq(Lg().Payload(last(L, "CONFIG_CHANGED")).confirmed, true, "the confirmation is audited")
		eq(FDCP.Rules.Current(L).session.awardMode, "auto")
		-- the controller itself never skips the confirmation
		local rules = FDCP.Rules.Current(L)
		rules.session.rollSeconds = 50
		local e, why = SC():ApplyRules(rules)
		isNil(e); eq(why, "CONFIRM_REQUIRED")
	end)

	it("a draft not saved goes away with Discard changes", function()
		local L = bound()
		open("rules")
		local form = SW().rules
		local row = rowOf(form, "session.awardMode")
		row.select:Select("council")
		click(form.card.revert)
		eq(row.select:Selected(), "confirm")
		eq(form.card.message:GetText(), "")
		click(form.card.save)
		eq(form.card.message:GetText(), "Nothing changed.")
		eq(count(L, "CONFIG_CHANGED"), 0)
	end)

	it("edits the permissions by rank; the two fixed ones stay with the Guild Master", function()
		local L = bound()
		open("permissions")
		local pane = SW().permissionsPane
		local byPerm = {}
		for _, row in ipairs(pane.rows) do byPerm[row.permission] = row end
		eq(#pane.rows, 12)
		falsy(byPerm["config.rules"].select:IsEnabled()); falsy(byPerm["config.permissions"].select:IsEnabled())
		truthy(byPerm["night.run"].select:IsEnabled())
		eq(byPerm["night.run"].select:Selected(), 1)
		eq(#byPerm["night.run"].select.choices, 5, "every rank of the guild")
		eq(byPerm["night.run"].select.choices[2].text, "1 · Officer")
		byPerm["credits.adjust"].select:Select(1)
		click(pane.card.save)
		eq(count(L, "PERMISSIONS_CHANGED"), 1)
		eq(FDCP.Permissions.Current(L)["credits.adjust"], 1)
		isNil(Lg().Payload(last(L, "PERMISSIONS_CHANGED")).confirmed)
		eq(PS():Can("credits.adjust", "Bryn-TestRealm", L), true, "the officers hold it now")
	end)

	it("with a season open the permissions ask for the confirmation too", function()
		local L = bound()
		openSeason(L)
		open("permissions")
		local pane = SW().permissionsPane
		for _, row in ipairs(pane.rows) do
			if row.permission == "night.run" then row.select:Select(2) end
		end
		click(pane.card.save)
		truthy(SW().dialog:IsShown())
		truthy(SW().dialog.body:GetText():find("Run a night: 1 · Officer -> 2 · Veteran", 1, true))
		eq(count(L, "PERMISSIONS_CHANGED"), 0)
		click(SW().dialog.confirm)
		eq(count(L, "PERMISSIONS_CHANGED"), 1)
		eq(Lg().Payload(last(L, "PERMISSIONS_CHANGED")).confirmed, true)
		local t, why = SC():ApplyPermissions(FDCP.Permissions.DefaultTable())
		isNil(t); eq(why, "CONFIRM_REQUIRED")
	end)

	it("the Guild Master reviews a change of the guild's ranks and closes it", function()
		bound()
		open("permissions")
		local pane = SW().permissionsPane
		Mock.guild.SetRankNames({ [0] = "Guild Master", "Veteran", "Officer", "Raider", "Initiate" }, { [1] = 2, [2] = 1 })
		Mock.Advance(3)
		truthy(pane.card.review:IsShown()); truthy(pane.card.reviewDone:IsShown())
		truthy(pane.card.review:GetText():find("reordered", 1, true))
		truthy(SC():RankReview())
		click(pane.card.reviewDone)
		isNil(PS():RankReview())
		falsy(pane.card.review:IsShown())
		eq(pane.card.message:GetText(), "Thanks: the review is closed.")
	end)
end)

describe("the Settings tab for an officer", function()
	before_boot(guild(1))

	it("sees the rules read-only: controls off, no buttons, the note says who can change them", function()
		local L = bound()
		open("rules")
		local form = SW().rules
		falsy(form.editable)
		falsy(form.card.save:IsShown()); falsy(form.card.revert:IsShown())
		eq(form.card.note:GetText(), "Only the Guild Master can change these settings. You see them as they are.")
		local row = rowOf(form, "session.awardMode")
		falsy(row.select:IsEnabled())
		eq(row.select:Selected(), "confirm", "the rules are shown as they are")
		falsy(rowOf(form, "session.autoAdvance").switch:IsEnabled())
		-- a forced click or a forced edit changes nothing
		row.select:Select("council")
		eq(form.draft.session.awardMode, "confirm", "a forced edit does not reach the draft")
		click(form.card.save)
		eq(form.card.message:GetText(), "Only the Guild Master can change the rules and the permissions.")
		eq(count(L, "CONFIG_CHANGED"), 0)
		form:OnSave()
		eq(count(L, "CONFIG_CHANGED"), 0)
	end)

	it("sees the permissions read-only and cannot save them", function()
		local L = bound()
		open("permissions")
		local pane = SW().permissionsPane
		falsy(pane.card.save:IsShown())
		for _, row in ipairs(pane.rows) do falsy(row.select:IsEnabled(), row.permission) end
		SW():OnRankPicked("night.run", 4)
		SW():OnSavePermissions()
		eq(pane.card.message:GetText(), "Only the Guild Master can change the rules and the permissions.")
		eq(count(L, "PERMISSIONS_CHANGED"), 0)
		falsy(pane.card.review:IsShown(), "the rank review is the Guild Master's")
	end)

	it("the controller refuses an officer before any event is built", function()
		local L = bound()
		local rules = FDCP.Rules.DefaultConfig()
		rules.session.rollSeconds = 99
		local e, why = SC():ApplyRules(rules, { confirmed = true })
		isNil(e); eq(why, "NOT_GM")
		local t = FDCP.Permissions.DefaultTable()
		t["night.run"] = 3
		e, why = SC():ApplyPermissions(t, { confirmed = true })
		isNil(e); eq(why, "NOT_GM")
		eq(count(L, "CONFIG_CHANGED") + count(L, "PERMISSIONS_CHANGED"), 0)
		local ok, code = SC():AcknowledgeRankReview()
		falsy(ok); eq(code, "NOT_GM")
	end)

	it("an officer cannot change who sets the label (M7-2b): a click, the controller and a forged event are all refused", function()
		local L = bound()
		open("rules")
		local form = SW().rules
		form.list:Select("priority")
		local row = rowOf(form, "responses.labelMode")
		falsy(row.select:IsEnabled())
		eq(row.select:Selected(), "suggest", "an officer sees the rule")
		local rules = FDCP.Rules.DefaultConfig()
		rules.responses.labelMode = "auto"
		local e, why = SC():ApplyRules(rules, { confirmed = true })
		isNil(e); eq(why, "NOT_GM")
		e, why = FDCP.Rules.Change(L, { author = "Bryn-TestRealm", ts = 10, rules = rules }, PS():Gate())
		isNil(e); eq(why, "NOT_GM")
		eq(FDCP.Rules.Current(L).responses.labelMode, "suggest")
	end)

	it("a forged change by the officer is refused by the trust gate, here and when it arrives from a peer", function()
		local L = bound()
		local rules = FDCP.Rules.DefaultConfig()
		rules.session.rollSeconds = 99
		local e, why = FDCP.Rules.Change(L, { author = "Bryn-TestRealm", ts = 10, rules = rules }, PS():Gate())
		isNil(e); eq(why, "NOT_GM")
		local t = FDCP.Permissions.DefaultTable()
		t["credits.adjust"] = 3
		e, why = FDCP.Permissions.Change(L, { author = "Bryn-TestRealm", ts = 10, table = t }, PS():Gate())
		isNil(e); eq(why, "NOT_GM")
		-- the events as a peer would send them (built without a gate in a ledger of its own)
		local forged = Lg().New()
		local cfg = assert(FDCP.Rules.Change(forged, { author = "Bryn-TestRealm", ts = 10, rules = rules }))
		local perm = assert(FDCP.Permissions.Change(forged, { author = "Bryn-TestRealm", ts = 11, table = t }))
		local report = PS():Merge(L, { cfg, perm })
		eq(report.added, 0)
		eq(#report.refused, 2)
		eq(report.refused[1].code, "NOT_GM"); eq(report.refused[2].code, "NOT_GM")
		eq(FDCP.Rules.Current(L).session.rollSeconds, 30)
		eq(FDCP.Permissions.Current(L)["credits.adjust"], 0)
	end)

	it("keeps the personal preferences free", function()
		bound()
		local root = open("personal")
		root.panes.personal.controls.animations:SetOn(false)
		eq(FDCP.Config:Get("animations"), false)
	end)
end)

describe("the Settings tab for a raider and without a guild", function()
	before_boot(guild(3))

	it("a raider sees the rules and the permissions but cannot change them", function()
		local L = bound()
		local root = open("rules")
		falsy(SW().rules.editable)
		falsy(SW().rules.card.save:IsShown())
		root.sub:Select("site")
		falsy(SW().site.editable); falsy(SW().site.card.save:IsShown())
		root.sub:Select("permissions")
		falsy(SW().permissionsPane.card.save:IsShown())
		local e, why = SC():ApplyRules(FDCP.Rules.DefaultConfig(), { confirmed = true })
		isNil(e); eq(why, "NOT_GM")
		eq(count(L, "CONFIG_CHANGED"), 0)
	end)
end)

describe("the Settings tab without a guild", function()
	before_boot(function() end)

	it("builds, keeps the personal preferences and writes nothing else", function()
		local root = open("personal")
		root.panes.personal.controls.effects:SetOn(false)
		eq(FDCP.Config:Get("effects"), false)
		root.sub:Select("rules")
		falsy(SW().rules.editable)
		local e, why = SC():ApplyRules(FDCP.Rules.DefaultConfig(), { confirmed = true })
		isNil(e); eq(why, "NOT_READY")
		root.sub:Select("permissions")
		root.sub:Select("season")
	end)
end)

describe("the game's settings window", function()
	before_boot(guild(0))

	it("offers the personal switches and a button that opens the addon's tab", function()
		bound()
		local options = SC():GameOptions()
		eq(options.type, "group"); eq(options.name, "Finland Dragon Credit Points")
		options.args.effects.set(nil, false)
		eq(FDCP.Config:Get("effects"), false)
		eq(options.args.effects.get(), false)
		options.args.sounds.set(nil, false)
		eq(FDCP.Config:Get("sounds"), false)
		options.args.open.func()
		truthy(FDCP.MainWindow:IsShown()); eq(FDCP.MainWindow:ActiveTab(), "settings")
	end)

	it("registers once and never raises, whatever the client does", function()
		truthy(pcall(function() SC():RegisterGameOptions() end))
		truthy(pcall(function() SC():RegisterGameOptions() end))
	end)
end)
