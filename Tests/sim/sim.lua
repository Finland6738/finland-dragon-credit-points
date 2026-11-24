-- The network simulator (M3-5): several clients of the addon in one Lua state, talking through addon messages.
-- Loaded by Tests/lib/harness.lua when this file exists; test files see it as the global `Sim`.
--
-- Every client is a whole world of its own (Tests/lib/harness.lua H.newWorld(): own mock client, own addon, own
-- SavedVariables). The simulator moves their clocks together and carries what one client's C_ChatInfo.SendAddonMessage
-- accepted (Mock.chat.sent) to the others through Mock.chat.Receive, which fires CHAT_MSG_ADDON as the client does:
--   RAID     to every client in the simulated raid, the sender included (the client echoes it, spike S4)
--   GUILD    to every client in the guild (all of them), the sender included
--   OFFICER  to every client whose rank reads the officer chat (Mock.guild.myRank <= Mock.guild.officerRanks), the sender
--            included (M6-5); sending is not checked, so a test can play a member who forges an officer message
--   WHISPER  to the client named as the target
-- A raid member without a client is a player without the addon: they are in everybody's raid roster and never answer.
--
--   local net = Sim.new{ realm = "Camelot" }
--   local a = net:Client("Aurel", { version = "1.2.0", setup = function(Mock) ... end, after = function(client) ... end })
--   net:Raid({ "Aurel", "Bryn", "Corin" }, { offline = { Corin = true } })   -- fires GROUP_ROSTER_UPDATE everywhere
--                                                                            (also ranks = { Aurel = 2 }, ml = "Aurel")
--   net:Advance(5)                                                           -- 0.1-second steps, delivery after each
--   a.addon()                                                                -- the client's FDCP table (fresh after a reload)
--   net:Reload("Aurel")   net:Drop("Bryn")   -- /reload, or the client goes away (its player stays in the raid)
--   net:Logout("Bryn")    net:Login("Bryn")  -- (M6-5) the player logs out (SavedVariables written, nothing sent or
--                                               received, its clock stops) and logs in again later at the simulator's time
-- The game's server for the whole raid (M4-9): what one player does that every raid member's client reads.
--   net:Roll("Bryn", 87)                 the server's roll message (CHAT_MSG_SYSTEM) on every client in the raid
--   net.rolls = { Bryn = { 87, 40 } }    what the next RandomRoll(1, 100) of a client gives (a click on a popup's Roll);
--                                          the client's own RandomRoll goes to every raid client through net:Roll
--   net:Loot("Bryn", link)               the loot message (CHAT_MSG_LOOT) of a player, on every client in the raid
--   net:Encounter(601, "Boss", "start" | "kill" | "wipe")   ENCOUNTER_START / END on every client
--   net:Lockdown(true | false)           the chat lockdown (no addon message goes out) on every client
--   net:Each(function(c) ... end)        runs on every client, then checks its errors
-- A Lua error caught by any client's error handler fails the test at once.
local H, T = ...

local Sim = {}
local Net = {}
Net.__index = Net

local START_NOW, START_EPOCH = 1000.0, 1767225600

function Sim.new(opts)
	opts = opts or {}
	return setmetatable({
		realm = opts.realm or "Camelot", guild = opts.guild, step = opts.step or 0.1,
		elapsed = 0, clients = {}, order = {}, raid = nil, raidOpts = {}, log = {},
	}, Net)
end

-- The world's errors fail the test.
local function checkErrors(c)
	local errors = c.Mock.errors
	if errors and #errors > 0 then
		error("Lua error in the client of " .. c.name .. ": " .. errors[1].message .. "\n" .. (errors[1].trace or ""), 0)
	end
end

-- The raid roster as client `c` sees it: the OTHER members.
local function rosterFor(net, c)
	local members = {}
	for i, name in ipairs(net.raid or {}) do
		if name ~= c.name then
			members[#members + 1] = { name = name, subgroup = math.floor((i - 1) / 5) + 1,
				online = not (net.raidOpts.offline and net.raidOpts.offline[name]),
				raidRank = net.raidOpts.ranks and net.raidOpts.ranks[name] or 0, isML = net.raidOpts.ml == name }
		end
	end
	return members
end

local function inRaid(net, name)
	for _, n in ipairs(net.raid or {}) do if n == name then return true end end
	return false
end

-- Applies the simulated raid to one client.
local function applyRaid(net, c)
	if net.raid and inRaid(net, c.name) then
		c.Mock.group.Set{ raid = true, members = rosterFor(net, c) }
	elseif #c.Mock.group.members > 0 then
		c.Mock.group.Leave()
	end
end

local function afterBoot(net, c)
	c.seen = #c.Mock.chat.sent
	local P = c.addon().Protocol
	if c.opts.version then P.addonVersion = c.opts.version end
	if c.opts.pv then P.VERSION = c.opts.pv end
	if c.opts.pm then P.MIN = c.opts.pm end
	-- RandomRoll: the server answers to the whole raid, with the value the test planned (50 when it planned none)
	c.E.RandomRoll = function(lo, hi)
		local rolls = c.Mock.loot.rolls
		rolls[#rolls + 1] = { lo = lo, hi = hi }
		local planned = net.rolls and net.rolls[c.name]
		local value = planned and table.remove(planned, 1) or 50
		net:Roll(c.name, value, lo, hi)
	end
	if c.opts.after then c.opts.after(c) end
end

-- A new client logged in as `name` on the simulator's realm, its clock at the simulator's time.
-- opts: version (addon version string), pv / pm (session protocol), guild (Mock.guild.Set table, default the
-- simulator's), setup(Mock) before the addon loads, after(client) once it has loaded (and after every reload).
function Net:Client(name, opts)
	opts = opts or {}
	local world = H.newWorld()
	local net = self
	local c = { name = name, full = name .. "-" .. self.realm, world = world, opts = opts, seen = 0 }
	c.Mock, c.E = world.Mock, world.E
	function c.addon() return c.E.FDCP end
	world.boot({ setups = { function(M)
		M.SetTime(START_NOW + net.elapsed)
		M.SetServerTime(START_EPOCH + net.elapsed)
		M.player.name, M.player.realm = name, net.realm
		local guild = opts.guild or net.guild
		if guild then M.guild.Set(guild) end
		if opts.setup then opts.setup(M) end
	end } })
	self.clients[name] = c
	self.order[#self.order + 1] = c
	afterBoot(self, c)
	applyRaid(self, c)
	checkErrors(c)
	return c
end

-- The raid: `names` in order (clients and players without the addon). opts.offline = { [name] = true };
-- opts.ranks = { [name] = 2 leader | 1 assistant } and opts.ml = name (the master looter), as GetRaidRosterInfo gives them.
-- Every client's roster changes at once (GROUP_ROSTER_UPDATE); a client not named leaves the raid.
function Net:Raid(names, opts)
	self.raid = names
	self.raidOpts = opts or {}
	for _, c in ipairs(self.order) do
		applyRaid(self, c)
		checkErrors(c)
	end
end

-- /reload of a client: its world keeps its clock, player, guild and raid; the addon starts again.
function Net:Reload(name)
	local c = assert(self.clients[name], "no client " .. tostring(name))
	c.Mock.Reload()
	c.Mock = c.world.Mock
	afterBoot(self, c)
	checkErrors(c)
	return c
end

-- The client goes away (the player disabled the addon, or logged out): nothing more is sent or received. The player stays
-- in the raid roster of the others until Raid() says otherwise.
function Net:Drop(name)
	local c = self.clients[name]
	if not c then return end
	self.clients[name] = nil
	for i, other in ipairs(self.order) do
		if other == c then table.remove(self.order, i) break end
	end
end

-- The player of client `name` logs out: PLAYER_LOGOUT and the SavedVariables written; from now on the client sends and
-- receives nothing and its clock stops (what it still had in its queue was saved with the outbox, as in the client).
function Net:Logout(name)
	local c = assert(self.clients[name], "no client " .. tostring(name))
	self:Deliver()
	c.saved = c.world.logout()
	self:Drop(name)
	self.away = self.away or {}
	self.away[name] = c
	return c
end

-- The player logs in again, at the simulator's time, with the SavedVariables written at the logout.
function Net:Login(name)
	local c = assert(self.away and self.away[name], "not logged out: " .. tostring(name))
	self.away[name] = nil
	c.Mock.SetTime(START_NOW + self.elapsed)
	c.Mock.SetServerTime(START_EPOCH + self.elapsed)
	c.world.boot({ carry = true, saved = c.saved })
	c.Mock = c.world.Mock
	c.saved = nil
	self.clients[name] = c
	self.order[#self.order + 1] = c
	afterBoot(self, c)
	applyRaid(self, c)
	checkErrors(c)
	return c
end

-- Hands what every client sent since the last delivery to the clients that receive it.
function Net:Deliver()
	for _, c in ipairs(self.order) do
		local sent = c.Mock.chat.sent
		for i = c.seen + 1, #sent do
			local e = sent[i]
			local targets = {}
			if e.chatType == "RAID" and inRaid(self, c.name) then
				for _, d in ipairs(self.order) do
					if inRaid(self, d.name) then targets[#targets + 1] = d end
				end
			elseif e.chatType == "GUILD" then
				for _, d in ipairs(self.order) do targets[#targets + 1] = d end
			elseif e.chatType == "OFFICER" then
				for _, d in ipairs(self.order) do
					local g = d.Mock.guild
					if g.name and (g.myRank or 99) <= (g.officerRanks or 1) then targets[#targets + 1] = d end
				end
			elseif e.chatType == "WHISPER" and type(e.target) == "string" then
				local short = e.target:match("^([^%-]+)")
				if self.clients[short] then targets[1] = self.clients[short] end
			end
			self.log[#self.log + 1] = { from = c.name, chatType = e.chatType, message = e.message, to = #targets }
			for _, d in ipairs(targets) do
				d.Mock.chat.Receive(e.prefix, e.message, e.chatType, c.full, e.target)
				checkErrors(d)
			end
		end
		c.seen = #sent
	end
end

-- Moves every client's time by `seconds` in steps, delivering the messages after each step.
function Net:Advance(seconds)
	local target = self.elapsed + seconds
	while self.elapsed < target - 1e-9 do
		local dt = math.min(self.step, target - self.elapsed)
		for _, c in ipairs(self.order) do
			c.Mock.Advance(dt, dt)
			checkErrors(c)
		end
		self.elapsed = self.elapsed + dt
		self:Deliver()
	end
end

-- Runs fn(client) on every client, in the order they logged in, and fails on a Lua error of any of them.
function Net:Each(fn)
	for _, c in ipairs(self.order) do
		fn(c)
		checkErrors(c)
	end
end

-- The server's roll message of `name` on every client in the raid (a player without the addon rolls with /roll too).
function Net:Roll(name, value, lo, hi)
	for _, c in ipairs(self.order) do
		if inRaid(self, c.name) then
			c.Mock.loot.Roll(name, value, lo or 1, hi or 100)
			checkErrors(c)
		end
	end
end

-- The loot message of `name` (the item reached their bags) on every client in the raid; the player's own client reads
-- it as "You receive loot".
function Net:Loot(name, link)
	for _, c in ipairs(self.order) do
		if inRaid(self, c.name) then
			c.Mock.loot.Receive(c.name ~= name and name or nil, link)
			checkErrors(c)
		end
	end
end

-- A boss encounter on every client: "start", "kill" or "wipe".
function Net:Encounter(id, name, what)
	self:Each(function(c)
		if what == "start" then c.Mock.encounter.Start(id, name) else c.Mock.encounter.End(id, name, what == "kill") end
	end)
end

-- The chat lockdown on every client.
function Net:Lockdown(on)
	self:Each(function(c) c.Mock.chat.lockdown = on and true or false end)
end

-- How many messages of addon-message prefix `prefix` and chat type `chatType` client `name` sent so far.
function Net:SentBy(name, chatType, prefix)
	local c = assert(self.clients[name], "no client " .. tostring(name))
	local n = 0
	for _, e in ipairs(c.Mock.chat.sent) do
		if (chatType == nil or e.chatType == chatType) and (prefix == nil or e.prefix == prefix) then n = n + 1 end
	end
	return n
end

return Sim
