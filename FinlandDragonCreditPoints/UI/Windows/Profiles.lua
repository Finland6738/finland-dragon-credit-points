-- ProfilesWindow: Settings › Profiles (docs/ANALISI.md §10, docs/specs/ui-style.md §6, M7-3). Three things on one card:
--   * the personal profiles (AceDB): the list, use / new / copy into the current / delete / reset;
--   * the presets of the rules (the Guild Master): pick one, see how many rules it would change, confirm, and it is written
--     in the ledger as the form would (CONFIG_CHANGED with the preset's code);
--   * the profile string: export the current profile as one line to paste on Discord, paste one and see what it changes
--     before applying it. (The guild's rules have their own string, History › Backup.)
-- Everything goes through App/SettingsController.lua; the confirmation dialog is the Settings window's. Lua 5.1.
-- Not verified in the real client: the look of the pane, the paste into the box and the copy (the owner's M7 checklist).
local ADDON_NAME, ns = ...
ns = ns or {}
local ProfilesWindow = {}
ns.ProfilesWindow = ProfilesWindow
if ns.addon then ns.addon.ProfilesWindow = ProfilesWindow end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

ProfilesWindow.MAX_CHANGES_SHOWN = 8

local function SC() return ns.SettingsController end
local function host() return ns.SettingsWindow end

-- locale-key: PROFILES_ERR_OTHER PROFILES_ERR_READ_ONLY PROFILES_ERR_BAD_NAME PROFILES_ERR_EXISTS PROFILES_ERR_NO_PROFILE
-- locale-key: PROFILES_ERR_CURRENT PROFILES_ERR_SAME PROFILES_ERR_UNCHANGED PROFILES_ERR_EMPTY PROFILES_ERR_FORMAT
-- locale-key: PROFILES_ERR_KIND PROFILES_ERR_NEWER PROFILES_ERR_DECODE PROFILES_ERR_INVALID PROFILES_ERR_BAD PROFILES_ERR_NOT_READY
function ProfilesWindow.ErrorText(code)
	code = tostring(code)
	local head = code:gsub(":.*$", "")
	local key = "PROFILES_ERR_" .. head
	if L[key] ~= key then return L[key] end
	local rules = ns.SettingsWindow and ns.SettingsWindow.ErrorText
	if rules and (head == "NOT_GM" or head == "RULES" or head == "CONFIRM_REQUIRED" or head == "PENDING" or head == "NOT_IN_GUILD") then
		return rules(code)
	end
	return L["PROFILES_ERR_OTHER"]:format(code)
end

---------------------------------------------------------------------------------------------------------------------
-- Build

-- locale-key: PROFILES_TITLE PROFILES_HINT PROFILES_LIST PROFILES_USE PROFILES_NEW PROFILES_COPY PROFILES_DELETE PROFILES_RESET
-- locale-key: PROFILES_NAME_HINT PROFILES_PRESETS PROFILES_PRESET_APPLY PROFILES_STRING PROFILES_EXPORT PROFILES_SELECT
-- locale-key: PROFILES_IMPORT
function ProfilesWindow:Build(pane)
	if self.pane then return self.pane end
	self.pane = pane
	local card = Widgets.Card(pane, {})
	card:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -4)
	card:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
	self.card = card
	local function text(kind, token, x, y, str)
		local fs = Theme.NewText(card, kind, token)
		fs:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
		if str then fs:SetText(str) end
		return fs
	end
	text("H2", "text-1", 16, 14, L["PROFILES_TITLE"])
	text("Small", "text-3", 16, 40, L["PROFILES_HINT"])
	-- the personal profiles
	text("Body", "text-2", 16, 70, L["PROFILES_LIST"])
	self.list = Widgets.ChoiceList(card, { rows = 5, rowHeight = 24, width = 250, onSelect = function(id) ProfilesWindow.selected = id end })
	self.list:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -92)
	self.name = Widgets.EditBox(card, { width = 150, maxLetters = ns.Profiles.NAME_MAX })
	self.name:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -232)
	self.new = Widgets.Button(card, { text = L["PROFILES_NEW"], style = "secondary", width = 92, height = 28,
		onClick = function() ProfilesWindow:OnNew() end })
	self.new:SetPoint("LEFT", self.name, "RIGHT", 8, 0)
	self.use = Widgets.Button(card, { text = L["PROFILES_USE"], style = "primary", width = 80, height = 28,
		onClick = function() ProfilesWindow:OnUse() end })
	self.use:SetPoint("TOPLEFT", card, "TOPLEFT", 276, -92)
	self.copy = Widgets.Button(card, { text = L["PROFILES_COPY"], style = "secondary", width = 80, height = 28,
		onClick = function() ProfilesWindow:OnCopy() end })
	self.copy:SetPoint("TOPLEFT", card, "TOPLEFT", 276, -126)
	self.delete = Widgets.Button(card, { text = L["PROFILES_DELETE"], style = "ghost", width = 80, height = 28,
		onClick = function() ProfilesWindow:OnDelete() end })
	self.delete:SetPoint("TOPLEFT", card, "TOPLEFT", 276, -160)
	self.reset = Widgets.Button(card, { text = L["PROFILES_RESET"], style = "ghost", width = 80, height = 28,
		onClick = function() ProfilesWindow:OnReset() end })
	self.reset:SetPoint("TOPLEFT", card, "TOPLEFT", 276, -194)
	-- the presets of the rules
	text("Body", "text-2", 400, 70, L["PROFILES_PRESETS"])
	self.presets = Widgets.ChoiceList(card, { rows = 5, rowHeight = 24, width = 300, onSelect = function(id) ProfilesWindow.preset = id; ProfilesWindow:PaintPreset() end })
	self.presets:SetPoint("TOPLEFT", card, "TOPLEFT", 400, -92)
	self.presetNote = text("Small", "text-3", 400, 220, "")
	self.apply = Widgets.Button(card, { text = L["PROFILES_PRESET_APPLY"], style = "primary", width = 140, height = 28,
		onClick = function() ProfilesWindow:OnApplyPreset() end })
	self.apply:SetPoint("TOPLEFT", card, "TOPLEFT", 400, -236)
	-- the profile string
	text("Body", "text-2", 16, 280, L["PROFILES_STRING"])
	self.import = Widgets.Button(card, { text = L["PROFILES_IMPORT"], style = "secondary", width = 130, height = 28,
		onClick = function() ProfilesWindow:OnImport() end })
	self.import:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -276)
	self.select = Widgets.Button(card, { text = L["PROFILES_SELECT"], style = "secondary", width = 120, height = 28,
		onClick = function() ProfilesWindow:SelectAll() end })
	self.select:SetPoint("RIGHT", self.import, "LEFT", -8, 0)
	self.export = Widgets.Button(card, { text = L["PROFILES_EXPORT"], style = "primary", width = 130, height = 28,
		onClick = function() ProfilesWindow:OnExport() end })
	self.export:SetPoint("RIGHT", self.select, "LEFT", -8, 0)
	self.field = CreateFrame("Frame", nil, card)
	self.field.fill = Theme.Slice(self.field, "rr_fill_8", "surface-2", "BACKGROUND")
	self.field.fill:SetAllPoints(self.field)
	self.field.ring = Theme.Slice(self.field, "rr_ring_8", "border", "BORDER")
	self.field.ring:SetAllPoints(self.field)
	self.field:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -312)
	self.field:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -16, 48)
	local scroll = CreateFrame("ScrollFrame", nil, self.field)
	scroll:SetPoint("TOPLEFT", self.field, "TOPLEFT", 10, -8)
	scroll:SetPoint("BOTTOMRIGHT", self.field, "BOTTOMRIGHT", -10, 8)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetWidth(math.max(200, (pane:GetWidth() or 700) - 80))
	if Theme.fontObjects.Mono then edit:SetFontObject(Theme.fontObjects.Mono)
	elseif Theme.fontObjects.Body then edit:SetFontObject(Theme.fontObjects.Body) end
	Theme.Text(edit, "text-1")
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	scroll:SetScrollChild(edit)
	self.edit = edit
	self.message = Theme.NewText(card, "Small", "text-2")
	self.message:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 16, 18)
	self.message:SetPoint("RIGHT", card, "RIGHT", -16, 0)
	self.message:SetJustifyH("LEFT")
	return pane
end

function ProfilesWindow:SetMessage(text, isError)
	if not self.message then return end
	self.message:SetText(text or "")
	Theme.Text(self.message, isError and "warn" or "text-2")
end

local function say(self, ok, code, text)
	if ok then self:SetMessage(text or "") else self:SetMessage(ProfilesWindow.ErrorText(code), true) end
	self:Refresh()
	return ok
end

---------------------------------------------------------------------------------------------------------------------
-- The personal profiles

-- locale-key: PROFILES_USED PROFILES_CREATED PROFILES_COPIED PROFILES_DELETED PROFILES_WAS_RESET PROFILES_CONFIRM_COPY_TITLE
-- locale-key: PROFILES_CONFIRM_COPY_BODY PROFILES_CONFIRM_DELETE_TITLE PROFILES_CONFIRM_DELETE_BODY PROFILES_CONFIRM_RESET_TITLE
-- locale-key: PROFILES_CONFIRM_RESET_BODY
function ProfilesWindow:OnUse()
	local name = self.selected
	if not name then return end
	say(self, SC():SelectProfile(name))
end

function ProfilesWindow:OnNew()
	local name = self.name:GetText()
	local ok, code = SC():NewProfile(name)
	if ok then self.name:Clear() end
	say(self, ok, code, L["PROFILES_CREATED"]:format(name))
end

function ProfilesWindow:OnCopy()
	local from, current = self.selected, SC():CurrentProfile()
	if not from or from == current then self:SetMessage(self.ErrorText("SAME"), true); return end
	host():Confirm({ title = L["PROFILES_CONFIRM_COPY_TITLE"], body = L["PROFILES_CONFIRM_COPY_BODY"]:format(from, current),
		confirm = L["PROFILES_COPY"],
		onConfirm = function() say(self, SC():CopyProfile(from)) end })
end

function ProfilesWindow:OnDelete()
	local name = self.selected
	if not name then return end
	if name == SC():CurrentProfile() then self:SetMessage(self.ErrorText("CURRENT"), true); return end
	host():Confirm({ title = L["PROFILES_CONFIRM_DELETE_TITLE"], body = L["PROFILES_CONFIRM_DELETE_BODY"]:format(name),
		confirm = L["PROFILES_DELETE"],
		onConfirm = function() self.selected = nil; say(self, SC():DeleteProfile(name), nil, L["PROFILES_DELETED"]:format(name)) end })
end

function ProfilesWindow:OnReset()
	local current = SC():CurrentProfile()
	host():Confirm({ title = L["PROFILES_CONFIRM_RESET_TITLE"], body = L["PROFILES_CONFIRM_RESET_BODY"]:format(current),
		confirm = L["PROFILES_RESET"],
		onConfirm = function() say(self, SC():ResetProfile(), nil, L["PROFILES_WAS_RESET"]) end })
end

---------------------------------------------------------------------------------------------------------------------
-- The presets

local function presetName(code) return L["RC_PRESET_" .. code] end

-- locale-key: PROFILES_PRESET_ACTIVE PROFILES_PRESET_CHANGES PROFILES_PRESET_SAME PROFILES_PRESET_GM
function ProfilesWindow:PaintPreset()
	local code = self.preset
	if not code then self.presetNote:SetText(L["PROFILES_PRESET_GM"]); self.apply:SetEnabled(false); return end
	local diff = SC():PresetDiff(code)
	local gm = SC():CanConfigure()
	if not diff then self.presetNote:SetText(""); self.apply:SetEnabled(false); return end
	self.presetNote:SetText(#diff == 0 and L["PROFILES_PRESET_SAME"] or L["PROFILES_PRESET_CHANGES"]:format(#diff))
	self.apply:SetEnabled(gm == true and #diff > 0)
end

-- The confirmation text: the count and the first rules, by name.
local function changesText(paths)
	local names = {}
	for i, path in ipairs(paths) do
		if i > ProfilesWindow.MAX_CHANGES_SHOWN then break end
		local field = ns.RuleFields and ns.RuleFields.Field(path)
		names[#names + 1] = field and ns.RulesForm.LabelOf(field) or path
	end
	local out = table.concat(names, "\n")
	if #paths > ProfilesWindow.MAX_CHANGES_SHOWN then out = out .. "\n" .. L["SETTINGS_AND_MORE"]:format(#paths - ProfilesWindow.MAX_CHANGES_SHOWN) end
	return out
end

-- locale-key: PROFILES_CONFIRM_PRESET_TITLE PROFILES_CONFIRM_PRESET_BODY PROFILES_PRESET_APPLIED
function ProfilesWindow:OnApplyPreset()
	local code = self.preset
	if not code then return end
	local ok, why = SC():CanConfigure()
	if not ok then self:SetMessage(self.ErrorText(why), true); return end
	local diff = SC():PresetDiff(code)
	if not diff or #diff == 0 then self:SetMessage(self.ErrorText("UNCHANGED"), true); return end
	host():Confirm({
		title = L["PROFILES_CONFIRM_PRESET_TITLE"],
		body = L["PROFILES_CONFIRM_PRESET_BODY"]:format(presetName(code), #diff, changesText(diff)),
		confirm = L["SETTINGS_CONFIRM"],
		onConfirm = function()
			local event, err = SC():ApplyPreset(code, { confirmed = SC():NeedsConfirmation() })
			say(self, event ~= nil, err, L["PROFILES_PRESET_APPLIED"]:format(presetName(code)))
			if event and host().rules then host().rules:Reload() end
		end,
	})
end

---------------------------------------------------------------------------------------------------------------------
-- The profile string

function ProfilesWindow:SelectAll()
	if not self.edit then return end
	self.edit:SetFocus()
	self.edit:HighlightText()
end

-- locale-key: PROFILES_EXPORTED
function ProfilesWindow:OnExport()
	local text, why = SC():ExportProfile()
	if not text then self:SetMessage(self.ErrorText(why), true); return end
	self.edit:SetText(text)
	self:SetMessage(L["PROFILES_EXPORTED"]:format(#text))
end

-- The preview as text: the settings that would change, "Theme: nebula > aurora".
local LABELS = { theme = "PERSONAL_THEME", fontSource = "PERSONAL_FONT", effects = "PERSONAL_EFFECTS", animations = "PERSONAL_ANIMATIONS",
	sounds = "PERSONAL_SOUNDS", guildLanguage = "PERSONAL_GUILD_LANGUAGE", rollSeconds = "PROFILES_ROLL_SECONDS" }
-- locale-key: PROFILES_ROLL_SECONDS
local function previewText(changes)
	local parts = {}
	for i, c in ipairs(changes) do
		if i > ProfilesWindow.MAX_CHANGES_SHOWN then break end
		parts[#parts + 1] = ("%s: %s > %s"):format(L[LABELS[c.key]] or c.key, tostring(c.from), tostring(c.to))
	end
	return table.concat(parts, "\n")
end

-- locale-key: PROFILES_CONFIRM_IMPORT_TITLE PROFILES_CONFIRM_IMPORT_BODY PROFILES_IMPORTED
function ProfilesWindow:OnImport()
	local text = self.edit and self.edit:GetText() or ""
	local preview, why = SC():PreviewProfile(text)
	if not preview then self:SetMessage(self.ErrorText(why), true); return end
	if #preview.changes == 0 then self:SetMessage(self.ErrorText("UNCHANGED"), true); return end
	host():Confirm({
		title = L["PROFILES_CONFIRM_IMPORT_TITLE"],
		body = L["PROFILES_CONFIRM_IMPORT_BODY"]:format(SC():CurrentProfile(), #preview.changes, previewText(preview.changes)),
		confirm = L["PROFILES_IMPORT"],
		onConfirm = function()
			local n, err = SC():ImportProfile(text)
			say(self, n ~= nil, err, L["PROFILES_IMPORTED"]:format(n or 0))
		end,
	})
end

---------------------------------------------------------------------------------------------------------------------
-- Draw

-- locale-key: PROFILES_CURRENT_MARK
function ProfilesWindow:Refresh()
	if not self.pane or not (ns.Config and ns.Config.db) then return end
	local current = SC():CurrentProfile()
	local choices = {}
	for _, name in ipairs(SC():Profiles()) do
		choices[#choices + 1] = { id = name, text = name == current and L["PROFILES_CURRENT_MARK"]:format(name) or name }
	end
	self.list:SetChoices(choices)
	local keep = self.selected
	local found = false
	for _, c in ipairs(choices) do if c.id == keep then found = true end end
	self.selected = found and keep or current
	self.list:Select(self.selected)
	local presets = {}
	for _, p in ipairs(SC():Presets()) do
		presets[#presets + 1] = { id = p.code, text = p.active and L["PROFILES_PRESET_ACTIVE"]:format(presetName(p.code)) or presetName(p.code),
			token = p.active and "text-1" or nil }
	end
	self.presets:SetChoices(presets)
	if self.preset then self.presets:Select(self.preset) end
	self:PaintPreset()
end

if ns.Bus then
	for _, ev in ipairs({ "SETTINGS_RULES_CHANGED", "SETTINGS_PERSONAL_CHANGED", "CONFIG_PROFILE_CHANGED", "LEDGER_SYNCED" }) do
		ns.Bus:On(ev, function() if ProfilesWindow.pane and ProfilesWindow.pane:IsShown() then ProfilesWindow:Refresh() end end, ProfilesWindow)
	end
end
