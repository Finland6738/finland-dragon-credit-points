-- MLSession: the Loot > Session sub-tab, the master looter's window (docs/ANALISI.md §4, §9.3 point 3, docs/specs/ui-style.md §3,
-- §6, preview fdcp-loot-session.webp, M4-5). On the left the session's items with their state; on the right the selected
-- item: its category and cost, the round's timer, the candidates (credits, response, roll, notes), the proposal (who, how
-- much, why: written by the addon) and the buttons. The addon writes the proposal; the master looter confirms it, rejects
-- it or modifies it, and a modification needs a reason (a code from Domain/Reasons.lua, never typed text).
--
-- The window draws what App/SessionController.lua's Board gives (App/SessionBoard.lua) and sends the master looter's
-- clicks back as commands (Command): it decides nothing. On another officer's client the same window shows the master
-- looter's view, read only: the items, the round, the proposal; the candidates (without credits and rolls, which travel
-- only to the master looter) only where the rules let that client see the verdicts (M5-4: the council by default).
-- The council's flags (M5-4, "upgrade ignored" and "possible waste") are written under the candidates as soon as the
-- responses arrive and stay with the proposal; a candidate they name says it in the Notes column. They never change
-- the winner: the master looter (for the council) modifies the proposal with a reason.
-- "Confirm all" is not built: one item is in progress at a time (docs/ANALISI.md §4, M2-6), so there is never a second
-- proposal to confirm with the first; with `session.autoAdvance` the next roll opens by itself after each award.
-- Lua 5.1; unprotected frames. Not verified in the real client: the window in a raid.
local ADDON_NAME, ns = ...
ns = ns or {}
local MLSession = {}
ns.MLSession = MLSession
if ns.addon then ns.addon.MLSession = MLSession end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

MLSession.ITEM_ROWS, MLSession.ITEM_H, MLSession.LIST_W = 6, 62, 300
MLSession.TICK = 1   -- seconds between two redraws of the timer while the tab is on screen
MLSession.SUBTABS = { "session", "deliver", "council" }   -- Council: UI/Windows/Council.lua (M5-8)

local function SC() return ns.SessionController end
local function SB() return ns.SessionBoard end
local short = function(name) return (tostring(name):gsub("%-.*$", "")) end

-- The game's own quality colours (the client's function wins when it has the quality).
local QUALITY = {
	[0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 },
	[5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 },
}
function MLSession.QualityColor(quality)
	if _G.GetItemQualityColor then
		local ok, r, g, b = pcall(_G.GetItemQualityColor, quality or 1)
		if ok and type(r) == "number" then return r, g, b end
	end
	local t = QUALITY[quality or 1] or QUALITY[1]
	return t[1], t[2], t[3]
end

-- locale-key: ML_CAT_WEAPON ML_CAT_OFFHAND ML_CAT_TRINKET ML_CAT_QUEST ML_CAT_JEWELRY ML_CAT_ARMOR ML_CAT_COSMETIC ML_CAT_OTHER
function MLSession.CategoryName(category)
	local key = "ML_CAT_" .. tostring(category):upper()
	if L[key] ~= key then return L[key] end
	return tostring(category or "")
end

-- What the client knows of an item: name, icon, level, slot. A name that is not loaded yet is asked once and the window
-- redraws when it arrives.
function MLSession:ItemInfo(itemID)
	local entry = ns.ItemCache and ns.ItemCache.Lookup(itemID)
	if (not entry or not entry.loaded) and ns.ItemCache and not (self.asked and self.asked[itemID]) then
		self.asked = self.asked or {}
		self.asked[itemID] = true
		ns.ItemCache.Get(itemID, function() MLSession:Refresh() end)
		entry = ns.ItemCache.Lookup(itemID) or entry
	end
	return entry or {}
end

function MLSession.ItemName(itemID, info)
	return info and info.name or L["ML_ITEM_UNKNOWN"]:format(tonumber(itemID) or 0)
end

-- "Finger · Item level 66 · Weapon": the slot is the game's own word for it.
function MLSession.ItemLine(item, info)
	local parts = {}
	local slot = item.equipLoc and _G[item.equipLoc]
	if type(slot) == "string" and slot ~= "" then parts[#parts + 1] = slot end
	if info and info.level and info.level > 0 then parts[#parts + 1] = L["ML_ITEM_LEVEL"]:format(info.level) end
	if item.category then parts[#parts + 1] = MLSession.CategoryName(item.category) end
	return table.concat(parts, " · ")
end

-- "1 credit" / "council" for the list and the badge.
local function costText(item)
	if item.council or item.cost == nil then return L["ML_COST_COUNCIL"] end
	return SB().CreditsText(item.cost)
end
MLSession.CostText = costText

local function clock(seconds)
	seconds = math.max(0, math.ceil(tonumber(seconds) or 0))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end
MLSession.Clock = clock

---------------------------------------------------------------------------------------------------------------------
-- Build

local function buildItemRow(list, i)
	local r = CreateFrame("Button", nil, list)
	r:SetHeight(MLSession.ITEM_H)
	r.parts = Theme.Panel(r, { radius = 12, fill = "surface-1", border = "border-subtle" })
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(34, 34)
	r.icon:SetPoint("LEFT", r, "LEFT", 12, 0)
	r.name = Theme.NewText(r, "BodyMedium", "text-1")
	r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 54, -10)
	r.name:SetPoint("TOPRIGHT", r, "TOPRIGHT", -104, -10)
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false)
	r.sub = Theme.NewText(r, "Small", "text-3")
	r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
	r.sub:SetPoint("TOPRIGHT", r, "TOPRIGHT", -104, -30)
	r.sub:SetJustifyH("LEFT")
	r.sub:SetWordWrap(false)
	r.badge = Widgets.Badge(r, "", "neutral")
	r.badge:SetPoint("RIGHT", r, "RIGHT", -10, 0)
	r:SetScript("OnClick", function(self) if self.index then MLSession:Select(self.index) end end)
	r:Hide()
	return r
end

local COLUMN_TOKENS = { MS = "accent-text", OS = "text-2", TMOG = "text-2", PASS = "text-3" }

-- The columns of the candidates' table.
-- locale-key: ML_COL_CANDIDATE ML_COL_CREDITS ML_COL_RESPONSE ML_COL_UPGRADE ML_COL_ROLL ML_COL_NOTES ML_NOTE_PROPOSED ML_NOTE_WAITING
local function candidateColumns()
	local function noteText(d)
		local text = ""
		if d.proposed then text = L["ML_NOTE_PROPOSED"]
		elseif d.flag then text = ns.Reasons.Text(d.flag.group, d.flag.code)
		elseif d.response == nil then text = L["ML_NOTE_WAITING"] end
		for _, code in ipairs(d.flags or {}) do   -- the council's flags that name the player (M5-4)
			local f = SB().FlagShort(code)
			text = text ~= "" and (text .. " · " .. f) or f
		end
		if d.note then text = text ~= "" and (text .. " · " .. d.note) or d.note end   -- the player's own note (M4-6)
		return text
	end
	return {
		{ id = "name", title = L["ML_COL_CANDIDATE"], flex = 1, text = function(d) return d.name end,
			value = function(d) return d.name:lower() end,
			render = function(fs, d)
				fs:SetText(d.name)
				Theme.ClassText(fs, ns.RosterWindow.ClassColor(d.class))
			end },
		{ id = "credits", title = L["ML_COL_CREDITS"], width = 76, align = "CENTER", mono = true,
			text = function(d) return d.credits or "·" end, value = function(d) return d.credits or -1 end },
		{ id = "response", title = L["ML_COL_RESPONSE"], width = 176,
			text = function(d)
				if not d.response then return "·" end
				local text = ns.Reasons.Text("RESPONSE", d.response)
				if d.label then text = text .. " · " .. ns.Reasons.Text("LABEL", d.label) end   -- the declared label (M4-6)
				return text
			end,
			token = function(d) return COLUMN_TOKENS[d.response] or "text-3" end,
			value = function(d) return d.tier or 99 end },
		{ id = "upgrade", title = L["ML_COL_UPGRADE"], width = 190,   -- the verdict the player's client sent (M5-2)
			text = function(d)
				if not d.upgrade then return "·" end
				return ns.UpgradeAdvisor.Text(d.upgrade)
			end,
			token = function(d)
				if not d.upgrade then return "text-3" end
				local tone = ns.UpgradeAdvisor.Tone(d.upgrade)
				return tone == "ok" and "ok" or tone == "warn" and "warn" or tone == "accent" and "accent-text" or "text-2"
			end,
			value = function(d)
				local u = d.upgrade
				if not u then return 99 end
				if u.usable == false then return 5 end
				return ({ BIG = 1, SMALL = 2, NONE = 3, NOT_COMPARABLE = 4 })[u.verdict] or 6
			end },
		{ id = "roll", title = L["ML_COL_ROLL"], width = 60, align = "RIGHT", mono = true,
			text = function(d) return d.roll or "—" end, value = function(d) return d.roll or -1 end },
		{ id = "note", title = L["ML_COL_NOTES"], flex = 1.7, sortable = false, text = noteText,
			token = function(d)
				if d.flag or (d.flags and #d.flags > 0) then return "warn" end
				return d.proposed and "ok" or "text-3"
			end },
	}
end

-- The tooltip of a candidate's row: the verdict for each spec the player's client sent, what is worn, the limits (M5-2).
function MLSession:ShowCandidateTip(row)
	local d, tip, A = row.data, GameTooltip, ns.UpgradeAdvisor
	if not d or not tip or not d.upgradeMS then return end
	tip:SetOwner(row, "ANCHOR_RIGHT")
	local lines = A.Lines(d.upgradeMS, "MS")
	tip:SetText(d.name)
	for _, line in ipairs(lines) do tip:AddLine(line, 1, 1, 1, true) end
	if d.upgradeOS then
		for _, line in ipairs(A.Lines(d.upgradeOS, "OS")) do tip:AddLine(line, 1, 1, 1, true) end
	end
	local names = A.EquippedNames(d.equipped)
	if #names > 0 then tip:AddLine(L["UPG_EQUIPPED"]:format(table.concat(names, ", ")), 0.8, 0.8, 0.8, true) end
	tip:AddLine(L["UPG_LIMITS"], 0.6, 0.6, 0.6, true)
	tip:Show()
end

-- Builds the tab's content in `page` (once). `frame` is the main window (the dialogs cover it).
function MLSession:Build(page, frame)
	if self.root then return self.root end
	local root = CreateFrame("Frame", nil, page)
	root:SetAllPoints(page)
	self.root, self.page, self.frame = root, page, frame

	root.sub = Widgets.Segmented(root, { { id = "session", text = L["ML_SUBTAB_SESSION"] },
		{ id = "deliver", text = L["ML_SUBTAB_DELIVER"] }, { id = "council", text = L["COUNCIL_SUBTAB"] } },
		function(id) MLSession:ShowSub(id) end)
	root.sub:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -4)
	root.panes = {}
	for _, id in ipairs(self.SUBTABS) do
		local pane = CreateFrame("Frame", nil, root)
		pane:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -40)
		pane:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
		pane:Hide()
		root.panes[id] = pane
	end
	self:BuildSession(root.panes.session)
	self:BuildDeliver(root.panes.deliver)
	if ns.CouncilWindow then ns.CouncilWindow:Build(root.panes.council, frame) end   -- M5-8
	root.sub:Select("session")
	root:SetScript("OnShow", function() MLSession:Arm(); MLSession:Refresh() end)
	root:SetScript("OnHide", function() MLSession:Disarm() end)
	self:Refresh()
	return root
end

function MLSession:ShowSub(id)
	if not self.root then return end
	for pid, pane in pairs(self.root.panes) do pane:SetShown(pid == id) end
	self:Refresh()
end

function MLSession:BuildSession(pane)
	local s = { pane = pane }
	self.ui = s

	-- header: eyebrow, title, state, message; the buttons at the right
	s.eyebrow = Theme.NewText(pane, "Eyebrow", "accent-text")
	s.eyebrow:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -4)
	s.eyebrow:SetText(L["ML_EYEBROW"]:upper())
	s.title = Theme.NewText(pane, "H1", "text-1")
	s.title:SetPoint("TOPLEFT", s.eyebrow, "BOTTOMLEFT", 0, -4)
	s.title:SetText(L["ML_TITLE"])
	s.status = Theme.NewText(pane, "Small", "text-2")
	s.status:SetPoint("TOPLEFT", s.title, "BOTTOMLEFT", 0, -4)
	s.message = Theme.NewText(pane, "Small", "text-2")
	s.message:SetPoint("LEFT", s.status, "RIGHT", 16, 0)

	s.pause = Widgets.Button(pane, { text = L["ML_PAUSE"], style = "secondary", width = 96, height = 32, onClick = function()
		MLSession:OnPause()
	end })
	s.pause:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -4)
	s.finish = Widgets.Button(pane, { text = L["ML_FINISH"], style = "ghost", width = 120, height = 32, onClick = function()
		MLSession:Do("END")
	end })
	s.finish:SetPoint("RIGHT", s.pause, "LEFT", -8, 0)
	s.notify = Widgets.Button(pane, { text = L["ML_NOTIFY"], style = "ghost", width = 130, height = 32, onClick = function()
		MLSession:OnNotify()
	end })
	s.notify:SetPoint("RIGHT", s.finish, "LEFT", -8, 0)
	s.missing = Widgets.Badge(pane, "", "warn")
	s.missing:SetPoint("RIGHT", s.notify, "LEFT", -8, 0)
	s.missing:Hide()

	-- the items (left)
	s.list = CreateFrame("Frame", nil, pane)
	s.list:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -66)
	s.list:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 0)
	s.list:SetWidth(self.LIST_W)
	s.list:EnableMouseWheel(true)
	s.list:SetScript("OnMouseWheel", function(_, delta) MLSession:ScrollItems(-delta) end)
	s.rows, s.offset = {}, 0
	for i = 1, self.ITEM_ROWS do
		local r = buildItemRow(s.list, i)
		r:SetPoint("TOPLEFT", s.list, "TOPLEFT", 0, -(i - 1) * (self.ITEM_H + 4))
		r:SetPoint("TOPRIGHT", s.list, "TOPRIGHT", 0, -(i - 1) * (self.ITEM_H + 4))
		s.rows[i] = r
	end
	s.empty = Theme.NewText(s.list, "Body", "text-3")
	s.empty:SetPoint("TOPLEFT", s.list, "TOPLEFT", 4, -8)
	s.empty:SetWidth(self.LIST_W - 8)
	s.empty:SetJustifyH("LEFT")

	-- the selected item (right)
	local card = Widgets.Card(pane, { height = 300 })
	card:SetPoint("TOPLEFT", pane, "TOPLEFT", self.LIST_W + 14, -66)
	card:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
	s.card = card
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(40, 40)
	card.icon:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -14)
	card.name = Theme.NewText(card, "H1", "text-1")
	card.name:SetPoint("TOPLEFT", card, "TOPLEFT", 66, -14)
	card.name:SetPoint("TOPRIGHT", card, "TOPRIGHT", -190, -14)
	card.name:SetJustifyH("LEFT")
	card.name:SetWordWrap(false)
	card.line = Theme.NewText(card, "Small", "text-3")
	card.line:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
	card.line:SetPoint("TOPRIGHT", card, "TOPRIGHT", -190, -38)
	card.line:SetJustifyH("LEFT")
	card.line:SetWordWrap(false)
	card.badge = Widgets.Badge(card, "", "accent")
	card.badge:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -16)
	card.round = Theme.NewText(card, "Small", "text-3")
	card.round:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -48)
	card.timer = Theme.NewText(card, "MonoMedium", "text-1")
	card.timer:SetPoint("RIGHT", card.round, "LEFT", -10, 0)
	card.bar = Widgets.ThinBar(card, { height = 4 })
	card.bar:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -70)
	card.bar:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -70)

	card.table = Widgets.DataTable(card, candidateColumns(), {
		rowHeight = 28, headerHeight = 26, pool = 45,
		rowSetup = function(r)
			r.bar = r:CreateTexture(nil, "ARTWORK")
			Theme.Fill(r.bar, "accent")
			r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
			r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
			r.bar:SetWidth(2)
			r.bar:Hide()
			r.square = Widgets.ClassMark(r)
			for _, fs in ipairs(r.cells) do fs:SetWordWrap(false) end
			-- the verdicts of both specs and the worn pieces, from what the player's client sent
			r:HookScript("OnEnter", function(self) MLSession:ShowCandidateTip(self) end)
			r:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		end,
		rowUpdate = function(r, d)
			r.bar:SetShown(d.proposed == true)
			Widgets.PaintClassMark(r.square, ns.RosterWindow.ClassColor(d.class))
			local pos = card.table.pos
			r.square:ClearAllPoints()
			r.square:SetPoint("LEFT", r, "LEFT", pos[1].x, 0)
			r.cells[1]:ClearAllPoints()
			r.cells[1]:SetWidth(math.max(pos[1].w - 22, 1))
			r.cells[1]:SetPoint("LEFT", r, "LEFT", pos[1].x + 16, 0)
			r:SetAlpha(d.inRound == false and 0.45 or 1)
		end,
	})
	card.table:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -84)
	card.table:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 128)
	card.table:SetEmptyText(L["ML_NO_CANDIDATES"])

	-- the proposal strip: the addon's sentence, then what to look at
	card.strip = CreateFrame("Frame", nil, card)
	card.strip:SetHeight(60)
	card.strip:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 16, 62)
	card.strip:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -16, 62)
	card.strip.fill = Theme.Slice(card.strip, "rr_fill_12", "surface-2", "BACKGROUND")
	card.strip.fill:SetAllPoints(card.strip)
	card.strip.main = Theme.NewText(card.strip, "Body", "text-1")
	card.strip.main:SetPoint("TOPLEFT", card.strip, "TOPLEFT", 14, -9)
	card.strip.main:SetPoint("TOPRIGHT", card.strip, "TOPRIGHT", -14, -9)
	card.strip.main:SetJustifyH("LEFT")
	card.strip.main:SetJustifyV("TOP")
	card.strip.sub = Theme.NewText(card.strip, "Small", "warn")
	card.strip.sub:SetPoint("BOTTOMLEFT", card.strip, "BOTTOMLEFT", 14, 8)
	card.strip.sub:SetPoint("BOTTOMRIGHT", card.strip, "BOTTOMRIGHT", -14, 8)
	card.strip.sub:SetJustifyH("LEFT")
	card.strip.sub:SetJustifyV("BOTTOM")

	-- the buttons: the main action at the far right, then Modify, Reject, Correct and Remove
	s.main = Widgets.Button(card, { text = "", style = "primary", width = 170, height = 36, onClick = function()
		MLSession:OnMain()
	end })
	s.main:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -16, 16)
	s.modify = Widgets.Button(card, { text = L["ML_MODIFY"], style = "secondary", width = 100, height = 36, onClick = function()
		MLSession:OpenDialog("modify")
	end })
	s.modify:SetPoint("RIGHT", s.main, "LEFT", -8, 0)
	s.reject = Widgets.Button(card, { text = L["ML_REJECT"], style = "secondary", width = 100, height = 36, onClick = function()
		MLSession:OpenDialog("reject")
	end })
	s.reject:SetPoint("RIGHT", s.modify, "LEFT", -8, 0)
	s.correct = Widgets.Button(card, { text = L["ML_CORRECT"], style = "secondary", width = 100, height = 36, onClick = function()
		MLSession:OpenDialog("correct")
	end })
	s.correct:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 16, 16)
	s.remove = Widgets.Button(card, { text = L["ML_REMOVE"], style = "ghost", width = 100, height = 36, onClick = function()
		MLSession:OnRemove()
	end })
	s.remove:SetPoint("LEFT", s.correct, "RIGHT", 8, 0)
end

-- The "to deliver" sub-tab (M4-7): the awarded items that have not reached their winner yet, how each one stands
-- (handed over and waiting for the loot message, to hand over by trade, held by whom) and the two buttons of the master
-- looter: hand the selected item over now (master loot, from the click) and mark it as delivered by hand.
-- locale-key: ML_DELIVER_EYEBROW ML_DELIVER_TITLE ML_DELIVER_HELP ML_DELIVER_EMPTY ML_COL_ITEM ML_COL_WINNER ML_COL_STATUS ML_GIVE ML_MARK_DELIVERED
function MLSession:BuildDeliver(pane)
	local d = { pane = pane }
	self.deliverUI = d
	d.eyebrow = Theme.NewText(pane, "Eyebrow", "accent-text")
	d.eyebrow:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -4)
	d.eyebrow:SetText(L["ML_DELIVER_EYEBROW"]:upper())
	d.title = Theme.NewText(pane, "H1", "text-1")
	d.title:SetPoint("TOPLEFT", d.eyebrow, "BOTTOMLEFT", 0, -4)
	d.title:SetText(L["ML_DELIVER_TITLE"])
	d.help = Theme.NewText(pane, "Small", "text-2")
	d.help:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -4)
	d.help:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
	d.help:SetJustifyH("LEFT")
	d.help:SetText(L["ML_DELIVER_HELP"])

	d.mark = Widgets.Button(pane, { text = L["ML_MARK_DELIVERED"], style = "secondary", width = 170, height = 36, onClick = function()
		MLSession:OnMarkDelivered()
	end })
	d.mark:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
	d.give = Widgets.Button(pane, { text = L["ML_GIVE"], style = "primary", width = 190, height = 36, onClick = function()
		MLSession:OnGive()
	end })
	d.give:SetPoint("RIGHT", d.mark, "LEFT", -8, 0)
	d.message = Theme.NewText(pane, "Small", "text-2")
	d.message:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 12)
	d.message:SetPoint("RIGHT", d.give, "LEFT", -12, 0)
	d.message:SetJustifyH("LEFT")

	d.table = Widgets.DataTable(pane, {
		{ id = "item", title = L["ML_COL_ITEM"], width = 230, text = function(r) return MLSession.ItemName(r.itemID, MLSession:ItemInfo(r.itemID)) end,
			render = function(fs, r)
				fs:SetText(MLSession.ItemName(r.itemID, MLSession:ItemInfo(r.itemID)))
				Theme.TextRGB(fs, MLSession.QualityColor(r.quality or MLSession:ItemInfo(r.itemID).quality))
			end },
		{ id = "winner", title = L["ML_COL_WINNER"], width = 150, text = function(r) return SB().Short(r.recipient or "") end,
			render = function(fs, r)
				fs:SetText(SB().Short(r.recipient or ""))
				Theme.ClassText(fs, ns.RosterWindow.ClassColor(SC() and SC():ClassOf(r.recipient)))
			end },
		{ id = "status", title = L["ML_COL_STATUS"], flex = 1, sortable = false, text = function(r) return r.text end,
			token = function(r) return (r.status == "GIVEN" and not r.noReceipt) and "text-2" or "warn" end },
	}, {
		rowHeight = 32, headerHeight = 26, pool = 30,
		onRowClick = function(r) MLSession:SelectDelivery(r) end,
		rowSetup = function(r)
			r.bar = r:CreateTexture(nil, "ARTWORK")
			Theme.Fill(r.bar, "accent")
			r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
			r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
			r.bar:SetWidth(2)
			r.bar:Hide()
			for _, fs in ipairs(r.cells) do fs:SetWordWrap(false) end
		end,
		rowUpdate = function(r, row)
			local sel = MLSession.deliverSel
			r.bar:SetShown(sel ~= nil and sel.which == row.which and sel.index == row.index)
		end,
	})
	d.table:SetPoint("TOPLEFT", d.help, "BOTTOMLEFT", 0, -14)
	d.table:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 52)
	d.table:SetEmptyText(L["ML_DELIVER_EMPTY"])
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing

function MLSession:Select(index)
	self.selected = index
	self:Refresh()
end

function MLSession:ScrollItems(delta)
	local s, board = self.ui, self.board
	if not s or not board then return end
	s.offset = math.min(math.max(s.offset + delta, 0), math.max(#board.items - self.ITEM_ROWS, 0))
	self:Refresh()
end

function MLSession:SetMessage(text, isError)
	local s = self.ui
	if not s then return end
	s.message:SetText(text or "")
	Theme.Text(s.message, isError and "warn" or "text-2")
end

local function paintRow(self, r, item)
	local info = self:ItemInfo(item.itemID)
	r.index = item.index
	r.icon:SetTexture(info.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	r.name:SetText(self.ItemName(item.itemID, info))
	Theme.TextRGB(r.name, self.QualityColor(item.quality or info.quality))
	local sub = self.CategoryName(item.category) .. " · " .. costText(item)
	if item.winner then sub = SB().Short(item.winner) .. " · " .. SB().CreditsText(item.paid) end
	r.sub:SetText(sub)
	local text, tone = SB().Badge(item)
	r.badge:SetBadge(text:upper(), tone)
	local on = self.board.selected == item.index
	Theme.Tint(r.parts.ring, on and "accent" or "border-subtle")
	Theme.Tint(r.parts.fill, on and "surface-2" or "surface-1")
	r:Show()
end

local function paintItems(self, board)
	local s = self.ui
	-- keep the selected item on screen
	if board.selected then
		if board.selected <= s.offset then s.offset = board.selected - 1 end
		if board.selected > s.offset + self.ITEM_ROWS then s.offset = board.selected - self.ITEM_ROWS end
	end
	s.offset = math.min(math.max(s.offset, 0), math.max(#board.items - self.ITEM_ROWS, 0))
	for i, r in ipairs(s.rows) do
		local item = board.items[s.offset + i]
		if item then paintRow(self, r, item) else r:Hide() end
	end
end

-- The sentence under the candidates when there is no proposal to read.
-- locale-key: ML_HINT_COLLECTING ML_HINT_PENDING ML_HINT_ROLLING ML_HINT_EXPIRED ML_HINT_COMPUTING ML_HINT_HELD ML_HINT_READONLY
local function hint(board, item)
	if board.state == "COLLECTING" then return L["ML_HINT_COLLECTING"] end
	if item.state == "PENDING" then return L["ML_HINT_PENDING"] end
	if item.state == "ROLLING" then
		return L[board.round and board.round.expired and "ML_HINT_EXPIRED" or "ML_HINT_ROLLING"]
	end
	if item.state == "COMPUTING" then return L["ML_HINT_COMPUTING"] end
	return ""
end

-- The timer and the round's name (the part that changes every second).
-- locale-key: ML_ROUND_TIER ML_ROUND_REROLL ML_ROUND_FREE ML_PAUSED
function MLSession:PaintTimer(board)
	local s = self.ui
	local card = s.card
	local r = board and board.round
	if not r then
		card.timer:SetText("")
		card.round:SetText("")
		card.bar:SetFraction(0)
		return
	end
	local label
	if r.kind == "REROLL" then label = L["ML_ROUND_REROLL"]
	elseif r.stage == "FREE_ROLL" then label = L["ML_ROUND_FREE"]
	elseif r.tier then label = L["ML_ROUND_TIER"]:format(r.tier) else label = "" end
	card.round:SetText(label)
	if r.remaining then
		card.timer:SetText(board.paused and (clock(r.remaining) .. " · " .. L["ML_PAUSED"]) or clock(r.remaining))
		card.bar:SetFraction(r.total and r.total > 0 and r.remaining / r.total or 0)
	else
		card.timer:SetText(board.paused and L["ML_PAUSED"] or "")
		card.bar:SetFraction(0)
	end
end

-- The main button: what the master looter does next.
-- locale-key: ML_START ML_OPEN_ROLL ML_CLOSE_ROUND ML_NEXT_ROUND ML_CONFIRM ML_CLOSE_VOTE
local MAIN = {
	{ "start", "START", "ML_START" }, { "closeRound", "CLOSE_ROUND", "ML_CLOSE_ROUND" },
	{ "advance", "ADVANCE", "ML_NEXT_ROUND" }, { "confirm", "CONFIRM", "ML_CONFIRM" },
	{ "closeVote", "CLOSE_VOTE", "ML_CLOSE_VOTE" }, { "openRoll", "OPEN_ROLL", "ML_OPEN_ROLL" },
}

local function paintButtons(self, board)
	local s, a = self.ui, board.actions or {}
	s.mainMode = nil
	for _, m in ipairs(MAIN) do
		if a[m[1]] then s.mainMode = m[2]; s.main:SetLabel(L[m[3]]); break end
	end
	s.main:SetShown(s.mainMode ~= nil)
	s.modify:SetShown(a.modify == true)
	s.reject:SetShown(a.reject == true)
	s.correct:SetShown(a.correct == true)
	s.remove:SetShown(a.remove == true)
	s.pause:SetShown(a.pause == true or a.resume == true)
	s.pause:SetLabel(L[a.resume and "ML_RESUME" or "ML_PAUSE"])
	s.finish:SetShown(a.finish == true and board.host)
	local mayNotify = board.host and ns.AddonCheck and ns.AddonCheck.CanManage and ns.AddonCheck:CanManage() == true
	local missing = board.missing and #board.missing or 0
	s.notify:SetShown(mayNotify and missing > 0)
	s.missing:SetShown(missing > 0)
	if missing > 0 then
		s.missing:SetBadge(L[missing == 1 and "ML_CANNOT_ROLL_ONE" or "ML_CANNOT_ROLL_N"]:format(missing):upper(), "warn")
	end
end

local function paintDetail(self, board)
	local s = self.ui
	local card = s.card
	local sel = board.selectedItem
	card:SetShown(sel ~= nil)
	if not sel then return end
	local info = self:ItemInfo(sel.itemID)
	card.icon:SetTexture(info.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	card.name:SetText(self.ItemName(sel.itemID, info))
	Theme.TextRGB(card.name, self.QualityColor(sel.quality or info.quality))
	card.line:SetText(self.ItemLine(sel, info))
	card.badge:SetBadge(sel.category and (self.CategoryName(sel.category) .. " · " .. costText(sel)):upper() or "", "accent")
	card.table:SetData(board.candidates)
	-- the strip
	local p = board.proposal
	local main, sub = "", ""
	if p then
		main = SB().ProposalText(p)
		local lines = SB().DiffTexts(p)
		for _, f in ipairs(SB().FlagTexts(p, board.flags)) do lines[#lines + 1] = f end
		for _, f in ipairs(SB().FlagLines(board.flags)) do lines[#lines + 1] = f end   -- the council's (M5-4)
		if p.autoIn then lines[#lines + 1] = L["ML_AUTO_IN"]:format(math.ceil(p.autoIn)) end
		if p.autoHeld then lines[#lines + 1] = L["ML_AUTO_HELD"] end   -- a council vote against the proposal (M5-5)
		local votes = SB().VoteText(board.votes)   -- the council's votes, before the ML confirms (§3.6)
		if votes ~= "" then lines[#lines + 1] = votes end
		sub = table.concat(lines, " ")
	elseif sel.winner then
		main = SB().AwardText(sel)
		sub = table.concat(SB().FlagLines(board.flags), " ")
	else
		main = hint(board, sel)
		sub = table.concat(SB().FlagLines(board.flags), " ")   -- before the round closes (§5.2)
	end
	card.strip.main:SetText(main)
	card.strip.sub:SetText(sub)
	self:PaintTimer(board)
end

-- The "to deliver" list: the rows, the selection (kept while its item is still undelivered, else the first row) and
-- the buttons. Only the master looter's client has a list; elsewhere the tab is empty and the buttons are hidden.
function MLSession:PaintDeliver()
	local d = self.deliverUI
	if not d then return end
	local rows = SC() and SC():Deliveries() or {}
	self.deliveries = rows
	local sel, found = self.deliverSel, nil
	for _, r in ipairs(rows) do
		if sel and r.which == sel.which and r.index == sel.index then found = r end
	end
	found = found or rows[1]
	self.deliverSel = found and { which = found.which, index = found.index } or nil
	d.table:SetData(rows)
	d.give:SetShown(found ~= nil and found.status ~= "GIVEN")
	d.mark:SetShown(found ~= nil)
	local board = self.board
	if found and board and board.readOnly then d.give:Hide(); d.mark:Hide() end
end

function MLSession:SelectDelivery(row)
	self.deliverSel = { which = row.which, index = row.index }
	self:SetDeliverMessage("")
	self:Refresh()
end

function MLSession:SetDeliverMessage(text, isError)
	local d = self.deliverUI
	if not d then return end
	d.message:SetText(text or "")
	Theme.Text(d.message, isError and "warn" or "text-2")
end

-- Hand the selected item over now, from the click: master loot when the game allows it, else it stays for a trade.
-- locale-key: ML_DELIVER_NOW_GIVEN ML_DELIVER_NOW_ALREADY
function MLSession:OnGive()
	local sel = self.deliverSel
	if not sel then return end
	local ok, code, method = SC():Deliver(sel.index, sel.which)
	if not ok then
		self:SetDeliverMessage(SB().ErrorText(code), true)
	elseif method == "MASTER" then
		self:SetDeliverMessage(L["ML_DELIVER_NOW_GIVEN"])
	elseif method == "LOOT" then
		self:SetDeliverMessage(L["ML_DELIVER_NOW_ALREADY"])
	else
		self:SetDeliverMessage(SB().DeliveryCodeText(code), true)
	end
	self:Refresh()
end

function MLSession:OnMarkDelivered()
	local sel = self.deliverSel
	if not sel then return end
	local ok, code = SC():MarkDelivered(sel.index, sel.which)
	if ok then self:SetDeliverMessage("") else self:SetDeliverMessage(SB().ErrorText(code), true) end
	self:Refresh()
end

function MLSession:Refresh()
	local s = self.ui
	if not s then return end
	local board = SC() and SC():Board(self.selected) or nil
	self.board = board
	self:PaintDeliver()
	if ns.CouncilWindow then ns.CouncilWindow:Refresh() end   -- the council's page follows the same board (M5-8)
	if not board then
		s.status:SetText(L["ML_NONE"])
		s.empty:SetText(L["ML_NONE_HELP"])
		for _, r in ipairs(s.rows) do r:Hide() end
		s.card:Hide()
		for _, b in ipairs({ s.pause, s.finish, s.notify, s.missing, s.main, s.modify, s.reject, s.correct, s.remove }) do b:Hide() end
		return
	end
	local status = ns.Reasons.Text("STATE", board.state)
	if board.held then status = L["ML_HINT_HELD"] end
	if board.paused then status = status .. " · " .. L["ML_PAUSED"] end
	if not board.host then status = status .. " · " .. L["ML_HINT_READONLY"] end
	local toDeliver = self.deliveries and #self.deliveries or 0
	if toDeliver > 0 then
		status = status .. " · " .. L[toDeliver == 1 and "ML_TO_DELIVER_ONE" or "ML_TO_DELIVER_N"]:format(toDeliver)
	end
	s.status:SetText(status)
	s.empty:SetText(#board.items == 0 and (board.held and L["ML_HINT_HELD"] or L["ML_EMPTY"]) or "")
	paintItems(self, board)
	paintDetail(self, board)
	paintButtons(self, board)
end

-- Redraws only the timer (the ticker of the visible tab).
function MLSession:RefreshTimer()
	local s = self.ui
	if not s or not self.root:IsVisible() then return self:Disarm() end
	if not s.card:IsShown() then return end
	local board = SC() and SC():Board(self.selected) or nil
	if board then self.board = board; self:PaintTimer(board) end
end

function MLSession:Arm()
	if self.ticker or not ns.Compat then return end
	self.ticker = ns.Compat.NewTicker(self.TICK, function() MLSession:RefreshTimer() end)
end

function MLSession:Disarm()
	if self.ticker then self.ticker:Cancel() end
	self.ticker = nil
end

---------------------------------------------------------------------------------------------------------------------
-- The master looter's clicks

-- Sends a command to the controller and shows the refusal in plain words. Returns ok, code.
function MLSession:Do(kind, fields)
	local ok, code = SC():Command(kind, fields)
	if ok then self:SetMessage("") else self:SetMessage(SB().ErrorText(code), true) end
	self:Refresh()
	return ok, code
end

function MLSession:OnMain()
	local mode, sel = self.ui.mainMode, self.board and self.board.selected
	if mode == "OPEN_ROLL" then return self:Do(mode, { index = sel }) end
	if mode then return self:Do(mode) end
end

function MLSession:OnPause()
	local a = self.board and self.board.actions or {}
	return self:Do(a.resume and "RESUME" or "PAUSE")
end

function MLSession:OnRemove()
	local sel = self.board and self.board.selected
	if sel then return self:Do("REMOVE_ITEM", { index = sel }) end
end

-- The "N raid members cannot roll" notice in /raid (App/AddonNotice.lua: the click is the player's).
function MLSession:OnNotify()
	local entry, code, extra = ns.AddonNotice:Send("MISSING")
	if not entry then
		self:SetMessage(ns.AddonPanel.ErrorText(code, extra), true)
	elseif entry.mode == "WHISPER" then
		self:SetMessage(L["NOTICE_SENT_WHISPER"]:format(entry.lines))
	else
		self:SetMessage(L["NOTICE_SENT"]:format("/raid", entry.lines))
	end
end

---------------------------------------------------------------------------------------------------------------------
-- The dialog: Modify, Reject and Correct share one card

local function parseCost(text)
	text = (text or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub(",", ".")
	if text == "" then return nil, nil end
	local n = tonumber(text)
	if not n or n < 0 or n ~= n then return nil, "ML_ERR_BAD_COST" end
	return n
end
MLSession.ParseCost = parseCost

local function dlgLabel(card, x, y)
	local fs = Theme.NewText(card, "Eyebrow", "accent-text")
	fs:SetPoint("TOPLEFT", card, "TOPLEFT", x, y)
	return fs
end

function MLSession:BuildDialog()
	if self.dlg then return self.dlg end
	local d = { }
	d.frame = Widgets.Dialog(self.frame, "FDCPMLDialog", { width = 620, height = 430 })
	local card = d.frame.card
	d.title = Theme.NewText(card, "H1", "text-1")
	d.title:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -20)
	d.hint = Theme.NewText(card, "Small", "text-2")
	d.hint:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -6)
	d.hint:SetWidth(572)
	d.hint:SetJustifyH("LEFT")
	d.listLabel = dlgLabel(card, 24, -84)
	d.list = Widgets.ChoiceList(card, { rows = 7, width = 272, onSelect = function() MLSession:DialogChanged() end })
	d.list:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -102)
	d.costLabel = dlgLabel(card, 24, -300)
	d.cost = Widgets.EditBox(card, { width = 130, maxLetters = 8, onChange = function() MLSession:DialogChanged() end })
	d.cost:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -318)
	d.reasonLabel = dlgLabel(card, 324, -84)
	d.reasons = Widgets.ChoiceList(card, { rows = 7, width = 272, onSelect = function() MLSession:DialogChanged() end })
	d.reasons:SetPoint("TOPLEFT", card, "TOPLEFT", 324, -102)
	d.preview = Theme.NewText(card, "Small", "text-1")
	d.preview:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 62)
	d.preview:SetWidth(572)
	d.preview:SetJustifyH("LEFT")
	d.preview:SetJustifyV("BOTTOM")
	d.error = Theme.NewText(card, "Small", "warn")
	d.error:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 28)
	d.error:SetWidth(380)
	d.error:SetJustifyH("LEFT")
	d.save = Widgets.Button(card, { text = L["ML_DLG_SAVE"], style = "primary", width = 130, height = 36, onClick = function()
		MLSession:DialogSave()
	end })
	d.save:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 20)
	d.cancel = Widgets.Button(card, { text = L["ML_DLG_CANCEL"], style = "secondary", width = 100, height = 36, onClick = function()
		d.frame:Close()
	end })
	d.cancel:SetPoint("RIGHT", d.save, "LEFT", -8, 0)
	self.dlg = d
	return d
end

-- The winners the master looter can pick: the candidates first (with their answer and credits), the rest of the raid,
-- then the guild bank and the disenchanter.
local function winnerChoices(board)
	local out, seen = {}, {}
	for _, c in ipairs(board.candidates or {}) do
		seen[c.player] = true
		local text = c.name
		if c.response then text = text .. " · " .. ns.Reasons.Text("RESPONSE", c.response) end
		text = text .. " · " .. SB().CreditsText(c.credits)
		out[#out + 1] = { id = c.player, text = text }
	end
	for _, name in ipairs(board.pool or {}) do
		if not seen[name] then
			seen[name] = true
			out[#out + 1] = { id = name, text = short(name), token = "text-3" }
		end
	end
	out[#out + 1] = { id = "@bank", text = ns.Reasons.Text("KIND", "BANK") }
	out[#out + 1] = { id = "@disenchant", text = ns.Reasons.Text("KIND", "DISENCHANT") }
	return out
end

local function reasonChoices()
	local out = {}
	for _, code in ipairs(SB().REASONS) do out[#out + 1] = { id = code, text = ns.Reasons.Text("CORRECTION", code) } end
	return out
end

-- The id of the current winner in the winners' list ("@bank", "@disenchant" or the player).
local function currentWinner(p)
	if p.target == "bank" or p.target == "disenchant" then return "@" .. p.target end
	return p.winner
end

-- Opens the dialog: "modify" (the proposal), "reject" (the proposal) or "correct" (the item's category or cost).
-- locale-key: ML_DLG_MODIFY_TITLE ML_DLG_WINNER ML_DLG_COST ML_DLG_REASON ML_DLG_REJECT_TITLE
-- locale-key: ML_DLG_REJECT_HINT ML_DLG_REJECT_THEN ML_DLG_CORRECT_TITLE ML_DLG_CORRECT_HINT ML_DLG_CATEGORY ML_DLG_COST_BASE
function MLSession:OpenDialog(mode)
	local board = self.board
	if not board or not board.host or not board.selected then return false end
	local d = self:BuildDialog()
	d.mode, d.index = mode, board.selected
	d.proposal = board.proposal
	d.error:SetText("")
	d.preview:SetText("")
	d.cost:SetText("")
	d.reasons:Clear()
	d.list:Clear()
	local withReasons, withCost = true, true
	if mode == "modify" then
		if not board.proposal then return false end
		d.title:SetText(L["ML_DLG_MODIFY_TITLE"])
		d.hint:SetText(SB().ProposalText(board.proposal))
		d.listLabel:SetText(L["ML_DLG_WINNER"]:upper())
		d.list:SetChoices(winnerChoices(board))
		local current = currentWinner(board.proposal)
		if current then d.list:Select(current) end
		d.costLabel:SetText(L["ML_DLG_COST"]:upper())
		d.cost:SetText(board.proposal.cost ~= nil and tostring(board.proposal.cost) or "")
	elseif mode == "reject" then
		if not board.proposal then return false end
		withReasons, withCost = false, false
		d.title:SetText(L["ML_DLG_REJECT_TITLE"])
		d.hint:SetText(L["ML_DLG_REJECT_HINT"])
		d.listLabel:SetText(L["ML_DLG_REJECT_THEN"]:upper())
		local list = {}
		for _, code in ipairs(SB().REJECT_OPTIONS) do list[#list + 1] = { id = code, text = ns.Reasons.Text("REJECT", code) } end
		d.list:SetChoices(list)
		d.list:Select("PENDING")
	elseif mode == "correct" then
		local item = board.selectedItem
		d.title:SetText(L["ML_DLG_CORRECT_TITLE"])
		d.hint:SetText(L["ML_DLG_CORRECT_HINT"])
		d.listLabel:SetText(L["ML_DLG_CATEGORY"]:upper())
		local list = {}
		for _, c in ipairs(ns.Classifier.CATEGORIES) do list[#list + 1] = { id = c, text = self.CategoryName(c) } end
		d.list:SetChoices(list)
		if item and item.category then d.list:Select(item.category) end
		d.costLabel:SetText(L["ML_DLG_COST_BASE"]:upper())
	else
		return false
	end
	d.save:SetLabel(mode == "reject" and L["ML_REJECT"] or L["ML_DLG_SAVE"])
	d.reasonLabel:SetText(L["ML_DLG_REASON"]:upper())
	if withReasons then d.reasons:SetChoices(reasonChoices()) else d.reasons:SetChoices({}) end
	d.reasons:SetShown(withReasons); d.reasonLabel:SetShown(withReasons)
	d.cost:SetShown(withCost); d.costLabel:SetShown(withCost)
	d.frame:Open()
	self:DialogChanged()
	return true
end

function MLSession:CloseDialog()
	if self.dlg then self.dlg.frame:Close() end
end

function MLSession:DialogOpen() return self.dlg ~= nil and self.dlg.frame:IsShown() end

-- The changes of a Modify dialog as MODIFY's fields; nil and a locale key when the cost is not a number.
function MLSession:ModifyChange()
	local d = self.dlg
	local p = d.proposal
	local change = {}
	local choice = d.list:Selected()
	if choice and choice ~= currentWinner(p) then
		if choice == "@bank" then change.target = "bank"
		elseif choice == "@disenchant" then change.target = "disenchant"
		else change.winner = choice end
	end
	local cost, bad = parseCost(d.cost:GetText())
	if bad then return nil, bad end
	if cost ~= nil and cost ~= p.cost then change.cost = cost end
	return change
end

-- A choice or a cost changed: Modify shows the proposal that would result and how it differs from the rules.
function MLSession:DialogChanged()
	local d = self.dlg
	if not d or d.mode ~= "modify" then return end
	d.error:SetText("")
	local change, bad = self:ModifyChange()
	if not change then d.preview:SetText(""); d.error:SetText(L[bad]); return end
	if next(change) == nil then d.preview:SetText(""); return end
	local p = SC():PreviewModify(change)
	if not p then d.preview:SetText(""); return end
	local lines = { SB().ProposalText(p) }
	for _, t in ipairs(SB().DiffTexts(p)) do lines[#lines + 1] = t end
	d.preview:SetText(table.concat(lines, " "))
end

-- Save: Modify needs a reason; every refusal of the state machine is shown in the dialog.
function MLSession:DialogSave()
	local d = self.dlg
	if not d or not d.frame:IsShown() then return end
	local ok, code
	if d.mode == "modify" then
		local reason = d.reasons:Selected()
		if not reason then d.error:SetText(SB().ErrorText("REASON_REQUIRED")); return false, "REASON_REQUIRED" end
		local change, bad = self:ModifyChange()
		if not change then d.error:SetText(L[bad]); return false, "BAD_COST" end
		if next(change) == nil then d.error:SetText(SB().ErrorText("NOTHING_CHANGED")); return false, "NOTHING_CHANGED" end
		change.reason = reason
		ok, code = self:Do("MODIFY", change)
	elseif d.mode == "reject" then
		ok, code = self:Do("REJECT", { ["then"] = d.list:Selected() or "PENDING" })
	elseif d.mode == "correct" then
		local reason = d.reasons:Selected()
		if not reason then d.error:SetText(SB().ErrorText("REASON_REQUIRED")); return false, "REASON_REQUIRED" end
		local cost, bad = parseCost(d.cost:GetText())
		if bad then d.error:SetText(L[bad]); return false, "BAD_COST" end
		local fields = { index = d.index, reason = reason }
		if cost ~= nil then fields.cost = cost else fields.category = d.list:Selected() end
		ok, code = self:Do("CORRECT_ITEM", fields)
	else
		return false, "MODE"
	end
	if ok then d.frame:Close() else d.error:SetText(SB().ErrorText(code)) end
	return ok, code
end

---------------------------------------------------------------------------------------------------------------------
-- Events

-- The effects that bring the follow-the-session selection back to the item in progress.
local FOLLOW = { OPEN_ROUND = true, PROPOSAL = true, NEXT_ROUND = true, AWARDED = true, REJECTED = true }

function MLSession:OnSession(effects)
	for _, e in ipairs(effects or {}) do
		if FOLLOW[e.type] then self.selected = nil end
		if e.type == "COLLECTED" and ns.MainWindow then
			ns.MainWindow:Open("loot")   -- the corpse was opened: the window opens on the session
		end
	end
	if self.root then self:Refresh() end
end

if ns.Bus then
	ns.Bus:On("SESSION_CHANGED", function(_, _, effects) MLSession:OnSession(effects) end, MLSession)
	for _, ev in ipairs({ "SESSION_STARTED", "SESSION_HELD", "SESSION_VIEW", "ADDON_CHECK_CHANGED", "GUILD_KEY_CHANGED", "THEME_CHANGED" }) do
		ns.Bus:On(ev, function()
			if ev == "SESSION_STARTED" then MLSession.selected = nil end
			if MLSession.root then MLSession:Refresh() end
		end, MLSession)
	end
end
