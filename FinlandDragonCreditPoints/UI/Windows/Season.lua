-- SeasonWindow: the season's page on the Settings tab (docs/ANALISI.md §6, §9.3, docs/specs/ui-style.md §6, M6-1b). Every
-- member sees the current season read-only (name, state, pack of instances with sizes, late-join rule, start credits). A
-- holder of `season.manage` (the Guild Master by default) also gets the buttons: open a season from a pack of instances, a
-- raid size each, the late-join rule and the start credits, and close it. Both ask for an explicit confirmation (closing a
-- second, separate one); nothing happens without it. Reads and writes through App/SeasonController.lua. Lua 5.1.
local ADDON_NAME, ns = ...
ns = ns or {}
local SeasonWindow = {}
ns.SeasonWindow = SeasonWindow
if ns.addon then ns.addon.SeasonWindow = SeasonWindow end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

SeasonWindow.SIZES = { 10, 20, 40 }
SeasonWindow.ROW_H = 34

local function SC() return ns.SeasonController end
local function instanceName(id)
	local inst = ns.Instances and ns.Instances.Get(id)
	return inst and inst.name or tostring(id)
end

-- The message of a refused action.
-- locale-key: SEASON_ERR_CONFIRM_REQUIRED SEASON_ERR_NOT_READY SEASON_ERR_PENDING SEASON_ERR_NOT_IN_GUILD
-- locale-key: SEASON_ERR_RANK_TOO_LOW SEASON_ERR_NOT_GM SEASON_ERR_SEASON_ALREADY_OPEN SEASON_ERR_NO_INSTANCES
-- locale-key: SEASON_ERR_NOT_IN_TABLE SEASON_ERR_SIZE SEASON_ERR_START_CREDITS SEASON_ERR_LATE_JOIN SEASON_ERR_NO_SEASON
-- locale-key: SEASON_ERR_NIGHT_OPEN SEASON_ERR_READ_ONLY SEASON_ERR_UNCHANGED
function SeasonWindow.ErrorText(code)
	local key = "SEASON_ERR_" .. tostring(code)
	if L[key] ~= key then return L[key] end
	return L["SEASON_ERR_OTHER"]:format(tostring(code))
end

-- locale-key: SEASON_METHOD_AVERAGE SEASON_METHOD_MEDIAN SEASON_METHOD_MIN SEASON_METHOD_ZERO SEASON_METHOD_FIXED
function SeasonWindow.MethodName(method) return L["SEASON_METHOD_" .. tostring(method):upper()] end

-- "Molten Core (40) · Onyxia's Lair (40)"
function SeasonWindow.PackText(season)
	local parts = {}
	for _, inst in ipairs(season and season.instances or {}) do
		parts[#parts + 1] = L["SEASON_PACK_ITEM"]:format(instanceName(inst.id), inst.size)
	end
	return table.concat(parts, " · ")
end

---------------------------------------------------------------------------------------------------------------------
-- Build

local function field(parent, labelKey, x, y)
	local t = Theme.NewText(parent, "Small", "text-2")
	t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	t:SetText(L[labelKey])
	return t
end

function SeasonWindow:Build(page)
	if self.root then return self.root end
	local root = CreateFrame("Frame", nil, page)
	root:SetAllPoints(page)
	self.root = root

	root.eyebrow = Theme.NewText(root, "Eyebrow", "accent-text")
	root.eyebrow:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -12)
	root.eyebrow:SetText(L["SEASON_TITLE"]:upper())
	root.card = Widgets.Card(root, { height = 150 })
	root.card:SetPoint("TOPLEFT", root.eyebrow, "BOTTOMLEFT", 0, -10)
	root.card:SetPoint("RIGHT", root, "RIGHT", 0, 0)
	local c = root.card
	root.name = Theme.NewText(c, "H2", "text-1")
	root.name:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -14)
	root.state = Widgets.Badge(c, L["SEASON_STATE_NONE"], "neutral")
	root.state:SetPoint("LEFT", root.name, "RIGHT", 12, 0)
	root.pack = Theme.NewText(c, "BodyMedium", "text-1")
	root.pack:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -52)
	root.rule = Theme.NewText(c, "Body", "text-2")
	root.rule:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -80)
	root.start = Theme.NewText(c, "Body", "text-2")
	root.start:SetPoint("TOPLEFT", c, "TOPLEFT", 16, -104)
	root.message = Theme.NewText(root, "Small", "text-2")
	root.message:SetPoint("TOPLEFT", root.card, "BOTTOMLEFT", 0, -8)

	-- the form that opens a season (only for who may manage seasons)
	root.form = Widgets.Card(root, { height = 330 })
	root.form:SetPoint("TOPLEFT", root.message, "BOTTOMLEFT", 0, -8)
	root.form:SetPoint("RIGHT", root, "RIGHT", 0, 0)
	local f = root.form
	f.title = Theme.NewText(f, "Eyebrow", "accent-text")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
	f.title:SetText(L["SEASON_FORM_TITLE"]:upper())
	field(f, "SEASON_FIELD_LABEL", 16, -40)
	f.label = Widgets.EditBox(f, { width = 220, maxLetters = 40 })
	f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -58)
	field(f, "SEASON_FIELD_START", 260, -40)
	f.startEdit = Widgets.EditBox(f, { width = 90, maxLetters = 6 })
	f.startEdit:SetPoint("TOPLEFT", f, "TOPLEFT", 260, -58)
	field(f, "SEASON_FIELD_PACK", 16, -96)
	f.rows = {}
	for i, inst in ipairs(ns.Instances and ns.Instances.LIST or {}) do
		local row = { id = inst.instanceID, size = inst.size }
		row.chip = Widgets.Chip(f, { text = instanceName(inst.instanceID), onClick = function(chip)
			chip:SetSelected(not chip:IsSelected())
			SeasonWindow:SetMessage("")
		end })
		row.chip:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -116 - (i - 1) * SeasonWindow.ROW_H)
		local items = {}
		for _, s in ipairs(SeasonWindow.SIZES) do items[#items + 1] = { id = s, text = L["SEASON_SIZE"]:format(s) } end
		row.seg = Widgets.Segmented(f, items, function(id) row.size = id end)
		row.seg:SetPoint("TOPLEFT", f, "TOPLEFT", 280, -114 - (i - 1) * SeasonWindow.ROW_H)
		row.seg:Select(inst.size)
		f.rows[i] = row
	end
	local rowsEnd = -116 - #f.rows * SeasonWindow.ROW_H
	field(f, "SEASON_FIELD_RULE", 16, rowsEnd - 6)
	local items = {}
	for _, m in ipairs(SC().METHODS) do items[#items + 1] = { id = m, text = L["SEASON_METHOD_" .. m:upper()] } end
	f.method = Widgets.Segmented(f, items, function(id) SeasonWindow.method = id end)
	f.method:SetPoint("TOPLEFT", f, "TOPLEFT", 16, rowsEnd - 24)
	f.open = Widgets.Button(f, { text = L["SEASON_OPEN"], style = "primary", width = 170, onClick = function() SeasonWindow:OnOpen() end })
	f.open:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
	f:SetHeight(-rowsEnd + 130)

	root.close = Widgets.Button(root, { text = L["SEASON_CLOSE"], style = "secondary", width = 170, onClick = function() SeasonWindow:OnClose() end })
	root.close:SetPoint("TOPLEFT", root.message, "BOTTOMLEFT", 0, -8)
	return root
end

-- The confirmation dialog, built the first time it is needed. Two steps for closing.
function SeasonWindow:Dialog()
	if self.dialog then return self.dialog end
	local d = Widgets.Dialog(self.root, "FDCPSeasonConfirm", { width = 480, height = 280 })
	local c = d.card
	d.title = Theme.NewText(c, "H2", "text-1")
	d.title:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -20)
	d.body = Theme.NewText(c, "Body", "text-2")
	d.body:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -60)
	d.body:SetWidth(440)
	d.body:SetJustifyH("LEFT")
	d.confirm = Widgets.Button(c, { text = L["SEASON_CONFIRM"], style = "primary", width = 150, height = 30,
		onClick = function() SeasonWindow:OnConfirm() end })
	d.confirm:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -20, 20)
	d.cancel = Widgets.Button(c, { text = L["SEASON_CANCEL"], style = "ghost", width = 110, height = 30,
		onClick = function() SeasonWindow:OnCancel() end })
	d.cancel:SetPoint("RIGHT", d.confirm, "LEFT", -8, 0)
	self.dialog = d
	return d
end

function SeasonWindow:SetMessage(text, isError)
	if not self.root then return end
	self.root.message:SetText(text or "")
	Theme.Text(self.root.message, isError and "warn" or "text-2")
end

---------------------------------------------------------------------------------------------------------------------
-- Actions

-- The form as the controller's arguments (without the confirmation).
function SeasonWindow:FormArgs()
	local f = self.root.form
	local instances = {}
	for _, row in ipairs(f.rows) do
		if row.chip:IsSelected() then instances[#instances + 1] = { id = row.id, size = row.size } end
	end
	local text = f.startEdit:GetText()
	local start
	if text == "" then start = nil else start = tonumber(text) end
	if text ~= "" and (start == nil or start < 0 or start ~= math.floor(start)) then start = -1 end
	return { label = f.label:GetText(), instances = instances, startCredits = start, lateJoin = self.method }
end

-- "Open": checks the form and shows the summary to confirm; nothing is written yet.
function SeasonWindow:OnOpen()
	if not self.root then return end
	if SC():CanManage() ~= true then self:SetMessage(self.ErrorText("RANK_TOO_LOW"), true); return end
	local args = self:FormArgs()
	if #args.instances == 0 then self:SetMessage(self.ErrorText("NO_INSTANCES"), true); return end
	if args.startCredits and args.startCredits < 0 then self:SetMessage(self.ErrorText("START_CREDITS"), true); return end
	local rules = SC():Rules()
	local pack = self.PackText({ instances = args.instances })
	local label = args.label ~= "" and args.label or SC():NextId()
	local d = self:Dialog()
	self.pending = { kind = "open", args = args, step = 1 }
	d.title:SetText(L["SEASON_CONFIRM_OPEN_TITLE"])
	d.body:SetText(L["SEASON_CONFIRM_OPEN_BODY"]:format(label, pack, self.MethodName(args.lateJoin or rules.members.lateJoin.method),
		args.startCredits or rules.season.startCredits))
	d.confirm:SetLabel(L["SEASON_CONFIRM"])
	d:Open()
end

-- "Close": the first of two steps.
function SeasonWindow:OnClose()
	if not self.root then return end
	if SC():CanManage() ~= true then self:SetMessage(self.ErrorText("RANK_TOO_LOW"), true); return end
	local s = SC():Current()
	if not s then self:SetMessage(self.ErrorText("NO_SEASON"), true); return end
	local d = self:Dialog()
	self.pending = { kind = "close", step = 1 }
	d.title:SetText(L["SEASON_CONFIRM_CLOSE_TITLE"])
	d.body:SetText(L["SEASON_CONFIRM_CLOSE_BODY"]:format(s.label or s.id))
	d.confirm:SetLabel(L["SEASON_CONFIRM_CLOSE"])
	d:Open()
end

function SeasonWindow:OnCancel()
	self.pending = nil
	if self.dialog then self.dialog:Close() end
end

-- The confirm button: an opening is written at once; a closing asks a second, separate confirmation first.
function SeasonWindow:OnConfirm()
	local p, d = self.pending, self.dialog
	if not p then return end
	if p.kind == "close" and p.step == 1 then
		p.step = 2
		local s = SC():Current()
		d.title:SetText(L["SEASON_CONFIRM_CLOSE2_TITLE"])
		d.body:SetText(L["SEASON_CONFIRM_CLOSE2_BODY"]:format(s and (s.label or s.id) or ""))
		d.confirm:SetLabel(L["SEASON_CONFIRM_CLOSE2"])
		return
	end
	self.pending = nil
	d:Close()
	if p.kind == "open" then
		p.args.confirmed = true
		local s, code = SC():Open(p.args)
		if s then self:SetMessage(L["SEASON_OPENED"]) else self:SetMessage(self.ErrorText(code), true) end
	else
		local s, code = SC():Close({ confirmed = true, confirmedAgain = true })
		if s then self:SetMessage(L["SEASON_CLOSED"]) else self:SetMessage(self.ErrorText(code), true) end
	end
	self:Refresh()
end

---------------------------------------------------------------------------------------------------------------------
-- Draw

function SeasonWindow:Refresh()
	local root = self.root
	if not root then return end
	local sc = SC()
	local ledger, s = sc:Ledger(), sc:Current()
	local rules = sc:Rules()
	local can = sc:CanManage() == true
	if s then
		root.name:SetText(s.label or s.id)
		root.state:SetBadge(L["SEASON_STATE_OPEN"], "ok")
		root.pack:SetText(L["SEASON_PACK"]:format(self.PackText(s)))
		root.start:SetText(L["SEASON_START"]:format(s.startCredits or 0))
	else
		root.name:SetText(L[ledger and "SEASON_NONE" or "SEASON_NOT_READY"])
		root.state:SetBadge(L["SEASON_STATE_NONE"], "neutral")
		root.pack:SetText("")
		root.start:SetText("")
	end
	root.rule:SetText(L["SEASON_RULE"]:format(self.MethodName(rules.members.lateJoin.method)))
	-- the buttons exist only for who may manage seasons
	local f = root.form
	f:SetShown(can and ledger ~= nil and s == nil)
	root.close:SetShown(can and s ~= nil)
	if f:IsShown() then
		if not self.method then self.method = rules.members.lateJoin.method end
		f.method:Select(self.method)
		if f.startEdit:GetText() == "" and not self.startTouched then f.startEdit:SetText(tostring(rules.season.startCredits)) end
	end
end

if ns.Bus then
	for _, ev in ipairs({ "SEASON_OPENED", "SEASON_CLOSED" }) do
		ns.Bus:On(ev, function() SeasonWindow:Refresh() end, SeasonWindow)
	end
end
