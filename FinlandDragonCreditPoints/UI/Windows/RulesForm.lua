-- RulesForm: the guild's rules as a form (docs/ANALISI.md §10, docs/specs/ui-style.md §6, M7-2). Lua 5.1; unprotected frames.
-- One component for the Settings tab's Rules and Site sub-tabs: a list of pages on the left (the Site one has a single page),
-- the fields of the chosen page on a card (a switch, a field, a choice, a line of text: Domain/RuleFields.lua says which), and the
-- Save and Revert buttons at the bottom. Everybody sees the rules; only the Guild Master can change them: for everybody
-- else the controls are off and the buttons are not there (App/SettingsController.lua refuses the write all the same).
-- The edits go to a draft copy of the rules; Save checks it (Rules.Validate), asks for an explicit confirmation when a season is
-- open (the change is kept in the ledger, audited) and writes the whole configuration with SettingsController:ApplyRules.
-- What does not draw (reading, writing, parsing, the permission) is in Domain/RuleFields.lua and App/SettingsController.lua.
local ADDON_NAME, ns = ...
ns = ns or {}
local RulesForm = {}
ns.RulesForm = RulesForm
if ns.addon then ns.addon.RulesForm = RulesForm end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

RulesForm.ROW_H, RulesForm.MAX_ROWS = 32, 24
RulesForm.COLUMNS = { costs = 3 }   -- the matrix: one row per category, a column per quality
RulesForm.MAX_LISTED = 8            -- changes listed in the confirmation

local Form = {}
Form.__index = Form

local function SC() return ns.SettingsController end
local RF = ns.RuleFields

-- The text of a field: its locale keys joined with " · " ("Weapon · Epic").
function RulesForm.LabelOf(field)
	local parts = {}
	for i, key in ipairs(field.keys) do parts[i] = L[key] end
	return table.concat(parts, " · ")
end

-- The text of a refused action or a refused edit.
-- locale-key: SETTINGS_ERR_NOT_READY SETTINGS_ERR_PENDING SETTINGS_ERR_NOT_IN_GUILD SETTINGS_ERR_NOT_GM SETTINGS_ERR_RANK_TOO_LOW
-- locale-key: SETTINGS_ERR_UNCHANGED SETTINGS_ERR_CONFIRM_REQUIRED SETTINGS_ERR_READ_ONLY SETTINGS_ERR_NUMBER SETTINGS_ERR_INT
-- locale-key: SETTINGS_ERR_RANGE SETTINGS_ERR_TEXT SETTINGS_ERR_RULES SETTINGS_ERR_TABLE
function RulesForm.ErrorText(code, detail)
	code = tostring(code)
	local head, rest = code:match("^(%u+):(.+)$")
	if head == "RULES" or head == "TABLE" then
		local field = rest and RF.Field(rest)
		return L["SETTINGS_ERR_" .. head]:format(field and RulesForm.LabelOf(field) or rest or "?")
	end
	local key = "SETTINGS_ERR_" .. code
	if L[key] ~= key then return L[key] end
	return L["SETTINGS_ERR_OTHER"]:format(code)
end

---------------------------------------------------------------------------------------------------------------------
-- Build

-- opts: pages (list of page ids), host (the SettingsWindow: Confirm and Say), list (true: the page list on the left).
-- locale-key: RULEPAGE_SESSION RULEPAGE_PRIORITY RULEPAGE_COSTS RULEPAGE_MULTIPLIERS RULEPAGE_MEMBERS RULEPAGE_COUNCIL
-- locale-key: RULEPAGE_LEGENDARY RULEPAGE_MESSAGES RULEPAGE_UPGRADE RULEPAGE_SITE
function RulesForm.New(parent, opts)
	local f = setmetatable({ parent = parent, pages = opts.pages, host = opts.host, bad = {}, rows = {} }, Form)
	local root = CreateFrame("Frame", nil, parent)
	root:SetAllPoints(parent)
	f.root = root
	local left = 0
	if opts.list ~= false and #opts.pages > 1 then
		local choices = {}
		for _, id in ipairs(opts.pages) do choices[#choices + 1] = { id = id, text = L["RULEPAGE_" .. id:upper()] } end
		f.list = Widgets.ChoiceList(root, { rows = #opts.pages, rowHeight = 30, width = 190, onSelect = function(id) f:SetPage(id) end })
		f.list:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -4)
		f.list:SetChoices(choices)
		left = 206
	end
	local card = Widgets.Card(root, {})
	card:SetPoint("TOPLEFT", root, "TOPLEFT", left, -4)
	card:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
	f.card = card
	card.title = Theme.NewText(card, "H2", "text-1")
	card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -14)
	card.note = Theme.NewText(card, "Small", "text-3")
	card.note:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
	card.note:SetPoint("RIGHT", card, "RIGHT", -16, 0)
	card.note:SetJustifyH("LEFT")
	card.message = Theme.NewText(card, "Small", "text-2")
	card.message:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 16, 22)
	card.message:SetPoint("RIGHT", card, "RIGHT", -300, 0)
	card.message:SetJustifyH("LEFT")
	card.save = Widgets.Button(card, { text = L["SETTINGS_SAVE"], style = "primary", width = 130, onClick = function() f:OnSave() end })
	card.save:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -16, 14)
	card.revert = Widgets.Button(card, { text = L["SETTINGS_REVERT"], style = "ghost", width = 130, onClick = function() f:OnRevert() end })
	card.revert:SetPoint("RIGHT", card.save, "LEFT", -8, 0)
	for i = 1, RulesForm.MAX_ROWS do
		local row = CreateFrame("Frame", nil, card)
		row:SetHeight(RulesForm.ROW_H - 4)
		row.label = Theme.NewText(row, "Body", "text-2")
		row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.label:SetJustifyH("LEFT")
		row:Hide()
		f.rows[i] = row
	end
	card:SetScript("OnSizeChanged", function() f:Layout() end)
	f.draft = ns.Rules.Copy(SC():Rules())
	f.page = opts.pages[1]
	if f.list then f.list:Select(f.page) else f:SetPage(f.page) end
	return f
end

-- The control a row uses for a kind, built the first time.
local function control(self, row, field)
	local kind = field.kind
	if kind == "bool" then
		if not row.switch then
			row.switch = Widgets.Switch(row, { onChange = function(on) self:OnEdit(row.field, on) end })
			row.switch:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		end
		return row.switch
	elseif kind == "choice" then
		if not row.select then
			row.select = Widgets.Select(row, { width = 170, rows = 5, onSelect = function(id) self:OnEdit(row.field, id) end })
			row.select:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		end
		return row.select
	end
	if not row.edit then
		row.edit = Widgets.EditBox(row, { width = 80, maxLetters = 200, onChange = function(text, user)
			if user then self:OnTyped(row, text) end
		end })
		row.edit:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	end
	return row.edit
end

-- A field takes the keyboard only for who may change the rules; a switch or a choice just turns off.
local function setEditable(c, editable)
	if c.edit then
		if c.edit.SetEnabled then c.edit:SetEnabled(editable) end
		c.edit:EnableMouse(editable)
		if not editable then c.edit:ClearFocus() end
		c:SetAlpha(editable and 1 or 0.6)
	else
		c:SetEnabled(editable)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Pages and rows

-- locale-key: RULEHINT_SESSION RULEHINT_PRIORITY RULEHINT_COSTS RULEHINT_MULTIPLIERS RULEHINT_MEMBERS RULEHINT_COUNCIL
-- locale-key: RULEHINT_LEGENDARY RULEHINT_MESSAGES RULEHINT_UPGRADE RULEHINT_SITE
function Form:SetPage(id)
	self.page = id
	self.fields = RF.Page(id)
	self.card.title:SetText(L["RULEPAGE_" .. id:upper()])
	for i, row in ipairs(self.rows) do
		local field = self.fields[i]
		row.field = field
		if field then
			row.label:SetText(RulesForm.LabelOf(field))
			for _, c in ipairs({ row.switch, row.edit, row.select }) do if c then c:Hide() end end
			local c = control(self, row, field)
			c:Show()
			if field.kind == "choice" then
				local choices = {}
				for _, o in ipairs(field.options) do choices[#choices + 1] = { id = o.value, text = L[o.key] } end
				c:SetChoices(choices)
			end
		end
		row:SetShown(field ~= nil)
	end
	self:Layout()
	self:Paint()
	self:Update()
end

function Form:ActivePage() return self.page end

-- Puts the rows in a grid: two columns (three for the matrix), a wide field takes a whole row.
function Form:Layout()
	local card = self.card
	if not self.fields then return end
	local W = (card:GetWidth() or 0) > 100 and card:GetWidth() or 700
	local cols = RulesForm.COLUMNS[self.page] or 2
	local gap = 16
	local colW = math.floor((W - 32 - gap * (cols - 1)) / cols)
	local col, line = 0, 0
	for i, field in ipairs(self.fields) do
		local row = self.rows[i]
		if row then
			if field.wide and col ~= 0 then col, line = 0, line + 1 end
			local x = 16 + col * (colW + gap)
			local width = field.wide and (W - 32) or colW
			row:SetWidth(width)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", self.card, "TOPLEFT", x, -(72 + line * RulesForm.ROW_H))
			local controlW = (field.kind == "choice" and 170) or (field.kind == "bool" and 44) or 80
			if field.wide then
				controlW = width - 220
				if row.edit then row.edit:SetWidth(controlW) end
			end
			row.label:SetWidth(math.max(60, width - controlW - 8))
			if field.wide then col, line = 0, line + 1 else
				col = col + 1
				if col >= cols then col, line = 0, line + 1 end
			end
		end
	end
end

-- Shows the draft's values in the controls (silently: nothing is edited by being drawn).
function Form:Paint()
	if not self.fields then return end
	local word = L["RULEOPT_COUNCIL"]
	for i, field in ipairs(self.fields) do
		local row = self.rows[i]
		local value = RF.Get(self.draft, field)
		if field.kind == "bool" then
			row.switch:SetOn(value == true, true)
		elseif field.kind == "choice" then
			if not row.select:Select(value, true) then row.select:SetChoices(row.select.choices) end
		else
			row.edit:SetText(RF.Format(field, value, word))
			Theme.Tint(row.edit.ring, "border")
		end
		self:PaintLabel(row)
	end
end

-- A label is amber while its value differs from the rules in force.
function Form:PaintLabel(row)
	local field = row.field
	if not field then return end
	local changed = RF.Get(self.draft, field) ~= RF.Get(SC():Rules(), field)
	Theme.Text(row.label, (changed or self.bad[field.id]) and "accent-text" or "text-2")
end

-- The state that follows the player's right: the controls on or off, the buttons there or not, the note.
-- locale-key: SETTINGS_READONLY
function Form:Update()
	local card = self.card
	local editable = SC():CanConfigure() == true
	self.editable = editable
	for i, field in ipairs(self.fields or {}) do
		local row = self.rows[i]
		local c = row and control(self, row, field)
		if c then setEditable(c, editable) end
	end
	card.save:SetShown(editable)
	card.revert:SetShown(editable)
	if editable then
		card.note:SetText(L["RULEHINT_" .. self.page:upper()])
	else
		card.note:SetText(L["SETTINGS_READONLY"])
	end
	self:ShowPending()
end

-- The count of changes not saved yet, in the message line (unless an error is showing).
function Form:ShowPending()
	if self.errorShown then return end
	local n = #SC():RulesDiff(self.draft)
	if n > 0 and self.editable then self:SetMessage(L["SETTINGS_PENDING"]:format(n)) else self:SetMessage("") end
end

function Form:SetMessage(text, isError)
	self.errorShown = isError and text ~= "" or false
	self.card.message:SetText(text or "")
	Theme.Text(self.card.message, isError and "warn" or "text-2")
end

-- The draft goes back to the rules in force.
function Form:Reload()
	self.draft = ns.Rules.Copy(SC():Rules())
	self.bad = {}
	self.errorShown = false
	self:Paint()
	self:Update()
end

-- Draws again: a form with nothing pending follows the rules in force (a sync or the Guild Master's other client changed them).
function Form:Refresh()
	if #SC():RulesDiff(self.draft) == 0 and next(self.bad) == nil then
		self.draft = ns.Rules.Copy(SC():Rules())
		self:Paint()
	end
	self:Update()
end

---------------------------------------------------------------------------------------------------------------------
-- Editing

-- A value of the controls (a switch, a choice, or a typed one already parsed): into the draft.
function Form:OnEdit(field, value)
	if not field or not self.editable then return false end
	RF.Set(self.draft, field, value)
	self.bad[field.id] = nil
	self.errorShown = false
	for i, f in ipairs(self.fields) do
		if f == field then
			local row = self.rows[i]
			if row.edit then Theme.Tint(row.edit.ring, "border") end
			self:PaintLabel(row)
		end
	end
	self:ShowPending()
	return true
end

-- What was typed in a field: parsed and checked at once; a wrong one is marked and never reaches the draft.
function Form:OnTyped(row, text)
	local field = row.field
	if not field or not self.editable then return end
	local value, code = RF.Parse(field, text, L["RULEOPT_COUNCIL"])
	if value == nil then
		self.bad[field.id] = code
		Theme.Tint(row.edit.ring, "err")
		self:PaintLabel(row)
		self:SetMessage(RulesForm.ErrorText(code), true)
		return
	end
	self:OnEdit(field, value)
end

function Form:OnRevert()
	if not self.editable then return end
	self:Reload()
end

-- The confirmation text of a season in progress: the count and the first changes, by name.
local function changesText(paths)
	local names = {}
	for i, path in ipairs(paths) do
		if i > RulesForm.MAX_LISTED then break end
		local field = RF.Field(path)
		names[#names + 1] = field and RulesForm.LabelOf(field) or path
	end
	local text = table.concat(names, "\n")
	if #paths > RulesForm.MAX_LISTED then text = text .. "\n" .. L["SETTINGS_AND_MORE"]:format(#paths - RulesForm.MAX_LISTED) end
	return text
end

-- Save: the checks first, then (with a season open) the confirmation, then the write.
function Form:OnSave()
	if not self.editable then self:SetMessage(RulesForm.ErrorText("NOT_GM"), true); return end
	local bad = next(self.bad)
	if bad then
		self:SetMessage(RulesForm.ErrorText(self.bad[bad]), true)
		return
	end
	local rules = ns.Rules.WithDefaults(self.draft)
	local ok, problems = ns.Rules.Validate(rules)
	if not ok then
		local page = RF.PageOfCode(problems[1])
		if page and self.list and page ~= self.page then self.list:Select(page) end
		self:SetMessage(RulesForm.ErrorText("RULES:" .. problems[1]), true)
		return
	end
	local diff = SC():RulesDiff(rules)
	if #diff == 0 then self:SetMessage(RulesForm.ErrorText("UNCHANGED"), true); return end
	if SC():NeedsConfirmation() then
		self.host:Confirm({
			title = L["SETTINGS_CONFIRM_RULES_TITLE"],
			body = L["SETTINGS_CONFIRM_RULES_BODY"]:format(#diff, changesText(diff)),
			confirm = L["SETTINGS_CONFIRM"],
			onConfirm = function() self:Write(rules, true) end,
		})
		return
	end
	self:Write(rules, false)
end

function Form:Write(rules, confirmed)
	local event, code = SC():ApplyRules(rules, { confirmed = confirmed })
	if not event then
		self:SetMessage(RulesForm.ErrorText(code), true)
		return false
	end
	self.errorShown = false
	self:Reload()
	self:SetMessage(L["SETTINGS_SAVED"])
	return true
end
