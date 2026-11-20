-- Locales (M1-5): every language has the same keys, English fills the gaps, the personal language needs /reload, the
-- guild language drives texts for everyone, numbers and dates follow the language. The commands run in each language and
-- never print a raw key. Read the game's globals inside the tests: every test boots a fresh client.

local function out() return table.concat(Mock.PlainOutput(), "\n") end

describe("languages", function()
	it("registers English and Italian, English first", function()
		local langs = FDCP.Locale.Languages()
		eq(langs[1].code, "enUS")
		eq(langs[2].code, "itIT")
		eq(langs[2].name, "Italiano")
		truthy(FDCP.Locale.Has("itIT"))
		falsy(FDCP.Locale.Has("deDE"))
	end)

	it("an unknown key answers with the key itself, never an empty string", function()
		eq(FDCP.L["NO_SUCH_KEY"], "NO_SUCH_KEY")
		eq(FDCP.Locale.Text("itIT", "NO_SUCH_KEY"), "NO_SUCH_KEY")
	end)

	it("a key missing in a language falls back to English", function()
		local Locale = FDCP.Locale
		local strings = Locale._strings()
		local saved = strings.itIT.HELP_HELP
		strings.itIT.HELP_HELP = nil
		eq(Locale.Text("itIT", "HELP_HELP"), "show this list")
		strings.itIT.HELP_HELP = saved
	end)

	it("an English-British client counts as English", function()
		T.boot(function(M) M.player.locale = "enGB" end)
		eq(FDCP.Locale.Active(), "enUS")
	end)

	it("a client language without a file falls back to English", function()
		T.boot(function(M) M.player.locale = "deDE" end)
		eq(FDCP.Locale.Active(), "enUS")
		Mock.Slash("/fdcp help")
		contains(out(), "Commands:")
	end)
end)

describe("every language", function()
	for _, code in ipairs({ "enUS", "itIT" }) do
		it(code .. ": help, debug, language and unknown command print texts, not keys", function()
			T.boot(function(M) M.player.locale = code end)
			eq(FDCP.Locale.Active(), code)
			Mock.Slash("/fdcp help")
			Mock.Slash("/fdcp debug")
			Mock.Slash("/fdcp language")
			Mock.Slash("/fdcp nope")
			local text = out()
			falsy(text:find("HELP_", 1, true), "a raw key leaked: " .. text)
			falsy(text:find("DEBUG_", 1, true), "a raw key leaked")
			falsy(text:find("LANGUAGE_", 1, true), "a raw key leaked")
			falsy(text:find("UNKNOWN_COMMAND", 1, true), "a raw key leaked")
			contains(text, code == "itIT" and "Comandi:" or "Commands:")
		end)

		it(code .. ": has exactly the English keys and the same placeholders", function()
			local strings = FDCP.Locale._strings()
			local function placeholders(s)
				local t = {}
				for p in s:gmatch("%%[%-%d%.]*[sdfx]") do t[#t + 1] = p end
				return table.concat(t, " ")
			end
			for key, text in pairs(strings.enUS) do
				truthy(strings[code][key] ~= nil, code .. " lacks " .. key)
				eq(placeholders(strings[code][key]), placeholders(text), key)
			end
			for key in pairs(strings[code]) do truthy(strings.enUS[key] ~= nil, code .. " has an extra " .. key) end
		end)
	end
end)

describe("personal language", function()
	it("defaults to automatic and needs /reload to change", function()
		eq(FDCP.Config:GetLanguage(), "auto")
		truthy(FDCP.Config:SetLanguage("itIT"))
		eq(FDCP.Locale.Active(), "enUS", "not applied yet")
		Mock.Reload()
		eq(FDCP.Locale.Active(), "itIT")
		Mock.Slash("/fdcp help")
		contains(out(), "Comandi:")
	end)

	it("auto goes back to the client's language", function()
		FDCP.Config:SetLanguage("itIT")
		Mock.Reload()
		truthy(FDCP.Config:SetLanguage("AUTO"))
		Mock.Reload()
		eq(FDCP.Locale.Active(), "enUS")
	end)

	it("/fdcp language shows, sets (case-insensitive) and refuses unknown codes", function()
		Mock.Slash("/fdcp language")
		contains(out(), "enUS, itIT")
		Mock.Slash("/fdcp language itit")
		contains(out(), "/reload")
		eq(FDCP.Config:GetLanguage(), "itIT")
		Mock.Slash("/fdcp language xxXX")
		contains(out(), "Unknown language: xxXX")
		eq(FDCP.Config:GetLanguage(), "itIT")
	end)

	it("a saved language that no longer exists is ignored", function()
		FDCP.Config.db.global.language = "deDE"
		eq(FDCP.Config:GetLanguage(), "auto")
		Mock.Reload()
		eq(FDCP.Locale.Active(), "enUS")
	end)

	it("a read-only database refuses the change", function()
		FDCP.Config.db.global.schema = 999
		Mock.Reload()
		local ok, err = FDCP.Config:SetLanguage("itIT")
		falsy(ok); eq(err, "READ_ONLY")
	end)
end)

describe("guild language", function()
	it("texts for everyone use the guild language, whatever the personal one", function()
		local Locale = FDCP.Locale
		eq(Locale.Guild("UNKNOWN_COMMAND", "x"), "Unknown command: x")
		truthy(FDCP.Config:Set("guildLanguage", "itIT"))
		eq(Locale.GuildLanguage(), "itIT")
		eq(Locale.Guild("UNKNOWN_COMMAND", "x"), "Comando sconosciuto: x")
		eq(FDCP.L["UNKNOWN_COMMAND"]:format("x"), "Unknown command: x", "personal texts stay English")
	end)

	it("only a registered language is accepted, and it survives /reload", function()
		local ok, err = FDCP.Config:Set("guildLanguage", "deDE")
		falsy(ok); eq(err, "BAD_VALUE")
		FDCP.Config:Set("guildLanguage", "itIT")
		Mock.Reload()
		eq(FDCP.Locale.GuildLanguage(), "itIT")
	end)
end)

describe("numbers and dates", function()
	it("numbers follow the language", function()
		local N = FDCP.Locale.FormatNumber
		eq(N(1.5, 2, "enUS"), "1.5")
		eq(N(1.5, 2, "itIT"), "1,5")
		eq(N(3, 2, "itIT"), "3")
		eq(N(1234567.25, 2, "enUS"), "1,234,567.25")
		eq(N(1234567.25, 2, "itIT"), "1.234.567,25")
		eq(N(-1000, 0, "itIT"), "-1.000")
		eq(N(999, 0, "enUS"), "999")
		eq(N(0.004, 2, "enUS"), "0")
	end)

	it("dates follow the language", function()
		local D = FDCP.Locale.FormatDate
		local t = 1763510400   -- 2025-11-19 00:00 UTC
		local short_en, short_it = D(t, "DATE_SHORT", "enUS"), D(t, "DATE_SHORT", "itIT")
		eq(short_en:match("^(%d+)/(%d+)$") ~= nil, true)
		eq(short_it:match("^(%d+)/(%d+)$") ~= nil, true)
		local a, b = short_en:match("^(%d+)/(%d+)$")
		eq(short_it, b .. "/" .. a)
		contains(D(t, "DATE_LONG", "itIT"), "/2025")
		contains(D(t, "DATETIME", "enUS"), ":")
	end)

	it("the active language is the default", function()
		T.boot(function(M) M.player.locale = "itIT" end)
		eq(FDCP.Locale.FormatNumber(2.5), "2,5")
	end)
end)
