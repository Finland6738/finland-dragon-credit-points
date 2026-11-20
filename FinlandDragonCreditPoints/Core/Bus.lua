-- Bus: the addon's internal events (docs/ANALISI.md §8.1). Modules talk through the bus instead of calling each other.
-- A failing handler is logged and never stops the others. Lua 5.1.
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}

local Bus = { handlers = {} }
ns.Bus, ns.modules.Bus = Bus, Bus

-- Bus:On("GUILD_KEY_CHANGED", fn, owner): fn(event, ...) runs on every Emit. `owner` (any value, default fn) is what
-- Off removes. Returns the owner.
function Bus:On(event, fn, owner)
	if type(event) ~= "string" or type(fn) ~= "function" then return nil end
	owner = owner or fn
	local list = self.handlers[event]
	if not list then list = {}; self.handlers[event] = list end
	list[#list + 1] = { fn = fn, owner = owner }
	return owner
end

-- Off(event, owner) removes that owner's handlers of one event; Off(nil, owner) removes it everywhere.
function Bus:Off(event, owner)
	local removed = 0
	for name, list in pairs(self.handlers) do
		if event == nil or event == name then
			for i = #list, 1, -1 do
				if list[i].owner == owner then table.remove(list, i); removed = removed + 1 end
			end
		end
	end
	return removed
end

-- Emit runs a snapshot of the handlers, so a handler may register or remove handlers. Returns how many ran.
function Bus:Emit(event, ...)
	local list = self.handlers[event]
	if not list then return 0 end
	local snapshot, ran = {}, 0
	for i, h in ipairs(list) do snapshot[i] = h end
	for _, h in ipairs(snapshot) do
		local ok, err = pcall(h.fn, event, ...)
		ran = ran + 1
		if not ok and ns.Log then ns.Log.warn("Bus", "HANDLER_ERROR", ns.Log.Plain(event), ns.Log.Plain(tostring(err):sub(1, 80))) end
	end
	return ran
end

function Bus:Count(event)
	local list = self.handlers[event]
	return list and #list or 0
end
