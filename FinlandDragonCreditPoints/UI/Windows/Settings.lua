-- SettingsWindow: the Settings tab (docs/ANALISI.md §3.9, §10, docs/specs/ui-style.md §6, M7-2): the sub-tabs Personal, Rules,
-- Permissions, Site, Season and About (M7-2c). Lua 5.1; unprotected frames.
--   Personal     the player's own preferences: theme, fonts, neon effects, animations, sounds, languages, the popup's position,
--                the personal stat weights and the wishlist. Free for everybody, nothing is shared.
--   Rules        the guild's rules, page by page (UI/Windows/RulesForm.lua): read-only for everybody but the Guild Master.
--   Permissions  the rank each permission needs (the Guild Master edits; the others read), plus the review of a guild rank change.
--   Site         the guild's key on the community site (a page of the same form).
--   Season       the season's page of M6-1b (UI/Windows/Season.lua).
--   About        who made the addon, the licence, the links to copy and the way to support it (UI/Windows/About.lua).
-- Every write goes through App/SettingsController.lua, which refuses anybody but the Guild Master; the window only hides what
-- the player may not use. Every change of the rules or of the permissions while a season is open asks an explicit confirmation
-- (this file's dialog) and stays in the ledger for the audit.
-- Not verified in the real client: the look of the tab, the dropdowns and the game's settings entry (M7-2 "in game").
local ADDON_NAME, ns = ...
ns = ns or {}
local SettingsWindow = {}
ns.SettingsWindow = SettingsWindow
if ns.addon then ns.addon.SettingsWindow = SettingsWindow end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

SettingsWindow.SUBTABS = { "personal", "profiles", "rules", "permissions", "site", "season", "about" }
SettingsWindow.RULE_PAGES = { "session", "priority", "costs", "multipliers", "members", "council", "legendary", "messages", "upgrade" }
SettingsWindow.ROW_H = 36

local function SC() return ns.SettingsController end
local function RF() return ns.RulesForm end

-- The message of a refused action (the one list of the tab).
function SettingsWindow.ErrorText(code, detail) return RF().ErrorText(code, detail) end

local function permKey(p) return "PERM_" .. p:upper():gsub("%.", "_") end

---------------------------------------------------------------------------------------------------------------------
-- The confirmation dialog (shared by every pane)

-- opts = { title, body, confirm (the button's text), onConfirm }. Nothing is written until the button is pressed.
function SettingsWindow:Confirm(opts)
	local d = self.dialog
	if not d then
		d = Widgets.Dialog(self.root, "FDCPSettingsConfirm", { width = 520, height = 360 })
		local c = d.card
		d.title = Theme.NewText(c, "H2", "text-1")
		d.title:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -20)
		d.body = Theme.NewText(c, "Body", "text-2")
		d.body:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -60)
		d.body:SetWidth(480)
		d.body:SetJustifyH("LEFT")
		d.body:SetJustifyV("TOP")
		d.confirm = Widgets.Button(c, { text = L["SETTINGS_CONFIRM"], style = "primary", width = 170, height = 30,
			onClick = function() SettingsWindow:OnConfirm() end })
		d.confirm:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -20, 20)
		d.cancel = Widgets.Button(c, { text = L["SETTINGS_CANCEL"], style = "ghost", width = 110, height = 30,
			onClick = function() SettingsWindow:OnCancel() end })
		d.cancel:SetPoint("RIGHT", d.confirm, "LEFT", -8, 0)
		self.dialog = d
	end
	self.pending = opts
	d.title:SetText(opts.title or "")
	d.body:SetText(opts.body or "")
	d.confirm:SetLabel(opts.confirm or L["SETTINGS_CONFIRM"])
	d:Open()
end

function SettingsWindow:OnCancel()
	self.pending = nil
	if self.dialog then self.dialog:Close() end
end

function SettingsWindow:OnConfirm()
	local p = self.pending
	self.pending = nil
	if self.dialog then self.dialog:Close() end
	if p and p.onConfirm then p.onConfirm() end
end

---------------------------------------------------------------------------------------------------------------------
-- Build

-- locale-key: SETTINGS_SUB_PERSONAL SETTINGS_SUB_PROFILES SETTINGS_SUB_RULES SETTINGS_SUB_PERMISSIONS SETTINGS_SUB_SITE SETTINGS_SUB_SEASON SETTINGS_SUB_ABOUT
function SettingsWindow:Build(page)
	if self.root then return self.root end
	local root = CreateFrame("Frame", nil, page)
	root:SetAllPoints(page)
	self.root, self.page = root, page
	local items = {}
	for _, id in ipairs(self.SUBTABS) do items[#items + 1] = { id = id, text = L["SETTINGS_SUB_" .. id:upper()] } end
	root.sub = Widgets.Segmented(root, items, function(id) SettingsWindow:ShowSub(id) end)
	root.sub:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -4)
	root.panes = {}
	for _, id in ipairs(self.SUBTABS) do
		local pane = CreateFrame("Frame", nil, root)
		pane:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -44)
		pane:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
		pane:Hide()
		root.panes[id] = pane
	end
	self:BuildPersonal(root.panes.personal)
	if ns.ProfilesWindow then ns.ProfilesWindow:Build(root.panes.profiles) end
	self.rules = ns.RulesForm.New(root.panes.rules, { pages = self.RULE_PAGES, host = self })
	self:BuildPermissions(root.panes.permissions)
	self.site = ns.RulesForm.New(root.panes.site, { pages = { "site" }, host = self, list = false })
	if ns.SeasonWindow then ns.SeasonWindow:Build(root.panes.season) end
	if ns.AboutWindow then ns.AboutWindow:Build(root.panes.about) end
	root.sub:Select("personal")
	return root
end

function SettingsWindow:ActiveSub() return self.root and self.root.sub:Active() end

function SettingsWindow:ShowSub(id)
	if not self.root then return end
	for pid, pane in pairs(self.root.panes) do pane:SetShown(pid == id) end
	self:Refresh()
end

-- Draws the sub-tab on show again.
function SettingsWindow:Refresh()
	if not self.root then return end
	local id = self:ActiveSub()
	if id == "personal" then self:RefreshPersonal()
	elseif id == "profiles" and ns.ProfilesWindow then ns.ProfilesWindow:Refresh()
	elseif id == "rules" then self.rules:Refresh()
	elseif id == "permissions" then self:RefreshPermissions()
	elseif id == "site" then self.site:Refresh()
	elseif id == "season" and ns.SeasonWindow then ns.SeasonWindow:Refresh()
	elseif id == "about" and ns.AboutWindow then ns.AboutWindow:Refresh() end
end

---------------------------------------------------------------------------------------------------------------------
-- Personal

-- locale-key: PERSONAL_TITLE PERSONAL_HINT PERSONAL_THEME PERSONAL_FONT PERSONAL_FONT_ADDON PERSONAL_FONT_GAME
-- locale-key: PERSONAL_EFFECTS PERSONAL_ANIMATIONS PERSONAL_SOUNDS PERSONAL_LANGUAGE PERSONAL_GUILD_LANGUAGE
-- locale-key: PERSONAL_POPUP PERSONAL_POPUP_RESET PERSONAL_WEIGHTS PERSONAL_WISHLIST PERSONAL_WISHLIST_CLEAR
function SettingsWindow:BuildPersonal(pane)
	local card = Widgets.Card(pane, {})
	card:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -4)
	card:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
	pane.card = card
	card.title = Theme.NewText(card, "H2", "text-1")
	card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -14)
	card.title:SetText(L["PERSONAL_TITLE"])
	card.hint = Theme.NewText(card, "Small", "text-3")
	card.hint:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
	card.hint:SetText(L["PERSONAL_HINT"])
	card.message = Theme.NewText(card, "Small", "text-2")
	card.message:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 16, 18)
	card.message:SetPoint("RIGHT", card, "RIGHT", -16, 0)
	card.message:SetJustifyH("LEFT")
	local c = {}
	pane.controls = c
	local function label(x, y, key)
		local fs = Theme.NewText(card, "Body", "text-2")
		fs:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
		fs:SetText(L[key])
		return fs
	end
	local function say(ok, code, text)
		if ok then self:PersonalMessage(text or "") else self:PersonalMessage(SettingsWindow.ErrorText(code), true) end
	end
	local function switch(name, x, y, key)
		label(x, y + 4, key)
		local s = Widgets.Switch(card, { onChange = function(on) say(SC():SetPersonal(name, on)) end })
		s:SetPoint("TOPLEFT", card, "TOPLEFT", x + 250, -y)
		c[name] = s
	end
	local function choice(name, x, y, key, choices, onSelect)
		label(x, y + 4, key)
		local s = Widgets.Select(card, { width = 170, rows = 5, choices = choices, onSelect = onSelect })
		s:SetPoint("TOPLEFT", card, "TOPLEFT", x + 250, -y)
		c[name] = s
	end
	local X1, X2, Y = 16, 430, 74
	-- the look
	local themes = {}
	for _, id in ipairs(Theme.List()) do themes[#themes + 1] = { id = id, text = Theme.Name(id) } end
	choice("theme", X1, Y, "PERSONAL_THEME", themes, function(id) say(SC():SetPersonal("theme", id)) end)
	choice("fontSource", X1, Y + 40, "PERSONAL_FONT", { { id = "addon", text = L["PERSONAL_FONT_ADDON"] },
		{ id = "game", text = L["PERSONAL_FONT_GAME"] } }, function(id) say(SC():SetPersonal("fontSource", id)) end)
	switch("effects", X1, Y + 80, "PERSONAL_EFFECTS")
	switch("animations", X1, Y + 120, "PERSONAL_ANIMATIONS")
	switch("sounds", X1, Y + 160, "PERSONAL_SOUNDS")
	-- the languages
	local languages, auto = {}, { { id = "auto", text = L["LANGUAGE_AUTO"] } }
	for _, lang in ipairs(ns.Locale.Languages()) do
		languages[#languages + 1] = { id = lang.code, text = lang.name }
		auto[#auto + 1] = { id = lang.code, text = lang.name }
	end
	choice("language", X2, Y, "PERSONAL_LANGUAGE", auto, function(id)
		local ok, code = SC():SetLanguage(id)
		say(ok, code, L["LANGUAGE_SET"]:format(id == "auto" and L["LANGUAGE_AUTO"] or id))
	end)
	choice("guildLanguage", X2, Y + 40, "PERSONAL_GUILD_LANGUAGE", languages, function(id) say(SC():SetPersonal("guildLanguage", id)) end)
	-- the popup, the weights and the wishlist
	label(X2, Y + 84, "PERSONAL_POPUP")
	c.popup = Widgets.Button(card, { text = L["PERSONAL_POPUP_RESET"], style = "secondary", width = 170, height = 28,
		onClick = function() SC():ResetPopup(); say(true, nil, L["PERSONAL_POPUP_DONE"]) end })
	c.popup:SetPoint("TOPLEFT", card, "TOPLEFT", X2 + 250, -(Y + 80))
	label(X2, Y + 124, "PERSONAL_WEIGHTS")
	c.weights = Widgets.Switch(card, { onChange = function(on)
		local ok, code = ns.PersonalUpgrade.SetEnabled(on)
		say(ok, code)
		if not ok then self:RefreshPersonal() end
	end })
	c.weights:SetPoint("TOPLEFT", card, "TOPLEFT", X2 + 250, -(Y + 120))
	card.weightsHint = Theme.NewText(card, "Small", "text-3")
	card.weightsHint:SetPoint("TOPLEFT", card, "TOPLEFT", X2, -(Y + 150))
	card.weightsHint:SetText(L["PERSONAL_WEIGHTS_HINT"])
	label(X2, Y + 184, "PERSONAL_WISHLIST")
	card.wishCount = Theme.NewText(card, "Body", "text-1")
	card.wishCount:SetPoint("TOPLEFT", card, "TOPLEFT", X2 + 250, -(Y + 184))
	c.wishClear = Widgets.Button(card, { text = L["PERSONAL_WISHLIST_CLEAR"], style = "ghost", width = 120, height = 28,
		onClick = function() SettingsWindow:OnClearWishlist() end })
	c.wishClear:SetPoint("LEFT", card.wishCount, "RIGHT", 12, 0)
end

-- locale-key: PERSONAL_POPUP_DONE PERSONAL_WEIGHTS_HINT PERSONAL_WISHLIST_COUNT PERSONAL_WISHLIST_CLEARED
-- locale-key: PERSONAL_CLEAR_TITLE PERSONAL_CLEAR_BODY
function SettingsWindow:OnClearWishlist()
	local n = #ns.PersonalUpgrade.WishList()
	if n == 0 then return end
	self:Confirm({ title = L["PERSONAL_CLEAR_TITLE"], body = L["PERSONAL_CLEAR_BODY"]:format(n), confirm = L["PERSONAL_WISHLIST_CLEAR"],
		onConfirm = function()
			ns.PersonalUpgrade.WishClear()
			self:PersonalMessage(L["PERSONAL_WISHLIST_CLEARED"])
			self:RefreshPersonal()
		end })
end

function SettingsWindow:PersonalMessage(text, isError)
	local card = self.root and self.root.panes.personal.card
	if not card then return end
	card.message:SetText(text or "")
	Theme.Text(card.message, isError and "warn" or "text-2")
end

function SettingsWindow:RefreshPersonal()
	local pane = self.root.panes.personal
	local c, Config = pane.controls, ns.Config
	c.theme:Select(ns.Theme.Current(), true)
	c.fontSource:Select(Config:Get("fontSource"), true)
	for _, name in ipairs({ "effects", "animations", "sounds" }) do c[name]:SetOn(Config:Get(name) == true, true) end
	c.language:Select(Config:GetLanguage(), true)
	c.guildLanguage:Select(Config:Get("guildLanguage"), true)
	c.weights:SetOn(ns.PersonalUpgrade.Enabled(), true)
	local n = #ns.PersonalUpgrade.WishList()
	pane.card.wishCount:SetText(L["PERSONAL_WISHLIST_COUNT"]:format(n))
	c.wishClear:SetEnabled(n > 0)
end

---------------------------------------------------------------------------------------------------------------------
-- Permissions

-- locale-key: PERMS_TITLE PERMS_HINT PERMS_RANK PERMS_RANK_UNNAMED PERMS_FIXED
-- locale-key: PERM_CONFIG_RULES PERM_CONFIG_PERMISSIONS PERM_SEASON_MANAGE PERM_NIGHT_RUN PERM_AWARD_CONFIRM PERM_COUNCIL_MEMBER
-- locale-key: PERM_CREDITS_ADJUST PERM_ROSTER_MANAGE PERM_EXPORT_PUBLIC PERM_VIEW_ATTENDANCE PERM_RAID_ADDONCHECK PERM_PROGRESS_EDIT
function SettingsWindow:BuildPermissions(pane)
	local card = Widgets.Card(pane, {})
	card:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -4)
	card:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
	pane.card = card
	card.title = Theme.NewText(card, "H2", "text-1")
	card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -14)
	card.title:SetText(L["PERMS_TITLE"])
	card.note = Theme.NewText(card, "Small", "text-3")
	card.note:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
	card.note:SetPoint("RIGHT", card, "RIGHT", -16, 0)
	card.note:SetJustifyH("LEFT")
	-- the review of a guild rank change (the Guild Master only)
	card.review = Theme.NewText(card, "Body", "warn")
	card.review:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -64)
	card.review:SetPoint("RIGHT", card, "RIGHT", -230, 0)
	card.review:SetJustifyH("LEFT")
	card.review:SetJustifyV("TOP")
	card.reviewDone = Widgets.Button(card, { text = L["PERMS_REVIEW_DONE"], style = "secondary", width = 200, onClick = function() SettingsWindow:OnReviewDone() end })
	card.reviewDone:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -62)
	card.message = Theme.NewText(card, "Small", "text-2")
	card.message:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 16, 22)
	card.message:SetPoint("RIGHT", card, "RIGHT", -300, 0)
	card.message:SetJustifyH("LEFT")
	card.save = Widgets.Button(card, { text = L["SETTINGS_SAVE"], style = "primary", width = 130, onClick = function() SettingsWindow:OnSavePermissions() end })
	card.save:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -16, 14)
	card.revert = Widgets.Button(card, { text = L["SETTINGS_REVERT"], style = "ghost", width = 130, onClick = function() SettingsWindow:ReloadPermissions() end })
	card.revert:SetPoint("RIGHT", card.save, "LEFT", -8, 0)
	pane.rows = {}
	for i, p in ipairs(ns.Permissions.LIST) do
		local row = { permission = p }
		row.label = Theme.NewText(card, "Body", "text-2")
		row.label:SetText(L[permKey(p)])
		row.select = Widgets.Select(card, { width = 190, rows = 6, onSelect = function(id) SettingsWindow:OnRankPicked(p, id) end })
		pane.rows[i] = row
	end
	pane.draft = nil
	self.permissionsPane = pane
	self:LayoutPermissions()
end

-- Two columns of six, below the review banner when there is one.
function SettingsWindow:LayoutPermissions()
	local pane = self.permissionsPane
	local card = pane.card
	local top = pane.reviewShown and 128 or 76
	local W = (card:GetWidth() or 0) > 100 and card:GetWidth() or 900
	local colW = math.floor((W - 48) / 2)
	for i, row in ipairs(pane.rows) do
		local col, line = math.floor((i - 1) / 6), (i - 1) % 6
		local x = 16 + col * (colW + 16)
		row.label:ClearAllPoints()
		row.label:SetPoint("TOPLEFT", card, "TOPLEFT", x, -(top + line * SettingsWindow.ROW_H + 6))
		row.label:SetWidth(colW - 210)
		row.select:ClearAllPoints()
		row.select:SetPoint("TOPLEFT", card, "TOPLEFT", x + colW - 190, -(top + line * SettingsWindow.ROW_H))
	end
end

-- The text of a rank index in the dropdowns: "1 · Officer" (the game's name) or "Rank 3" when the client gives none.
function SettingsWindow.RankText(names, i)
	if names[i] then return L["PERMS_RANK"]:format(i, names[i]) end
	return L["PERMS_RANK_UNNAMED"]:format(i)
end

function SettingsWindow:PermissionsMessage(text, isError)
	local card = self.permissionsPane and self.permissionsPane.card
	if not card then return end
	card.message:SetText(text or "")
	Theme.Text(card.message, isError and "warn" or "text-2")
end

function SettingsWindow:ReloadPermissions()
	local pane = self.permissionsPane
	pane.draft = ns.Permissions.Normalize(SC():Table())
	self:PermissionsMessage("")
	self:PaintPermissions()
end

-- The choices of a row: every rank of the guild (the ones the table already uses too), the fixed permissions only the Guild Master.
function SettingsWindow:PaintPermissions()
	local pane = self.permissionsPane
	local names, count = SC():RankNames()
	local top = count > 0 and count - 1 or ns.Permissions.MAX_RANK
	for _, r in pairs(pane.draft) do if r > top then top = r end end
	local editable = SC():CanConfigure() == true
	local now = SC():Table()
	for _, row in ipairs(pane.rows) do
		local p = row.permission
		local choices = {}
		if ns.Permissions.FIXED[p] then
			choices[1] = { id = ns.Permissions.GM, text = SettingsWindow.RankText(names, ns.Permissions.GM) }
		else
			for i = 0, top do choices[#choices + 1] = { id = i, text = SettingsWindow.RankText(names, i) } end
		end
		row.select:SetChoices(choices)
		row.select:Select(pane.draft[p], true)
		row.select:SetEnabled(editable and not ns.Permissions.FIXED[p])
		Theme.Text(row.label, pane.draft[p] ~= now[p] and "accent-text" or "text-2")
	end
end

-- locale-key: PERMS_REVIEW_DONE PERMS_REVIEW_MISSING PERMS_REVIEW_ACK
function SettingsWindow:RefreshPermissions()
	local pane = self.permissionsPane
	local card = pane.card
	local editable = SC():CanConfigure() == true
	if not pane.draft or #SC():TableDiff(pane.draft) == 0 then pane.draft = ns.Permissions.Normalize(SC():Table()) end
	-- the review of a rank change, for the Guild Master
	local review = SC():RankReview()
	pane.reviewShown = review ~= nil
	card.review:SetShown(review ~= nil)
	card.reviewDone:SetShown(review ~= nil)
	if review then
		local text = ns.Reasons.Text("RANKS", review.code)
		if review.missing and #review.missing > 0 then
			local labels = {}
			for i, p in ipairs(review.missing) do labels[i] = L[permKey(p)] end
			text = text .. "\n" .. L["PERMS_REVIEW_MISSING"]:format(table.concat(labels, ", "))
		end
		card.review:SetText(text)
	end
	card.note:SetText(editable and L["PERMS_HINT"] or L["SETTINGS_READONLY"])
	card.save:SetShown(editable)
	card.revert:SetShown(editable)
	self:LayoutPermissions()
	self:PaintPermissions()
	if not editable then self:PermissionsMessage("") end
end

function SettingsWindow:OnRankPicked(p, rank)
	local pane = self.permissionsPane
	if SC():CanConfigure() ~= true then return end
	pane.draft[p] = rank
	local n = #SC():TableDiff(pane.draft)
	self:PermissionsMessage(n > 0 and L["SETTINGS_PENDING"]:format(n) or "")
	for _, row in ipairs(pane.rows) do
		if row.permission == p then Theme.Text(row.label, rank ~= SC():Table()[p] and "accent-text" or "text-2") end
	end
end

-- Save: the same two steps as the rules: a confirmation with a season open, then the write.
function SettingsWindow:OnSavePermissions()
	local pane = self.permissionsPane
	if SC():CanConfigure() ~= true then self:PermissionsMessage(SettingsWindow.ErrorText("NOT_GM"), true); return end
	local diff = SC():TableDiff(pane.draft)
	if #diff == 0 then self:PermissionsMessage(SettingsWindow.ErrorText("UNCHANGED"), true); return end
	local draft = ns.Permissions.Normalize(pane.draft)
	local function write(confirmed)
		local event, code = SC():ApplyPermissions(draft, { confirmed = confirmed })
		if not event then self:PermissionsMessage(SettingsWindow.ErrorText(code), true); return end
		self:ReloadPermissions()
		self:PermissionsMessage(L["SETTINGS_SAVED"])
	end
	if SC():NeedsConfirmation() then
		local names, lines = SC():RankNames(), {}
		for _, d in ipairs(diff) do
			lines[#lines + 1] = L["PERMS_CHANGE_LINE"]:format(L[permKey(d.permission)], SettingsWindow.RankText(names, d.from),
				SettingsWindow.RankText(names, d.to))
		end
		self:Confirm({ title = L["SETTINGS_CONFIRM_PERMS_TITLE"], body = L["SETTINGS_CONFIRM_PERMS_BODY"]:format(#diff, table.concat(lines, "\n")),
			confirm = L["SETTINGS_CONFIRM"], onConfirm = function() write(true) end })
		return
	end
	write(false)
end

-- The Guild Master has looked at the table after a rank change.
function SettingsWindow:OnReviewDone()
	local ok, code = SC():AcknowledgeRankReview()
	if ok then self:PermissionsMessage(L["PERMS_REVIEW_ACK"]) else self:PermissionsMessage(SettingsWindow.ErrorText(code), true) end
	self:RefreshPermissions()
end

---------------------------------------------------------------------------------------------------------------------
-- Events

if ns.Bus then
	for _, ev in ipairs({ "SETTINGS_RULES_CHANGED", "SETTINGS_PERMISSIONS_CHANGED", "GUILD_RANKS_READY", "GUILD_RANKS_CHANGED",
		"GUILD_KEY_CHANGED", "PERMISSIONS_QUEUE_DRAINED" }) do
		ns.Bus:On(ev, function() SettingsWindow:Refresh() end, SettingsWindow)
	end
end
