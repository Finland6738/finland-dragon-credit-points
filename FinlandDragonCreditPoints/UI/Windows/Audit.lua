-- AuditWindow: History › Audit (docs/ANALISI.md §7, docs/specs/ui-style.md §6, M6-2): what the council and the Guild Master
-- did outside the rules, with the reason and the author: awards that departed from the rule, corrections of category or
-- cost, votes, voids, manual adjustments (Domain/Council.lua's audit) and the changes of the guild's configuration
-- (Domain/History.lua, with the settings that changed), the compactions and the restores (M6-7). Filter by kind and search on the words of a line. Everything comes
-- from the local ledger. Lua 5.1. Not verified in the real client: the pane's look in game (the owner's M6 checklist).
local ADDON_NAME, ns = ...
ns = ns or {}
local AuditWindow = {}
ns.AuditWindow = AuditWindow
if ns.addon then ns.addon.AuditWindow = AuditWindow end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

-- The filters: the kinds of entry each one keeps.
AuditWindow.FILTERS = { "all", "council", "void", "adjust", "config" }
AuditWindow.KINDS = {
	council = { MODIFY = true, CORRECT = true, VOTE = true },
	void = { VOID = true },
	adjust = { ADJUST = true },
	config = { CONFIG = true, PERMISSIONS = true, COMPACTED = true, RESTORED = true },
}
AuditWindow.filter, AuditWindow.search = "all", ""
AuditWindow.CHANGES_SHOWN = 4

local function RC() return ns.RosterController end
local function short(name) return (tostring(name or "?"):gsub("%-.*$", "")) end

-- The sentence of one entry. Council entries use the council's own line (the same words as /fdcp council audit).
-- locale-key: AUDIT_CONFIG AUDIT_CONFIG_PRESET AUDIT_CONFIG_MORE AUDIT_PERMISSIONS AUDIT_COMPACTED AUDIT_RESTORED
-- locale-key: AUDIT_RESTORED_ARCHIVE
function AuditWindow.Line(entry)
	if entry.kind == "CONFIG" then
		local shown = {}
		for i = 1, math.min(#entry.changes, AuditWindow.CHANGES_SHOWN) do shown[i] = entry.changes[i] end
		local text = L["AUDIT_CONFIG"]:format(#entry.changes, table.concat(shown, ", "))
		if #entry.changes > #shown then text = text .. " " .. L["AUDIT_CONFIG_MORE"]:format(#entry.changes - #shown) end
		if entry.preset then text = text .. " " .. L["AUDIT_CONFIG_PRESET"]:format(ns.Reasons.Text("PRESET", entry.preset)) end
		return short(entry.author) .. ": " .. text
	elseif entry.kind == "PERMISSIONS" then
		return short(entry.author) .. ": " .. L["AUDIT_PERMISSIONS"]
	elseif entry.kind == "COMPACTED" then
		return short(entry.author) .. ": " .. L["AUDIT_COMPACTED"]:format(entry.removed or 0)
	elseif entry.kind == "RESTORED" then
		return short(entry.author) .. ": " .. L[entry.archive and "AUDIT_RESTORED_ARCHIVE" or "AUDIT_RESTORED"]:format(entry.added or 0)
	end
	return ns.CouncilService.AuditLine(entry)
end

-- The entries that pass the filter and the search (a part of the line, any case). Pure on its inputs.
function AuditWindow.Filter(entries, filter, search)
	local kinds = AuditWindow.KINDS[filter]
	local q = (search or ""):lower()
	local out = {}
	for _, e in ipairs(entries) do
		if (kinds == nil or kinds[e.kind]) and (q == "" or AuditWindow.Line(e):lower():find(q, 1, true)) then
			out[#out + 1] = e
		end
	end
	return out
end

local function dayOf(ts)
	local fmt = _G.date or (os and os.date)
	return (ts and fmt) and fmt("%d/%m", ts) or ""
end

-- locale-key: HISTORY_COL_DATE AUDIT_COL_ENTRY
local function columns()
	return {
		{ id = "date", title = L["HISTORY_COL_DATE"], width = 64, mono = true, text = function(d) return dayOf(d.ts) end,
			value = function(d) return d.ts end },
		{ id = "line", title = L["AUDIT_COL_ENTRY"], flex = 1, sortable = false, text = function(d) return AuditWindow.Line(d) end,
			token = function(d) return d.voided and "text-3" or "text-1" end },
	}
end

-- locale-key: AUDIT_ALL AUDIT_COUNCIL AUDIT_VOID AUDIT_ADJUST AUDIT_CONFIG_FILTER AUDIT_SEARCH AUDIT_EMPTY
function AuditWindow:Build(pane)
	if self.pane then return self.pane end
	self.pane = pane
	local names = { all = "AUDIT_ALL", council = "AUDIT_COUNCIL", void = "AUDIT_VOID", adjust = "AUDIT_ADJUST", config = "AUDIT_CONFIG_FILTER" }
	local items = {}
	for _, id in ipairs(self.FILTERS) do items[#items + 1] = { id = id, text = L[names[id]] } end
	self.seg = Widgets.Segmented(pane, items, function(id) AuditWindow:SetFilter(id) end)
	self.seg:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -4)
	self.box = Widgets.EditBox(pane, { width = 200, height = 28, maxLetters = 40, onChange = function(text, user)
		if user then AuditWindow:SetSearch(text) end
	end })
	self.box:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -4)
	self.hint = Theme.NewText(pane, "Small", "text-3")
	self.hint:SetPoint("RIGHT", self.box, "LEFT", -8, 0)
	self.hint:SetText(L["AUDIT_SEARCH"])
	self.table = Widgets.DataTable(pane, columns(), { rowHeight = 30, headerHeight = 28, pool = 24, rowSetup = function(r)
		for _, fs in ipairs(r.cells) do fs:SetWordWrap(false) end
	end })
	self.table:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -46)
	self.table:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
	self.table:SetEmptyText(L["AUDIT_EMPTY"])
	self.seg:Select("all")
	return pane
end

function AuditWindow:SetFilter(id)
	self.filter = id
	self:Refresh()
end

function AuditWindow:SetSearch(text)
	self.search = text or ""
	self:Refresh()
end

function AuditWindow:Refresh()
	if not self.table then return end
	local ledger = RC() and RC():Ledger()
	local season = ns.HistoryWindow and ns.HistoryWindow.seasonShown
	local all = ledger and season and ns.History.Audit(ledger, season) or {}
	self.all = all
	self.rows = AuditWindow.Filter(all, self.filter, self.search)
	self.table:SetData(self.rows)
	self.table:SortBy("date", true)
end

if ns.Bus then
	for _, ev in ipairs({ "ROSTER_UPDATED", "NIGHT_OPENED", "NIGHT_CLOSED" }) do
		ns.Bus:On(ev, function() AuditWindow:Refresh() end, AuditWindow)
	end
end
