-- InspectCheck: the master looter's cross-check of a flagged player's gear (docs/ANALISI.md §5.2, M7-5d). Lua 5.1. The
-- roll-cheating evidence (Domain/Cheat.lua) comes from the player's own client, which a modified client could fake; when the
-- player is in range the master looter's client inspects them and compares the item levels worn now with what their client
-- reported (Cheat.CrossCheck). Only the gear worn now can be checked: the gear of the fight is the player's word.
--
-- Everything goes through Core/Compat.lua (CanInspect, NotifyInspect, GetInventoryItemLink on the unit, INSPECT_READY;
-- all in the Forever API dump). Throttled: one inspection every THROTTLE seconds, never twice the same player within
-- MAX_AGE, nothing during a chat lockdown or a fight (the inspection is courtesy, not a requirement).
--
-- InspectCheck:Request(name, slots)   queue an inspection of `name` (full name) for the inventory slots `slots`
-- InspectCheck:Seen(name)             { [slot] = item level (0 = empty) } of the last inspection, or nil
-- Bus event: "INSPECT_CHECKED"(name, seen).
-- Not verified in the real client: the range of CanInspect in a raid and whether INSPECT_READY carries the gear in time.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local IC = { queue = {}, seen = {}, pending = nil, lastAt = -math.huge }
ns.InspectCheck, ns.modules.InspectCheck = IC, IC

local type, pairs, ipairs, remove = type, pairs, ipairs, table.remove

IC.THROTTLE = 2      -- seconds between two inspections
IC.MAX_AGE = 120     -- seconds an inspection stands
IC.TIMEOUT = 5       -- seconds to wait for INSPECT_READY

local function C() return ns.Compat end
local function now() return C() and C().Now() or 0 end

-- The unit token of a raid member by full name, or nil.
local function unitOf(name)
	local G = C() and C().Group
	if not (G and G.Members) then return nil end
	for _, m in ipairs(G.Members()) do
		if m.name and ns.GuildRanks and ns.GuildRanks.FullName(m.name) == name then return m.unit, m.guid end
		if m.name == name then return m.unit, m.guid end
	end
	return nil
end

function IC:Seen(name)
	local s = self.seen[name]
	if not s or now() - s.at > self.MAX_AGE then return nil end
	return s.levels
end

function IC:Request(name, slots)
	if type(name) ~= "string" or type(slots) ~= "table" or #slots == 0 then return false end
	if self:Seen(name) then return false end
	for _, q in ipairs(self.queue) do if q.name == name then return false end end
	if self.pending and self.pending.name == name then return false end
	self.queue[#self.queue + 1] = { name = name, slots = slots }
	self:Pump()
	return true
end

-- Starts the next inspection when the throttle, the lockdown and the fight allow it.
function IC:Pump()
	local t = now()
	if self.pending and t - self.pending.at > self.TIMEOUT then self.pending = nil end
	if self.pending or #self.queue == 0 then return end
	if t - self.lastAt < self.THROTTLE then
		-- one wake-up for the rest of the throttle (no ticker: nothing runs while the queue is empty)
		if not self.waking and C_Timer and C_Timer.After then
			self.waking = true
			C_Timer.After(self.THROTTLE - (t - self.lastAt), function() IC.waking = nil; IC:Pump() end)
		end
		return
	end
	local c = C()
	if c.InCombat and c.InCombat() then return end
	if c.Chat and c.Chat.InChatLockdown and c.Chat.InChatLockdown() then return end
	local q = remove(self.queue, 1)
	local unit, guid = unitOf(q.name)
	if not unit or not c.Inspect.Can(unit) then return self:Pump() end
	if c.Inspect.Notify(unit) ~= "available" then return end
	self.pending = { name = q.name, unit = unit, guid = guid, slots = q.slots, at = t }
	self.lastAt = t
end

-- INSPECT_READY(guid): read the slots of the pending inspection.
function IC:OnReady(guid)
	local p = self.pending
	if not p or (guid ~= nil and p.guid ~= nil and C().Readable(guid) ~= p.guid) then return end
	self.pending = nil
	local levels = {}
	for _, slot in ipairs(p.slots) do
		local link = C().Inspect.Link(p.unit, slot)
		if link then
			local level = C().Item.Level(link)
			if level then levels[slot] = level end
		else
			levels[slot] = 0
		end
	end
	C().Inspect.Clear()
	self.seen[p.name] = { at = now(), levels = levels }
	if ns.Bus then ns.Bus:Emit("INSPECT_CHECKED", p.name, levels) end
	self:Pump()
end

if ns.addon and CreateFrame then
	ns.addon.InspectCheck = IC   -- also reachable from tests
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("INSPECT_READY")
	frame:SetScript("OnEvent", function(_, _, guid) IC:OnReady(guid) end)
end
