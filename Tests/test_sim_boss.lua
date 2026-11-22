-- A whole boss, end to end (M4-9): a raid of 40 on the network simulator (Tests/sim/sim.lua), every client a whole addon
-- with nothing stubbed (no SessionController.Env override, no hand-made host: the guild's ledger, the permission gate, the
-- protocol, the popups, the master looter's window, the roll listener, the delivery and the raid announcements are the
-- real modules). 39 members run the addon, one does not. The boss fight locks the chat down, the corpse is opened during
-- that lockdown, a second lockdown falls in the middle of a round, a raider and the master looter /reload mid-session,
-- two players tie and reroll, a player without the addon rolls by hand. Plan A hands the items over by master loot;
-- plan B (the winner is not on the master loot list) by a trade. docs/ANALISI.md §4, §11, §12 (the M4 exit).
local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end

local ML_NAME = "Aurel"
local ML = full(ML_NAME)
local NO_ADDON = "Zed"   -- in the raid, never installed the addon
-- 40 invented names: the master looter first, the player without the addon last.
local NAMES = {
	"Aurel", "Bryn", "Corin", "Dara", "Edda", "Fenn", "Gale", "Hale", "Ilse", "Joss",
	"Kael", "Lyra", "Mott", "Nyla", "Orin", "Pell", "Quin", "Rhea", "Sorn", "Tova",
	"Ulla", "Vane", "Wren", "Xan", "Yara", "Arlo", "Bex", "Cael", "Dov", "Elin",
	"Faye", "Gorm", "Hild", "Ivo", "Jora", "Kip", "Lune", "Mira", "Nox", "Zed",
}
local BOSS, BOSS_NAME = 663, "Lucifron"
local BOSS_GUID = "Creature-0-3-2000-1-11502-0000A1B2C3"

local function link(id, name) return "|cffa335ee|Hitem:" .. id .. "::::::::70:::::|h[" .. name .. "]|h|r" end
local ITEMS = {
	{ id = 19003, name = "Ring of the Keeper", equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0 },
	{ id = 19002, name = "Sword of Embers", equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 7 },
	{ id = 19007, name = "Helm of the Flame", equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 4 },
}
for _, def in ipairs(ITEMS) do def.link = link(def.id, def.name) end

-- Every client knows the items (the popup's names) and the guild: the master looter is the Guild Master, Bryn an officer
-- (she follows the session read-only), the others raiders (rank 3); every member of the raid is in the guild.
local OFFICER = "Bryn"
local function rankOf(n) return n == ML_NAME and 0 or n == OFFICER and 1 or 3 end
local function guildFor(me)
	local members = {}
	for _, n in ipairs(NAMES) do
		if n ~= me then members[#members + 1] = { name = n, rank = rankOf(n), class = "WARRIOR" } end
	end
	return { name = "Dragon", members = members, myRank = rankOf(me) }
end

local function setupFor(name)
	return function(M)
		for _, def in ipairs(ITEMS) do
			M.items.Add{ id = def.id, link = def.link, name = def.name, quality = 4, equipLoc = def.equipLoc,
				classID = def.classID, subclassID = def.subclassID }
		end
		M.guild.Set(guildFor(name))
		local candidates = {}
		for _, n in ipairs(NAMES) do candidates[#candidates + 1] = n end
		M.loot.Set{ method = "master", masterLooter = name == ML_NAME, masterPartyID = 1, threshold = 3,
			candidates = candidates, slots = {} }
		M.encounter.Set{ instance = { name = "Molten Core", type = "raid", difficultyID = 9, difficultyName = "Normal",
			maxPlayers = 40, instanceID = 409 } }
	end
end

---------------------------------------------------------------------------------------------------------------------
-- The raid

local function A(c) return c.addon() end
local function SC(c) return A(c).SessionController end
local function popup(c) return A(c).MemberLootPopup end
local function card(c) return popup(c).cards[1] end
local function shown(c) local k = card(c); return k ~= nil and k:IsShown() and k.data ~= nil end

-- Boots the 39 clients, forms the raid, lets the presence check settle (the player without the addon goes MISSING) and
-- opens the season on the master looter's guild ledger, through the permission gate.
local function raid()
	local net = Sim.new{ realm = REALM, step = 0.25 }
	local c = {}
	for _, n in ipairs(NAMES) do
		if n ~= NO_ADDON then c[n] = net:Client(n, { setup = setupFor(n) }) end
	end
	net:Raid(NAMES)
	net:Advance(3)   -- the guild roster read on every client (the permission gate), HELLO on RAID
	local a = A(c[ML_NAME])
	local L = assert(a.NightController:Ledger(), "the guild's ledger")
	assert(a.Season.Open(L, { author = ML, ts = a.Compat.ServerTime(), season = "S1",
		instances = { { id = 409, size = 40 } } }, nil, a.PermissionService:Gate()))
	-- the master looter opens the night: its client asks the raid who runs the addon
	local night, code = a.NightController:Open({ instanceID = 409 })
	assert(night, "the night opens: " .. tostring(code))
	net:Advance(20)   -- the answers, and AddonCheck's TIMEOUT for Zed
	return net, c, L
end

-- The boss: the pull and the fight lock the chat down; the master looter opens the corpse while the lockdown lasts.
local function kill(net, c)
	net:Encounter(BOSS, BOSS_NAME, "start")
	net:Lockdown(true)
	net:Advance(5)
	net:Encounter(BOSS, BOSS_NAME, "kill")
	local slots = {}
	for i, def in ipairs(ITEMS) do
		slots[i] = { link = def.link, name = def.name, quality = 4, sources = { BOSS_GUID, 1 } }
	end
	c[ML_NAME].Mock.loot.Set{ slots = slots }
	c[ML_NAME].Mock.loot.Open()
	net:Advance(3)
	net:Lockdown(false)
	net:Advance(3)
end

-- A raider's answer and roll, from the popup (M7-5c: three buttons; a roll button answers and rolls in one click, the roll
-- being the game's RandomRoll, answered to the whole raid). The test answers everybody first and rolls after, so the answer
-- goes through the popup's Choose and the roll through the button of the answer given.
local function answer(c, rs) A(c).MemberLootPopup:Choose(rs) end
local function roll(c)
	local d = card(c).data
	card(c).buttons[(d.response and d.response ~= "PASS") and d.response or "MS"]:Click()
end

local function session(c) return SC(c).session end
local function item(c, i) local s = session(c); return s.items[i or s.active] end
local function ml(c) return A(c[ML_NAME]).MLSession end

describe("a whole boss on a raid of 40", function()
	it("runs from the kill to the last delivery with the real modules", function()
		local net, c, L = raid()
		local mlc = c[ML_NAME]
		local a = A(mlc)
		eq(a.AddonCheck:StateOf(full(NO_ADDON)), "MISSING", "the player without the addon is seen")

		-- the kill: the session waits for the lockdown, then collects the corpse; the window opens on it
		kill(net, c)
		local s = session(mlc)
		truthy(s, "a session on the master looter's client")
		eq(s.state, "COLLECTING")
		eq(#s.items, 3)
		truthy(a.MainWindow:IsShown(), "the window opened on the corpse")
		eq(a.MainWindow:ActiveTab(), "loot")
		falsy(s.raid.addon[full(NO_ADDON)], "Zed cannot roll")
		truthy(s.raid.present[full(NO_ADDON)])
		local ui = ml(c).ui
		truthy(ui.missing:IsShown(), "the window warns: 1 raid member cannot roll")
		truthy(ui.notify:IsShown())
		ui.notify:Click()   -- the notice with Zed's name in /raid
		net:Advance(1)
		local noticed = false
		for _, m in ipairs(mlc.Mock.chat.messages) do
			if m.chatType == "RAID" and m.message:find(NO_ADDON, 1, true) then noticed = true end
		end
		truthy(noticed, "the notice names Zed")

		-- Start: the items are announced, the first roll opens by itself, a popup on every client with the addon
		ml(c):OnMain()
		net:Advance(2)
		eq(s.state, "ROLLING")
		eq(s.active, 1)
		for n, cl in pairs(c) do truthy(shown(cl), n .. " sees the popup") end
		-- the officer follows the session read-only; a raider does not see the master looter's window
		local view = SC(c[OFFICER]):View()
		truthy(view, "the officer sees the session")
		eq(view.host, false); truthy(view.readOnly)
		eq(view.view.ml, ML)
		local board = SC(c[OFFICER]):Board()
		eq(#board.items, 3)
		eq(board.active, 1)
		isNil(SC(c.Corin):View(), "a raider sees the popup only")
		falsy(SC(c[OFFICER]):Command("CONFIRM"), "the officer cannot command the session")

		-- Item 1, the ring: ten main-spec, five off-spec, the rest pass; a lockdown falls in the middle of the answers
		local ms1 = { "Bryn", "Corin", "Dara", "Edda", "Fenn", "Gale", "Hale", "Ilse", "Joss", "Kael" }
		local os1 = { "Lyra", "Mott", "Nyla", "Orin", "Pell" }
		net.rolls = { Bryn = { 95, 30 }, Corin = { 95, 70 }, Dara = { 12 }, Edda = { 40 }, Fenn = { 3 }, Gale = { 88 },
			Hale = { 61 }, Ilse = { 7 }, Joss = { 55 }, Kael = { 90 } }
		for i, n in ipairs(ms1) do
			if i == 6 then net:Lockdown(true) end
			answer(c[n], "MS")
		end
		for _, n in ipairs(os1) do answer(c[n], "OS") end
		local said = {}
		for _, n in ipairs(ms1) do said[n] = true end
		for _, n in ipairs(os1) do said[n] = true end
		for n, cl in pairs(c) do if not said[n] then answer(cl, "PASS") end end
		net:Advance(3)
		net:Lockdown(false)
		net:Advance(3)
		local it1 = item(mlc, 1)
		eq(it1.responses[full("Bryn")], "MS")
		eq(it1.responses[full("Kael")], "MS", "an answer held by the lockdown arrives after it")
		eq(it1.responses[full("Pell")], "OS")
		eq(it1.responses[full("Mira")], "PASS")
		for _, n in ipairs(ms1) do roll(c[n]) end
		net:Roll(NO_ADDON, 100)   -- a /roll by hand from the player without the addon
		net:Advance(2)
		eq(A(mlc).RollListener:Stats().byCode.NO_ADDON, 1, "Zed's roll is discarded: addon not active")
		eq(it1.round.kind, "REROLL", "Bryn and Corin tied on 95")
		deepEq(it1.round.among, { full("Bryn"), full("Corin") })
		truthy(shown(c.Bryn)); truthy(shown(c.Corin))
		falsy(shown(c.Dara), "the reroll is for the tied only")
		roll(c.Bryn); roll(c.Corin)
		net:Advance(2)
		eq(s.state, "PROPOSAL")
		eq(it1.proposal.winner, full("Corin"))
		ml(c):OnMain()   -- Confirm: credits charged and GiveMasterLoot in the same click
		eq(it1.state, "ASSIGNED")
		eq(#mlc.Mock.loot.given, 1)
		eq(mlc.Mock.loot.given[1].candidate, 3, "Corin's index on the master loot list")
		net:Loot("Corin", ITEMS[1].link)
		net:Advance(2)
		eq(it1.state, "DELIVERED")

		-- Item 2, the sword: the next roll opens by itself; a raider and the master looter /reload mid-round
		eq(s.active, 2)
		net:Advance(2)
		for _, n in ipairs({ "Corin", "Dara", "Edda" }) do answer(c[n], "MS") end
		net.rolls = { Corin = { 99 }, Dara = { 60 }, Edda = { 20 } }
		for n, cl in pairs(c) do
			if n ~= "Corin" and n ~= "Dara" and n ~= "Edda" and shown(cl) then answer(cl, "PASS") end
		end
		net:Advance(2)
		net:Reload("Dara")
		mlc.Mock.loot.Set{ slots = {} }   -- a /reload closes the loot window
		net:Reload(ML_NAME)
		-- while the raid answers the master looter's new question, the session keeps who has the addon (an item opened
		-- now must not leave the raid out)
		for _ = 1, 12 do
			local n = 0
			for _ in pairs(SC(c[ML_NAME]).session.raid.addon or {}) do n = n + 1 end
			eq(n, 39, "the members with the addon, during the answers")
			net:Advance(0.5)
		end
		mlc = c[ML_NAME]
		s = session(mlc)
		truthy(s, "the master looter's session is back after the /reload")
		eq(s.state, "ROLLING"); eq(s.active, 2)
		mlc.Mock.Slash("/fdcp")   -- the window opens on the session again
		eq(A(mlc).MainWindow:ActiveTab(), "loot")
		-- the state comes back by whisper behind the master looter's other whispers: how long depends on the bytes of the
		-- messages (the zlib of the platform), so give it a few more seconds (M7-2d: 6.5 s on the CI's Linux)
		for _ = 1, 10 do
			if shown(c.Dara) then break end
			net:Advance(0.5)
		end
		truthy(shown(c.Dara), "Dara's card is back")
		eq(card(c.Dara).data.response, "MS", "with her answer")
		truthy(card(c.Dara).buttons.MS.selected)
		for _, n in ipairs({ "Corin", "Dara", "Edda" }) do roll(c[n]) end
		net:Advance(2)
		local it2 = item(mlc, 2)
		eq(s.state, "PROPOSAL")
		eq(it2.proposal.winner, full("Dara"), "Corin paid the ring: fewer credits come first")
		ml(c):OnMain()
		eq(it2.state, "ASSIGNED", "charged although the corpse is closed")
		eq(it2.delivery.code, "NO_WINDOW")
		-- the master looter opens the corpse again: the sword is handed over by itself
		local slots = {}
		for i = 2, #ITEMS do
			slots[#slots + 1] = { link = ITEMS[i].link, name = ITEMS[i].name, quality = 4, sources = { BOSS_GUID, 1 } }
		end
		mlc.Mock.loot.Set{ slots = slots }
		mlc.Mock.loot.Open()
		eq(#mlc.Mock.loot.given, 2, "the sword given on the reopened corpse")
		eq(it2.delivery.status, "GIVEN")
		net:Loot("Dara", ITEMS[2].link)
		net:Advance(2)
		eq(it2.state, "DELIVERED")

		-- Item 3, the helm: only Fenn answers; the round waits for its timer. Plan B: the winner is not on the master
		-- loot list, the award stays and the item goes by trade.
		eq(s.active, 3)
		net:Advance(2)
		answer(c.Fenn, "MS")
		net.rolls = { Fenn = { 77 } }
		roll(c.Fenn)
		net:Advance(5)
		eq(s.state, "ROLLING", "the others may still answer")
		net:Advance(30)
		local it3 = item(mlc, 3)
		eq(s.state, "PROPOSAL")
		eq(it3.proposal.winner, full("Fenn"))
		local candidates = {}
		for _, n in ipairs(NAMES) do if n ~= "Fenn" then candidates[#candidates + 1] = n end end
		mlc.Mock.loot.Set{ candidates = candidates }
		ml(c):OnMain()
		eq(it3.state, "ASSIGNED")
		eq(it3.delivery.method, "TRADE")
		eq(it3.delivery.code, "NO_CANDIDATE")
		net:Loot(ML_NAME, ITEMS[3].link)   -- the master looter takes it from the corpse
		mlc.Mock.trade.Open("Fenn")
		mlc.Mock.trade.Put("player", ITEMS[3].link)
		mlc.Mock.trade.Finish()
		eq(it3.state, "DELIVERED")
		eq(it3.deliveredVia, "TRADE")

		-- the end
		eq(s.state, "ANNOUNCING")
		truthy(ml(c).ui.finish:IsShown())
		ml(c).ui.finish:Click()
		net:Advance(3)
		eq(s.state, "ENDED")
		for n, cl in pairs(c) do falsy(shown(cl), n .. "'s popup closed") end

		-- the ledger: three awards, the credits computed from them
		local awards = A(mlc).Ledger.Sorted(A(mlc).NightController:Ledger(), function(e) return e.type == "ITEM_AWARDED" end)
		eq(#awards, 3)
		eq(awards[1].payload.member, full("Corin")); truthy(awards[1].payload.reroll)
		eq(awards[2].payload.member, full("Dara"))
		eq(awards[3].payload.member, full("Fenn"))
		local credits = A(mlc).Ledger.Credits(A(mlc).NightController:Ledger(), "S1")
		eq(credits[full("Corin")], s.items[1].costs.MS)
		-- the raid read it in /raid
		local said = {}
		for _, m in ipairs(mlc.Mock.chat.messages) do
			if m.chatType == "RAID" then
				for _, def in ipairs(ITEMS) do
					if m.message:find(def.name, 1, true) then said[def.name] = (said[def.name] or 0) + 1 end
				end
			end
		end
		for _, def in ipairs(ITEMS) do eq(said[def.name], 2, def.name .. ": announced, then its result") end
		eq(A(mlc).Protocol.Session.stats.forged, 0)
	end)
end)
