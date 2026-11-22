-- MemberWindow: the history of one member (docs/ANALISI.md §7 "Membro", docs/specs/ui-style.md §6, M6-1): the items they won,
-- how their credits went (the curve, one line per move), what the council did about them and, **for the officers only**
-- (`view.attendance`, §6), their attendance. Everything comes from Domain/History.lua, read from the local ledger; the
-- attendance is asked for only when the player holds the permission, so the data is not even in the window of a member.
-- Lua 5.1; unprotected frames.
-- Not verified in the real client: the window's look in game (the owner's M6 checklist).
local ADDON_NAME, ns = ...
ns = ns or {}
local MemberWindow = {}
ns.MemberWindow = MemberWindow
if ns.addon then ns.addon.MemberWindow = MemberWindow end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

MemberWindow.FRAME_NAME = "FDCPMemberFrame"

local function short(name) return (tostring(name or "?"):gsub("%-.*$", "")) end
local function num(n)
	if type(n) ~= "number" then return tostring(n) end
	return (("%.2f"):format(n):gsub("0+$", ""):gsub("%.$", ""))
end
local function plus(n) return (n >= 0 and "+" or "") .. num(n) end

-- "14/10" from a night's date, or "" when it has none.
local function dayOf(date)
	local _, m, d = tostring(date or ""):match("^(%d+)%-(%d+)%-(%d+)$")
	return m and (d .. "/" .. m) or ""
end
MemberWindow.DayOf = dayOf

local function ML() return ns.MLSession end

-- The colour and name of an item as the session shows them.
local function itemLine(id)
	local info = ML() and ML():ItemInfo(id) or {}
	local name = ML() and ML().ItemName(id, info) or tostring(id)
	local r, g, b = 1, 1, 1
	if ML() then r, g, b = ML().QualityColor(info.quality) end
	return name, { r, g, b }
end
MemberWindow.ItemLine = itemLine

-- Whether the player may see the attendance (view.attendance): officers by default.
function MemberWindow.CanSeeAttendance()
	local NC = ns.NightController
	if not NC then return false end
	local ok = NC:Can("view.attendance")
	return ok and true or false
end

-- The lines of the window for the data of History.Member: a list of { text, token?, color?, head?, onClick? }.
-- locale-key: MEMBER_CREDITS MEMBER_ITEMS_HEAD MEMBER_NO_ITEMS MEMBER_ITEM_LINE MEMBER_ITEM_VOIDED MEMBER_CURVE_HEAD
-- locale-key: MEMBER_CURVE_LINE MEMBER_COUNCIL_HEAD MEMBER_NO_COUNCIL MEMBER_ATT_HEAD MEMBER_ATT_LINE MEMBER_ATT_NIGHT
-- locale-key: HISTORY_KIND_START HISTORY_KIND_AWARD HISTORY_KIND_ADJUST HISTORY_STATE_PLAYED HISTORY_STATE_BENCH HISTORY_STATE_ABSENT
function MemberWindow.BuildLines(data, openItem)
	local lines = {}
	local function add(text, extra)
		local line = { text = text }
		for k, v in pairs(extra or {}) do line[k] = v end
		lines[#lines + 1] = line
	end
	add(L["MEMBER_CREDITS"]:format(num(data.total), num(data.initial)), { token = "text-1" })
	add("")
	add(L["MEMBER_ITEMS_HEAD"]:upper(), { head = true })
	if #data.items == 0 then add(L["MEMBER_NO_ITEMS"], { token = "text-3" }) end
	for i = #data.items, 1, -1 do
		local a = data.items[i]
		local name, color = itemLine(a.item)
		local text = L["MEMBER_ITEM_LINE"]:format(dayOf(a.nightDate), name, num(a.cost))
		if a.voided then text = text .. " " .. L["MEMBER_ITEM_VOIDED"] end
		add(text, { color = not a.voided and color or nil, token = a.voided and "text-3" or nil,
			onClick = openItem and function() openItem(a.item) end or nil })
	end
	add("")
	add(L["MEMBER_CURVE_HEAD"]:upper(), { head = true })
	for _, p in ipairs(data.curve) do
		add(L["MEMBER_CURVE_LINE"]:format(L["HISTORY_KIND_" .. p.kind], plus(p.delta), num(p.total)), { token = "text-2" })
	end
	add("")
	add(L["MEMBER_COUNCIL_HEAD"]:upper(), { head = true })
	if #data.council == 0 then add(L["MEMBER_NO_COUNCIL"], { token = "text-3" }) end
	for _, entry in ipairs(data.council) do
		add(ns.CouncilService.AuditLine(entry), { token = entry.voided and "text-3" or "text-2" })
	end
	if data.attendance then
		local a = data.attendance
		add("")
		add(L["MEMBER_ATT_HEAD"]:upper(), { head = true })
		add(L["MEMBER_ATT_LINE"]:format(a.played, a.benched, a.bosses, a.possible, a.percent), { token = "text-1" })
		for _, n in ipairs(a.perNight) do
			add(L["MEMBER_ATT_NIGHT"]:format(dayOf(n.date), L["HISTORY_STATE_" .. n.state]), { token = "text-2" })
		end
	end
	return lines
end

function MemberWindow:Build()
	if self.frame then return self.frame end
	self.frame = Widgets.LineWindow({ name = self.FRAME_NAME, title = L["MEMBER_TITLE"], width = 480, x = 40, y = 0 })
	return self.frame
end

-- Opens the window on a member (their main's full name) of a season (default: the one in use).
function MemberWindow:Show(member, season)
	local RC = ns.RosterController
	local ledger = RC and RC:Ledger()
	if not ledger then return false, "NOT_READY" end
	season = season or (RC:Season() and RC:Season().id)
	if not season then return false, "NO_SEASON" end
	local data, why = ns.History.Member(ledger, season, member, { attendance = self.CanSeeAttendance() })
	if not data then return false, why end
	local f = self:Build()
	self.data, self.shown = data, member
	f:SetHeader(short(member), L["MEMBER_SUB"]:format(ns.RosterWindow and ns.RosterWindow.ClassName(data.class) or "", tostring(season)))
	f:SetLines(self.BuildLines(data, function(item) if ns.ItemWindow then ns.ItemWindow:Show(item) end end))
	f:Open()
	return true
end

function MemberWindow:Close() if self.frame then self.frame:Hide() end end
function MemberWindow:IsShown() return self.frame ~= nil and self.frame:IsShown() end
