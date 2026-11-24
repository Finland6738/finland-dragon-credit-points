-- RosterWindow: the Roster tab (docs/ANALISI.md §6, §9.3, docs/specs/ui-style.md §3, §6, M3-7). It hosts the sub-tabs
-- Pool, Night, Addon and Readiness (M8-3: shown only to who may ask the raid) and draws the first one: the site's three role columns (Tank, Healer, DPS) with the class colour
-- square, the declared spec, the Trial badge, the count against the target, the 4 pt gradient bar and the free slots; the
-- header names the faction of the player's guild (one guild is one faction in game: no faction switch, fix/roster-join).
-- The header's buttons: for a player outside the pool "Join the roster" and "Link as alt", for a member without a
-- declaration "Declare your specs" (UI/Windows/RosterForms.lua draws the forms), with the state of the player's own
-- request; for the officers "Add a player" and "Add the raid group", the status button of each row and the inbox of the
-- players' requests with the members still without a declaration.
-- Reads App/RosterController.lua; it never touches the ledger itself. Lua 5.1; unprotected frames.
local ADDON_NAME, ns = ...
ns = ns or {}
local RosterWindow = {}
ns.RosterWindow = RosterWindow
if ns.addon then ns.addon.RosterWindow = RosterWindow end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

RosterWindow.ROW_H, RosterWindow.ROWS, RosterWindow.INBOX_ROWS = 22, 11, 3
RosterWindow.MAX_UNDECLARED = 12   -- names listed under the inbox (the rest is a count)
RosterWindow.SUBTABS = { "pool", "night", "addon", "readiness" }

-- The game's own class colours (the spec lists them; the client's table wins when it has the class).
local CLASS_COLORS = {
	WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 },
	ROGUE = { 1, 0.96, 0.41 }, PRIEST = { 1, 1, 1 }, SHAMAN = { 0, 0.44, 0.87 }, MAGE = { 0.25, 0.78, 0.92 },
	WARLOCK = { 0.53, 0.53, 0.93 }, DRUID = { 1, 0.49, 0.04 },
}
function RosterWindow.ClassColor(class)
	local c = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
	if c and c.r then return c.r, c.g, c.b end
	local t = CLASS_COLORS[class] or { 0.8, 0.8, 0.8 }
	return t[1], t[2], t[3]
end

local function RC() return ns.RosterController end

-- locale-key: ROLE_TANK ROLE_HEALER ROLE_DAMAGER
function RosterWindow.RoleName(role) return L["ROLE_" .. tostring(role)] end
-- locale-key: CLASS_WARRIOR CLASS_PALADIN CLASS_HUNTER CLASS_ROGUE CLASS_PRIEST CLASS_SHAMAN CLASS_MAGE CLASS_WARLOCK CLASS_DRUID
function RosterWindow.ClassName(class) return L["CLASS_" .. tostring(class)] end
local FACTION_KEYS = { Horde = "FACTION_Horde", Alliance = "FACTION_Alliance" }
function RosterWindow.FactionName(faction) return L[FACTION_KEYS[faction] or "FACTION_Horde"] end

-- "Aurel-Realm" -> "Aurel"
local function short(name) return (tostring(name):gsub("%-.*$", "")) end
RosterWindow.ShortName = short

-- The spec of an entry: "Holy" (the table's name), or an empty text.
local function specText(m)
	local s = m.ms1 and ns.Specs and ns.Specs.Get(m.ms1)
	return s and s.name or ""
end

-- The refusal of a write as a sentence.
-- locale-key: ROSTER_ERR_RANK_TOO_LOW ROSTER_ERR_NOT_READY ROSTER_ERR_NO_SEASON ROSTER_ERR_PENDING ROSTER_ERR_NOT_MEMBER ROSTER_ERR_UNCHANGED
-- locale-key: ROSTER_ERR_NOT_GM ROSTER_ERR_NOT_IN_GUILD ROSTER_ERR_ALREADY_JOINED ROSTER_ERR_IS_ALT ROSTER_ERR_TOO_SOON
-- locale-key: ROSTER_ERR_MS1_REQUIRED ROSTER_ERR_DUPLICATE_SPEC ROSTER_ERR_SPEC_CLASS ROSTER_ERR_NO_CLASS
-- locale-key: ROSTER_ERR_MAIN_UNKNOWN ROSTER_ERR_ALREADY_LINKED ROSTER_ERR_NOT_IN_RAID ROSTER_ERR_NOBODY_MISSING
-- locale-key: ROSTER_ERR_REQUEST_PENDING ROSTER_ERR_REQUEST_CLOSED ROSTER_ERR_SEASON_CLOSED ROSTER_ERR_FACTION_MISMATCH
function RosterWindow.ErrorText(code)
	local key = "ROSTER_ERR_" .. tostring(code)
	if L[key] ~= key then return L[key] end
	return L["ROSTER_ERR_OTHER"]:format(tostring(code))
end

---------------------------------------------------------------------------------------------------------------------
-- The shell: sub-tabs

-- Builds the tab's content in `page` (once): the sub-tab selector and one pane per sub-tab. `titleBar` is the window's
-- (the Addon chip lives there).
function RosterWindow:Build(page, titleBar)
	if self.root then return self.root end
	local root = CreateFrame("Frame", nil, page)
	root:SetAllPoints(page)
	self.root, self.page = root, page

	local items = {
		{ id = "pool", text = L["ROSTER_SUBTAB_POOL"] },
		{ id = "night", text = L["NIGHT_SUBTAB"] },
		{ id = "addon", text = L["ADDON_PANEL_SUBTAB"] },
		{ id = "readiness", text = L["READY_SUBTAB"] },
	}
	root.sub = Widgets.Segmented(root, items, function(id) RosterWindow:ShowSub(id) end)
	root.sub:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -4)

	root.panes = {}
	for _, id in ipairs(self.SUBTABS) do
		local pane = CreateFrame("Frame", nil, root)
		pane:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -40)
		pane:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
		pane:Hide()
		root.panes[id] = pane
	end
	self:BuildPool(root.panes.pool)
	if ns.NightsWindow then ns.NightsWindow:Build(root.panes.night) end
	if ns.AddonPanel then ns.AddonPanel:Build(root.panes.addon, titleBar) end
	if ns.ReadinessPanel then ns.ReadinessPanel:Build(root.panes.readiness) end
	root.sub:Select("pool")
	self:Refresh()
	return root
end

function RosterWindow:ShowSub(id)
	if not self.root then return end
	for pid, pane in pairs(self.root.panes) do pane:SetShown(pid == id) end
	self:Refresh()
end

function RosterWindow:SelectSub(id)
	if not self.root then return false end
	return self.root.sub:Select(id)
end

function RosterWindow:ActiveSub() return self.root and self.root.sub:Active() end

---------------------------------------------------------------------------------------------------------------------
-- Pool

local function buildRow(card, i)
	local r = CreateFrame("Frame", nil, card)
	r:SetHeight(RosterWindow.ROW_H)
	r.square = Widgets.ClassMark(r)
	r.square:SetPoint("LEFT", r, "LEFT", 0, 0)
	r.name = Theme.NewText(r, "BodyMedium", "text-1")
	r.name:SetPoint("LEFT", r.square, "RIGHT", 8, 0)
	r.spec = Theme.NewText(r, "Small", "text-3")
	r.spec:SetPoint("LEFT", r, "LEFT", 118, 0)
	r.trial = Theme.NewText(r, "Th", "warn")
	r.trial:SetPoint("LEFT", r, "LEFT", 200, 0)
	r.trial:SetText(L["ROSTER_TRIAL"]:upper())
	r.status = Widgets.Button(r, { text = "", style = "ghost", width = 74, height = 20, onClick = function()
		RosterWindow:OnToggleStatus(r.member, r.nextStatus)
	end })
	r.status:SetPoint("RIGHT", r, "RIGHT", 0, 0)
	r:Hide()
	return r
end

function RosterWindow:BuildPool(pane)
	local pool = { pane = pane, cards = {} }
	self.pool = pool

	pool.eyebrow = Theme.NewText(pane, "Eyebrow", "accent-text")
	pool.eyebrow:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -4)
	pool.eyebrow:SetText(L["ROSTER_POOL_TITLE"]:upper())

	-- the header's buttons, right to left: the officers' two, then the player's
	local function forms() return ns.RosterForms end
	pool.addRaid = Widgets.Button(pane, { text = L["ROSTER_ADD_RAID"], style = "secondary", width = 120, height = 28,
		onClick = function() RosterWindow:OnAddRaid() end })
	pool.add = Widgets.Button(pane, { text = L["ROSTER_ADD_PLAYER"], style = "secondary", width = 110, height = 28,
		onClick = function() if forms() then forms():OpenAdd() end end })
	pool.join = Widgets.Button(pane, { text = L["ROSTER_JOIN"], style = "primary", width = 120, height = 28,
		onClick = function() if forms() then forms():OpenJoin() end end })
	pool.alt = Widgets.Button(pane, { text = L["ROSTER_LINK_ALT"], style = "ghost", width = 110, height = 28,
		onClick = function() if forms() then forms():OpenAlt() end end })
	pool.mine = Theme.NewText(pane, "Small", "text-2")
	pool.mine:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -36)
	pool.mine:SetJustifyH("RIGHT")
	pool.summary = Theme.NewText(pane, "MonoMedium", "text-1")
	pool.summary:SetPoint("TOPLEFT", pool.eyebrow, "BOTTOMLEFT", 0, -6)
	pool.message = Theme.NewText(pane, "Small", "text-2")
	pool.message:SetPoint("LEFT", pool.summary, "RIGHT", 16, 0)
	pool.empty = Theme.NewText(pane, "Body", "text-3")
	pool.empty:SetPoint("TOPLEFT", pool.summary, "BOTTOMLEFT", 0, -16)

	for i, role in ipairs(RC().ROLES) do
		local card = Widgets.Card(pane, { height = 330 })
		card.role = role
		card:EnableMouseWheel(true)
		card:SetScript("OnMouseWheel", function(_, delta) RosterWindow:Scroll(role, -delta * 3) end)
		card.title = Theme.NewText(card, "H2", "text-1")
		card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -14)
		card.title:SetText(RosterWindow.RoleName(role))
		card.count = Theme.NewText(card, "MonoMedium", "accent-text")
		card.count:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -14)
		card.bar = Widgets.ThinBar(card, { height = 4 })
		card.bar:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -42)
		card.bar:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -42)
		card.free = Theme.NewText(card, "Small", "text-3")
		card.free:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -54)
		card.rows, card.offset = {}, 0
		for ri = 1, RosterWindow.ROWS do
			local r = buildRow(card, ri)
			r:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -78 - (ri - 1) * RosterWindow.ROW_H)
			r:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -78 - (ri - 1) * RosterWindow.ROW_H)
			card.rows[ri] = r
		end
		pool.cards[role] = card
	end

	-- the inbox of the players' requests (officers)
	pool.inbox = Widgets.Card(pane, { height = 148 })
	pool.inbox.title = Theme.NewText(pool.inbox, "Eyebrow", "accent-text")
	pool.inbox.title:SetPoint("TOPLEFT", pool.inbox, "TOPLEFT", 16, -12)
	pool.inbox.rows = {}
	for i = 1, RosterWindow.INBOX_ROWS do
		local r = CreateFrame("Frame", nil, pool.inbox)
		r:SetHeight(28)
		r:SetPoint("TOPLEFT", pool.inbox, "TOPLEFT", 16, -34 - (i - 1) * 30)
		r:SetPoint("TOPRIGHT", pool.inbox, "TOPRIGHT", -16, -34 - (i - 1) * 30)
		r.text = Theme.NewText(r, "Body", "text-1")
		r.text:SetPoint("LEFT", r, "LEFT", 0, 0)
		r.reject = Widgets.Button(r, { text = L["ROSTER_REJECT"], style = "ghost", width = 90, height = 24, onClick = function()
			RosterWindow:OnDecide(r.id, false)
		end })
		r.reject:SetPoint("RIGHT", r, "RIGHT", 0, 0)
		r.approve = Widgets.Button(r, { text = L["ROSTER_APPROVE"], style = "primary", width = 100, height = 24, onClick = function()
			RosterWindow:OnDecide(r.id, true)
		end })
		r.approve:SetPoint("RIGHT", r.reject, "LEFT", -8, 0)
		r:Hide()
		pool.inbox.rows[i] = r
	end
	pool.inbox.undeclared = Theme.NewText(pool.inbox, "Small", "text-3")
	pool.inbox.undeclared:SetPoint("TOPLEFT", pool.inbox, "TOPLEFT", 16, -126)
	pool.inbox.undeclared:SetPoint("TOPRIGHT", pool.inbox, "TOPRIGHT", -16, -126)
	pool.inbox.undeclared:SetJustifyH("LEFT")
	pool.inbox:Hide()
	pane:SetScript("OnSizeChanged", function() RosterWindow:LayoutPool() end)
	self:LayoutPool()
end

function RosterWindow:LayoutPool()
	local pool = self.pool
	if not pool then return end
	local width = (pool.pane:GetWidth() or 0) > 100 and pool.pane:GetWidth() or 920
	local gap = 14
	local w = math.floor((width - gap * 2) / 3)
	for i, role in ipairs(RC().ROLES) do
		local card = pool.cards[role]
		card:SetWidth(w)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", pool.pane, "TOPLEFT", (i - 1) * (w + gap), -64)
	end
	-- the header's buttons from the right, only the shown ones
	local x = 0
	for _, b in ipairs({ pool.addRaid, pool.add, pool.alt, pool.join }) do
		b:ClearAllPoints()
		if b:IsShown() then
			b:SetPoint("TOPRIGHT", pool.pane, "TOPRIGHT", -x, 0)
			x = x + b:GetWidth() + 8
		end
	end
	pool.inbox:ClearAllPoints()
	pool.inbox:SetPoint("TOPLEFT", pool.pane, "TOPLEFT", 0, -64 - 330 - 12)
	pool.inbox:SetPoint("TOPRIGHT", pool.pane, "TOPRIGHT", 0, -64 - 330 - 12)
end

function RosterWindow:Scroll(role, delta)
	local card = self.pool and self.pool.cards[role]
	if not card then return end
	local total = card.total or 0
	card.offset = math.min(math.max(card.offset + delta, 0), math.max(total - self.ROWS, 0))
	self:RefreshPool()
end

function RosterWindow:SetMessage(text, isError)
	local pool = self.pool
	if not pool then return end
	pool.message:SetText(text or "")
	Theme.Text(pool.message, isError and "warn" or "text-2")
end

-- locale-key: ROSTER_MAKE_TRIAL ROSTER_MAKE_RAIDER
function RosterWindow:OnToggleStatus(member, status)
	if not member or not status then return end
	local e, code = RC():SetStatus(member, status)
	if e then self:SetMessage(L["ROSTER_STATUS_DONE"]:format(short(member))) else self:SetMessage(self.ErrorText(code), true) end
	self:Refresh()
end

function RosterWindow:OnDecide(id, approve)
	if not id then return end
	local ok, code
	if approve then ok, code = RC():Approve(id) else ok, code = RC():Reject(id) end
	if ok then
		self:SetMessage(L[approve and "ROSTER_APPROVED" or "ROSTER_REJECTED"])
	else
		self:SetMessage(self.ErrorText(code), true)
	end
	self:Refresh()
end

-- "Add the raid group": the confirmation lists who would be added, then the members join without a declaration.
function RosterWindow:OnAddRaid()
	local missing, code = RC():RaidMissing()
	if not missing then self:SetMessage(self.ErrorText(code), true) return end
	if #missing == 0 then self:SetMessage(self.ErrorText("NOBODY_MISSING"), true) return end
	local list = {}
	for i, m in ipairs(missing) do list[i] = short(m.name) end
	local forms = ns.RosterForms
	local function run()
		local added, refused = RC():AddRaid()
		if not added then
			self:SetMessage(self.ErrorText(refused), true)
		else
			self:SetMessage(L["ROSTER_ADD_RAID_DONE"]:format(#added, #refused), #refused > 0)
		end
		self:Refresh()
	end
	if not forms then return run() end
	forms:Confirm({ title = L["ROSTER_ADD_RAID_TITLE"],
		body = L["ROSTER_ADD_RAID_BODY"]:format(#missing, table.concat(list, ", ")),
		confirm = L["ROSTER_ADD_RAID_CONFIRM"], onConfirm = run })
end

-- The text of one request of the inbox.
-- locale-key: ROSTER_REQ_JOIN ROSTER_REQ_ALT ROSTER_REQ_DECLARE
function RosterWindow.RequestText(r)
	if r.kind == "ALT" then return L["ROSTER_REQ_ALT"]:format(short(r.alt), short(r.main)) end
	local s = r.ms1 and ns.Specs and ns.Specs.Get(r.ms1)
	local what = s and (RosterWindow.ClassName(s.class) .. " " .. s.name) or ""
	return L[r.declare and "ROSTER_REQ_DECLARE" or "ROSTER_REQ_JOIN"]:format(short(r.member), what)
end

-- The line of the player's own request, and its colour token ("" when there is none or it is of another season).
-- locale-key: ROSTER_MINE_SENDING ROSTER_MINE_SENT ROSTER_MINE_PENDING ROSTER_MINE_APPROVED ROSTER_MINE_REJECTED
-- locale-key: ROSTER_MINE_REFUSED
function RosterWindow.MineText(status)
	local rec = status and status.request
	if not rec then return "", "text-2" end
	local state = rec.state or "SENDING"
	local what = rec.kind == "ALT" and L["ROSTER_MINE_ALT"]:format(short(rec.main or "")) or L["ROSTER_MINE_JOIN"]
	if state == "REFUSED" then
		return L["ROSTER_MINE_REFUSED"]:format(what, RosterWindow.ErrorText(rec.code)), "warn"
	end
	local tone = state == "APPROVED" and "ok" or (state == "REJECTED" and "warn" or "text-2")
	return L["ROSTER_MINE_" .. state]:format(what), tone
end

-- The player's buttons for where they stand: outside the pool "Join" and "Link as alt", in it without a declaration
-- "Declare your specs", nothing once declared or linked.
function RosterWindow:RefreshMine(officer)
	local pool = self.pool
	local status = RC():MyStatus()
	local state = status and status.state
	pool.join:SetShown(state == "OUT" or state == "UNDECLARED")
	pool.join:SetLabel(L[state == "UNDECLARED" and "ROSTER_DECLARE" or "ROSTER_JOIN"])
	pool.alt:SetShown(state == "OUT")
	pool.add:SetShown(officer and status ~= nil)
	pool.addRaid:SetShown(officer and status ~= nil)
	local text, tone = self.MineText(status)
	pool.mine:SetText(text)
	Theme.Text(pool.mine, tone)
	self:LayoutPool()
	return status
end

function RosterWindow:RefreshPool()
	local pool = self.pool
	if not pool then return end
	local data, code = RC():Pool()
	local officer = RC():Can("roster.manage") == true
	pool.eyebrow:SetText((L["ROSTER_POOL_TITLE"] .. " · " .. self.FactionName(RC():Faction())):upper())
	local status = self:RefreshMine(officer)
	if not data then
		pool.summary:SetText("")
		-- locale-key: ROSTER_MEMBER_VIEW
		local key = code == "NO_SEASON" and (status and "ROSTER_MEMBER_VIEW" or "ROSTER_NO_SEASON") or "ROSTER_NOT_READY"
		pool.empty:SetText(L[key])
		for _, card in pairs(pool.cards) do card:Hide() end
		pool.inbox:Hide()
		return
	end
	pool.empty:SetText(data.total == 0 and L["ROSTER_EMPTY"] or "")
	pool.summary:SetText(L["ROSTER_SUMMARY"]:format(data.total, data.trial, #data.undeclared))
	for _, role in ipairs(RC().ROLES) do
		local card, r = pool.cards[role], data.roles[role]
		card:Show()
		card.total = r.count
		card.offset = math.min(card.offset, math.max(r.count - self.ROWS, 0))
		card.count:SetText(("%d/%d"):format(r.count, r.target))
		card.bar:SetFraction(r.target > 0 and r.count / r.target or (r.count > 0 and 1 or 0))
		card.free:SetText(r.free > 0 and L["ROSTER_FREE_SLOTS"]:format(r.free) or "")
		for i, row in ipairs(card.rows) do
			local m = r.list[card.offset + i]
			if m then
				row.member = m.member
				Widgets.PaintClassMark(row.square, self.ClassColor(m.class))
				row.name:SetText(short(m.member) .. (m.altCount > 0 and L["ROSTER_ALTS"]:format(m.altCount) or ""))
				if Theme.IsDark() then Theme.Text(row.name, "text-1") end
				row.spec:SetText(specText(m))
				row.trial:SetShown(m.status == "TRIAL")
				row.nextStatus = m.status == "TRIAL" and "ACTIVE" or "TRIAL"
				row.status:SetLabel(L[m.status == "TRIAL" and "ROSTER_MAKE_RAIDER" or "ROSTER_MAKE_TRIAL"])
				row.status:SetShown(officer)
				row:Show()
			else
				row:Hide()
			end
		end
	end
	-- the inbox: officers only
	if officer then
		local pending = RC():Pending() or {}
		pool.inbox:Show()
		pool.inbox.title:SetText(L["ROSTER_INBOX"]:format(#pending):upper())
		for i, row in ipairs(pool.inbox.rows) do
			local req = pending[i]
			if req then
				row.id = req.id
				row.text:SetText(self.RequestText(req))
				row:Show()
			else
				row:Hide()
			end
		end
		if #pending == 0 then
			pool.inbox.rows[1].text:SetText(L["ROSTER_INBOX_EMPTY"])
			pool.inbox.rows[1].approve:Hide(); pool.inbox.rows[1].reject:Hide()
			pool.inbox.rows[1]:Show()
		else
			for _, row in ipairs(pool.inbox.rows) do row.approve:Show(); row.reject:Show() end
		end
		-- the members added without a declaration (by an officer, "Add the raid group"): they declare from their window
		local list = {}
		for i, m in ipairs(data.undeclared) do
			if i > self.MAX_UNDECLARED then list[#list + 1] = "…" break end
			list[#list + 1] = short(m.member)
		end
		pool.inbox.undeclared:SetText(#list > 0 and L["ROSTER_UNDECLARED"]:format(#data.undeclared, table.concat(list, ", "))
			or "")
	else
		pool.inbox:Hide()
	end
end

-- The Readiness sub-tab is for who may ask the raid; for everybody else it is not there (and is left if it was open).
function RosterWindow:UpdateSubtabs()
	local seg = self.root and self.root.sub
	local button = seg and seg.buttons.readiness
	if not button then return end
	local ok = ns.ReadinessCheck and ns.ReadinessCheck:CanManage() == true
	button:SetShown(ok)
	if not ok and seg:Active() == "readiness" then seg:Select("pool") end
end

function RosterWindow:Refresh()
	if not self.root then return end
	self:UpdateSubtabs()
	self:RefreshPool()
	if ns.NightsWindow then ns.NightsWindow:Refresh() end
	if ns.AddonPanel and ns.AddonPanel.root then ns.AddonPanel:Refresh() end
	if ns.ReadinessPanel and ns.ReadinessPanel.root then ns.ReadinessPanel:Refresh() end
end

if ns.Bus then
	for _, ev in ipairs({ "ROSTER_UPDATED", "ROSTER_MY_REQUEST", "GUILD_RANKS_READY", "GUILD_RANKS_CHANGED", "CREDIT_SNAPSHOT",
		"LEDGER_SYNCED" }) do
		ns.Bus:On(ev, function() RosterWindow:Refresh() end, RosterWindow)
	end
end
