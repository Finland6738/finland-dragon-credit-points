-- ExportWindow: History › Export (docs/ANALISI.md §7, docs/specs/ui-style.md §6, M6-3): the credits table of the season shown
-- as text ready to paste: Discord (monospaced table, in parts when it is long), CSV and JSON. The text sits in a box with
-- everything selected, so Ctrl+C copies it (an addon cannot write to the clipboard). Needs the permission `export.public`
-- (officers by default): without it the pane says so and a forced call is refused. Never carries the attendance (the text
-- comes from Domain/Export.lua, which only reads what the Credits tab shows to everybody). Lua 5.1.
-- Not verified in the real client: the copy box, the selection and the pane's look in game (the owner's M6 checklist).
local ADDON_NAME, ns = ...
ns = ns or {}
local ExportWindow = {}
ns.ExportWindow = ExportWindow
if ns.addon then ns.addon.ExportWindow = ExportWindow end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

ExportWindow.kind, ExportWindow.part = "discord", 1

local function RC() return ns.RosterController end

-- The guild's language for Domain/Export.lua: separators and dates from the locale, labels and names through locale keys.
-- locale-key: EXPORT_COL_RANK EXPORT_COL_MEMBER EXPORT_COL_CLASS EXPORT_COL_ROLE EXPORT_COL_CREDITS EXPORT_TITLE
-- locale-key: EXPORT_UPDATED EXPORT_PART_LINE
function ExportWindow.Format()
	return {
		decimal = L["NUMBER_DECIMAL"], group = L["NUMBER_GROUP"], date = L["DATE_LONG"],
		className = function(code) return L["CLASS_" .. tostring(code)] end,
		roleName = function(code) return L["ROLE_" .. tostring(code)] end,
		labels = {
			rank = L["EXPORT_COL_RANK"], member = L["EXPORT_COL_MEMBER"], class = L["EXPORT_COL_CLASS"],
			role = L["EXPORT_COL_ROLE"], credits = L["EXPORT_COL_CREDITS"], title = L["EXPORT_TITLE"],
			updated = L["EXPORT_UPDATED"], part = L["EXPORT_PART_LINE"],
		},
	}
end

-- The texts of one export: { text ... } or nil and a reason ("RANK_TOO_LOW" without `export.public`, "NOT_READY",
-- "SEASON_UNKNOWN"). The one door to the data: the pane and any other caller go through it.
function ExportWindow.Generate(kind, season)
	local rc = RC()
	if not rc then return nil, "NOT_READY" end
	local ok, why = rc:Can("export.public")
	if not ok then return nil, why or "RANK_TOO_LOW" end
	local ledger = rc:Ledger()
	if not ledger or not season then return nil, "NOT_READY" end
	return ns.Export.Build(ledger, season, kind, ExportWindow.Format(), { faction = rc:Faction() })
end

-- locale-key: EXPORT_KIND_DISCORD EXPORT_KIND_CSV EXPORT_KIND_JSON EXPORT_SELECT EXPORT_NEXT EXPORT_HINT
function ExportWindow:Build(pane)
	if self.pane then return self.pane end
	self.pane = pane
	local items = {}
	for _, id in ipairs(ns.Export.KINDS) do items[#items + 1] = { id = id, text = L["EXPORT_KIND_" .. id:upper()] } end
	self.seg = Widgets.Segmented(pane, items, function(id) ExportWindow:SetKind(id) end)
	self.seg:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -4)
	self.next = Widgets.Button(pane, { text = L["EXPORT_NEXT"], style = "secondary", width = 140, onClick = function() ExportWindow:NextPart() end })
	self.next:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -2)
	self.select = Widgets.Button(pane, { text = L["EXPORT_SELECT"], style = "primary", width = 140, onClick = function() ExportWindow:SelectAll() end })
	self.select:SetPoint("RIGHT", self.next, "LEFT", -8, 0)
	self.hint = Theme.NewText(pane, "Small", "text-3")
	self.hint:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -44)
	self.hint:SetText(L["EXPORT_HINT"])
	self.info = Theme.NewText(pane, "Small", "text-3")
	self.info:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -44)
	self.message = Theme.NewText(pane, "Body", "text-3")
	self.message:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -72)
	-- the copy box: a multi-line edit box in a scroll frame, on a surface-2 field
	self.field = CreateFrame("Frame", nil, pane)
	self.field:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -64)
	self.field:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
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
	-- the text is a copy of the ledger's numbers: an edit by hand is put back at once
	edit:SetScript("OnTextChanged", function(self, user)
		if user and ExportWindow.text and self:GetText() ~= ExportWindow.text then self:SetText(ExportWindow.text) end
	end)
	scroll:SetScrollChild(edit)
	self.scroll, self.edit = scroll, edit
	self.seg:Select("discord")
	return pane
end

function ExportWindow:SetKind(kind)
	self.kind, self.part = kind, 1
	self:Refresh()
end

function ExportWindow:NextPart()
	if not self.texts or #self.texts < 2 then return end
	self.part = self.part % #self.texts + 1
	self:Refresh()
end

-- Selects the whole text so Ctrl+C copies it.
function ExportWindow:SelectAll()
	if not self.edit or not self.text then return end
	self.edit:SetFocus()
	self.edit:HighlightText()
end

-- locale-key: EXPORT_DENIED EXPORT_NOT_READY EXPORT_PART
function ExportWindow:Refresh()
	if not self.edit then return end
	local season = ns.HistoryWindow and ns.HistoryWindow.seasonShown
	local texts, why = ExportWindow.Generate(self.kind, season)
	self.texts = texts
	if not texts then
		self.text = nil
		self.edit:SetText("")
		self.field:Hide(); self.select:Hide(); self.next:Hide(); self.hint:Hide(); self.info:SetText("")
		self.message:SetText(L[why == "RANK_TOO_LOW" and "EXPORT_DENIED" or "EXPORT_NOT_READY"])
		return
	end
	self.message:SetText("")
	self.field:Show(); self.select:Show(); self.hint:Show()
	if self.part > #texts then self.part = 1 end
	self.text = texts[self.part]
	self.edit:SetText(self.text)
	self.next:SetShown(#texts > 1)
	self.info:SetText(#texts > 1 and L["EXPORT_PART"]:format(self.part, #texts) or "")
end

if ns.Bus then
	for _, ev in ipairs({ "ROSTER_UPDATED", "NIGHT_OPENED", "NIGHT_CLOSED" }) do
		ns.Bus:On(ev, function() if ExportWindow.pane and ExportWindow.pane:IsShown() then ExportWindow:Refresh() end end, ExportWindow)
	end
end
