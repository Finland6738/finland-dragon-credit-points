-- AddonPanel: "Addon in the raid" (docs/ANALISI.md §4.1, docs/specs/ui-style.md §6, M3-6): the Roster > Addon sub-tab with one
-- row per raid member (name, state, version) and the buttons that ask again and write the notice in /raid, plus the
-- summary chip in the title bar. Visible only to who has `raid.addonCheck` (or runs the night). Lua 5.1; unprotected frames.
-- The texts come from App/AddonCheck.lua and App/AddonNotice.lua; this file only draws and calls them.
local ADDON_NAME, ns = ...
ns = ns or {}
local AddonPanel = {}
ns.AddonPanel = AddonPanel
if ns.addon then ns.addon.AddonPanel = AddonPanel end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

AddonPanel.COLUMNS, AddonPanel.PER_COLUMN, AddonPanel.ROW_H = 2, 20, 22
local TONES = { ACTIVE = "ok", OUTDATED = "warn", INCOMPATIBLE = "err", MISSING = "err", WAITING = "text-3" }
local TOKENS = { ACTIVE = "ok", OUTDATED = "warn", INCOMPATIBLE = "err", MISSING = "err", WAITING = "text-3" }
AddonPanel.TONES = TONES

local function check() return ns.AddonCheck end
local function mayManage() local ok = check():CanManage(); return ok == true end

-- The message for a refused action
-- locale-key: NOTICE_ERR_NOT_IN_RAID NOTICE_ERR_ENCOUNTER NOTICE_ERR_CHAT_BLOCKED NOTICE_ERR_THROTTLED NOTICE_ERR_NOBODY
-- locale-key: NOTICE_ERR_TEXT_TOO_LONG NOTICE_ERR_SEND_FAILED NOTICE_ERR_RANK_TOO_LOW ("ENCOUNTER", "THROTTLED" with seconds, a permission code...).
function AddonPanel.ErrorText(code, extra)
	local key = "NOTICE_ERR_" .. tostring(code)
	if code == "THROTTLED" then return L[key]:format(math.ceil(tonumber(extra) or 0)) end
	if L[key] ~= key then return L[key] end
	return L["NOTICE_ERR_OTHER"]:format(tostring(code))
end

-- The summary chip: "37/40 with the addon", green when everybody can roll, amber otherwise.
function AddonPanel:BuildChip(titleBar)
	local chip = Widgets.Badge(titleBar, "", "ok")
	chip:SetPoint("RIGHT", titleBar.close, "LEFT", -12, 0)
	chip:Hide()
	self.chip = chip
	return chip
end

function AddonPanel:RefreshChip()
	local chip = self.chip
	if not chip then return end
	local s = check():Summary()
	if not s.inRaid or not mayManage() then chip:Hide(); return end
	chip:SetBadge(s.text, s.with == s.total and "ok" or "warn")
	chip:Show()
end

-- Builds the sub-tab inside the roster `page` (once).
function AddonPanel:Build(page, titleBar)
	if self.root then return self.root end
	self:BuildChip(titleBar)
	local root = CreateFrame("Frame", nil, page)
	root:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -40)
	root:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
	self.root = root

	-- the sub-tabs of the Roster page: Pool and Night come with M3-7
	root.sub = Widgets.Segmented(page, { { id = "addon", text = L["ADDON_PANEL_SUBTAB"] } }, function() end)
	root.sub:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -4)
	root.sub:Select("addon")

	root.eyebrow = Theme.NewText(root, "Eyebrow", "accent-text")
	root.eyebrow:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -4)
	root.eyebrow:SetText(L["ADDON_PANEL_TITLE"]:upper())
	root.summary = Theme.NewText(root, "MonoMedium", "text-1")
	root.summary:SetPoint("TOPLEFT", root.eyebrow, "BOTTOMLEFT", 0, -6)
	root.counts = Theme.NewText(root, "Small", "text-3")
	root.counts:SetPoint("LEFT", root.summary, "RIGHT", 12, 0)
	root.message = Theme.NewText(root, "Small", "text-2")
	root.message:SetPoint("TOPLEFT", root.summary, "BOTTOMLEFT", 0, -6)
	root.empty = Theme.NewText(root, "Body", "text-3")
	root.empty:SetPoint("TOPLEFT", root.message, "BOTTOMLEFT", 0, -16)

	root.ask = Widgets.Button(root, { text = L["ADDON_PANEL_ASK"], style = "secondary", width = 140,
		onClick = function() AddonPanel:OnAsk() end })
	root.notifyOutdated = Widgets.Button(root, { text = L["ADDON_PANEL_NOTIFY_OUTDATED"], style = "secondary", width = 190,
		onClick = function() AddonPanel:OnNotify("OUTDATED") end })
	root.notify = Widgets.Button(root, { text = L["ADDON_PANEL_NOTIFY"], style = "primary", width = 160,
		onClick = function() AddonPanel:OnNotify("MISSING") end })
	root.notify:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
	root.notifyOutdated:SetPoint("RIGHT", root.notify, "LEFT", -8, 0)
	root.ask:SetPoint("RIGHT", root.notifyOutdated, "LEFT", -8, 0)

	-- rows: two columns of PER_COLUMN, from the top of the list down
	root.rows = {}
	local colW = 0
	root:SetScript("OnSizeChanged", function() AddonPanel:Layout() end)
	for i = 1, self.COLUMNS * self.PER_COLUMN do
		local r = CreateFrame("Frame", nil, root)
		r:SetHeight(self.ROW_H)
		r.name = Theme.NewText(r, "BodyMedium", "text-1")
		r.name:SetPoint("LEFT", r, "LEFT", 4, 0)
		r.state = Theme.NewText(r, "Small", "text-3")
		r.state:SetPoint("LEFT", r, "LEFT", 150, 0)
		r.version = Theme.NewText(r, "MonoSmall", "text-3")
		r.version:SetPoint("RIGHT", r, "RIGHT", -4, 0)
		r:Hide()
		root.rows[i] = r
	end
	self:Layout()
	return root
end

function AddonPanel:Layout()
	local root = self.root
	if not root then return end
	local width = (root:GetWidth() or 0) > 100 and root:GetWidth() or 900
	local colW = math.floor((width - 16) / self.COLUMNS)
	for i, r in ipairs(root.rows) do
		local col = math.floor((i - 1) / self.PER_COLUMN)
		local row = (i - 1) % self.PER_COLUMN
		r:SetWidth(colW)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", root, "TOPLEFT", col * (colW + 16), -110 - row * self.ROW_H)
	end
end

-- Draws the table from AddonCheck.
function AddonPanel:Refresh()
	self:RefreshChip()
	local root = self.root
	if not root then return end
	local AC = check()
	local allowed = mayManage()
	local s = AC:Summary()
	root.ask:SetShown(allowed); root.notify:SetShown(allowed); root.notifyOutdated:SetShown(allowed)
	if not allowed then
		root.summary:SetText(""); root.counts:SetText("")
		root.empty:SetText(L["ADDON_PANEL_FORBIDDEN"])
		for _, r in ipairs(root.rows) do r:Hide() end
		return
	end
	if not s.inRaid then
		root.summary:SetText(""); root.counts:SetText("")
		root.empty:SetText(L["ADDON_PANEL_NO_RAID"])
		for _, r in ipairs(root.rows) do r:Hide() end
		return
	end
	root.empty:SetText("")
	root.summary:SetText(s.text)
	root.counts:SetText(L["ADDON_PANEL_COUNTS"]:format(s.MISSING + s.INCOMPATIBLE, s.OUTDATED, s.WAITING))
	local rows = AC:Rows()
	-- who needs attention first: not active, incompatible, outdated, waiting, then the active ones; names inside
	local rank = { MISSING = 1, INCOMPATIBLE = 2, OUTDATED = 3, WAITING = 4, ACTIVE = 5 }
	table.sort(rows, function(a, b)
		if rank[a.state] ~= rank[b.state] then return rank[a.state] < rank[b.state] end
		return a.name < b.name
	end)
	for i, r in ipairs(root.rows) do
		local data = rows[i]
		if data then
			r.name:SetText(ns.Notice.ShortName(data.name))
			r.state:SetText(data.label)
			Theme.Text(r.state, TOKENS[data.state] or "text-3")
			r.version:SetText(data.av and L["ADDON_PANEL_VERSION"]:format(tostring(data.av)) or "")
			r:Show()
		else
			r:Hide()
		end
	end
end

function AddonPanel:SetMessage(text, isError)
	if not self.root then return end
	self.root.message:SetText(text or "")
	Theme.Text(self.root.message, isError and "warn" or "text-2")
end

function AddonPanel:OnAsk()
	local ok, code = check():Request()
	if ok then self:SetMessage(L["NOTICE_ASKED"]) else self:SetMessage(self.ErrorText(code), true) end
end

-- locale-key: NOTICE_SENT NOTICE_SENT_WHISPER
function AddonPanel:OnNotify(kind)
	local entry, code, extra = ns.AddonNotice:Send(kind)
	if not entry then self:SetMessage(self.ErrorText(code, extra), true); return end
	if entry.mode == "WHISPER" then
		self:SetMessage(L["NOTICE_SENT_WHISPER"]:format(entry.lines))
	else
		self:SetMessage(L["NOTICE_SENT"]:format("/raid", entry.lines))
	end
end

if ns.Bus then
	ns.Bus:On("ADDON_CHECK_CHANGED", function() AddonPanel:Refresh() end, AddonPanel)
	ns.Bus:On("GUILD_RANKS_READY", function() AddonPanel:Refresh() end, AddonPanel)
	ns.Bus:On("GUILD_RANKS_CHANGED", function() AddonPanel:Refresh() end, AddonPanel)
end
