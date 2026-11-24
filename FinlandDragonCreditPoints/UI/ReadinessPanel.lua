-- ReadinessPanel: "Raid readiness" (docs/ANALISI.md §4.2, docs/specs/ui-style.md §3 and §6, M8-3): the Roster > Readiness sub-tab
-- with one row per raid member (name in the class colour, status, the slots without an enchant, the state of each consumable
-- category), the Check button that asks the raid, and the Notify button that writes the summary in /raid and whispers each
-- raider what is lacking (after a confirmation). Visible only to who may ask the raid (`ReadinessCheck:CanManage()`: the runner
-- of the night or `raid.addonCheck`). Lua 5.1; unprotected frames.
-- The table and the verdicts are App/ReadinessCheck.lua's, the messages App/ReadinessNotifier.lua's; this file only draws.
-- Readiness is self-reported and transient (ADR 0010): nothing here is saved.
-- Not verified in the real client: the look of the table, the buttons, the chat (docs/checklists/M8.md section 2).
local ADDON_NAME, ns = ...
ns = ns or {}
local ReadinessPanel = {}
ns.ReadinessPanel = ReadinessPanel
if ns.addon then ns.addon.ReadinessPanel = ReadinessPanel end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

ReadinessPanel.ROW_H = 26
-- the consumable columns, in the order of the table
ReadinessPanel.CATEGORIES = { "FOOD_BUFF", "FOOD", "FLASK", "POTION", "WATER", "AMMO", "PET_FOOD" }
-- worst first
ReadinessPanel.STATUS_RANK = { MISSING = 1, WARN = 2, UNKNOWN = 3, OK = 4 }
ReadinessPanel.STATUS_TOKEN = { OK = "ok", WARN = "warn", MISSING = "err", UNKNOWN = "text-3" }

local function check() return ns.ReadinessCheck end
local function notifier() return ns.ReadinessNotifier end
local function allowed() local ok = check():CanManage(); return ok == true end
local function short(name) return (tostring(name):gsub("%-.*$", "")) end

-- The message of a refused action.
-- locale-key: READY_ERR_NOT_IN_RAID READY_ERR_DISABLED READY_ERR_TOO_SOON READY_ERR_THROTTLED READY_ERR_RANK_TOO_LOW READY_ERR_PENDING
-- locale-key: READY_ERR_NOT_IN_GUILD READY_ERR_NO_CHECK READY_ERR_NOBODY READY_ERR_BUSY READY_ERR_SEND_FAILED READY_ERR_OTHER
function ReadinessPanel.ErrorText(code, extra)
	local key = "READY_ERR_" .. tostring(code)
	if (code == "TOO_SOON" or code == "THROTTLED") and L[key] ~= key then
		return L[key]:format(math.ceil(tonumber(extra) or 0))
	end
	if L[key] ~= key then return L[key] end
	return L["READY_ERR_OTHER"]:format(tostring(code))
end

-- locale-key: READY_STATUS_OK READY_STATUS_WARN READY_STATUS_MISSING READY_STATUS_UNKNOWN
function ReadinessPanel.StatusName(status) return L["READY_STATUS_" .. tostring(status)] end

-- locale-key: READY_REASON_NOT_ASKED READY_REASON_WAITING READY_REASON_NO_ADDON READY_REASON_OFFLINE READY_REASON_NO_ANSWER
function ReadinessPanel.ReasonName(reason) return L["READY_REASON_" .. tostring(reason)] end

-- The slots without an enchant, by name: "Wrist, Hands".
function ReadinessPanel.SlotNames(result, status)
	local names = {}
	for _, e in ipairs(result and result.enchants or {}) do
		if e.status == status then names[#names + 1] = L["READY_SLOT_" .. tostring(e.slot)] end
	end
	return table.concat(names, ", ")
end

-- The enchants cell of a row: the missing slots (red), the slots that could not be read (grey), the reason of a row without
-- an answer (grey), "OK" otherwise.
function ReadinessPanel.EnchantCell(row)
	if row.reason then return ReadinessPanel.ReasonName(row.reason), "text-3" end
	local missing = ReadinessPanel.SlotNames(row.result, "MISSING")
	if missing ~= "" then return missing, "err" end
	local unknown = ReadinessPanel.SlotNames(row.result, "UNKNOWN")
	if unknown ~= "" then return unknown .. " ?", "text-3" end
	return L["READY_OK"], "ok"
end

-- The cell of one consumable category: "-" not required of this raider, "OK", "have/need" (low or none) or "?" (unknown).
function ReadinessPanel.CategoryCell(row, cat)
	local needs = ns.Readiness.Needs(check():Rules(), { class = row.class, role = row.role })
	if not needs[cat] then return "-", "text-3" end
	if row.reason then return "?", "text-3" end
	for _, it in ipairs(row.result and row.result.items or {}) do
		if it.cat == cat then
			if it.status == "UNKNOWN" then return "?", "text-3" end
			return ("%d/%d"):format(it.have or 0, it.need or needs[cat]), it.status == "WARN" and "warn" or "err"
		end
	end
	return L["READY_OK"], "ok"
end

local function columns()
	local cols = {
		{ id = "name", title = L["READY_COL_NAME"], width = 116, text = function(d) return short(d.name) end,
			value = function(d) return short(d.name):lower() end,
			render = function(fs, d)
				fs:SetText(short(d.name))
				local r, g, b = ns.RosterWindow.ClassColor(d.class)
				Theme.ClassText(fs, r, g, b)
			end },
		{ id = "status", title = L["READY_COL_STATUS"], width = 84, text = function(d) return ReadinessPanel.StatusName(d.status) end,
			token = function(d) return ReadinessPanel.STATUS_TOKEN[d.status] or "text-3" end,
			value = function(d) return ReadinessPanel.STATUS_RANK[d.status] or 9 end },
		{ id = "enchants", title = L["READY_COL_ENCHANTS"], flex = 1, text = function(d) return (ReadinessPanel.EnchantCell(d)) end,
			token = function(d) return select(2, ReadinessPanel.EnchantCell(d)) end, sortable = false },
	}
	for _, cat in ipairs(ReadinessPanel.CATEGORIES) do
		cols[#cols + 1] = { id = "cat_" .. cat, title = L["READY_CAT_" .. cat], width = 70, align = "CENTER", sortable = false,
			text = function(d) return (ReadinessPanel.CategoryCell(d, cat)) end,
			token = function(d) return select(2, ReadinessPanel.CategoryCell(d, cat)) end }
	end
	return cols
end

-- Builds the sub-tab inside `page`, the Readiness pane of the Roster tab (once).
-- locale-key: READY_COL_NAME READY_COL_STATUS READY_COL_ENCHANTS READY_CAT_FOOD_BUFF READY_CAT_FOOD READY_CAT_FLASK READY_CAT_POTION
-- locale-key: READY_CAT_WATER READY_CAT_AMMO READY_CAT_PET_FOOD
function ReadinessPanel:Build(page)
	if self.root then return self.root end
	local root = CreateFrame("Frame", nil, page)
	root:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	root:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
	self.root = root

	root.eyebrow = Theme.NewText(root, "Eyebrow", "accent-text")
	root.eyebrow:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -4)
	root.eyebrow:SetText(L["READY_TITLE"]:upper())
	root.summary = Theme.NewText(root, "MonoMedium", "text-1")
	root.summary:SetPoint("TOPLEFT", root.eyebrow, "BOTTOMLEFT", 0, -6)
	root.counts = Theme.NewText(root, "Small", "text-3")
	root.counts:SetPoint("LEFT", root.summary, "RIGHT", 12, 0)
	root.message = Theme.NewText(root, "Small", "text-2")
	root.message:SetPoint("TOPLEFT", root.summary, "BOTTOMLEFT", 0, -6)
	root.empty = Theme.NewText(root, "Body", "text-3")
	root.empty:SetPoint("TOPLEFT", root.message, "BOTTOMLEFT", 0, -16)

	root.notify = Widgets.Button(root, { text = L["READY_NOTIFY"], style = "primary", width = 190, onClick = function() ReadinessPanel:OnNotify() end })
	root.notify:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
	root.ask = Widgets.Button(root, { text = L["READY_CHECK"], style = "secondary", width = 150, onClick = function() ReadinessPanel:OnCheck() end })
	root.ask:SetPoint("RIGHT", root.notify, "LEFT", -8, 0)

	-- the confirmation of the notify button, in the place of the message line
	local c = CreateFrame("Frame", nil, root)
	c:SetHeight(30)
	c:SetPoint("TOPLEFT", root.summary, "BOTTOMLEFT", 0, -6)
	c:SetPoint("RIGHT", root, "RIGHT", 0, 0)
	c.text = Theme.NewText(c, "Body", "text-1")
	c.text:SetPoint("LEFT", c, "LEFT", 0, 0)
	c.yes = Widgets.Button(c, { text = L["READY_CONFIRM"], style = "primary", width = 130, height = 28, onClick = function() ReadinessPanel:OnConfirm() end })
	c.yes:SetPoint("RIGHT", c, "RIGHT", 0, 0)
	c.no = Widgets.Button(c, { text = L["READY_CANCEL"], style = "ghost", width = 100, height = 28, onClick = function() ReadinessPanel:OnCancel() end })
	c.no:SetPoint("RIGHT", c.yes, "LEFT", -8, 0)
	c:Hide()
	root.confirm = c

	root.table = Widgets.DataTable(root, columns(), { rowHeight = self.ROW_H, headerHeight = 28, pool = 40 })
	root.table:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -84)
	root.table:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
	root.table:SetEmptyText("")
	root.table:SortBy("status", false)
	return root
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing

function ReadinessPanel:SetMessage(text, isError)
	if not self.root then return end
	self.root.message:SetText(text or "")
	Theme.Text(self.root.message, isError and "warn" or "text-2")
end

-- The summary line: "31 ok · 5 warn · 3 missing · 1 unknown" and "36/40 answered".
-- locale-key: READY_SUMMARY READY_COUNTS
function ReadinessPanel.SummaryText(s)
	return L["READY_SUMMARY"]:format(s.OK, s.WARN, s.MISSING, s.UNKNOWN), L["READY_COUNTS"]:format(s.answered, s.asked)
end

-- Draws the table and the buttons from ReadinessCheck.
-- locale-key: READY_CHECK READY_CHECK_WAIT READY_NOTIFY READY_NOTIFY_WAIT READY_FORBIDDEN READY_NO_RAID READY_DISABLED READY_NOT_ASKED
function ReadinessPanel:Refresh()
	local root = self.root
	if not root then return end
	local rc, nt = check(), notifier()
	local ok = allowed()
	local raid = ns.AddonCheck and ns.AddonCheck.raid
	local inRaid = raid and raid.inRaid == true
	root.ask:SetShown(ok); root.notify:SetShown(ok)
	if not ok or not inRaid then
		root.summary:SetText(""); root.counts:SetText("")
		root.confirm:Hide(); root.message:Show()
		root.empty:SetText(L[ok and "READY_NO_RAID" or "READY_FORBIDDEN"])
		root.table:SetData({})
		root.table:Hide()
		root.ask:SetEnabled(false); root.notify:SetEnabled(false)
		return
	end
	root.table:Show()
	root.empty:SetText("")
	local enabled = rc:Rules().enabled ~= false
	local s = rc:Summary()
	local text, counts = self.SummaryText(s)
	root.summary:SetText(text)
	root.counts:SetText(counts)
	root.table:SetData(rc:Rows())
	root.table:SetEmptyText("")
	-- the buttons: the wait of the check and of the notice shows in their labels
	local wait = rc:Wait()
	root.ask:SetLabel(wait > 0 and L["READY_CHECK_WAIT"]:format(math.ceil(wait)) or L["READY_CHECK"])
	root.ask:SetEnabled(enabled and wait <= 0)
	local nwait = nt:Wait()
	root.notify:SetLabel(nwait > 0 and L["READY_NOTIFY_WAIT"]:format(math.ceil(nwait)) or L["READY_NOTIFY"])
	root.notify:SetEnabled(enabled and nwait <= 0 and not nt:Busy())
	if not enabled then self:SetMessage(L["READY_DISABLED"], true)
	elseif not rc.request and not self.sticky then self:SetMessage(L["READY_NOT_ASKED"]) end
	if wait > 0 or nwait > 0 or nt:Busy() then self:Tick() end
end

-- Draws again in a second while a wait runs (the labels count down).
function ReadinessPanel:Tick()
	if self.ticking or not self.root or not self.root:IsShown() then return end
	self.ticking = true
	ns.Compat.After(1, function()
		self.ticking = false
		if self.root and self.root:IsShown() then self:Refresh() end
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- The buttons

-- locale-key: READY_ASKED
function ReadinessPanel:OnCheck()
	self.sticky = true
	local q, code, extra = check():Request()
	if q then self:SetMessage(L["READY_ASKED"]) else self:SetMessage(self.ErrorText(code, extra), true) end
	self:Refresh()
end

-- The notify button asks first: what would be written (how many lines and whispers), a Send and a Cancel.
-- locale-key: READY_CONFIRM_BODY
function ReadinessPanel:OnNotify()
	self.sticky = true
	local plan, code, extra = notifier():Check()
	if not plan then self:SetMessage(self.ErrorText(code, extra), true); return end
	local c = self.root.confirm
	c.text:SetText(L["READY_CONFIRM_BODY"]:format(#plan.raid, plan.counts.whispers))
	self.root.message:Hide()
	c:Show()
end

function ReadinessPanel:CloseConfirm()
	if not self.root then return end
	self.root.confirm:Hide()
	self.root.message:Show()
end

function ReadinessPanel:OnCancel() self:CloseConfirm() end

-- locale-key: READY_SENT READY_SENT_QUEUED
function ReadinessPanel:OnConfirm()
	self:CloseConfirm()
	local entry, code, extra = notifier():Send()
	if not entry then self:SetMessage(self.ErrorText(code, extra), true); self:Refresh(); return end
	self:SetMessage(L[entry.queued and "READY_SENT_QUEUED" or "READY_SENT"]:format(entry.raid, entry.whispers))
	self:Refresh()
end

if ns.Bus then
	for _, ev in ipairs({ "READINESS_CHANGED", "READINESS_NOTICE_SENT", "ADDON_CHECK_CHANGED", "GUILD_RANKS_READY",
		"GUILD_RANKS_CHANGED", "SETTINGS_RULES_CHANGED" }) do
		ns.Bus:On(ev, function() if ReadinessPanel.root then ReadinessPanel:Refresh() end end, ReadinessPanel)
	end
end
