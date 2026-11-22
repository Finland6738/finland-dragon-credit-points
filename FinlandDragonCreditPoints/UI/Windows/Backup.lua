-- BackupWindow: History › Backup (docs/ANALISI.md §7 "Importazione", §8.3, docs/specs/ui-style.md §6, M6-7): three modes
-- over one text box. **Settings**: the string of the rules in force (everybody) and, for the Guild Master, the import of a
-- pasted one. **Backup**: the string of the whole ledger (officers) and, for `season.manage`, the restore of a pasted one.
-- **Archive**: the closed seasons; a season's archive string (officers) and, for `season.manage`, its compaction, which
-- needs the archive first and two confirmations. Every write goes through App/BackupService.lua and asks a confirmation
-- in a dialog that says what will happen; nothing is written before it. The box is editable (to paste); Select all picks
-- the whole text so Ctrl+C copies it (an addon cannot write to the clipboard). Lua 5.1.
-- Not verified in the real client: the pane's look, the paste of a long string and the copy (the owner's M6 checklist).
local ADDON_NAME, ns = ...
ns = ns or {}
local BackupWindow = {}
ns.BackupWindow = BackupWindow
if ns.addon then ns.addon.BackupWindow = BackupWindow end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

BackupWindow.MODES = { "config", "backup", "archive" }
BackupWindow.mode = "config"
BackupWindow.MAX_CHANGES_SHOWN = 6

local function S() return ns.BackupService end
local function can(p)
	local nc = ns.NightController
	return nc and nc:Can(p) == true
end

-- locale-key: BACKUP_ERR_OTHER BACKUP_ERR_EMPTY BACKUP_ERR_FORMAT BACKUP_ERR_KIND BACKUP_ERR_NEWER BACKUP_ERR_DECODE
-- locale-key: BACKUP_ERR_INVALID BACKUP_ERR_RULES BACKUP_ERR_NOT_GM BACKUP_ERR_RANK_TOO_LOW BACKUP_ERR_PENDING
-- locale-key: BACKUP_ERR_NOT_READY BACKUP_ERR_ARCHIVE_FIRST BACKUP_ERR_ALREADY_COMPACTED BACKUP_ERR_NOTHING_TO_COMPACT
-- locale-key: BACKUP_ERR_SEASON_OPEN BACKUP_ERR_UNCHANGED
function BackupWindow.ErrorText(code)
	code = tostring(code)
	local key = "BACKUP_ERR_" .. code:gsub(":.*$", "")
	if L[key] ~= key then return L[key] end
	return L["BACKUP_ERR_OTHER"]:format(code)
end

---------------------------------------------------------------------------------------------------------------------
-- Build

-- locale-key: BACKUP_MODE_CONFIG BACKUP_MODE_BACKUP BACKUP_MODE_ARCHIVE BACKUP_SELECT BACKUP_GENERATE BACKUP_IMPORT
-- locale-key: BACKUP_RESTORE BACKUP_ARCHIVE BACKUP_COMPACT BACKUP_HINT_CONFIG BACKUP_HINT_BACKUP BACKUP_HINT_ARCHIVE
function BackupWindow:Build(pane)
	if self.pane then return self.pane end
	self.pane = pane
	local items = {}
	for _, id in ipairs(self.MODES) do items[#items + 1] = { id = id, text = L["BACKUP_MODE_" .. id:upper()] } end
	self.seg = Widgets.Segmented(pane, items, function(id) BackupWindow:SetMode(id) end)
	self.seg:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -4)
	self.generate = Widgets.Button(pane, { text = L["BACKUP_GENERATE"], style = "primary", width = 140,
		onClick = function() BackupWindow:OnGenerate() end })
	self.generate:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -2)
	self.select = Widgets.Button(pane, { text = L["BACKUP_SELECT"], style = "secondary", width = 130,
		onClick = function() BackupWindow:SelectAll() end })
	self.select:SetPoint("RIGHT", self.generate, "LEFT", -8, 0)
	self.apply = Widgets.Button(pane, { text = L["BACKUP_IMPORT"], style = "secondary", width = 140,
		onClick = function() BackupWindow:OnApply() end })
	self.apply:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -44)
	self.compact = Widgets.Button(pane, { text = L["BACKUP_COMPACT"], style = "secondary", width = 140,
		onClick = function() BackupWindow:OnCompact() end })
	self.compact:SetPoint("RIGHT", self.apply, "LEFT", -8, 0)
	self.hint = Theme.NewText(pane, "Small", "text-3")
	self.hint:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -50)
	self.hint:SetPoint("RIGHT", self.compact, "LEFT", -12, 0)
	self.hint:SetJustifyH("LEFT")
	self.message = Theme.NewText(pane, "Body", "text-2")
	self.message:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -82)
	self.message:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -82)
	self.message:SetJustifyH("LEFT")
	-- the seasons of the Archive mode
	self.seasons = Widgets.ChoiceList(pane, { rows = 6, width = 260, onSelect = function(id) BackupWindow.season = id; BackupWindow:Refresh() end })
	self.seasons:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -108)
	-- the box: a multi-line edit box in a scroll frame, on a surface-2 field
	self.field = CreateFrame("Frame", nil, pane)
	self.field.fill = Theme.Slice(self.field, "rr_fill_8", "surface-2", "BACKGROUND")
	self.field.fill:SetAllPoints(self.field)
	self.field.ring = Theme.Slice(self.field, "rr_ring_8", "border", "BORDER")
	self.field.ring:SetAllPoints(self.field)
	local scroll = CreateFrame("ScrollFrame", nil, self.field)
	scroll:SetPoint("TOPLEFT", self.field, "TOPLEFT", 10, -8)
	scroll:SetPoint("BOTTOMRIGHT", self.field, "BOTTOMRIGHT", -10, 8)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetWidth(math.max(200, (pane:GetWidth() or 600) - 40))
	if Theme.fontObjects.Mono then edit:SetFontObject(Theme.fontObjects.Mono)
	elseif Theme.fontObjects.Body then edit:SetFontObject(Theme.fontObjects.Body) end
	Theme.Text(edit, "text-1")
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	scroll:SetScrollChild(edit)
	self.scroll, self.edit = scroll, edit
	self.seg:Select(self.mode)
	return pane
end

-- The confirmation dialog, built the first time it is needed.
-- locale-key: BACKUP_CONFIRM BACKUP_CANCEL
function BackupWindow:Dialog()
	if self.dialog then return self.dialog end
	local d = Widgets.Dialog(self.pane, "FDCPBackupConfirm", { width = 500, height = 300 })
	local c = d.card
	d.title = Theme.NewText(c, "H2", "text-1")
	d.title:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -20)
	d.body = Theme.NewText(c, "Body", "text-2")
	d.body:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -60)
	d.body:SetWidth(460)
	d.body:SetJustifyH("LEFT")
	d.confirm = Widgets.Button(c, { text = L["BACKUP_CONFIRM"], style = "primary", width = 160, height = 30,
		onClick = function() BackupWindow:OnConfirm() end })
	d.confirm:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -20, 20)
	d.cancel = Widgets.Button(c, { text = L["BACKUP_CANCEL"], style = "ghost", width = 110, height = 30,
		onClick = function() BackupWindow:OnCancel() end })
	d.cancel:SetPoint("RIGHT", d.confirm, "LEFT", -8, 0)
	self.dialog = d
	return d
end

function BackupWindow:SetMessage(text, isError)
	if not self.message then return end
	self.message:SetText(text or "")
	Theme.Text(self.message, isError and "warn" or "text-2")
end

function BackupWindow:SetText(text)
	self.text = text
	if self.edit then self.edit:SetText(text or "") end
end

---------------------------------------------------------------------------------------------------------------------
-- Actions

function BackupWindow:SetMode(mode)
	self.mode = mode
	self.pending = nil
	self:SetText("")
	self:SetMessage("")
	self:Refresh()
end

-- Selects the whole text so Ctrl+C copies it.
function BackupWindow:SelectAll()
	if not self.edit then return end
	self.edit:SetFocus()
	self.edit:HighlightText()
end

-- locale-key: BACKUP_GENERATED BACKUP_PICK_SEASON
function BackupWindow:OnGenerate()
	local text, why
	if self.mode == "config" then
		text, why = S():ExportConfig()
	elseif self.mode == "backup" then
		text, why = S():BackupText()
	else
		if not self.season then self:SetMessage(L["BACKUP_PICK_SEASON"], true); return end
		text, why = S():ArchiveText(self.season)
	end
	if not text then self:SetMessage(self.ErrorText(why), true); return end
	self:SetText(text)
	self:SetMessage(L["BACKUP_GENERATED"]:format(#text))
	self:Refresh()
end

local function changesText(changes, max)
	local shown = {}
	for i, c in ipairs(changes) do
		if i > max then break end
		shown[#shown + 1] = c
	end
	local text = table.concat(shown, ", ")
	if #changes > max then text = text .. " " .. L["BACKUP_MORE"]:format(#changes - max) end
	return text
end

-- Import (Settings) or Restore (Backup): reads the box, shows what would change, asks the confirmation.
-- locale-key: BACKUP_IMPORT_TITLE BACKUP_IMPORT_BODY BACKUP_RESTORE_TITLE BACKUP_RESTORE_BODY BACKUP_NO_CHANGE BACKUP_MORE
function BackupWindow:OnApply()
	local text = self.edit and self.edit:GetText() or ""
	local d
	if self.mode == "config" then
		if not can("config.rules") then self:SetMessage(self.ErrorText("NOT_GM"), true); return end
		local preview, why = S():PreviewConfig(text)
		if not preview then self:SetMessage(self.ErrorText(why), true); return end
		if #preview.changes == 0 then self:SetMessage(L["BACKUP_NO_CHANGE"]); return end
		d = self:Dialog()
		self.pending = { kind = "import", text = text }
		d.title:SetText(L["BACKUP_IMPORT_TITLE"])
		d.body:SetText(L["BACKUP_IMPORT_BODY"]:format(#preview.changes, changesText(preview.changes, self.MAX_CHANGES_SHOWN)))
	elseif self.mode == "backup" then
		if not can("season.manage") then self:SetMessage(self.ErrorText("RANK_TOO_LOW"), true); return end
		local preview, why = S():PreviewRestore(text)
		if not preview then self:SetMessage(self.ErrorText(why), true); return end
		d = self:Dialog()
		self.pending = { kind = "restore", text = text }
		d.title:SetText(L["BACKUP_RESTORE_TITLE"])
		d.body:SetText(L["BACKUP_RESTORE_BODY"]:format(preview.events, preview.new, tostring(preview.by or "?")))
	else
		return
	end
	d.confirm:SetLabel(L["BACKUP_CONFIRM"])
	d:Open()
end

-- Compact (Archive): the first of two confirmations.
-- locale-key: BACKUP_COMPACT_TITLE BACKUP_COMPACT_BODY BACKUP_COMPACT2_TITLE BACKUP_COMPACT2_BODY BACKUP_CONFIRM_COMPACT
-- locale-key: BACKUP_CONFIRM_COMPACT2
function BackupWindow:OnCompact()
	if not can("season.manage") then self:SetMessage(self.ErrorText("RANK_TOO_LOW"), true); return end
	local s = self:SelectedSeason()
	if not s then self:SetMessage(L["BACKUP_PICK_SEASON"], true); return end
	if s.compacted then self:SetMessage(self.ErrorText("ALREADY_COMPACTED"), true); return end
	if not S().archived[s.id] then self:SetMessage(self.ErrorText("ARCHIVE_FIRST"), true); return end
	local d = self:Dialog()
	self.pending = { kind = "compact", season = s.id, label = s.label or s.id, step = 1 }
	d.title:SetText(L["BACKUP_COMPACT_TITLE"])
	d.body:SetText(L["BACKUP_COMPACT_BODY"]:format(s.label or s.id, s.removable))
	d.confirm:SetLabel(L["BACKUP_CONFIRM_COMPACT"])
	d:Open()
end

function BackupWindow:OnCancel()
	self.pending = nil
	if self.dialog then self.dialog:Close() end
end

-- locale-key: BACKUP_IMPORTED BACKUP_RESTORED BACKUP_COMPACTED
function BackupWindow:OnConfirm()
	local p, d = self.pending, self.dialog
	if not p then return end
	if p.kind == "compact" and p.step == 1 then
		p.step = 2
		d.title:SetText(L["BACKUP_COMPACT2_TITLE"])
		d.body:SetText(L["BACKUP_COMPACT2_BODY"]:format(p.label))
		d.confirm:SetLabel(L["BACKUP_CONFIRM_COMPACT2"])
		return
	end
	self.pending = nil
	d:Close()
	if p.kind == "import" then
		local e, why = S():ImportConfig(p.text, { confirmed = true })
		if e then self:SetMessage(L["BACKUP_IMPORTED"]) else self:SetMessage(self.ErrorText(why), true) end
	elseif p.kind == "restore" then
		local r, why = S():Restore(p.text, { confirmed = true })
		if r then self:SetMessage(L["BACKUP_RESTORED"]:format(r.added, #r.refused + #r.pending)) else self:SetMessage(self.ErrorText(why), true) end
	else
		local n, why = S():Compact(p.season, { confirmed = true, confirmedAgain = true })
		if n then self:SetMessage(L["BACKUP_COMPACTED"]:format(p.label, n)) else self:SetMessage(self.ErrorText(why), true) end
	end
	self:Refresh()
end

function BackupWindow:SelectedSeason()
	for _, s in ipairs(self.list or {}) do
		if s.id == self.season then return s end
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- Draw

-- locale-key: BACKUP_SEASON_ROW BACKUP_SEASON_COMPACTED BACKUP_NOT_READY
function BackupWindow:Refresh()
	if not self.pane then return end
	local mode, service = self.mode, S()
	local ready = service ~= nil and service:Ledger() ~= nil
	self.hint:SetText(L["BACKUP_HINT_" .. mode:upper()])
	local archive = mode == "archive"
	self.seasons:SetShown(archive)
	self.field:ClearAllPoints()
	self.field:SetPoint("TOPLEFT", self.pane, "TOPLEFT", archive and 272 or 0, -108)
	self.field:SetPoint("BOTTOMRIGHT", self.pane, "BOTTOMRIGHT", 0, 0)
	if not ready then
		self.field:Hide(); self.generate:Hide(); self.select:Hide(); self.apply:Hide(); self.compact:Hide(); self.seasons:Hide()
		self:SetMessage(L["BACKUP_NOT_READY"])
		return
	end
	self.field:Show(); self.generate:Show(); self.select:Show()
	-- the buttons exist only for who may use them
	local officer = can("view.attendance")
	if mode == "config" then
		self.apply:SetLabel(L["BACKUP_IMPORT"])
		self.apply:SetShown(can("config.rules"))
		self.generate:SetShown(true)
	else
		self.apply:SetLabel(L["BACKUP_RESTORE"])
		self.apply:SetShown(mode == "backup" and can("season.manage"))
		self.generate:SetShown(officer)
	end
	self.compact:SetShown(archive and can("season.manage"))
	if archive then
		self.list = service:Seasons()
		local choices = {}
		for _, s in ipairs(self.list) do
			local text = L["BACKUP_SEASON_ROW"]:format(tostring(s.label or s.id), s.removable)
			if s.compacted then text = L["BACKUP_SEASON_COMPACTED"]:format(tostring(s.label or s.id)) end
			choices[#choices + 1] = { id = s.id, text = text, token = s.compacted and "text-3" or nil }
		end
		self.seasons:SetChoices(choices)
		if self.season and self:SelectedSeason() then self.seasons:Select(self.season) else self.season = nil end
	end
end

if ns.Bus then
	for _, ev in ipairs({ "LEDGER_SYNCED", "LEDGER_COMPACTED", "LEDGER_RESTORED", "SEASON_CLOSED" }) do
		ns.Bus:On(ev, function() if BackupWindow.pane and BackupWindow.pane:IsShown() then BackupWindow:Refresh() end end, BackupWindow)
	end
end
