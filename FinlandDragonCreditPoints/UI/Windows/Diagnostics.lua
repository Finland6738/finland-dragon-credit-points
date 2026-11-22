-- DiagnosticsWindow: `/fdcp debug` (M7-4). A small movable window with the bug report in a copy box: the text is selected
-- when the window opens (and by the button), so Ctrl+C copies it (an addon cannot write to the clipboard). The text comes from
-- App/Diagnostics.lua and holds no names. An edit by hand is put back at once. Lua 5.1; unprotected frames.
-- Not verified in the real client: the window's look, the selection and the copy (M7-4 "in game").
local ADDON_NAME, ns = ...
ns = ns or {}
local DiagnosticsWindow = {}
ns.DiagnosticsWindow = DiagnosticsWindow
if ns.addon then ns.addon.DiagnosticsWindow = DiagnosticsWindow end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

-- locale-key: DIAG_WINDOW_TITLE DIAG_WINDOW_HINT DIAG_SELECT DIAG_REFRESH
function DiagnosticsWindow:Build()
	if self.frame then return self.frame end
	local w = CreateFrame("Frame", "FDCPDiagnosticsWindow", UIParent)
	self.frame = w
	w:SetSize(720, 520)
	w:SetFrameStrata("DIALOG")
	w:SetToplevel(true)
	w:SetClampedToScreen(true)
	w:SetMovable(true)
	w:EnableMouse(true)
	w:RegisterForDrag("LeftButton")
	w:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	w.parts = Theme.Panel(w, { radius = 12, fill = "bg", border = "border", shadow = true, highlight = true })
	w.titleBar = Widgets.TitleBar(w, { title = L["DIAG_WINDOW_TITLE"], subtitle = "", onClose = function() w:Hide() end })
	w.titleBar:SetPoint("TOPLEFT", w, "TOPLEFT", 0, 0)
	w.titleBar:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 0)
	w.titleBar:EnableMouse(true)
	w.titleBar:RegisterForDrag("LeftButton")
	w.titleBar:SetScript("OnDragStart", function() w:StartMoving() end)
	w.titleBar:SetScript("OnDragStop", function() w:StopMovingOrSizing() end)
	w:SetScript("OnDragStart", function() w:StartMoving() end)
	w:SetScript("OnDragStop", function() w:StopMovingOrSizing() end)
	if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "FDCPDiagnosticsWindow" end

	w.hint = Theme.NewText(w, "Small", "text-3")
	w.hint:SetPoint("TOPLEFT", w, "TOPLEFT", 20, -64)
	w.hint:SetPoint("RIGHT", w, "RIGHT", -300, 0)
	w.hint:SetJustifyH("LEFT")
	w.hint:SetText(L["DIAG_WINDOW_HINT"])
	w.refresh = Widgets.Button(w, { text = L["DIAG_REFRESH"], style = "secondary", width = 120, onClick = function() DiagnosticsWindow:Refresh() end })
	w.refresh:SetPoint("TOPRIGHT", w, "TOPRIGHT", -20, -58)
	w.select = Widgets.Button(w, { text = L["DIAG_SELECT"], style = "primary", width = 140, onClick = function() DiagnosticsWindow:SelectAll() end })
	w.select:SetPoint("RIGHT", w.refresh, "LEFT", -8, 0)

	w.field = CreateFrame("Frame", nil, w)
	w.field:SetPoint("TOPLEFT", w, "TOPLEFT", 20, -100)
	w.field:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -20, 20)
	w.field.fill = Theme.Slice(w.field, "rr_fill_8", "surface-2", "BACKGROUND")
	w.field.fill:SetAllPoints(w.field)
	w.field.ring = Theme.Slice(w.field, "rr_ring_8", "border", "BORDER")
	w.field.ring:SetAllPoints(w.field)
	local scroll = CreateFrame("ScrollFrame", nil, w.field)
	scroll:SetPoint("TOPLEFT", w.field, "TOPLEFT", 10, -8)
	scroll:SetPoint("BOTTOMRIGHT", w.field, "BOTTOMRIGHT", -10, 8)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetWidth(660)
	if Theme.fontObjects.Mono then edit:SetFontObject(Theme.fontObjects.Mono)
	elseif Theme.fontObjects.Body then edit:SetFontObject(Theme.fontObjects.Body) end
	Theme.Text(edit, "text-1")
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	edit:SetScript("OnTextChanged", function(self, user)   -- a copy of the report: an edit by hand is put back
		if user and DiagnosticsWindow.text and self:GetText() ~= DiagnosticsWindow.text then self:SetText(DiagnosticsWindow.text) end
	end)
	scroll:SetScrollChild(edit)
	w.scroll, w.edit = scroll, edit
	w:Hide()
	return w
end

-- Builds the report again and shows it.
function DiagnosticsWindow:Refresh()
	local w = self:Build()
	self.text = ns.Diagnostics:Text()
	w.edit:SetText(self.text)
end

-- Selects the whole text so Ctrl+C copies it.
function DiagnosticsWindow:SelectAll()
	if not self.frame or not self.text then return end
	self.frame.edit:SetFocus()
	self.frame.edit:HighlightText()
end

function DiagnosticsWindow:Open()
	self:Refresh()
	self.frame:Show()
	self:SelectAll()
end

function DiagnosticsWindow:IsShown() return self.frame and self.frame:IsShown() or false end
