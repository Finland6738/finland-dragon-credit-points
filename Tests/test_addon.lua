-- The addon as a whole (M1-2): loading in TOC order, the Forever check, the slash commands and the /reload round trip
-- of the SavedVariables. Adapted from Azeroth Accord (Tests/test_addon.lua), same owner, GPL-3.0.
-- `Mock` is the fake client; the game's globals (FinlandDragonCreditPoints, LibStub, ...) are plain globals here too. Read them
-- inside the test, not at the top of the file: every test boots a fresh client.

describe("loading", function()
	it("loads every TOC file in order without a Lua error", function()
		eq(#Mock.errors, 0)
		local order = {}
		for i, name in ipairs(Mock.loadedFiles) do order[name] = i end
		local libStub = order["FinlandDragonCreditPoints/Libs/Ace3/LibStub/LibStub.lua"]
		local aceAddon = order["FinlandDragonCreditPoints/Libs/Ace3/AceAddon-3.0/AceAddon-3.0.lua"]
		local english = order["FinlandDragonCreditPoints/Locale/enUS.lua"]
		local italian = order["FinlandDragonCreditPoints/Locale/itIT.lua"]
		local init = order["FinlandDragonCreditPoints/Core/Init.lua"]
		truthy(libStub and aceAddon and english and italian and init, "the libraries, locales and Init were loaded")
		truthy(libStub < aceAddon and aceAddon < english and english < italian and italian < init, "TOC order is kept")
	end)

	it("creates the addon object and enables it at login", function()
		local ACC = LibStub("AceAddon-3.0"):GetAddon("FinlandDragonCreditPoints")
		eq(ACC, FDCP)
		truthy(ACC:IsEnabled(), "enabled after PLAYER_LOGIN")
	end)

	it("recognises Forever and stays quiet", function()
		truthy(FDCP:IsForever())
		eq(#Mock.output, 0, "nothing printed at login")
	end)

	it("warns when the client is not Forever", function()
		-- the setup runs after the mock client is built and before the addon's files load
		T.boot(function() WOW_PROJECT_ID = WOW_PROJECT_MAINLINE end)
		falsy(FDCP:IsForever())
		contains(table.concat(Mock.PlainOutput(), "\n"), "built for WoW Forever")
	end)

	it("falls back to the Interface number when the project constants are missing", function()
		T.boot(function() WOW_PROJECT_ID, WOW_PROJECT_CAMELOT = nil, nil end)
		truthy(FDCP:IsForever(), "interface 16001 counts as Forever")
	end)

	it("speaks Italian in an Italian client", function()
		T.boot(function(M) M.player.locale = "itIT" end)
		Mock.Slash("/fdcp help")
		contains(table.concat(Mock.PlainOutput(), "\n"), "Comandi:")
	end)
end)

describe("slash commands", function()
	it("/fdcp help prints every command", function()
		truthy(Mock.Slash("/fdcp help"))
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "Commands:")
		for _, c in ipairs(FDCP.commands) do contains(text, "/fdcp " .. c.name) end
	end)

	it("a bare /fdcp shows the help until the window exists", function()
		truthy(Mock.Slash("/fdcp"))
		contains(table.concat(Mock.PlainOutput(), "\n"), "Commands:")
	end)

	it("an unknown command is reported and the help follows", function()
		Mock.Slash("/fdcp frobnicate")
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "Unknown command: frobnicate")
		contains(text, "Commands:")
	end)

	it("runs the handler of a registered command", function()
		local got
		local commands = FDCP.commands
		commands[#commands + 1] = { name = "later", help = "x", handler = function(_, input) got = input end }
		Mock.Slash("/fdcp later now")
		eq(got, "later now")
	end)

	it("the AddOn Compartment entry points exist", function()
		eq(type(FinlandDragonCreditPoints_OnAddonCompartmentClick), "function")
		FinlandDragonCreditPoints_OnAddonCompartmentEnter(nil, UIParent)
		truthy(GameTooltip:IsShown())
		FinlandDragonCreditPoints_OnAddonCompartmentLeave()
		falsy(GameTooltip:IsShown())
	end)
end)

describe("/reload", function()
	it("passes SavedVariables from one run to the next", function()
		FinlandDragonCreditPointsDB = { counter = 1, nested = { "a", "b" } }
		FinlandDragonCreditPointsCharDB = { seen = true }
		Mock.Reload()
		-- Config merges its defaults around the test values (from M1.4); the values themselves are kept
		eq(FinlandDragonCreditPointsDB.counter, 1)
		deepEq(FinlandDragonCreditPointsDB.nested, { "a", "b" })
		eq(FinlandDragonCreditPointsCharDB.seen, true)
		FinlandDragonCreditPointsDB.counter = FinlandDragonCreditPointsDB.counter + 1
		Mock.Reload()
		eq(FinlandDragonCreditPointsDB.counter, 2)
	end)

	it("rebuilds the Lua state: values that are not saved are gone", function()
		FinlandDragonCreditPointsDB = { kept = "yes" }
		SomeRuntimeValue = "lost"
		local before = FDCP
		Mock.Reload()
		isNil(SomeRuntimeValue)
		ne(FDCP, before, "a new addon object")
		eq(FinlandDragonCreditPointsDB.kept, "yes")
		eq(#Mock.errors, 0)
	end)

	it("keeps the world: clock, player and guild", function()
		Mock.guild.Set({ name = "Keepers", myRank = 2 })
		Mock.Advance(30)
		local now = GetTime()
		Mock.Reload()
		eq(GetTime(), now)
		eq(GetGuildInfo("player"), "Keepers")
	end)

	it("the slash commands work again after a reload", function()
		Mock.Reload()
		Mock.ClearOutput()
		truthy(Mock.Slash("/fdcp help"))
		contains(table.concat(Mock.PlainOutput(), "\n"), "Commands:")
	end)

	it("fires PLAYER_LOGOUT first and PLAYER_ENTERING_WORLD with isReloadingUi after", function()
		local seen = {}
		local frame = CreateFrame("Frame")
		frame:RegisterEvent("PLAYER_LOGOUT")
		frame:SetScript("OnEvent", function(_, event) seen[#seen + 1] = event end)
		FinlandDragonCreditPointsDB = {}
		Mock.Reload()
		deepEq(seen, { "PLAYER_LOGOUT" })
		local reloading
		local f2 = CreateFrame("Frame")
		f2:RegisterEvent("PLAYER_ENTERING_WORLD")
		f2:SetScript("OnEvent", function(_, _, isInitialLogin, isReloadingUi) reloading = isReloadingUi end)
		Mock.Fire("PLAYER_ENTERING_WORLD", false, true)
		eq(reloading, true)
	end)

	it("refuses SavedVariables the client could not store", function()
		FinlandDragonCreditPointsDB = { handler = function() end }
		local err = raises(function() Mock.Reload() end)
		contains(err, "cannot be saved")
	end)
end)
