-- Diagnostics and bug reports (M7-4): the report holds no names, the error catcher keeps the addon's own errors (cleaned),
-- and /fdcp debug opens a selectable window (mock client).
local function D() return FDCP.Diagnostics end
local function DW() return FDCP.DiagnosticsWindow end

local NAMES = { "Testchar", "Keepers", "Aurel", "Bryn", "Corin", "Crown of Embers", "Hidden" }

local function noNames(text, what)
	for _, name in ipairs(NAMES) do falsy(text:find(name, 1, true), name .. " must not appear in " .. what) end
end

describe("the bug report", function()
	before_boot()

	it("has the versions, the capabilities, the ledger, the errors and the log", function()
		local text = D():Text()
		contains(text, "FDCP bug report")
		contains(text, "Addon version dev, protocol")
		contains(text, "Client: 1.60.1 (build 70170)")
		contains(text, "Features:")
		contains(text, "Errors of the addon:")
		contains(text, "Log of the addon:")
	end)

	it("never holds a name, even when names went into the log, the guild and the errors", function()
		Mock.guild.Set{ name = "Keepers", myRank = 0, members = { { name = "Aurel", rank = 1 }, { name = "Bryn", rank = 2 } } }
		FDCP.Log.warn("Test", "SOMEONE", "Corin-TestRealm", FDCP.Log.Plain("ok"))
		D().Record("Interface/AddOns/FinlandDragonCreditPoints/App/X.lua:12: no such member \"Aurel-TestRealm\" in 'Keepers'")
		D().Record("Interface/AddOns/FinlandDragonCreditPoints/App/Y.lua:3: bad Bryn")   -- a name outside any quotes: the scrub gets it
		local text = D():Text()
		noNames(text, "the report")
		contains(text, "X.lua:12")
		contains(text, "<text>")
		contains(text, "<name>")
	end)

	it("scrubs the longest name first and every occurrence", function()
		eq(D().Scrub("Aurel-Camelot and Aurel and Aurel", { "Aurel-Camelot", "Aurel" }), "<name> and <name> and <name>")
		eq(D().Scrub("nothing here", { "Aurel" }), "nothing here")
	end)

	it("speaks Italian in an Italian client", function()
		T.boot(function(M) M.player.locale = "itIT" end)
		local text = D():Text()
		contains(text, "Rapporto bug FDCP")
		contains(text, "Errori dell'addon:")
		falsy(text:find("DIAG_", 1, true), "a raw key leaked")
	end)
end)

describe("the error catcher", function()
	before_boot()

	it("keeps the addon's own errors, cleaned, counted once per message", function()
		falsy(D().Record("Interface/AddOns/SomeOtherAddon/Core.lua:5: boom"))
		truthy(D().Record("Interface\\AddOns\\FinlandDragonCreditPoints\\Net\\Sync.lua:77: attempt to index a nil value"))
		truthy(D().Record("Interface\\AddOns\\FinlandDragonCreditPoints\\Net\\Sync.lua:77: attempt to index a nil value"))
		eq(#D().errors, 1)
		eq(D().errors[1].count, 2)
		contains(D().errors[1].text, "Net/Sync.lua:77")
		falsy(D().errors[1].text:find("Interface", 1, true))
		contains(D():Text(), "x2")
	end)

	it("sees an error raised through the game's error handler and passes it on", function()
		local before = #Mock.errors
		geterrorhandler()("Interface/AddOns/FinlandDragonCreditPoints/App/Z.lua:9: failed")
		eq(#D().errors, 1)
		eq(#Mock.errors, before + 1, "the game's handler still ran")
		Mock.ClearErrors()
		geterrorhandler()("Interface/AddOns/Other/Z.lua:9: failed")
		eq(#D().errors, 1, "another addon's error is not ours")
		Mock.ClearErrors()
	end)

	it("keeps only the last ten different errors", function()
		for i = 1, 14 do D().Record(("Interface/AddOns/FinlandDragonCreditPoints/App/E%d.lua:1: x"):format(i)) end
		eq(#D().errors, D().MAX_ERRORS)
		contains(D().errors[#D().errors].text, "E14.lua")
		falsy(D().errors[1].text:find("E1.lua", 1, true))
	end)
end)

describe("/fdcp debug", function()
	before_boot()

	it("opens the window with the report selected", function()
		Mock.Slash("/fdcp debug")
		truthy(DW():IsShown())
		eq(DW().frame.edit:GetText(), D():Text())
		truthy(DW().frame.edit._highlighted)
	end)

	it("puts an edit by hand back", function()
		Mock.Slash("/fdcp debug")
		local edit = DW().frame.edit
		edit:SetText("typed by hand")
		edit:GetScript("OnTextChanged")(edit, true)
		eq(edit:GetText(), DW().text)
	end)

	it("prints the same report in the chat with 'chat' and lists the command in help", function()
		Mock.ClearOutput()
		Mock.Slash("/fdcp debug chat")
		local text = table.concat(Mock.PlainOutput(), "\n")
		contains(text, "FDCP bug report")
		contains(text, "Client: 1.60.1")
		noNames(text, "/fdcp debug chat")
	end)
end)
