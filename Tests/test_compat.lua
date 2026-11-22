-- Compat (M1-3): the only door to the game API. Every area is tested on the mock client, and every unverified API is
-- tested for degradation: missing, erroring or secret, nothing may raise (docs/roadmap/M1-foundations.md, M1-3).
-- `Compat` is the addon's module (FDCP.Compat); the game's globals are plain globals here (read them inside the test).

local function compat() return FDCP.Compat end

local ITEM_A = "|cffa335ee|Hitem:1001::::::::60:::::|h[Crown of Embers]|h|r"
local ITEM_B = "|cffa335ee|Hitem:1002::::::::60:::::|h[Helm of Frost]|h|r"

local function addItems()
	Mock.items.Add{ id = 1001, link = ITEM_A, name = "Crown of Embers", quality = 4, level = 70, equipLoc = "INVTYPE_HEAD",
		stats = { ITEM_MOD_STRENGTH_SHORT = 40, ITEM_MOD_STAMINA_SHORT = 60 }, specs = { 71, 72 } }
	Mock.items.Add{ id = 1002, link = ITEM_B, name = "Helm of Frost", quality = 4, level = 64, equipLoc = "INVTYPE_HEAD",
		stats = { ITEM_MOD_STRENGTH_SHORT = 30, ITEM_MOD_STAMINA_SHORT = 70 }, specs = { 73 } }
end

describe("guarded calls", function()
	it("Resolve finds nested globals and never raises", function()
		eq(compat().Resolve("C_PartyInfo.GetLootMethod"), C_PartyInfo.GetLootMethod)
		isNil(compat().Resolve("C_Nothing.AtAll"))
		isNil(compat().Resolve(nil))
		isNil(compat().Resolve(""))
	end)

	it("Call reports available, missing, error and restricted", function()
		eq((compat().Call("IsInGroup")), "available")
		eq((compat().Call("NoSuchFunction")), "missing")
		SomethingBroken = function() error("boom") end
		eq((compat().Call("SomethingBroken")), "error")
		SomethingForbidden = function() error("action blocked: restricted") end
		eq((compat().Call("SomethingForbidden")), "restricted")
	end)

	it("a secret result is dropped and the state is restricted", function()
		HiddenThing = function() return Mock.SECRET, 7 end
		local state, a, b = compat().Call("HiddenThing")
		eq(state, "restricted")
		isNil(a)
		eq(b, 7)
	end)

	it("IsSecret and Readable never look inside a secret", function()
		truthy(compat().IsSecret(Mock.SECRET))
		falsy(compat().IsSecret("text"))
		falsy(compat().IsSecret(nil))
		isNil(compat().Readable(Mock.SECRET))
		eq(compat().Readable(5), 5)
	end)

	it("ReadableCopy keeps plain fields and drops secrets and functions", function()
		local copy = compat().ReadableCopy({ a = 1, b = Mock.SECRET, f = function() end, nested = { x = 1, deep = { y = 1 } } })
		deepEq(copy, { a = 1, nested = { x = 1 } })
		isNil(compat().ReadableCopy(Mock.SECRET))
		isNil(compat().ReadableCopy("no"))
	end)
end)

describe("loot method and master looter", function()
	it("reads the method from C_PartyInfo through Enum.LootMethod", function()
		Mock.loot.Set{ method = "master", masterLooter = true }
		eq(compat().Loot.Method(), "master")
		truthy(compat().Loot.IsMasterLootMethod())
		truthy(compat().Loot.IsMasterLooter())
		Mock.loot.Set{ method = "personal", masterLooter = false }
		eq(compat().Loot.Method(), "personal")
		falsy(compat().Loot.IsMasterLootMethod())
		falsy(compat().Loot.IsMasterLooter())
	end)

	it("falls back to the legacy GetLootMethod string when the new API is missing", function()
		C_PartyInfo.GetLootMethod = nil
		isNil(compat().Loot.Method(), "nothing to ask")
		GetLootMethod = function() return "master", 0, 1 end
		local method, party, raid = compat().Loot.Method()
		eq(method, "master")
		eq(party, 0)
		eq(raid, 1)
	end)

	it("an unknown method, a missing enum or an erroring API answer nil", function()
		Enum.LootMethod = nil
		isNil(compat().Loot.Method())
		T.boot()
		C_PartyInfo.GetLootMethod = function() error("boom") end
		isNil(compat().Loot.Method())
	end)

	it("a secret method answer is nil", function()
		C_PartyInfo.GetLootMethod = function() return Mock.SECRET, Mock.SECRET end
		isNil(compat().Loot.Method())
	end)

	it("reads the threshold and the legacy mode", function()
		Mock.loot.Set{ threshold = 3, legacy = true }
		eq(compat().Loot.Threshold(), 3)
		eq(compat().Loot.LegacyMode(), true)
		Mock.loot.Set{ legacy = false }
		eq(compat().Loot.LegacyMode(), false)
		C_Loot.IsLegacyLootModeEnabled = nil
		isNil(compat().Loot.LegacyMode())
		GetLootThreshold = nil
		isNil(compat().Loot.Threshold())
	end)

	it("says whether a method can be chosen, and sets it", function()
		Mock.loot.Set{ legacy = false }
		eq(compat().Loot.MethodAvailable("master"), false)
		eq(compat().Loot.MethodAvailable("group"), true)
		isNil(compat().Loot.MethodAvailable("nonsense"))
		Mock.loot.Set{ legacy = true }
		eq(compat().Loot.SetMethod("master", "Testchar"), "available")
		eq(compat().Loot.Method(), "master")
		eq(compat().Loot.SetMethod("nonsense"), "missing")
		C_PartyInfo.SetLootMethod = nil
		eq(compat().Loot.SetMethod("master", "Testchar"), "missing")
	end)
end)

describe("the loot window and master loot", function()
	local function twoSlots()
		Mock.loot.Set{ method = "master", masterLooter = true, candidates = { "Aurel", "Bryn", "Corin" }, slots = {
			{ link = ITEM_A, name = "Crown of Embers", quantity = 1, quality = 4, sources = { "Creature-0-1-2-3-4567-0000", 1 } },
			{ link = ITEM_B, name = "Helm of Frost", quantity = 2, quality = 3, locked = true, isQuest = true },
		} }
	end

	it("reads every slot with link, quality and source", function()
		twoSlots()
		eq(compat().Loot.NumItems(), 2)
		local slots = compat().Loot.Slots()
		eq(#slots, 2)
		eq(slots[1].link, ITEM_A)
		eq(slots[1].name, "Crown of Embers")
		eq(slots[1].quality, 4)
		eq(slots[1].hasItem, true)
		deepEq(slots[1].sources, { { guid = "Creature-0-1-2-3-4567-0000", quantity = 1 } })
		eq(slots[2].quantity, 2)
		eq(slots[2].locked, true)
		eq(slots[2].isQuestItem, true)
		deepEq(slots[2].sources, {})
	end)

	it("reads the older GetLootSlotInfo shape too", function()
		twoSlots()
		Mock.loot.legacySlotInfo = true
		local s = compat().Loot.Slot(1)
		eq(s.quality, 4)
		eq(s.locked, false)
		eq(compat().Loot.Slot(2).isQuestItem, true)
	end)

	it("an empty slot and a missing window give nothing", function()
		twoSlots()
		isNil(compat().Loot.Slot(9))
		isNil(compat().Loot.Slot("x"))
		Mock.loot.Set{ slots = {} }
		eq(compat().Loot.NumItems(), 0)
		deepEq(compat().Loot.Slots(), {})
	end)

	it("a hidden field does not hide the slot", function()
		twoSlots()
		GetLootSlotInfo = function() return 1, Mock.SECRET, 1, 0, 4, false, false end
		local s = compat().Loot.Slot(1)
		eq(s.link, ITEM_A)
		isNil(s.name)
		eq(s.quality, 4)
	end)

	it("lists the candidates by the index GiveMasterLoot takes", function()
		twoSlots()
		deepEq(compat().Loot.Candidates(1), { { index = 1, name = "Aurel" }, { index = 2, name = "Bryn" }, { index = 3, name = "Corin" } })
		Mock.loot.Set{ masterLooter = false }
		deepEq(compat().Loot.Candidates(1), {}, "not the master looter")
		deepEq(compat().Loot.Candidates("x"), {})
	end)

	it("gives an item to a candidate and says what the client answered", function()
		twoSlots()
		eq(compat().Loot.Give(1, 2), "available")
		deepEq(Mock.loot.given, { { slot = 1, candidate = 2 } })
		eq(compat().Loot.NumItems(), 1)
		eq(compat().Loot.Give("x", 2), "missing")
		GiveMasterLoot = function() error("ADDON_ACTION_FORBIDDEN: blocked") end
		eq(compat().Loot.Give(1, 1), "restricted")
		GiveMasterLoot = nil
		eq(compat().Loot.Give(1, 1), "missing")
	end)

	it("candidates stop at once when the API is missing", function()
		twoSlots()
		GetMasterLootCandidate = nil
		deepEq(compat().Loot.Candidates(1), {})
	end)
end)

describe("the trade window", function()
	it("reads the partner and the items of the open trade", function()
		deepEq(compat().Trade.PlayerItems(), {})
		isNil(compat().Trade.Partner(), "no trade open")
		Mock.trade.Open("Corin", "Otherrealm")
		Mock.trade.Put("player", ITEM_A)
		Mock.trade.Put("target", ITEM_B)
		eq(compat().Trade.Partner(), "Corin-Otherrealm")
		deepEq(compat().Trade.PlayerItems(), { ITEM_A })
		deepEq(compat().Trade.TargetItems(), { ITEM_B })
		Mock.trade.Open("Bryn")
		eq(compat().Trade.Partner(), "Bryn", "a player of the own realm has no realm part")
	end)

	it("knows the client's trade complete message, and never a hidden one", function()
		truthy(compat().Trade.IsCompleteMessage("Trade complete."))
		falsy(compat().Trade.IsCompleteMessage("Trade cancelled."))
		falsy(compat().Trade.IsCompleteMessage(Mock.SECRET))
		falsy(compat().Trade.IsCompleteMessage(nil))
		ERR_TRADE_COMPLETE = nil
		falsy(compat().Trade.IsCompleteMessage("Trade complete."))
	end)

	it("degrades without an error when the APIs are missing", function()
		Mock.trade.Open("Corin")
		GetTradePlayerItemLink, GetTradeTargetItemLink = nil, nil
		deepEq(compat().Trade.PlayerItems(), {})
		deepEq(compat().Trade.TargetItems(), {})
		compat():Probe()
		eq(compat():State("trade.GetTradePlayerItemLink"), "missing")
		eq(compat():State("trade.ERR_TRADE_COMPLETE"), "available")
	end)
end)

describe("rolls and loot messages", function()
	it("builds the roll pattern from the global and parses a result", function()
		local roll = compat().Roll.Parse("Aurel rolls 87 (1-100)")
		deepEq(roll, { player = "Aurel", roll = 87, min = 1, max = 100 })
		isNil(compat().Roll.Parse("Aurel passes"))
		isNil(compat().Roll.Parse(42))
	end)

	it("follows the client's own wording and argument order, in any language", function()
		RANDOM_ROLL_RESULT = "%2$d %1$s (%3$d-%4$d) tira"   -- an invented order: argument positions are respected
		deepEq(compat().Roll.Parse("55 Bryn (1-100) tira"), { player = "Bryn", roll = 55, min = 1, max = 100 })
		RANDOM_ROLL_RESULT = "%s tira %d (%d-%d)"            -- the Italian client
		deepEq(compat().Roll.Parse("Corin tira 12 (1-20)"), { player = "Corin", roll = 12, min = 1, max = 20 })
		RANDOM_ROLL_RESULT = nil
		isNil(compat().Roll.Parse("Corin tira 12 (1-20)"))
	end)

	it("escapes pattern characters of the format", function()
		local pattern = compat().Roll.BuildPattern("%s (50%%) [x] + y?")
		truthy(("Aurel (50%) [x] + y?"):match(pattern))
		isNil(compat().Roll.BuildPattern(nil))
		isNil(compat().Roll.BuildPattern(12))
	end)

	it("a secret message is not looked at, and says so", function()
		local roll, why = compat().Roll.Parse(Mock.SECRET)
		isNil(roll)
		eq(why, "secret")
		local loot, why2 = compat().Roll.ParseLoot(Mock.SECRET)
		isNil(loot)
		eq(why2, "secret")
		isNil(compat().Roll.Match("%s", Mock.SECRET))
	end)

	it("parses the loot messages: others, self, several", function()
		deepEq(compat().Roll.ParseLoot("Aurel receives loot: " .. ITEM_A .. "."), { kind = "LOOT_ITEM", player = "Aurel", link = ITEM_A, count = 1 })
		deepEq(compat().Roll.ParseLoot("You receive loot: " .. ITEM_B .. "."), { kind = "LOOT_ITEM_SELF", link = ITEM_B, count = 1 })
		local multiple = compat().Roll.ParseLoot("Bryn receives loot: " .. ITEM_A .. "x3.")
		eq(multiple.kind, "LOOT_ITEM_MULTIPLE")
		eq(multiple.count, 3)
		eq(multiple.player, "Bryn")
		eq(compat().Roll.ParseLoot("You receive loot: " .. ITEM_A .. "x2.").count, 2)
		isNil(compat().Roll.ParseLoot("something else entirely"))
		LOOT_ITEM, LOOT_ITEM_SELF = nil, nil
		isNil(compat().Roll.ParseLoot("Aurel receives loot: " .. ITEM_A .. "."))
	end)

	it("RandomRoll is called with a valid range and the answer is the system message", function()
		local seen
		local frame = CreateFrame("Frame")
		frame:RegisterEvent("CHAT_MSG_SYSTEM")
		frame:SetScript("OnEvent", function(_, _, text) seen = compat().Roll.Parse(text) end)
		eq(compat().Roll.Send(1, 100), "available")
		deepEq(Mock.loot.rolls, { { lo = 1, hi = 100 } })
		eq(seen.player, "Testchar")
		eq(seen.max, 100)
		eq(compat().Roll.Send(10, 1), "missing", "an upside-down range is refused")
		eq(compat().Roll.Send("a", 2), "missing")
		RandomRoll = nil
		eq(compat().Roll.Send(1, 100), "missing")
	end)

	it("the mock's messages round trip through the parsers", function()
		local got = {}
		local frame = CreateFrame("Frame")
		frame:RegisterEvent("CHAT_MSG_SYSTEM")
		frame:RegisterEvent("CHAT_MSG_LOOT")
		frame:SetScript("OnEvent", function(_, event, text)
			got[#got + 1] = event == "CHAT_MSG_SYSTEM" and compat().Roll.Parse(text) or compat().Roll.ParseLoot(text)
		end)
		Mock.loot.Roll("Aurel", 91, 1, 100)
		Mock.loot.Receive("Bryn", ITEM_A, 1)
		Mock.loot.Receive(nil, ITEM_B, 2)
		eq(got[1].roll, 91)
		eq(got[2].player, "Bryn")
		eq(got[3].count, 2)
		Mock.loot.Set{ secretMessages = true }
		Mock.loot.Roll("Aurel", 91, 1, 100)
		eq(#got, 3, "secret messages produce nothing")
	end)
end)

describe("encounters and the instance", function()
	it("follows IsEncounterInProgress", function()
		falsy(compat().Encounter.InProgress())
		Mock.encounter.Start(1, "Boss")
		truthy(compat().Encounter.InProgress())
		Mock.encounter.End(1, "Boss", true)
		falsy(compat().Encounter.InProgress())
	end)

	it("an error or a hidden answer counts as in progress, a missing function does not", function()
		IsEncounterInProgress = function() error("boom") end
		truthy(compat().Encounter.InProgress())
		IsEncounterInProgress = function() return Mock.SECRET end
		truthy(compat().Encounter.InProgress())
		IsEncounterInProgress = nil
		falsy(compat().Encounter.InProgress())
	end)

	it("describes the instance and the raid difficulty", function()
		Mock.encounter.Set{ raidDifficulty = 15 }
		deepEq(compat().Encounter.Instance(), { name = "Test Raid", type = "raid", difficultyID = 14, difficultyName = "Normal",
			maxPlayers = 20, instanceID = 9001 })
		eq(compat().Encounter.RaidDifficultyID(), 15)
		GetInstanceInfo = nil
		isNil(compat().Encounter.Instance())
		local inside, kind = compat().Encounter.InInstance()
		falsy(inside)
		eq(kind, "none")
		IsInInstance = nil
		inside, kind = compat().Encounter.InInstance()
		falsy(inside)
		isNil(kind)
	end)
end)

describe("chat lockdown and restrictions", function()
	it("sending is allowed when nothing blocks it", function()
		truthy(compat().Chat.CanSend())
		falsy(compat().Chat.InChatLockdown())
		falsy(compat().Chat.OutgoingAddonRestricted())
		isNil(compat().Chat.RestrictionAny())
	end)

	it("the lockdown, the read-only state and every restriction kind stop sending", function()
		Mock.chat.lockdown = true
		falsy(compat().Chat.CanSend())
		Mock.chat.lockdown = false
		Mock.chat.restricted = true
		falsy(compat().Chat.CanSend())
		Mock.chat.restricted = false
		Mock.restrictions.Set{ Encounter = 1 }
		eq(compat().Chat.RestrictionAny(), "Encounter")
		local active, state = compat().Chat.RestrictionActive("Encounter")
		truthy(active)
		eq(state, 1)
		falsy(compat().Chat.CanSend())
		Mock.restrictions.Set{}
		truthy(compat().Chat.CanSend())
	end)

	it("an erroring or hidden lockdown API is the safe side, a missing one is not a block", function()
		C_ChatInfo.InChatMessagingLockdown = function() error("boom") end
		truthy(compat().Chat.InChatLockdown())
		C_ChatInfo.InChatMessagingLockdown = function() return Mock.SECRET end
		truthy(compat().Chat.InChatLockdown())
		C_ChatInfo.InChatMessagingLockdown = nil
		falsy(compat().Chat.InChatLockdown())
		C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = nil
		falsy(compat().Chat.OutgoingAddonRestricted())
	end)

	it("restriction state falls back to IsAddOnRestrictionActive, and a secret state is active", function()
		Mock.restrictions.Set{ Combat = 1 }
		C_RestrictedActions.GetAddOnRestrictionState = nil
		truthy((compat().Chat.RestrictionActive("Combat")))
		falsy((compat().Chat.RestrictionActive("Map")))
		C_RestrictedActions.GetAddOnRestrictionState = function() return Mock.SECRET end
		truthy((compat().Chat.RestrictionActive("Map")))
		Enum.AddOnRestrictionType = nil
		falsy((compat().Chat.RestrictionActive("Combat")), "no enum: nothing can be restricted")
	end)

	it("knows about combat lockdown", function()
		falsy(compat().InCombat())
		InCombatLockdown = nil
		falsy(compat().InCombat())
	end)
end)

describe("items and stats", function()
	it("reads info, instant info and item level", function()
		addItems()
		local info = compat().Item.Info(ITEM_A)
		eq(info.name, "Crown of Embers")
		eq(info.quality, 4)
		eq(info.equipLoc, "INVTYPE_HEAD")
		eq(info.link, ITEM_A)
		local instant = compat().Item.Instant(1001)
		eq(instant.itemID, 1001)
		eq(instant.classID, 4)
		eq(compat().Item.Level(ITEM_A), 70)
		isNil(compat().Item.Info(9999))
		isNil(compat().Item.Info(nil))
		isNil(compat().Item.Level(nil))
	end)

	it("an item that is not cached answers nil and loads on request", function()
		Mock.items.Add{ id = 1003, link = "|Hitem:1003|h[Far Away]|h", name = "Far Away", cached = false }
		isNil(compat().Item.Info(1003))
		eq(compat().Item.Instant(1003).itemID, 1003, "instant info needs no cache")
		eq(compat().Item.Request(1003), "available")
		Mock.Advance(1)
		eq(compat().Item.Info(1003).name, "Far Away")
		eq(compat().Item.Request("x"), "missing")
	end)

	it("reads the stats and the delta as plain tables", function()
		addItems()
		deepEq(compat().Item.Stats(ITEM_A), { ITEM_MOD_STRENGTH_SHORT = 40, ITEM_MOD_STAMINA_SHORT = 60 })
		deepEq(compat().Item.StatDelta(ITEM_B, ITEM_A), { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_STAMINA_SHORT = -10 })
		isNil(compat().Item.Stats(1001), "a link is needed")
		isNil(compat().Item.StatDelta(ITEM_A, nil))
	end)

	it("hidden or missing stats degrade to nil", function()
		addItems()
		Mock.items.secret = true
		isNil(compat().Item.Stats(ITEM_A))
		Mock.items.secret = false
		Mock.items.noStats = true
		isNil(compat().Item.Stats(ITEM_A))
		C_Item.GetItemStatDelta = nil
		isNil(compat().Item.StatDelta(ITEM_A, ITEM_B))
	end)

	it("falls back to the old globals when C_Item lacks the call", function()
		addItems()
		C_Item.GetItemInfo = nil
		GetItemInfo = function() return "Old Global Item", "link", 3 end
		local info = compat().Item.Info(1)
		eq(info.name, "Old Global Item")
		eq(info.quality, 3)
		GetItemInfo = nil
		isNil(compat().Item.Info(1))
	end)

	it("says whether an item can be equipped and for which specializations", function()
		addItems()
		eq(compat().Item.IsEquippable(ITEM_A), true)
		isNil(compat().Item.IsEquippable(nil))
		eq(compat().Item.ContainsSpec(ITEM_A, 1, 71), true)
		eq(compat().Item.ContainsSpec(ITEM_A, 1, 73), false)
		isNil(compat().Item.ContainsSpec(ITEM_A, "x", 71))
		deepEq(compat().Item.SpecInfo(ITEM_A), { 71, 72 })
		isNil(compat().Item.SpecInfo(9999))
		C_Item.IsEquippableItem = nil
		isNil(compat().Item.IsEquippable(ITEM_A))
		C_Item.DoesItemContainSpec = nil
		isNil(compat().Item.ContainsSpec(ITEM_A, 1, 71))
	end)

	it("reads the equipped item of a slot", function()
		addItems()
		Mock.items.equipped[1] = ITEM_B
		eq(compat().Item.EquippedLink(1), ITEM_B)
		isNil(compat().Item.EquippedLink(2))
		GetInventoryItemLink = function() return Mock.SECRET end
		isNil(compat().Item.EquippedLink(1))
	end)
end)

describe("specializations", function()
	it("reads the active specialization with its role", function()
		Mock.specs.Set{ active = 3 }
		eq(compat().Spec.Count(), 3)
		eq(compat().Spec.Index(), 3)
		local active = compat().Spec.Active()
		eq(active.id, 73)
		eq(active.name, "Protection")
		eq(active.role, "TANK")
		eq(compat().Spec.Role(1), "DAMAGER")
		isNil(compat().Spec.Role("x"))
		isNil(compat().Spec.Info(9))
	end)

	it("no specialization chosen, or no API, gives nil and 0", function()
		Mock.specs.active = nil
		isNil(compat().Spec.Index())
		isNil(compat().Spec.Active())
		C_SpecializationInfo.GetSpecialization = nil
		isNil(compat().Spec.Index())
		C_SpecializationInfo.GetSpecializationInfo = nil
		isNil(compat().Spec.Info(1))
		GetNumSpecializations = nil
		eq(compat().Spec.Count(), 0)
	end)

	it("the role comes from the info when GetSpecializationRole is missing", function()
		GetSpecializationRole = nil
		eq(compat().Spec.Role(3), "TANK")
	end)

	it("another unit's specialization is nil until the inspect data is in", function()
		isNil(compat().Spec.Inspect("target"))
		Mock.specs.Set{ inspect = { target = 72 } }
		eq(compat().Spec.Inspect("target"), 72)
		isNil(compat().Spec.Inspect(nil))
	end)
end)

describe("guild, ranks and group", function()
	before_boot(function(M)
		M.guild.Set{ name = "Keepers", ranks = { [0] = "Guild Master", "Officer", "Raider", "Initiate" }, myRank = 1, members = {
			{ name = "Aurel", rank = 0, class = "WARRIOR", online = true, guid = "Player-1-0000B001" },
			{ name = "Bryn", rank = 2, class = "MAGE", online = false, guid = "Player-1-0000B002" },
		} }
	end)

	it("reads the player's guild, rank and officer status", function()
		truthy(compat().Guild.InGuild())
		eq(compat().Guild.GuildName(), "Keepers")
		local guildName, rankName, rankIndex = compat().Guild.PlayerRank()
		eq(guildName, "Keepers")
		eq(rankName, "Officer")
		eq(rankIndex, 1)
		truthy(compat().Guild.IsOfficer())
		falsy(compat().Guild.IsGuildLeader())
	end)

	it("lists the ranks by index and reads the officer flag", function()
		eq(compat().Guild.NumRanks(), 4)
		eq(compat().Guild.RankName(0), "Guild Master")
		deepEq(compat().Guild.Ranks(), { { index = 0, name = "Guild Master" }, { index = 1, name = "Officer" },
			{ index = 2, name = "Raider" }, { index = 3, name = "Initiate" } })
		truthy(compat().Guild.RankIsOfficer(0))
		truthy(compat().Guild.RankIsOfficer(1))
		falsy(compat().Guild.RankIsOfficer(2))
		isNil(compat().Guild.RankIsOfficer("x"))
		eq(compat().Guild.RankIndexByGUID("Player-1-0000B002"), 2)
		isNil(compat().Guild.RankIndexByGUID("Player-9"))
	end)

	it("reads the roster and finds a member's rank without the realm or the case", function()
		local rows = compat().Guild.Roster()
		eq(#rows, 3)
		eq(compat().Guild.MemberRankIndex("aurel-TestRealm"), 0)
		eq(compat().Guild.MemberRankIndex("Bryn"), 2)
		isNil(compat().Guild.MemberRankIndex("Nobody"))
		local row = compat().Guild.RosterRow(3)
		eq(row.name, "Bryn")
		eq(row.rankName, "Raider")
		eq(row.online, false)
		isNil(compat().Guild.RosterRow(9))
	end)

	it("without a guild everything is empty", function()
		Mock.guild.Leave()
		falsy(compat().Guild.InGuild())
		eq(compat().Guild.NumRanks(), 0)
		deepEq(compat().Guild.Roster(), {})
		deepEq(compat().Guild.Ranks(), {})
		isNil(compat().Guild.PlayerRank())
		isNil(compat().Guild.MemberRankIndex("Aurel"))
	end)

	it("missing or hidden guild APIs degrade", function()
		GuildControlGetNumRanks = nil
		eq(compat().Guild.NumRanks(), 0)
		GuildControlGetRankName = function() return Mock.SECRET end
		isNil(compat().Guild.RankName(0))
		C_GuildInfo.GuildControlGetRankFlags = nil
		isNil(compat().Guild.RankIsOfficer(2))
		GetGuildRosterInfo = function() return Mock.SECRET end
		isNil(compat().Guild.RosterRow(1))
		IsInGuild = nil
		falsy(compat().Guild.InGuild())
	end)

	it("lists the group members and keeps secret ones honest", function()
		Mock.group.Set{ raid = true, members = { { name = "Aurel", inGuild = true }, { name = "Bryn", inGuild = false } } }
		truthy(compat().Group.InRaid())
		eq(compat().Group.Size(), 3)
		local members = compat().Group.Members()
		eq(#members, 2)
		eq(members[1].inGuild, true)
		eq(members[2].inGuild, false)
		Mock.group.secretGUIDs = true
		members = compat().Group.Members()
		eq(#members, 2, "a count is honest about what could not be read")
		isNil(members[1].guid)
		isNil(members[1].name)
		isNil(compat().Group.RaidRosterRow(1))
	end)

	it("reads a raid roster row and the leader flag", function()
		Mock.group.Set{ raid = true, members = { { name = "Aurel" } } }
		eq(compat().Group.RaidRosterRow(1).name, "Aurel")
		isNil(compat().Group.RaidRosterRow(9))
		truthy(compat().Group.IsLeader())
		falsy(compat().Group.IsAssistant())
		UnitIsGroupLeader = nil
		falsy(compat().Group.IsLeader())
	end)
end)

describe("calendar", function()
	local function raidNight()
		Mock.calendar.opened = false   -- the calendar adapter asks the client to load it at login (M3-4): start closed
		Mock.calendar.Set{ events = { [20] = { { title = "Official raid", eventType = 0, invites = {
			{ name = "Aurel", inviteStatus = 1, guid = "Player-1-0000B001" }, { name = "Bryn", inviteStatus = 4 } } } } } }
	end

	it("reads nothing until the calendar is opened, then the day's events", function()
		raidNight()
		deepEq(compat().Calendar.DayEvents(0, 20), {})
		eq(compat().Calendar.Open(), "available")
		local events = compat().Calendar.DayEvents(0, 20)
		eq(#events, 1)
		eq(events[1].title, "Official raid")
		eq(events[1].calendarType, "GUILD_EVENT")
		eq(compat().Calendar.MonthInfo(0).numDays, 30)
		deepEq(compat().Calendar.DayEvents(0, 21), {})
		deepEq(compat().Calendar.DayEvents("x", 20), {})
	end)

	it("reads the invites of an open event", function()
		raidNight()
		compat().Calendar.Open()
		truthy(compat().Calendar.OpenEvent(0, 20, 1))
		eq(compat().Calendar.NumInvites(), 2)
		eq(compat().Calendar.Invite(1).name, "Aurel")
		eq(compat().Calendar.Invite(1).guid, "Player-1-0000B001")
		eq(compat().Calendar.Invite(2).inviteStatus, 4)
		isNil(compat().Calendar.Invite(3))
		isNil(compat().Calendar.Invite("x"))
		compat().Calendar.CloseEvent()
		eq(compat().Calendar.NumInvites(), 0)
		falsy(compat().Calendar.OpenEvent(0, 5, 1))
	end)

	it("a missing or hidden calendar degrades", function()
		raidNight()
		compat().Calendar.Open()
		C_Calendar.GetDayEvent = function() return Mock.SECRET end
		deepEq(compat().Calendar.DayEvents(0, 20), {})
		C_Calendar = nil
		deepEq(compat().Calendar.DayEvents(0, 20), {})
		isNil(compat().Calendar.MonthInfo(0))
		eq(compat().Calendar.Open(), "missing")
		eq(compat().Calendar.NumInvites(), 0)
		falsy(compat().Calendar.OpenEvent(0, 20, 1))
	end)
end)

describe("player, time and encoding", function()
	it("reads the player's identity", function()
		eq(compat().Player.Name(), "Testchar")
		eq(compat().Player.Realm(), "TestRealm")
		eq(compat().Player.Faction(), "Horde")
		eq(compat().Player.ClassFile(), "WARRIOR")
		eq(compat().Player.ClassID(), 1)
		eq(compat().Player.Level(), 60)
		eq(compat().Player.Locale(), "enUS")
		truthy(compat().Player.GUID())
	end)

	it("missing player APIs degrade", function()
		UnitName, GetLocale, GetNormalizedRealmName, UnitClass = nil, nil, nil, nil
		isNil(compat().Player.Name())
		eq(compat().Player.Locale(), "enUS")
		eq(compat().Player.Realm(), "TestRealm", "falls back to GetRealmName")
		isNil(compat().Player.ClassFile())
	end)

	it("keeps time, with a fallback", function()
		eq(compat().ServerTime(), GetServerTime())
		eq(compat().ServerDay(), 20260101)
		near(compat().Now(), GetTime(), 1e-6)
		GetServerTime, GetTime = nil, nil
		eq(type(compat().ServerTime()), "number")
		eq(type(compat().Now()), "number")
	end)

	it("wraps the timers", function()
		local n = 0
		truthy(compat().After(1, function() n = n + 1 end))
		local ticker = compat().NewTicker(1, function() n = n + 10 end)
		truthy(ticker)
		Mock.Advance(2)
		eq(n, 21)
		ticker:Cancel()
		C_Timer = nil
		falsy(compat().After(1, function() end))
		isNil(compat().NewTicker(1, function() end))
		isNil(compat().NewTimer(1, function() end))
	end)

	it("encodes and decodes, and says why it could not", function()
		local text = compat().Base64.Encode(compat().CBOR.Encode({ a = 1, b = "x" }))
		deepEq(compat().CBOR.Decode(compat().Base64.Decode(text)), { a = 1, b = "x" })
		local round = compat().Compress.Inflate(compat().Compress.Deflate(("abc"):rep(100)))
		eq(round, ("abc"):rep(100))
		local value, err = compat().CBOR.Decode("not cbor")
		isNil(value)
		contains(err, "error")
		C_EncodingUtil = nil
		local v2, err2 = compat().CBOR.Encode({})
		isNil(v2)
		contains(err2, "missing")
	end)
end)

describe("the probe and /fdcp debug", function()
	local PLAIN = { "available", "missing", "restricted", "error", "unknown" }

	it("probes every API and feature at login", function()
		truthy(compat().probed, "PLAYER_LOGIN probes")
		eq(compat():State("loot.GetLootMethod"), "available")
		eq(compat():State("encounter.IsEncounterInProgress"), "available")
		eq(compat():State("roll.RANDOM_ROLL_RESULT"), "available")
		eq(compat():State("restriction.AddOnRestrictionType"), "available")
		eq(compat():State("encoding.roundTrip"), "available")
		eq(compat():State("loot.GetLootMethodLegacy"), "missing", "the legacy global is not defined")
		isNil(compat():State("nonsense"))
		for _, id in ipairs(compat().FEATURES) do
			notNil(compat():Feature(id), id)
		end
	end)

	it("reports unknown for what only the real client can settle", function()
		eq(compat():Feature("lootWindow"), "unknown")
		eq(compat():Feature("rollMessages"), "unknown")
		eq(compat():Feature("itemStatDelta"), "unknown")
		eq(compat():Feature("calendarRaid"), "unknown")
		eq(compat():Feature("addonMessages"), "unknown")
		eq(compat():Feature("encounterState"), "available")
		eq(compat():Feature("masterLoot"), "unknown", "no master loot group yet")
		Mock.loot.Set{ method = "master", masterLooter = true }
		compat():Probe()
		eq(compat():Feature("masterLoot"), "available")
	end)

	it("sees a missing capability as missing, an erroring one as error, a hidden one as restricted", function()
		C_Item.GetItemStatDelta = nil
		IsEncounterInProgress = function() error("boom") end
		C_ChatInfo.InChatMessagingLockdown = function() return true end
		GetLootThreshold = function() return Mock.SECRET end
		compat():Probe()
		eq(compat():State("item.C_Item.GetItemStatDelta"), "missing")
		eq(compat():Feature("itemStatDelta"), "missing")
		eq(compat():State("encounter.IsEncounterInProgress"), "error")
		eq(compat():Feature("encounterState"), "unknown")
		eq(compat():State("chat.InChatMessagingLockdown"), "restricted")
		eq(compat():State("loot.GetLootThreshold"), "restricted")
	end)

	it("a feature a module settled keeps its state across probes", function()
		truthy(compat():SetFeature("lootWindow", "available", "read at the first corpse"))
		falsy(compat():SetFeature("lootWindow", "available"), "no change the second time")
		compat():Probe()
		eq(compat():Feature("lootWindow"), "available")
	end)

	it("the specialization and guild rank features follow the data", function()
		eq(compat():Feature("specialization"), "available")
		eq(compat():Feature("guildRanks"), "unknown", "no guild")
		Mock.guild.Set{ name = "Keepers", myRank = 0 }
		compat():Probe()
		eq(compat():Feature("guildRanks"), "available")
		Mock.specs.active = nil
		compat():Probe()
		eq(compat():Feature("specialization"), "unknown")
	end)

	it("/fdcp debug prints the table and never a name", function()
		Mock.guild.Set{ name = "Keepers", myRank = 0, members = { { name = "Aurel", rank = 1 } } }
		addItems()
		Mock.items.equipped[1] = ITEM_A
		Mock.group.Set{ raid = true, members = { { name = "Bryn" } } }
		Mock.loot.Set{ method = "master", masterLooter = true, slots = { { link = ITEM_A, name = "Crown of Embers" } } }
		Mock.ClearOutput()
		truthy(Mock.Slash("/fdcp debug chat"))
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "Client: 1.60.1 (build 70170), interface 16001")
		contains(text, "(Forever)")
		contains(text, "Features:")
		contains(text, "[unknown] lootWindow")
		contains(text, "[available] encounterState")
		matches(text, "APIs: %d+ available, %d+ missing, %d+ restricted, %d+ error")
		contains(text, "[available] loot.GetLootMethod")
		for _, name in ipairs({ "Testchar", "Keepers", "Aurel", "Bryn", "Crown of Embers", "Test Realm" }) do
			falsy(text:find(name, 1, true), name .. " must not appear in /fdcp debug")
		end
		for state in text:gmatch("\n  %[(%a+)%]") do
			local known = false
			for _, s in ipairs(PLAIN) do if s == state then known = true end end
			truthy(known, "unexpected state " .. state)
		end
	end)

	it("/fdcp debug probes again, so a change since login shows", function()
		Mock.ClearOutput()
		Mock.Slash("/fdcp debug chat")
		contains(table.concat(Mock.PlainOutput(), "\n"), "[available] encounter.IsEncounterInProgress")
		IsEncounterInProgress = nil
		Mock.ClearOutput()
		Mock.Slash("/fdcp debug chat")
		contains(table.concat(Mock.PlainOutput(), "\n"), "[missing] encounter.IsEncounterInProgress")
	end)

	it("/fdcp debug speaks Italian in an Italian client, and /fdcp help lists it", function()
		T.boot(function(M) M.player.locale = "itIT" end)
		Mock.ClearOutput()
		Mock.Slash("/fdcp debug chat")
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "Funzioni:")
		contains(text, "id progetto")
		Mock.ClearOutput()
		Mock.Slash("/fdcp help")
		contains(table.concat(Mock.PlainOutput(), "\n"), "/fdcp debug - apre il rapporto bug")
	end)

	it("the English help lists /fdcp debug", function()
		Mock.Slash("/fdcp help")
		contains(table.concat(Mock.PlainOutput(), "\n"), "/fdcp debug")
	end)
end)

-- The exit criterion of M1-3: every unverified API degrades without an error in the mock, whether it is missing, raises
-- or answers with a secret value. Every public function of every area is called with every API sabotaged in turn.
describe("degradation sweep", function()
	local function exercise()
		local C = compat()
		local calls = {
			function() return C.Player.Name(), C.Player.Realm(), C.Player.Faction(), C.Player.GUID(), C.Player.Level(), C.Player.ClassID(),
				C.Player.ClassFile(), C.Player.Locale() end,
			function() return C.Guild.InGuild(), C.Guild.GuildName(), C.Guild.PlayerRank(), C.Guild.GuildRealm(), C.Guild.IsGuildLeader(),
				C.Guild.IsOfficer(), C.Guild.RequestRoster(), C.Guild.RosterCount(), C.Guild.Roster(), C.Guild.MemberRankIndex("Aurel") end,
			function() return C.Guild.NumRanks(), C.Guild.RankName(1), C.Guild.Ranks(), C.Guild.RankFlags(1), C.Guild.RankIsOfficer(1),
				C.Guild.RankIndexByGUID("Player-1-0000B001") end,
			function() return C.Group.InRaid(), C.Group.InGroup(), C.Group.Size(), C.Group.IsLeader(), C.Group.IsAssistant(), C.Group.Units(),
				C.Group.Members(), C.Group.RaidRosterRow(1) end,
			function() return C.Encounter.InProgress(), C.Encounter.InInstance(), C.Encounter.Instance(), C.Encounter.RaidDifficultyID() end,
			function() return C.Chat.InChatLockdown(), C.Chat.OutgoingAddonRestricted(), C.Chat.RestrictionAny(), C.Chat.CanSend(),
				C.InCombat() end,
			function() return C.Loot.Method(), C.Loot.IsMasterLootMethod(), C.Loot.IsMasterLooter(), C.Loot.Threshold(), C.Loot.LegacyMode(),
				C.Loot.MethodAvailable("master"), C.Loot.SetMethod("group") end,
			function() return C.Loot.NumItems(), C.Loot.Slot(1), C.Loot.Slots(), C.Loot.Candidates(1), C.Loot.Give(1, 1) end,
			function() return C.Roll.Parse("Aurel rolls 5 (1-100)"), C.Roll.ParseLoot("You receive loot: x."), C.Roll.Send(1, 100) end,
			function() return C.Trade.Partner(), C.Trade.PlayerItems(), C.Trade.TargetItems(), C.Trade.IsCompleteMessage("Trade complete.") end,
			function() return C.Item.Info(1001), C.Item.Instant(1001), C.Item.Level(ITEM_A), C.Item.Stats(ITEM_A), C.Item.StatDelta(ITEM_A, ITEM_B),
				C.Item.IsEquippable(ITEM_A), C.Item.ContainsSpec(ITEM_A, 1, 71), C.Item.SpecInfo(ITEM_A), C.Item.EquippedLink(1),
				C.Item.Request(1001) end,
			function() return C.Spec.Count(), C.Spec.Index(), C.Spec.Info(1), C.Spec.Active(), C.Spec.Role(1), C.Spec.Inspect("target") end,
			function() return C.Calendar.Open(), C.Calendar.MonthInfo(0), C.Calendar.DayEvents(0, 20), C.Calendar.OpenEvent(0, 20, 1),
				C.Calendar.NumInvites(), C.Calendar.Invite(1), C.Calendar.CloseEvent() end,
			function() return C.ServerTime(), C.ServerDay(), C.Now(), C.After(1, function() end), C.NewTimer(1, function() end),
				C.NewTicker(1, function() end) end,
			function() return C.CBOR.Encode({}), C.CBOR.Decode("x"), C.Base64.Encode("x"), C.Base64.Decode("x"), C.Compress.Deflate("x"),
				C.Compress.Inflate("x") end,
			function() return C.BuildInfo() end,
			function() C:Probe(); return C:DebugLines() end,
		}
		for i, call in ipairs(calls) do
			local ok, err = pcall(call)
			if not ok then error("call group " .. i .. " raised: " .. tostring(err), 0) end
		end
	end

	-- Replaces the value at a dotted path of the game's globals: nil (missing), a function that raises, one that returns a
	-- secret, or a table of such functions; returns false when the path is not there to sabotage.
	local function sabotage(path, mode)
		local parts = {}
		for part in path:gmatch("[^.]+") do parts[#parts + 1] = part end
		local holder = _G
		for i = 1, #parts - 1 do
			holder = holder[parts[i]]
			if type(holder) ~= "table" then return false end
		end
		local leaf = parts[#parts]
		local current = holder[leaf]
		if current == nil then return false end
		if mode == "missing" then
			holder[leaf] = nil
		elseif type(current) ~= "function" then
			holder[leaf] = (mode == "secret") and Mock.SECRET or nil
		elseif mode == "error" then
			holder[leaf] = function() error("simulated failure") end
		else
			holder[leaf] = function() return Mock.SECRET, Mock.SECRET, Mock.SECRET end
		end
		return true
	end

	local function context()
		addItems()
		Mock.items.equipped[1] = ITEM_A
		Mock.guild.Set{ name = "Keepers", myRank = 1, members = { { name = "Aurel", rank = 0, guid = "Player-1-0000B001" } } }
		Mock.group.Set{ raid = true, members = { { name = "Aurel", inGuild = true } } }
		Mock.loot.Set{ method = "master", masterLooter = true, candidates = { "Aurel" }, slots = { { link = ITEM_A, name = "Crown of Embers",
			sources = { "Creature-0-1-2-3-4567-0000", 1 } } } }
		Mock.calendar.Set{ events = { [20] = { { title = "Official raid", invites = { { name = "Aurel" } } } } } }
		C_Calendar.OpenCalendar()
	end

	it("the full surface works on a healthy client", function()
		context()
		exercise()
	end)

	for _, mode in ipairs({ "missing", "error", "secret" }) do
		it("every API in turn " .. mode .. ": nothing raises", function()
			local defs = compat().CAPABILITY_DEFS
			local touched = 0
			for _, def in ipairs(defs) do
				T.boot()
				context()
				if sabotage(def[3], mode) then
					touched = touched + 1
					local ok, err = pcall(exercise)
					if not ok then fail(def[3] .. " (" .. mode .. "): " .. tostring(err)) end
				end
			end
			truthy(touched > 40, "the sweep reached the APIs (" .. touched .. ")")
		end)
	end

	it("every API missing at once: the addon still answers", function()
		context()
		for _, def in ipairs(compat().CAPABILITY_DEFS) do sabotage(def[3], "missing") end
		exercise()
		compat():Probe()
		eq(compat():State("loot.GetLootMethod"), "missing")
		for _, id in ipairs(compat().FEATURES) do
			local state = compat():Feature(id)
			truthy(state == "missing" or state == "unknown", id .. " is " .. tostring(state))
		end
	end)

	it("every API hidden at once: the addon still answers", function()
		context()
		for _, def in ipairs(compat().CAPABILITY_DEFS) do sabotage(def[3], "secret") end
		exercise()
	end)

	it("every API failing at once: the addon still answers", function()
		context()
		for _, def in ipairs(compat().CAPABILITY_DEFS) do sabotage(def[3], "error") end
		exercise()
	end)
end)
