-- ItemWindow: the history of one item (docs/ANALISI.md §7 "Oggetto", docs/specs/ui-style.md §6, M6-1): how many times it
-- dropped and was given, who owns it (a member who has it several times is counted), and every drop with the night, the
-- recipient and the cost. Awards are public: nothing here is for the officers only. Everything comes from
-- Domain/History.lua (the local ledger). Lua 5.1; unprotected frames.
-- Not verified in the real client: the window's look in game (the owner's M6 checklist).
local ADDON_NAME, ns = ...
ns = ns or {}
local ItemWindow = {}
ns.ItemWindow = ItemWindow
if ns.addon then ns.addon.ItemWindow = ItemWindow end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

ItemWindow.FRAME_NAME = "FDCPItemFrame"

local function short(name) return (tostring(name or "?"):gsub("%-.*$", "")) end
local function num(n)
	if type(n) ~= "number" then return tostring(n) end
	return (("%.2f"):format(n):gsub("0+$", ""):gsub("%.$", ""))
end

-- The lines of the window for the data of History.Item.
-- locale-key: ITEM_SUMMARY ITEM_OWNERS_HEAD ITEM_OWNER_LINE ITEM_NO_OWNERS ITEM_DROPS_HEAD ITEM_DROP_LINE ITEM_NO_DROPS
-- locale-key: ITEM_DROP_VOIDED HISTORY_TARGET_BANK HISTORY_TARGET_DISENCHANT HISTORY_TARGET_ML
function ItemWindow.BuildLines(data, openMember)
	local lines = {}
	local function add(text, extra)
		local line = { text = text }
		for k, v in pairs(extra or {}) do line[k] = v end
		lines[#lines + 1] = line
	end
	add(L["ITEM_SUMMARY"]:format(#data.drops, data.count, data.seen), { token = "text-1" })
	add("")
	add(L["ITEM_OWNERS_HEAD"]:upper(), { head = true })
	if #data.owners == 0 then add(L["ITEM_NO_OWNERS"], { token = "text-3" }) end
	for _, o in ipairs(data.owners) do
		add(L["ITEM_OWNER_LINE"]:format(short(o.member), o.count), { token = "text-1",
			onClick = openMember and function() openMember(o.member) end or nil })
	end
	add("")
	add(L["ITEM_DROPS_HEAD"]:upper(), { head = true })
	if #data.drops == 0 then add(L["ITEM_NO_DROPS"], { token = "text-3" }) end
	for i = #data.drops, 1, -1 do
		local d = data.drops[i]
		local to = d.target == "member" and short(d.member) or L["HISTORY_TARGET_" .. d.target:upper()]
		local text = L["ITEM_DROP_LINE"]:format(ns.MemberWindow.DayOf(d.nightDate), to, num(d.cost))
		if d.voided then text = text .. " " .. L["ITEM_DROP_VOIDED"] end
		add(text, { token = d.voided and "text-3" or "text-2",
			onClick = (openMember and d.target == "member" and d.member) and function() openMember(d.member) end or nil })
	end
	return lines
end

function ItemWindow:Build()
	if self.frame then return self.frame end
	self.frame = Widgets.LineWindow({ name = self.FRAME_NAME, title = L["ITEM_TITLE"], width = 480, x = -40, y = 0 })
	return self.frame
end

-- Opens the window on an item id (every season, or opts.season).
function ItemWindow:Show(item, opts)
	local RC = ns.RosterController
	local ledger = RC and RC:Ledger()
	if not ledger then return false, "NOT_READY" end
	local data = ns.History.Item(ledger, item, opts)
	local f = self:Build()
	self.data, self.shown = data, item
	local name = ns.MemberWindow.ItemLine(item)
	f:SetHeader(name, L["ITEM_SUB"]:format(tonumber(item) or 0))
	f:SetLines(self.BuildLines(data, function(member) if ns.MemberWindow then ns.MemberWindow:Show(member) end end))
	f:Open()
	return true
end

function ItemWindow:Close() if self.frame then self.frame:Hide() end end
function ItemWindow:IsShown() return self.frame ~= nil and self.frame:IsShown() end
