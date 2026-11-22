-- CreditsWindow: the Credits tab (docs/ANALISI.md §9.3 point 4, docs/specs/ui-style.md §3, §6, M3-8), as the community site's
-- loot credits table: one accordion per season (the newest open), one column per night with `+N` in mono, the total in a
-- chip and the queue position ("less credits = more priority"), sortable headers, a filter by role and by class, and the
-- player's own row highlighted. Everything comes from Domain/CreditTable.lua (the local ledger of an officer) or, on every
-- other member's client, from the snapshot an officer sent (Domain/CreditSnapshot.lua, Net/Snapshot.lua, M6-6); this
-- file draws.
-- Lua 5.1; unprotected frames.
local ADDON_NAME, ns = ...
ns = ns or {}
local CreditsWindow = {}
ns.CreditsWindow = CreditsWindow
if ns.addon then ns.addon.CreditsWindow = CreditsWindow end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

CreditsWindow.HEAD_H = 52          -- the accordion header of a season
CreditsWindow.MAX_NIGHTS = 8       -- night columns shown (the newest); the older ones stay in the total
CreditsWindow.NIGHT_W = 66
CreditsWindow.ROLES = { "TANK", "HEALER", "DAMAGER" }
CreditsWindow.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function RC() return ns.RosterController end

-- "+2", "+0.5"
local function plus(n) return "+" .. (("%.2f"):format(n):gsub("0+$", ""):gsub("%.$", "")) end
CreditsWindow.Plus = plus
local function num(n) return (("%.2f"):format(n):gsub("0+$", ""):gsub("%.$", "")) end
CreditsWindow.Num = num

-- "2026-10-14" -> "14/10"
local function shortDate(d)
	local y, m, dd = tostring(d or ""):match("^(%d+)%-(%d+)%-(%d+)$")
	return y and (dd .. "/" .. m) or ""
end
CreditsWindow.ShortDate = shortDate

local function instanceName(id)
	local inst = ns.Instances and ns.Instances.Get(id)
	return inst and inst.name or ""
end

---------------------------------------------------------------------------------------------------------------------
-- State

CreditsWindow.role, CreditsWindow.class, CreditsWindow.openSeason = nil, nil, nil

-- The season whose table is open: the one picked, else the newest.
function CreditsWindow:OpenSeason(seasons)
	for _, s in ipairs(seasons) do if s.id == self.openSeason then return s.id end end
	return seasons[1] and seasons[1].id or nil
end

function CreditsWindow:SetRole(role)
	self.role = role
	if self.root then self.root.roleSeg:Select(role or "ALL") end
	self:Refresh()
end

function CreditsWindow:SetClass(class)
	self.class = class
	self:Refresh()
end

-- The class button steps through "all classes" and the classes of the game.
function CreditsWindow:CycleClass()
	local idx = 0
	for i, c in ipairs(self.CLASSES) do if c == self.class then idx = i end end
	idx = idx + 1
	self:SetClass(idx <= #self.CLASSES and self.CLASSES[idx] or nil)
end

function CreditsWindow:ToggleSeason(id)
	self.openSeason = id
	self:Refresh()
end

---------------------------------------------------------------------------------------------------------------------
-- Build

local function Mine(m)
	local me = RC() and RC():Me()
	if not me then return false end
	if m.member == me then return true end
	for _, a in ipairs(m.alts or {}) do if a == me then return true end end
	return false
end
CreditsWindow.IsMine = Mine

-- The columns of a season's table: queue position, player, class and spec, one per night (the newest MAX_NIGHTS), total.
-- locale-key: CREDITS_COL_RANK CREDITS_COL_PLAYER CREDITS_COL_SPEC CREDITS_COL_TOTAL
local function columns(nights)
	local cols = {
		{ id = "rank", title = L["CREDITS_COL_RANK"], width = 60, mono = true, text = function(d) return d.rank end,
			value = function(d) return d.rank end },
		{ id = "player", title = L["CREDITS_COL_PLAYER"], flex = 1, text = function(d) return ns.RosterWindow.ShortName(d.member) end,
			value = function(d) return ns.RosterWindow.ShortName(d.member):lower() end,
			render = function(fs, d)
				fs:SetText(ns.RosterWindow.ShortName(d.member))
				fs:SetTextColor(ns.RosterWindow.ClassColor(d.class))
			end },
		{ id = "spec", title = L["CREDITS_COL_SPEC"], flex = 1.4, token = function() return "text-2" end,
			text = function(d)
				local s = d.ms1 and ns.Specs and ns.Specs.Get(d.ms1)
				local cls = d.class and ns.RosterWindow.ClassName(d.class) or ""
				return s and (cls .. " · " .. s.name) or cls
			end },
	}
	local first = math.max(#nights - CreditsWindow.MAX_NIGHTS + 1, 1)
	for i = first, #nights do
		local n = nights[i]
		cols[#cols + 1] = { id = "n" .. i, width = CreditsWindow.NIGHT_W, align = "RIGHT", mono = true, night = n.id,
			title = shortDate(n.date) .. "\n" .. instanceName(n.instanceID),
			text = function(d) local v = d.perNight[n.id] return v and v ~= 0 and plus(v) or "·" end,
			value = function(d) return d.perNight[n.id] or 0 end,
			render = function(fs, d)
				local v = d.perNight[n.id]
				if v and v ~= 0 then fs:SetText(plus(v)); Theme.Text(fs, "accent-text") else fs:SetText("·"); Theme.Text(fs, "text-3") end
			end }
	end
	cols[#cols + 1] = { id = "total", title = L["CREDITS_COL_TOTAL"], width = 84, align = "CENTER", mono = true,
		text = function(d) return num(d.total) end, value = function(d) return d.total end }
	return cols
end

-- One accordion card per season, built on demand: the header (sigma, label, summary, chevron) and a table for its nights.
function CreditsWindow:SeasonCard(id)
	local root = self.root
	local card = root.cards[id]
	if card then return card end
	card = Widgets.Card(root.list, { height = self.HEAD_H })
	card.id = id
	card.head = CreateFrame("Button", nil, card)
	card.head:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
	card.head:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
	card.head:SetHeight(self.HEAD_H)
	card.head:SetScript("OnClick", function() CreditsWindow:ToggleSeason(id) end)
	card.sigma = Theme.NewText(card.head, "H2", "accent-text")
	card.sigma:SetPoint("LEFT", card.head, "LEFT", 18, 0)
	card.sigma:SetText("Σ")
	card.title = Theme.NewText(card.head, "BodyMedium", "text-1")
	card.title:SetPoint("TOPLEFT", card.head, "TOPLEFT", 52, -10)
	card.sub = Theme.NewText(card.head, "Mono", "text-3")
	card.sub:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
	card.count = Theme.NewText(card.head, "Small", "text-1")
	card.count:SetPoint("RIGHT", card.head, "RIGHT", -44, 0)
	card.chevron = Theme.NewText(card.head, "Body", "text-3")
	card.chevron:SetPoint("RIGHT", card.head, "RIGHT", -18, 0)
	card:Hide()
	root.cards[id] = card
	return card
end

function CreditsWindow:Build(page)
	if self.root then return self.root end
	local root = CreateFrame("Frame", nil, page)
	root:SetAllPoints(page)
	self.root, self.page = root, page
	root.cards = {}

	root.eyebrow = Theme.NewText(root, "Eyebrow", "accent-text")
	root.eyebrow:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -12)
	root.title = Theme.NewText(root, "H1", "text-1")
	root.title:SetPoint("TOPLEFT", root.eyebrow, "BOTTOMLEFT", 0, -6)
	root.title:SetText(L["TAB_CREDITS"])

	root.faction = Widgets.Segmented(root, {
		{ id = "Horde", text = L["FACTION_Horde"] }, { id = "Alliance", text = L["FACTION_Alliance"] },
	}, function(id) RC():SetFaction(id); CreditsWindow:Refresh() end)
	root.faction:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -12)

	local roles = { { id = "ALL", text = L["CREDITS_ALL"] } }
	for _, r in ipairs(self.ROLES) do roles[#roles + 1] = { id = r, text = ns.RosterWindow.RoleName(r) } end
	root.roleSeg = Widgets.Segmented(root, roles, function(id) CreditsWindow.role = id ~= "ALL" and id or nil; CreditsWindow:Refresh() end)
	root.roleSeg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -84)
	root.classBtn = Widgets.Button(root, { text = "", style = "ghost", width = 130, height = 28, onClick = function()
		CreditsWindow:CycleClass()
	end })
	root.classBtn:SetPoint("LEFT", root.roleSeg, "RIGHT", 12, 0)
	root.hint = Theme.NewText(root, "Small", "text-2")
	root.hint:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -90)
	root.hint:SetText(L["CREDITS_HINT"])
	root.empty = Theme.NewText(root, "Body", "text-3")
	root.empty:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -140)

	root.list = CreateFrame("Frame", nil, root)
	root.list:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -128)
	root.list:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
	root:SetScript("OnSizeChanged", function() CreditsWindow:Layout() end)
	root.roleSeg:Select("ALL")
	self:Refresh()
	return root
end

-- The table of a season card, rebuilt when the nights shown change.
function CreditsWindow:EnsureTable(card, nights)
	local ids = {}
	for i, n in ipairs(nights) do ids[i] = tostring(n.id) end
	local key = table.concat(ids, ",")   -- the night ids: a snapshot's columns are not the ledger's
	if card.table and card.tableKey == key then return card.table end
	if card.table then card.table:Hide() end
	local t = Widgets.DataTable(card, columns(nights), {
		rowHeight = 40, headerHeight = 44, pool = 30,
		rowSetup = function(r)
			r.mine = r:CreateTexture(nil, "BACKGROUND")
			Theme.Fill(r.mine, "accent", 0.12)
			r.mine:SetAllPoints(r)
			r.mine:Hide()
			r.bar = r:CreateTexture(nil, "ARTWORK")
			Theme.Fill(r.bar, "accent")
			r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
			r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
			r.bar:SetWidth(2)
			r.bar:Hide()
			r.chip = Theme.Slice(r, "rr_fill_8", "surface-3", "BACKGROUND")
			r.chip:SetSize(46, 24)
			r.square = r:CreateTexture(nil, "ARTWORK")
			r.square:SetSize(10, 10)
			r.square:SetColorTexture(1, 1, 1, 1)
		end,
		rowUpdate = function(r, d)
			local own = Mine(d)
			r.mine:SetShown(own)
			r.bar:SetShown(own)
			r.square:SetColorTexture(ns.RosterWindow.ClassColor(d.class))
			local pos = card.table.pos
			local n = #card.table.columns
			r.chip:ClearAllPoints()
			r.chip:SetPoint("CENTER", r, "LEFT", pos[n].x + (pos[n].w - 8) / 2, 0)
			r.square:ClearAllPoints()
			r.square:SetPoint("LEFT", r, "LEFT", pos[2].x - 14, 0)
		end,
	})
	t:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -self.HEAD_H)
	t:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
	t:SetEmptyText(L["CREDITS_EMPTY"])
	card.table, card.tableKey = t, key
	return t
end

-- The accordion: the open season's card takes what the closed headers leave.
function CreditsWindow:Layout()
	local root = self.root
	if not root or not root.order then return end
	local h = root.list:GetHeight()
	if not h or h < 100 then h = 440 end
	local gap = 10
	local closed = 0
	for _, id in ipairs(root.order) do if id ~= root.openId then closed = closed + 1 end end
	local openH = math.max(h - closed * (self.HEAD_H + gap) - (#root.order > 1 and 0 or 0), self.HEAD_H + 120)
	local y = 0
	for _, id in ipairs(root.order) do
		local card = root.cards[id]
		local isOpen = id == root.openId
		local ch = isOpen and openH or self.HEAD_H
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", root.list, "TOPLEFT", 0, -y)
		card:SetPoint("TOPRIGHT", root.list, "TOPRIGHT", 0, -y)
		card:SetHeight(ch)
		y = y + ch + gap
	end
end

-- Where the numbers come from: the local ledger (an officer), or the snapshot an officer sent (every other member, M6-6).
-- { ledger = L } | { snapshot = kept } | nil.
function CreditsWindow:Source()
	local kept = ns.Snapshot and ns.Snapshot:ForView()
	if kept then return { snapshot = kept } end
	local L0 = RC() and RC():Ledger()
	return L0 and { ledger = L0 } or nil
end

-- The data the window shows for a season, filtered: { table = CreditTable.Build, rows }.
function CreditsWindow:Data(seasonId, src)
	src = src or self:Source()
	if not src then return nil end
	local data
	if src.snapshot then
		data = ns.CreditSnapshot.Table(src.snapshot.data, seasonId, RC():Faction())
	else
		data = ns.CreditTable.Build(src.ledger, seasonId, { faction = RC():Faction() })
	end
	if not data then return nil end
	return data, ns.CreditTable.Filter(data.rows, self.role, self.class)
end

function CreditsWindow:Refresh()
	local root = self.root
	if not root then return end
	local src = self:Source()
	root.faction:Select(RC() and RC():Faction() or "Horde")
	root.classBtn:SetLabel((self.class and ns.RosterWindow.ClassName(self.class) or L["CREDITS_CLASS"]) .. " ▾")
	local seasons = {}
	if src and src.snapshot then
		seasons = ns.CreditSnapshot.Seasons(src.snapshot.data)
	elseif src then
		seasons = ns.CreditTable.Seasons(src.ledger)
	end
	for _, c in pairs(root.cards) do c:Hide() end
	root.order = {}
	if #seasons == 0 then
		root.eyebrow:SetText("")
		root.empty:SetText(L[src and "ROSTER_NO_SEASON" or "ROSTER_NOT_READY"])
		return
	end
	root.empty:SetText("")
	root.openId = self:OpenSeason(seasons)
	for _, s in ipairs(seasons) do
		local card = self:SeasonCard(s.id)
		root.order[#root.order + 1] = s.id
		local isOpen = s.id == root.openId
		local data, rows = self:Data(s.id, src)
		local label = s.label or tostring(s.id)
		card.title:SetText(label)
		local state = L[s.open and "CREDITS_STATE_OPEN" or "CREDITS_STATE_CLOSED"]
		local upd = data and data.updated and L["CREDITS_UPDATED"]:format(shortDate(data.updated)) or ""
		local sub = L["CREDITS_SEASON_SUB"]:format(s.nights, state) .. (upd ~= "" and (" · " .. upd) or "")
		-- locale-key: CREDITS_SNAPSHOT
		if src.snapshot then sub = sub .. " · " .. L["CREDITS_SNAPSHOT"]:format(ns.RosterWindow.ShortName(src.snapshot.from or "")) end
		card.sub:SetText(sub)
		card.count:SetText(L["CREDITS_IN_ROSTER"]:format(data and #data.rows or 0))
		card.chevron:SetText(isOpen and "^" or "v")
		card:Show()
		if isOpen then
			if s.open then root.eyebrow:SetText(L["CREDITS_EYEBROW_OPEN"]:format(label):upper()) else root.eyebrow:SetText(L["CREDITS_EYEBROW_CLOSED"]:format(label):upper()) end
			local t = self:EnsureTable(card, data.nights)
			t:Show()
			t:SetData(rows)
			if not t.sortId then t:SortBy("rank", false) end
		elseif card.table then
			card.table:Hide()
		end
	end
	self:Layout()
	local open = root.cards[root.openId]
	if open and open.table then open.table:Layout(); open.table:Refresh() end   -- the card has its final height now
end

if ns.Bus then
	for _, ev in ipairs({ "ROSTER_UPDATED", "ROSTER_VIEW_CHANGED", "GUILD_RANKS_READY", "GUILD_KEY_CHANGED", "NIGHT_OPENED", "NIGHT_CLOSED",
	"CREDIT_SNAPSHOT", "LEDGER_SYNCED" }) do
		ns.Bus:On(ev, function() CreditsWindow:Refresh() end, CreditsWindow)
	end
end
