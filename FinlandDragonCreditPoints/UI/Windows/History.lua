-- HistoryWindow: the History tab (docs/ANALISI.md §7, docs/specs/ui-style.md §6, M6-1): the sub-tabs Nights, Log, Audit,
-- Export, and Backup. **Nights** is here; **Log** and **Audit** are UI/Windows/Log.lua and Audit.lua (M6-2); **Export** is
-- UI/Windows/Export.lua (M6-3); **Backup** is UI/Windows/Backup.lua (M6-7). Nights: the nights of a season by week, newest first, with the instance, the bosses killed, the drops and the credits spent; the
-- selected night opens its detail (the bosses, what dropped to whom and, for the officers only, the lineup and the bench) and
-- from a drop the Member and Item windows open. Everything comes from Domain/History.lua; this file draws. Lua 5.1.
-- Not verified in the real client: the tab's look in game (the owner's M6 checklist).
local ADDON_NAME, ns = ...
ns = ns or {}
local HistoryWindow = {}
ns.HistoryWindow = HistoryWindow
if ns.addon then ns.addon.HistoryWindow = HistoryWindow end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

HistoryWindow.SUBTABS = { "nights", "log", "audit", "export", "backup" }
HistoryWindow.DETAIL_ROWS = 8
HistoryWindow.DROP_ROW_H = 26

local function RC() return ns.RosterController end
local function short(name) return (tostring(name or "?"):gsub("%-.*$", "")) end
local function num(n)
	if type(n) ~= "number" then return tostring(n) end
	return (("%.2f"):format(n):gsub("0+$", ""):gsub("%.$", ""))
end
-- A boss's name: the client's Encounter Journal first, else the site's English name, else the number.
function HistoryWindow.BossName(encounterID)
	local _, boss = ns.Instances.OfEncounter(encounterID)
	if not boss then return tostring(encounterID) end
	local E = ns.Compat and ns.Compat.Encounter
	local localName = E and E.JournalName and E.JournalName(boss.journalID, boss.encounterID)
	return localName or boss.name
end

local function instanceName(id)
	local inst = ns.Instances and ns.Instances.Get(id)
	return inst and inst.name or tostring(id)
end

-- locale-key: DIFFICULTY_normal DIFFICULTY_veteran
local function difficultyName(code) return L["DIFFICULTY_" .. tostring(code)] end

---------------------------------------------------------------------------------------------------------------------
-- State

HistoryWindow.season, HistoryWindow.nightId, HistoryWindow.dropId = nil, nil, nil

-- The season shown: the one picked, else the one in use, else the newest.
function HistoryWindow:CurrentSeason(seasons)
	for _, s in ipairs(seasons) do if s.id == self.season then return s.id end end
	local cur = RC() and RC():Season()
	if cur then
		for _, s in ipairs(seasons) do if s.id == cur.id then return cur.id end end
	end
	return seasons[1] and seasons[1].id or nil
end

-- The button steps through the seasons, newest first.
function HistoryWindow:CycleSeason()
	local ledger = RC() and RC():Ledger()
	if not ledger then return end
	local seasons = ns.CreditTable.Seasons(ledger)
	local cur, idx = self:CurrentSeason(seasons), 0
	for i, s in ipairs(seasons) do if s.id == cur then idx = i end end
	if #seasons == 0 then return end
	self.season = seasons[idx % #seasons + 1].id
	self.nightId, self.dropId = nil, nil
	self:Refresh()
end

function HistoryWindow:SelectNight(id)
	self.nightId, self.dropId = id, nil
	self:Refresh()
end

---------------------------------------------------------------------------------------------------------------------
-- Build

-- locale-key: HISTORY_SUB_NIGHTS HISTORY_SUB_LOG HISTORY_SUB_AUDIT HISTORY_SUB_EXPORT HISTORY_SUB_BACKUP
function HistoryWindow:Build(page)
	if self.root then return self.root end
	local root = CreateFrame("Frame", nil, page)
	root:SetAllPoints(page)
	self.root, self.page = root, page
	local items = {}
	for _, id in ipairs(self.SUBTABS) do items[#items + 1] = { id = id, text = L["HISTORY_SUB_" .. id:upper()] } end
	root.sub = Widgets.Segmented(root, items, function(id) HistoryWindow:ShowSub(id) end)
	root.sub:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -4)
	root.panes = {}
	for _, id in ipairs(self.SUBTABS) do
		local pane = CreateFrame("Frame", nil, root)
		pane:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -44)
		pane:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
		pane:Hide()
		root.panes[id] = pane
	end
	self:BuildNights(root.panes.nights)
	if ns.LogWindow then ns.LogWindow:Build(root.panes.log) end
	if ns.AuditWindow then ns.AuditWindow:Build(root.panes.audit) end
	if ns.ExportWindow then ns.ExportWindow:Build(root.panes.export) end
	if ns.BackupWindow then ns.BackupWindow:Build(root.panes.backup) end
	root.sub:Select("nights")
	self:Refresh()
	return root
end

function HistoryWindow:ShowSub(id)
	if not self.root then return end
	for pid, pane in pairs(self.root.panes) do pane:SetShown(pid == id) end
	if id == "nights" then self:Refresh()
	elseif id == "log" and ns.LogWindow then ns.LogWindow:Refresh()
	elseif id == "audit" and ns.AuditWindow then ns.AuditWindow:Refresh()
	elseif id == "export" and ns.ExportWindow then ns.ExportWindow:Refresh()
	elseif id == "backup" and ns.BackupWindow then ns.BackupWindow:Refresh() end
end

function HistoryWindow:ActiveSub() return self.root and self.root.sub:Active() end

-- locale-key: HISTORY_COL_WEEK HISTORY_COL_DATE HISTORY_COL_INSTANCE HISTORY_COL_BOSSES HISTORY_COL_DROPS HISTORY_COL_SPENT
local function nightColumns()
	return {
		{ id = "week", title = L["HISTORY_COL_WEEK"], width = 70, mono = true, token = function() return "text-3" end,
			text = function(d) return d.firstOfWeek and ns.MemberWindow.DayOf(d.week) or "" end, value = function(d) return d.date end },
		{ id = "date", title = L["HISTORY_COL_DATE"], width = 64, mono = true, text = function(d) return ns.MemberWindow.DayOf(d.date) end,
			value = function(d) return d.date end },
		{ id = "instance", title = L["HISTORY_COL_INSTANCE"], flex = 1, text = function(d) return instanceName(d.instanceID) end,
			value = function(d) return instanceName(d.instanceID):lower() end },
		{ id = "bosses", title = L["HISTORY_COL_BOSSES"], width = 70, align = "CENTER", mono = true,
			text = function(d) return d.bossTotal and (#d.bosses .. "/" .. d.bossTotal) or tostring(#d.bosses) end,
			value = function(d) return #d.bosses end },
		{ id = "drops", title = L["HISTORY_COL_DROPS"], width = 60, align = "CENTER", mono = true,
			text = function(d) return tostring(d.dropCount) end, value = function(d) return d.dropCount end },
		{ id = "spent", title = L["HISTORY_COL_SPENT"], width = 70, align = "RIGHT", mono = true,
			text = function(d) return num(d.spent) end, value = function(d) return d.spent end },
	}
end

-- locale-key: HISTORY_COL_ITEM HISTORY_COL_TO HISTORY_COL_COST
local function dropColumns()
	return {
		{ id = "item", title = L["HISTORY_COL_ITEM"], flex = 1.4, text = function(d) return (ns.MemberWindow.ItemLine(d.item)) end,
			render = function(fs, d)
				local name, color = ns.MemberWindow.ItemLine(d.item)
				fs:SetText(d.voided and (name .. " " .. L["ITEM_DROP_VOIDED"]) or name)
				if d.voided then Theme.Text(fs, "text-3") else Theme.TextRGB(fs, color[1], color[2], color[3]) end
			end },
		{ id = "to", title = L["HISTORY_COL_TO"], flex = 1, text = function(d)
			return d.target == "member" and short(d.member) or L["HISTORY_TARGET_" .. d.target:upper()]
		end },
		{ id = "cost", title = L["HISTORY_COL_COST"], width = 64, align = "RIGHT", mono = true, text = function(d) return num(d.cost) end,
			value = function(d) return d.cost end },
	}
end

-- locale-key: HISTORY_TITLE HISTORY_SELECT_NIGHT HISTORY_OPEN_MEMBER HISTORY_OPEN_ITEM
function HistoryWindow:BuildNights(pane)
	local n = { pane = pane }
	self.nights = n
	n.eyebrow = Theme.NewText(pane, "Eyebrow", "accent-text")
	n.eyebrow:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -4)
	n.title = Theme.NewText(pane, "H1", "text-1")
	n.title:SetPoint("TOPLEFT", n.eyebrow, "BOTTOMLEFT", 0, -4)
	n.title:SetText(L["HISTORY_TITLE"])
	n.seasonBtn = Widgets.Button(pane, { text = "", style = "ghost", width = 190, height = 28, onClick = function() HistoryWindow:CycleSeason() end })
	n.seasonBtn:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -4)
	n.empty = Theme.NewText(pane, "Body", "text-3")
	n.empty:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -80)

	-- the list of nights, left; the detail of the selected one, right
	n.table = Widgets.DataTable(pane, nightColumns(), {
		rowHeight = 32, headerHeight = 30, pool = 20,
		onRowClick = function(d) HistoryWindow:SelectNight(d.id) end,
		rowSetup = function(r)
			r.sel = r:CreateTexture(nil, "BACKGROUND")
			Theme.Fill(r.sel, "accent", 0.12)
			r.sel:SetAllPoints(r)
			r.sel:Hide()
		end,
		rowUpdate = function(r, d) r.sel:SetShown(d.id == HistoryWindow.nightId) end,
	})
	n.table:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -78)
	n.table:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 0)
	n.table:SetWidth(520)
	n.table:SetEmptyText(L["HISTORY_NO_NIGHTS"])

	n.detail = Widgets.Card(pane, { height = 300 })
	n.detail:SetPoint("TOPLEFT", pane, "TOPLEFT", 536, -78)
	n.detail:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
	n.head = Theme.NewText(n.detail, "BodyMedium", "text-1")
	n.head:SetPoint("TOPLEFT", n.detail, "TOPLEFT", 16, -14)
	n.bosses = Theme.NewText(n.detail, "Small", "text-2")
	n.bosses:SetPoint("TOPLEFT", n.head, "BOTTOMLEFT", 0, -6)
	n.bosses:SetWidth(360)
	n.bosses:SetJustifyH("LEFT")
	n.raid = Theme.NewText(n.detail, "Small", "text-2")
	n.raid:SetPoint("TOPLEFT", n.bosses, "BOTTOMLEFT", 0, -6)
	n.raid:SetWidth(360)
	n.raid:SetJustifyH("LEFT")
	n.bench = Theme.NewText(n.detail, "Small", "text-2")
	n.bench:SetPoint("TOPLEFT", n.raid, "BOTTOMLEFT", 0, -6)
	n.bench:SetWidth(360)
	n.bench:SetJustifyH("LEFT")
	n.drops = Widgets.DataTable(n.detail, dropColumns(), {
		rowHeight = self.DROP_ROW_H, headerHeight = 26, pool = 24,
		onRowClick = function(d) HistoryWindow.dropId = d.id; HistoryWindow:PaintButtons() end,
	})
	n.drops:SetPoint("TOPLEFT", n.detail, "TOPLEFT", 12, -112)
	n.drops:SetPoint("BOTTOMRIGHT", n.detail, "BOTTOMRIGHT", -12, 52)
	n.drops:SetEmptyText(L["HISTORY_NO_DROPS"])
	n.member = Widgets.Button(n.detail, { text = L["HISTORY_OPEN_MEMBER"], style = "secondary", width = 120, height = 30,
		onClick = function() HistoryWindow:OpenMember() end })
	n.member:SetPoint("BOTTOMLEFT", n.detail, "BOTTOMLEFT", 16, 12)
	n.item = Widgets.Button(n.detail, { text = L["HISTORY_OPEN_ITEM"], style = "secondary", width = 120, height = 30,
		onClick = function() HistoryWindow:OpenItem() end })
	n.item:SetPoint("LEFT", n.member, "RIGHT", 8, 0)
	n.hint = Theme.NewText(n.detail, "Body", "text-3")
	n.hint:SetPoint("TOPLEFT", n.detail, "TOPLEFT", 16, -16)
	n.hint:SetText(L["HISTORY_SELECT_NIGHT"])
end

---------------------------------------------------------------------------------------------------------------------
-- Actions

local function selectedDrop(self)
	for _, d in ipairs(self.dropList or {}) do if d.id == self.dropId then return d end end
end

function HistoryWindow:OpenMember()
	local d = selectedDrop(self)
	if d and d.target == "member" and d.member and ns.MemberWindow then return ns.MemberWindow:Show(d.member, self.seasonShown) end
end

function HistoryWindow:OpenItem()
	local d = selectedDrop(self)
	if d and ns.ItemWindow then return ns.ItemWindow:Show(d.item) end
end

function HistoryWindow:PaintButtons()
	local n = self.nights
	if not n then return end
	local d = selectedDrop(self)
	local function enable(b, on) b:SetEnabled(on and true or false); b:SetAlpha(on and 1 or 0.45) end
	enable(n.member, d and d.target == "member" and d.member)
	enable(n.item, d ~= nil)
	self.nights.table:Refresh()
end

---------------------------------------------------------------------------------------------------------------------
-- Refresh

local function names(list)
	local out = {}
	for i, name in ipairs(list or {}) do out[i] = short(name) end
	return table.concat(out, ", ")
end

-- locale-key: HISTORY_NIGHT_HEAD HISTORY_BOSSES_LINE HISTORY_NO_BOSSES HISTORY_RAID_LINE HISTORY_BENCH_LINE
function HistoryWindow:Refresh()
	local n = self.nights
	if not n or not self.root then return end
	local ledger = RC() and RC():Ledger()
	local seasons = ledger and ns.CreditTable.Seasons(ledger) or {}
	if #seasons == 0 then
		n.eyebrow:SetText("")
		n.empty:SetText(L[ledger and "ROSTER_NO_SEASON" or "ROSTER_NOT_READY"])
		n.table:Hide(); n.detail:Hide(); n.seasonBtn:Hide()
		return
	end
	n.empty:SetText("")
	n.table:Show(); n.detail:Show(); n.seasonBtn:Show()
	local season = self:CurrentSeason(seasons)
	self.seasonShown = season
	local label
	for _, s in ipairs(seasons) do if s.id == season then label = s.label or tostring(s.id) end end
	n.eyebrow:SetText(L["HISTORY_EYEBROW"]:format(label):upper())
	n.seasonBtn:SetLabel(label .. " ▾")
	local attendance = ns.MemberWindow.CanSeeAttendance()
	local view = ns.History.Nights(ledger, season, { attendance = attendance })
	self.view = view
	local rows = {}
	for _, week in ipairs(view.weeks) do
		for i, night in ipairs(week.nights) do
			night.firstOfWeek = i == 1
			rows[#rows + 1] = night
		end
	end
	n.table:SetData(rows)
	n.table:SortBy("date", true)
	local found
	for _, night in ipairs(view.nights) do if night.id == self.nightId then found = night end end
	found = found or view.nights[1]
	self.nightId = found and found.id or nil
	if not found then
		n.head:SetText(""); n.bosses:SetText(""); n.raid:SetText(""); n.bench:SetText("")
		n.hint:SetText(L["HISTORY_NO_NIGHTS"]); n.hint:Show()
		n.drops:Hide(); n.member:Hide(); n.item:Hide()
		self.dropList = {}
		return
	end
	n.hint:Hide(); n.drops:Show(); n.member:Show(); n.item:Show()
	n.head:SetText(L["HISTORY_NIGHT_HEAD"]:format(found.date or "", instanceName(found.instanceID), found.size, difficultyName(found.difficulty)))
	if #found.bosses == 0 then
		n.bosses:SetText(L["HISTORY_NO_BOSSES"])
	else
		local list = {}
		for i, id in ipairs(found.bosses) do
			list[i] = HistoryWindow.BossName(id)
		end
		n.bosses:SetText(L["HISTORY_BOSSES_LINE"]:format(table.concat(list, ", ")))
	end
	if found.lineup then
		n.raid:SetText(L["HISTORY_RAID_LINE"]:format(#found.lineup.raid, names(found.lineup.raid)))
		n.bench:SetText(L["HISTORY_BENCH_LINE"]:format(#found.lineup.bench, names(found.lineup.bench)))
		n.raid:Show(); n.bench:Show()
	else
		n.raid:SetText(""); n.bench:SetText("")
		n.raid:Hide(); n.bench:Hide()
	end
	self.dropList = found.drops
	local keep
	for _, d in ipairs(found.drops) do if d.id == self.dropId then keep = d end end
	self.dropId = keep and keep.id or nil
	n.drops:SetData(found.drops)
	self:PaintButtons()
end

if ns.Bus then
	for _, ev in ipairs({ "ROSTER_UPDATED", "GUILD_RANKS_READY", "GUILD_KEY_CHANGED", "NIGHT_OPENED", "NIGHT_CLOSED" }) do
		ns.Bus:On(ev, function() HistoryWindow:Refresh() end, HistoryWindow)
	end
end
