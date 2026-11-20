-- Config, Log and Bus (M1-4): per-guild data, schema migrations, read-only on a newer schema, the ring buffer without
-- names and the internal event bus. Read the game's globals inside the tests: every test boots a fresh client.

local function config() return FDCP.Config end

describe("Bus", function()
	it("runs handlers in order and passes the arguments", function()
		local got = {}
		FDCP.Bus:On("T", function(ev, a, b) got[#got + 1] = ev .. a .. b end)
		FDCP.Bus:On("T", function() got[#got + 1] = "second" end)
		eq(FDCP.Bus:Emit("T", 1, 2), 2)
		deepEq(got, { "T12", "second" })
	end)

	it("a failing handler is logged and the others still run", function()
		local ran = false
		FDCP.Bus:On("T", function() error("boom") end)
		FDCP.Bus:On("T", function() ran = true end)
		eq(FDCP.Bus:Emit("T"), 2)
		truthy(ran)
		contains(table.concat(FDCP.Log.Lines(), "\n"), "HANDLER_ERROR")
	end)

	it("Off removes by owner, for one event or all", function()
		local owner = {}
		FDCP.Bus:On("A", function() end, owner)
		FDCP.Bus:On("B", function() end, owner)
		eq(FDCP.Bus:Off("A", owner), 1)
		eq(FDCP.Bus:Off(nil, owner), 1)
		eq(FDCP.Bus:Count("B"), 0)
	end)

	it("a handler may remove itself while the event runs", function()
		local n = 0
		local owner = {}
		FDCP.Bus:On("A", function() n = n + 1; FDCP.Bus:Off("A", owner) end, owner)
		FDCP.Bus:On("A", function() n = n + 10 end)
		FDCP.Bus:Emit("A"); FDCP.Bus:Emit("A")
		eq(n, 21)
	end)
end)

describe("Log", function()
	it("keeps the newest entries in a ring buffer", function()
		local Log = FDCP.Log
		Log.Clear()
		Log.SetLevel("debug")
		for i = 1, Log.CAPACITY + 5 do Log.debug("T", "X", i) end
		local e = Log.Entries()
		eq(#e, Log.CAPACITY)
		eq(e[1].args[1], 6)
		eq(e[#e].args[1], Log.CAPACITY + 5)
	end)

	it("drops entries below the level", function()
		local Log = FDCP.Log
		Log.Clear(); Log.SetLevel("warn")
		falsy(Log.info("T", "X"))
		truthy(Log.error("T", "X"))
		eq(#Log.Entries(), 1)
		falsy(Log.SetLevel("nonsense"))
	end)

	it("never prints a name: strings are hidden unless marked plain", function()
		local Log = FDCP.Log
		Log.Clear()
		Log.warn("T", "CODE", "Aurel-Stormrage", Log.Plain("READ_ONLY"), 7, true)
		local text = table.concat(Log.Lines(), "\n")
		contains(text, "CODE <text> READ_ONLY 7 true")
		falsy(text:find("Aurel", 1, true))
	end)
end)

describe("guild key", function()
	it("is <realm>/<guild>", function()
		Mock.guild.Set({ name = "Keepers" })
		config():UpdateGuildKey()
		eq(config():GuildKey(), FDCP.Compat.Player.Realm() .. "/Keepers")
	end)

	it("is nil without a guild", function()
		Mock.guild.Leave()
		config():UpdateGuildKey()
		isNil(config():GuildKey())
		isNil(config():GuildData())
	end)

	it("changes with the guild and tells the bus", function()
		local keys = {}
		FDCP.Bus:On("GUILD_KEY_CHANGED", function(_, k) keys[#keys + 1] = k end)
		Mock.guild.Set({ name = "One" }); config():UpdateGuildKey()
		Mock.guild.Set({ name = "Two" }); config():UpdateGuildKey()
		falsy(config():UpdateGuildKey(), "no change, no event")
		eq(#keys, 2)
		ne(keys[1], keys[2])
	end)
end)

describe("per-guild data", function()
	it("two guilds never share a table, and the data survives /reload", function()
		Mock.guild.Set({ name = "One" }); config():UpdateGuildKey()
		config():GuildData().season = "s1"
		Mock.guild.Set({ name = "Two" }); config():UpdateGuildKey()
		isNil(config():GuildData().season)
		config():GuildData().season = "s2"
		Mock.Reload()
		eq(config():GuildKey(), FDCP.Compat.Player.Realm() .. "/Two")
		eq(config():GuildData().season, "s2")
		eq(config():GuildData(FDCP.Compat.Player.Realm() .. "/One").season, "s1")
	end)
end)

describe("settings", function()
	it("has defaults and keeps a valid change across /reload", function()
		eq(config():Get("rollSeconds"), 30)
		truthy(config():Set("rollSeconds", 45))
		Mock.Reload()
		eq(config():Get("rollSeconds"), 45)
	end)

	it("rejects unknown names, wrong types and out-of-range values", function()
		local ok, err = config():Set("nope", 1); falsy(ok); eq(err, "UNKNOWN_SETTING")
		ok, err = config():Set("rollSeconds", "x"); falsy(ok); eq(err, "BAD_TYPE")
		ok, err = config():Set("rollSeconds", 1); falsy(ok); eq(err, "OUT_OF_RANGE")
		ok, err = config():Set("rollSeconds", 0 / 0); falsy(ok); eq(err, "BAD_VALUE")
		ok, err = config():Set("guildLanguage", "xxXX"); falsy(ok); eq(err, "BAD_VALUE")
		eq(config():Get("rollSeconds"), 30)
	end)

	it("announces a change on the bus", function()
		local seen
		FDCP.Bus:On("CONFIG_CHANGED", function(_, n, v, o) seen = { n, v, o } end)
		config():Set("debug", true)
		deepEq(seen, { "debug", true, false })
	end)
end)

describe("schema", function()
	it("a new database is stamped with the current schema", function()
		eq(FinlandDragonCreditPointsDB.global.schema, config().SCHEMA)
		falsy(config():IsReadOnly())
	end)

	it("migrates step by step, in order, and stops at a failing step", function()
		local order = {}
		local steps = {
			[1] = function(g) order[#order + 1] = 1; g.a = 1 end,
			[2] = function(g) order[#order + 1] = 2; g.b = g.a + 1 end,
			[3] = function() error("bad") end,
			[4] = function() order[#order + 1] = 4 end,
		}
		local g = {}
		local ok, v = config().Migrate(g, 0, 4, steps)
		falsy(ok); eq(v, 2)
		deepEq(order, { 1, 2 })
		eq(g.b, 2)
		ok, v = config().Migrate({}, 2, 4, { [3] = function() end })
		falsy(ok); eq(v, 3, "a missing step stops too")
		ok, v = config().Migrate({}, 2, 2, {})
		truthy(ok); eq(v, 2)
	end)

	it("an old database (schema 0 data) is migrated at load", function()
		FinlandDragonCreditPointsDB = { global = { schema = 0, guilds = { ["R/G"] = { kept = 1 } } } }
		Mock.Reload()
		eq(FinlandDragonCreditPointsDB.global.schema, config().SCHEMA)
		eq(config():GuildData("R/G").kept, 1)
	end)

	it("a newer schema opens read-only and nothing is written", function()
		local newer = config().SCHEMA + 1
		FinlandDragonCreditPointsDB = { global = { schema = newer, guilds = { ["R/G"] = { kept = 1 } } } }
		Mock.Reload()
		truthy(config():IsReadOnly())
		local ok, err = config():Set("rollSeconds", 40)
		falsy(ok); eq(err, "READ_ONLY")
		Mock.guild.Set({ name = "Fresh" }); config():UpdateGuildKey()
		isNil(config():GuildData(), "no new guild table in a read-only database")
		eq(config():GuildData("R/G").kept, 1, "existing data stays readable")
		Mock.Reload()
		eq(FinlandDragonCreditPointsDB.global.schema, newer, "the version is not lowered")
		contains(table.concat(FDCP.Log.Lines(), "\n"), "SCHEMA_NEWER")
	end)
end)

describe("character data", function()
	it("is a table that survives /reload", function()
		config().char.windowX = 10
		Mock.Reload()
		eq(config().char.windowX, 10)
	end)
end)
