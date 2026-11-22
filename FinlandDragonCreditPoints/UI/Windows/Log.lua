-- LogWindow: History › Log (docs/ANALISI.md §7, docs/specs/ui-style.md §6, M6-2): everything that dropped in a season,
-- assigned or not: the night, the boss, the item, who got it, for which response and at what cost. A voided award stays,
-- marked. Filters (all / given / not given / cancelled) and a search on the item, the member and the boss. Everything comes
-- from Domain/History.lua (the local ledger); awards are public, so nothing here is for the officers only. Lua 5.1.
-- Not verified in the real client: the pane's look in game (the owner's M6 checklist).
local ADDON_NAME, ns = ...
ns = ns or {}
local LogWindow = {}
ns.LogWindow = LogWindow
if ns.addon then ns.addon.LogWindow = LogWindow end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

LogWindow.STATES = { "all", "assigned", "unassigned", "voided" }
LogWindow.state, LogWindow.search = "all", ""

local function RC() return ns.RosterController end
local function short(name) return (tostring(name or "?"):gsub("%-.*$", "")) end
local function num(n)
	if type(n) ~= "number" then return tostring(n) end
	return (("%.2f"):format(n):gsub("0+$", ""):gsub("%.$", ""))
end

-- The words of a row's recipient: the member, or where the item went, or "not given".
-- locale-key: HISTORY_TARGET_BANK HISTORY_TARGET_DISENCHANT HISTORY_TARGET_ML HISTORY_TARGET_NONE
function LogWindow.Recipient(row)
	if row.target == "member" then return short(row.member) end
	return L["HISTORY_TARGET_" .. tostring(row.target):upper()]
end

-- The response of a row in words ("Main spec", ...), or "".
function LogWindow.Response(row)
	return row.response and ns.Reasons.Text("RESPONSE", row.response) or ""
end

local function bossText(row)
	return row.boss and ns.HistoryWindow.BossName(row.boss) or ""
end

-- The rows of the log that pass the state and the search (text: part of the item's name, the member's name or the
-- boss's name, any case). Pure on its inputs: tests call it without a window.
function LogWindow.Filter(rows, state, search)
	local f = ns.History.FilterLog(rows, { state = state ~= "all" and state or nil })
	local q = (search or ""):lower()
	if q == "" then return f end
	local out = {}
	for _, r in ipairs(f) do
		local name = (ns.MemberWindow.ItemLine(r.item))
		local hay = (tostring(name) .. " " .. tostring(r.item) .. " " .. short(r.member) .. " " .. bossText(r)):lower()
		if hay:find(q, 1, true) then out[#out + 1] = r end
	end
	return out
end

-- locale-key: HISTORY_COL_DATE HISTORY_COL_BOSS HISTORY_COL_ITEM HISTORY_COL_TO HISTORY_COL_RESPONSE HISTORY_COL_COST
local function columns()
	return {
		{ id = "date", title = L["HISTORY_COL_DATE"], width = 64, mono = true, text = function(d) return ns.MemberWindow.DayOf(d.nightDate) end,
			value = function(d) return d.ts end },
		{ id = "boss", title = L["HISTORY_COL_BOSS"], flex = 1, text = bossText, value = function(d) return bossText(d):lower() end },
		{ id = "item", title = L["HISTORY_COL_ITEM"], flex = 1.4, text = function(d) return (ns.MemberWindow.ItemLine(d.item)) end,
			render = function(fs, d)
				local name, color = ns.MemberWindow.ItemLine(d.item)
				fs:SetText(d.voided and (name .. " " .. L["ITEM_DROP_VOIDED"]) or name)
				if d.voided then Theme.Text(fs, "text-3") else fs:SetTextColor(color[1], color[2], color[3]) end
			end },
		{ id = "to", title = L["HISTORY_COL_TO"], flex = 1, text = LogWindow.Recipient },
		{ id = "response", title = L["HISTORY_COL_RESPONSE"], width = 110, text = LogWindow.Response },
		{ id = "cost", title = L["HISTORY_COL_COST"], width = 64, align = "RIGHT", mono = true,
			text = function(d) return d.kind == "AWARD" and num(d.cost) or "" end, value = function(d) return d.cost end },
	}
end

-- locale-key: HISTORY_LOG_ALL HISTORY_LOG_ASSIGNED HISTORY_LOG_UNASSIGNED HISTORY_LOG_VOIDED HISTORY_LOG_SEARCH
-- locale-key: HISTORY_LOG_EMPTY
function LogWindow:Build(pane)
	if self.pane then return self.pane end
	self.pane = pane
	local items = {}
	for _, id in ipairs(self.STATES) do items[#items + 1] = { id = id, text = L["HISTORY_LOG_" .. id:upper()] } end
	self.filter = Widgets.Segmented(pane, items, function(id) LogWindow:SetState(id) end)
	self.filter:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -4)
	self.box = Widgets.EditBox(pane, { width = 220, height = 28, maxLetters = 40, onChange = function(text, user)
		if user then LogWindow:SetSearch(text) end
	end })
	self.box:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -4)
	self.hint = Theme.NewText(pane, "Small", "text-3")
	self.hint:SetPoint("RIGHT", self.box, "LEFT", -8, 0)
	self.hint:SetText(L["HISTORY_LOG_SEARCH"])
	self.count = Theme.NewText(pane, "Small", "text-2")
	self.count:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -44)
	self.table = Widgets.DataTable(pane, columns(), { rowHeight = 30, headerHeight = 28, pool = 24 })
	self.table:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -66)
	self.table:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
	self.table:SetEmptyText(L["HISTORY_LOG_EMPTY"])
	self.filter:Select("all")
	return pane
end

function LogWindow:SetState(id)
	self.state = id
	self:Refresh()
end

function LogWindow:SetSearch(text)
	self.search = text or ""
	self:Refresh()
end

-- locale-key: HISTORY_LOG_COUNT
function LogWindow:Refresh()
	if not self.table then return end
	local ledger = RC() and RC():Ledger()
	local season = ns.HistoryWindow and ns.HistoryWindow.seasonShown
	local all = ledger and season and ns.History.Log(ledger, season) or {}
	self.all = all
	local rows = LogWindow.Filter(all, self.state, self.search)
	self.rows = rows
	self.table:SetData(rows)
	self.table:SortBy("date", true)
	self.count:SetText(L["HISTORY_LOG_COUNT"]:format(#rows, #all))
end

if ns.Bus then
	for _, ev in ipairs({ "ROSTER_UPDATED", "NIGHT_OPENED", "NIGHT_CLOSED" }) do
		ns.Bus:On(ev, function() LogWindow:Refresh() end, LogWindow)
	end
end
