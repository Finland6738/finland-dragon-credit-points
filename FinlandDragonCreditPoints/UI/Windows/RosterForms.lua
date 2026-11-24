-- RosterForms: the dialogs of Roster > Pool (docs/ANALISI.md §6, §6.1, fix/roster-join). Lua 5.1; unprotected frames.
--
--   * the declaration form: "Join the roster" (a player outside the pool) and "Declare your specs" (a member added without
--     a declaration). The class is the client's; MS1 is required, MS2 and OS optional (the specs of the class, Data/
--     Specs.lua), the weekdays and a short note optional. "Send" sends the request to the officers (RosterController:
--     SendJoin). The other-faction twin is not asked: the two factions are two guilds with two ledgers in game, so a twin
--     can never be in the same pool.
--   * the officers' "Add a player": the same form with the list of the raid's and the guild's characters not in the pool
--     (RosterController:Candidates, the class read from the game) on the left. "Add" asks for a confirmation that shows the
--     credits the player starts with (the late-joiner rule), then writes the MEMBER_JOINED (RosterController:AddMember).
--   * "Link as alt": the list of the season's mains; "Send" sends the request (RosterController:SendAlt).
--   * a confirmation (title, text, Confirm / Cancel), also used by "Add the raid group" (UI/Windows/Roster.lua).
-- Reads and writes through App/RosterController.lua only; every refusal is RosterWindow.ErrorText's sentence.
local ADDON_NAME, ns = ...
ns = ns or {}
local RosterForms = {}
ns.RosterForms = RosterForms
if ns.addon then ns.addon.RosterForms = RosterForms end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

RosterForms.JOIN_W, RosterForms.ADD_W, RosterForms.H = 560, 800, 500
RosterForms.LIST_W, RosterForms.LIST_ROWS = 240, 14
RosterForms.MAX_SPECS = 4          -- a class has at most four specs (the druid)

local function RC() return ns.RosterController end
local function RW() return ns.RosterWindow end
local function short(name) return (tostring(name):gsub("%-.*$", "")) end
local function num(n)
	if type(n) ~= "number" then return "?" end
	return (("%.2f"):format(n):gsub("0+$", ""):gsub("%.$", ""))
end

-- The parent of the dialogs: the Roster tab when it is built, else the screen.
local function host() return (RW() and RW().root) or UIParent end

-- locale-key: DAY_MON DAY_TUE DAY_WED DAY_THU DAY_FRI DAY_SAT DAY_SUN
local function dayName(d) return L["DAY_" .. d] end

---------------------------------------------------------------------------------------------------------------------
-- Confirmation

function RosterForms:Confirm(opts)
	local d = self.confirm
	if not d then
		d = Widgets.Dialog(host(), "FDCPRosterConfirm", { width = 520, height = 300 })
		local c = d.card
		d.title = Theme.NewText(c, "H2", "text-1")
		d.title:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -20)
		d.title:SetPoint("TOPRIGHT", c, "TOPRIGHT", -20, -20)
		d.title:SetJustifyH("LEFT")
		d.body = Theme.NewText(c, "Body", "text-2")
		d.body:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -60)
		d.body:SetWidth(480)
		d.body:SetJustifyH("LEFT")
		d.body:SetJustifyV("TOP")
		d.ok = Widgets.Button(c, { text = L["ROSTER_CONFIRM"], style = "primary", width = 150, height = 30,
			onClick = function() RosterForms:OnConfirm() end })
		d.ok:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -20, 20)
		d.cancel = Widgets.Button(c, { text = L["ROSTER_CANCEL"], style = "ghost", width = 110, height = 30,
			onClick = function() RosterForms:OnCancelConfirm() end })
		d.cancel:SetPoint("RIGHT", d.ok, "LEFT", -8, 0)
		self.confirm = d
	end
	self.pending = opts
	d.title:SetText(opts.title or "")
	d.body:SetText(opts.body or "")
	d.ok:SetLabel(opts.confirm or L["ROSTER_CONFIRM"])
	d.cancel:SetLabel(opts.cancel or L["ROSTER_CANCEL"])
	d:Open()
	return d
end

function RosterForms:OnConfirm()
	local p = self.pending
	self.pending = nil
	if self.confirm then self.confirm:Close() end
	if p and p.onConfirm then p.onConfirm() end
end

function RosterForms:OnCancelConfirm()
	local p = self.pending
	self.pending = nil
	if self.confirm then self.confirm:Close() end
	if p and p.onCancel then p.onCancel() end
end

---------------------------------------------------------------------------------------------------------------------
-- The declaration form

-- A row of chips: `n` chips, single choice (or several with `multi`); :Set(items, selected), :Value().
local function chipRow(parent, n, multi, onChange)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(28)
	row.chips, row.items = {}, {}
	for i = 1, n do
		local chip = Widgets.Chip(row, { text = "", onClick = function(ch)
			if multi then
				ch:SetSelected(not ch:IsSelected())
			else
				for _, other in ipairs(row.chips) do other:SetSelected(other == ch) end
			end
			if onChange then onChange() end
		end })
		row.chips[i] = chip
	end
	function row:Set(items, selected)
		self.items = items
		local x = 0
		for i, chip in ipairs(self.chips) do
			local it = items[i]
			chip:ClearAllPoints()
			if it then
				chip.value = it.id
				chip:SetLabel(it.text)
				chip:SetPoint("LEFT", self, "LEFT", x, 0)
				x = x + chip:GetWidth() + 6
				local on
				if multi then on = type(selected) == "table" and selected[it.id] == true else on = selected == it.id end
				chip:SetSelected(on)
				chip:Show()
			else
				chip.value = nil
				chip:SetSelected(false)
				chip:Hide()
			end
		end
	end
	-- the chosen id (single), or the list of chosen ids in the items' order (multi; nil when none)
	function row:Value()
		if multi then
			local out = {}
			for _, chip in ipairs(self.chips) do
				if chip:IsShown() and chip:IsSelected() then out[#out + 1] = chip.value end
			end
			return #out > 0 and out or nil
		end
		for _, chip in ipairs(self.chips) do
			if chip:IsShown() and chip:IsSelected() then return chip.value end
		end
		return nil
	end
	-- a click on the chip of `id` (tests, and the keyboardless flow)
	function row:Pick(id)
		for _, chip in ipairs(self.chips) do
			if chip:IsShown() and chip.value == id then chip:Click() return true end
		end
		return false
	end
	return row
end
RosterForms.ChipRow = chipRow

local NONE = 0   -- the "—" chip of an optional spec

local function label(parent, key)
	local t = Theme.NewText(parent, "Eyebrow", "text-3")
	t:SetText(L[key]:upper())
	t:SetJustifyH("LEFT")
	return t
end

function RosterForms:BuildForm()
	if self.form then return self.form end
	local d = Widgets.Dialog(host(), "FDCPRosterForm", { width = self.JOIN_W, height = self.H })
	local c = d.card
	d.title = Theme.NewText(c, "H2", "text-1")
	d.title:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -20)
	d.title:SetJustifyH("LEFT")

	-- the officers' list of candidates (Add a player only)
	d.listLabel = label(c, "ROSTER_FORM_CANDIDATES")
	d.listLabel:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -60)
	d.list = Widgets.ChoiceList(c, { rows = self.LIST_ROWS, rowHeight = 24, width = self.LIST_W,
		onSelect = function(id) RosterForms:OnCandidate(id) end })
	d.list:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -80)

	-- the fields, in a frame that moves right when the list is there
	local f = CreateFrame("Frame", nil, c)
	f:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -56)
	f:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -20, 60)
	d.fields = f
	d.class = Theme.NewText(f, "BodyMedium", "text-1")
	d.class:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	d.class:SetJustifyH("LEFT")
	local y = -28
	local function section(key, row)
		local t = label(f, key)
		t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
		row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y - 18)
		row:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y - 18)
		y = y - 58
		return t
	end
	local changed = function() RosterForms:UpdateForm() end
	d.ms1 = chipRow(f, self.MAX_SPECS, false, changed)
	d.ms1Label = section("ROSTER_FORM_MS1", d.ms1)
	d.ms2 = chipRow(f, self.MAX_SPECS + 1, false, changed)
	d.ms2Label = section("ROSTER_FORM_MS2", d.ms2)
	d.os = chipRow(f, self.MAX_SPECS + 1, false, changed)
	d.osLabel = section("ROSTER_FORM_OS", d.os)
	d.days = chipRow(f, 7, true, changed)
	d.daysLabel = section("ROSTER_FORM_DAYS", d.days)
	d.noteLabel = label(f, "ROSTER_FORM_NOTE")
	d.noteLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
	d.note = Widgets.EditBox(f, { width = 300, height = 28, maxLetters = ns.Roster.NOTE_MAX or 80 })
	d.note:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y - 18)

	-- the line above the buttons: what will happen, or why not
	d.info = Theme.NewText(c, "Small", "text-2")
	d.info:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 20, 62)
	d.info:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -20, 62)
	d.info:SetJustifyH("LEFT")
	d.ok = Widgets.Button(c, { text = L["ROSTER_FORM_SEND"], style = "primary", width = 150, height = 30,
		onClick = function() RosterForms:OnSubmit() end })
	d.ok:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -20, 20)
	d.cancel = Widgets.Button(c, { text = L["ROSTER_CANCEL"], style = "ghost", width = 110, height = 30,
		onClick = function() d:Close() end })
	d.cancel:SetPoint("RIGHT", d.ok, "LEFT", -8, 0)
	self.form = d
	return d
end

-- Fills the spec rows for `class` (keeping what is still valid).
function RosterForms:SetClass(class)
	local d = self.form
	d.classFile = class
	if class then
		d.class:SetText(L["ROSTER_FORM_CLASS"]:format(RW().ClassName(class)))
		Theme.Text(d.class, "text-1")
	else
		d.class:SetText(L["ROSTER_FORM_PICK"])
		Theme.Text(d.class, "text-3")
	end
	local specs = class and ns.Specs and ns.Specs.OfClass(class) or {}
	local main, opt = {}, { { id = NONE, text = L["ROSTER_FORM_NONE"] } }
	for _, s in ipairs(specs) do
		main[#main + 1] = { id = s.id, text = s.name }
		opt[#opt + 1] = { id = s.id, text = s.name }
	end
	d.ms1:Set(main, nil)
	d.ms2:Set(class and opt or {}, NONE)
	d.os:Set(class and opt or {}, NONE)
end

-- The declaration the form holds: { ms1, ms2?, os?, avail?, note? }.
function RosterForms:Fields()
	local d = self.form
	if not d then return {} end
	local out = { ms1 = d.ms1:Value() }
	local ms2, os = d.ms2:Value(), d.os:Value()
	if ms2 and ms2 ~= NONE then out.ms2 = ms2 end
	if os and os ~= NONE then out.os = os end
	out.avail = d.days:Value()
	local note = d.note:GetText()
	note = note and note:gsub("^%s+", ""):gsub("%s+$", "")
	if note and note ~= "" then out.note = note end
	return out
end

-- The info line and the state of the main button, after every change.
function RosterForms:UpdateForm()
	local d = self.form
	if not d then return end
	local f = self:Fields()
	local ok = f.ms1 ~= nil and d.classFile ~= nil and (d.mode ~= "add" or d.member ~= nil)
	d.ok:SetEnabled(ok)
	if d.error then
		d.info:SetText(d.error)
		Theme.Text(d.info, "warn")
		return
	end
	Theme.Text(d.info, "text-2")
	if d.mode == "add" then
		if not d.member then d.info:SetText(L["ROSTER_FORM_PICK"]) return end
		local value = RC():JoinCredits(d.member)
		d.info:SetText(value and L["ROSTER_FORM_CREDITS"]:format(short(d.member), num(value)) or "")
	else
		d.info:SetText(L[d.mode == "declare" and "ROSTER_FORM_DECLARE_INFO" or "ROSTER_FORM_JOIN_INFO"])
	end
end

local function layout(self, mode)
	local d = self.form
	local withList = mode == "add"
	d.card:SetWidth(withList and self.ADD_W or self.JOIN_W)
	d.list:SetShown(withList)
	d.listLabel:SetShown(withList)
	d.fields:ClearAllPoints()
	d.fields:SetPoint("TOPLEFT", d.card, "TOPLEFT", withList and (40 + self.LIST_W) or 20, -56)
	d.fields:SetPoint("BOTTOMRIGHT", d.card, "BOTTOMRIGHT", -20, 60)
end

local function reset(d)
	d.error, d.member = nil, nil
	d.days:Set((function()
		local out = {}
		for i, day in ipairs(ns.Roster.DAYS) do out[i] = { id = day, text = dayName(day) } end
		return out
	end)(), {})
	d.note:SetText("")
end

-- The player's form: "Join the roster", or "Declare your specs" when already in the pool without a declaration.
function RosterForms:OpenJoin()
	local status, code = RC():MyStatus()
	if not status then if RW() then RW():SetMessage(RW().ErrorText(code), true) end return nil end
	local d = self:BuildForm()
	reset(d)
	d.mode = status.state == "UNDECLARED" and "declare" or "join"
	layout(self, d.mode)
	d.title:SetText(L[d.mode == "declare" and "ROSTER_DECLARE" or "ROSTER_JOIN"])
	d.ok:SetLabel(L["ROSTER_FORM_SEND"])
	self:SetClass(ns.Compat.Player.ClassFile())
	self:UpdateForm()
	d:Open()
	return d
end

-- The officers' form: a candidate from the raid or the guild, then the declaration.
function RosterForms:OpenAdd()
	local list, code = RC():Candidates()
	if not list then if RW() then RW():SetMessage(RW().ErrorText(code), true) end return nil end
	local d = self:BuildForm()
	reset(d)
	d.mode = "add"
	layout(self, "add")
	d.title:SetText(L["ROSTER_ADD_PLAYER"])
	d.ok:SetLabel(L["ROSTER_FORM_ADD"])
	d.candidates = {}
	local choices = {}
	for i, m in ipairs(list) do
		d.candidates[m.name] = m
		-- locale-key: ROSTER_FORM_IN_RAID ROSTER_FORM_ONLINE ROSTER_FORM_OFFLINE
		local where = L[m.inRaid and "ROSTER_FORM_IN_RAID" or (m.online and "ROSTER_FORM_ONLINE" or "ROSTER_FORM_OFFLINE")]
		choices[i] = { id = m.name, text = short(m.name) .. "  ·  " .. RW().ClassName(m.class) .. "  ·  " .. where,
			token = m.inRaid and "text-1" or (m.online and "text-2" or "text-3") }
	end
	d.list:SetChoices(choices)
	d.list:Clear()
	self:SetClass(nil)
	if #choices == 0 then d.error = L["ROSTER_FORM_NOBODY"] end
	self:UpdateForm()
	d:Open()
	return d
end

function RosterForms:OnCandidate(name)
	local d = self.form
	local m = d and d.candidates and d.candidates[name]
	if not m then return end
	d.member, d.error = m.name, nil
	self:SetClass(m.class)
	self:UpdateForm()
end

-- The main button: the player's request goes out, or the officer's addition asks for its confirmation.
function RosterForms:OnSubmit()
	local d = self.form
	if not d then return end
	local fields = self:Fields()
	if d.mode == "add" then
		local name, class = d.member, d.classFile
		if not name then return end
		fields.class = class
		local s = fields.ms1 and ns.Specs and ns.Specs.Get(fields.ms1)
		local value = RC():JoinCredits(name)
		d:Close()
		self:Confirm({
			title = L["ROSTER_ADD_CONFIRM_TITLE"],
			body = L["ROSTER_ADD_CONFIRM_BODY"]:format(short(name), RW().ClassName(class) .. (s and (" " .. s.name) or ""),
				num(value)),
			confirm = L["ROSTER_FORM_ADD"],
			onConfirm = function()
				local e, code = RC():AddMember(name, fields)
				if RW() then
					if e then RW():SetMessage(L["ROSTER_ADDED"]:format(short(name))) else RW():SetMessage(RW().ErrorText(code), true) end
					RW():Refresh()
				end
			end,
			onCancel = function() d:Open() end,
		})
		return
	end
	local rec, code, wait = RC():SendJoin(fields)
	if not rec then
		d.error = code == "TOO_SOON" and L["ROSTER_ERR_TOO_SOON"]:format(math.ceil(wait or 0)) or RW().ErrorText(code)
		self:UpdateForm()
		d.error = nil
		return
	end
	d:Close()
	if RW() then RW():SetMessage(L["ROSTER_REQUEST_SENT"]); RW():Refresh() end
end

---------------------------------------------------------------------------------------------------------------------
-- Link as alt

function RosterForms:OpenAlt()
	local d = self.alt
	if not d then
		d = Widgets.Dialog(host(), "FDCPRosterAlt", { width = 440, height = 420 })
		local c = d.card
		d.title = Theme.NewText(c, "H2", "text-1")
		d.title:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -20)
		d.title:SetText(L["ROSTER_LINK_ALT"])
		d.body = Theme.NewText(c, "Body", "text-2")
		d.body:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -56)
		d.body:SetWidth(400)
		d.body:SetJustifyH("LEFT")
		d.body:SetText(L["ROSTER_ALT_BODY"])
		d.list = Widgets.ChoiceList(c, { rows = 9, rowHeight = 24, width = 400,
			onSelect = function() RosterForms:UpdateAlt() end })
		d.list:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -84)
		d.info = Theme.NewText(c, "Small", "warn")
		d.info:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 20, 62)
		d.info:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -20, 62)
		d.info:SetJustifyH("LEFT")
		d.ok = Widgets.Button(c, { text = L["ROSTER_FORM_SEND"], style = "primary", width = 150, height = 30,
			onClick = function() RosterForms:OnSubmitAlt() end })
		d.ok:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -20, 20)
		d.cancel = Widgets.Button(c, { text = L["ROSTER_CANCEL"], style = "ghost", width = 110, height = 30,
			onClick = function() d:Close() end })
		d.cancel:SetPoint("RIGHT", d.ok, "LEFT", -8, 0)
		self.alt = d
	end
	local choices = {}
	for i, name in ipairs(RC():Mains()) do choices[i] = { id = name, text = short(name) } end
	d.list:SetChoices(choices)
	d.list:Clear()
	d.info:SetText(#choices == 0 and L["ROSTER_ALT_NOBODY"] or "")
	self:UpdateAlt()
	d:Open()
	return d
end

function RosterForms:UpdateAlt()
	local d = self.alt
	if d then d.ok:SetEnabled(d.list:Selected() ~= nil) end
end

function RosterForms:OnSubmitAlt()
	local d = self.alt
	local main = d and d.list:Selected()
	if not main then return end
	local rec, code, wait = RC():SendAlt(main)
	if not rec then
		d.info:SetText(code == "TOO_SOON" and L["ROSTER_ERR_TOO_SOON"]:format(math.ceil(wait or 0)) or RW().ErrorText(code))
		return
	end
	d:Close()
	if RW() then RW():SetMessage(L["ROSTER_REQUEST_SENT"]); RW():Refresh() end
end
