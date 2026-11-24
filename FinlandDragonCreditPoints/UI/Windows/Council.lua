-- CouncilWindow: the Loot > Council sub-tab (docs/ANALISI.md §3.6, §3.7, §9.3, docs/specs/ui-style.md §3, §6, M5-8). The
-- loot council's page: on the left the item on the table (the proposal, the flags "upgrade ignored" and "possible
-- waste", the votes, the member's own vote, and the master looter's shortcuts to Modify and Correct, which open the
-- Session tab's reason dialogs); on the right three views: the awards a void can cancel, the audit of the council's
-- interventions and the legendary projects. Cancelling an award, adjusting a member's credits and opening a project
-- open a dialog whose reason is mandatory (a code from Domain/Reasons.lua, never typed text).
--
-- The window decides nothing: it draws what App/SessionController.lua's board (App/SessionBoard.lua), App/CouncilService.lua
-- (membership, vote, void, adjust, audit) and App/LegendaryService.lua (the projects) give, and sends the clicks back to
-- those services, whose refusals (rank, reason, season) it shows in a sentence. Lua 5.1; unprotected frames.
-- Not verified in the real client: the page in a raid and the dialogs' look (the owner's M5 checklist).
local ADDON_NAME, ns = ...
ns = ns or {}
local CouncilWindow = {}
ns.CouncilWindow = CouncilWindow
if ns.addon then ns.addon.CouncilWindow = CouncilWindow end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

CouncilWindow.VIEWS = { "awards", "audit", "legendary" }
CouncilWindow.CARD_W = 400
CouncilWindow.VOTE_ROWS = 3

local function SC() return ns.SessionController end
local function CS() return ns.CouncilService end
local function LS() return ns.LegendaryService end
local function SB() return ns.SessionBoard end
local function ML() return ns.MLSession end
local function me() return ns.GuildRanks and ns.GuildRanks.Me() or nil end
local short = function(name) return (tostring(name or "?"):gsub("%-.*$", "")) end

local function enable(button, on)
	button:SetEnabled(on and true or false)
	button:SetAlpha(on and 1 or 0.45)
end

local function itemName(id) return ML().ItemName(id, ML():ItemInfo(id)) end
local function itemColor(id, quality) return ML().QualityColor(quality or ML():ItemInfo(id).quality) end

local function num(n)
	if type(n) ~= "number" then return tostring(n) end
	if n == math.floor(n) then return ("%d"):format(n) end
	return ("%.2f"):format(n)
end

---------------------------------------------------------------------------------------------------------------------
-- Build

-- locale-key: COUNCIL_EYEBROW COUNCIL_TITLE COUNCIL_VIEW_AWARDS COUNCIL_VIEW_AUDIT COUNCIL_VIEW_LEGENDARY
function CouncilWindow:Build(pane, frame)
	if self.root then return self.root end
	local root = CreateFrame("Frame", nil, pane)
	root:SetAllPoints(pane)
	self.root, self.pane, self.frame = root, pane, frame

	root.eyebrow = Theme.NewText(root, "Eyebrow", "accent-text")
	root.eyebrow:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -4)
	root.eyebrow:SetText(L["COUNCIL_EYEBROW"]:upper())
	root.title = Theme.NewText(root, "H1", "text-1")
	root.title:SetPoint("TOPLEFT", root.eyebrow, "BOTTOMLEFT", 0, -4)
	root.title:SetText(L["COUNCIL_TITLE"])
	-- the status and the message take one line each up to the right edge (the views start at a fixed height below them):
	-- a longer one is cut, and the status shows whole in a tooltip
	root.status = Theme.NewText(root, "Small", "text-2")
	root.status:SetPoint("TOPLEFT", root.title, "BOTTOMLEFT", 0, -4)
	root.status:SetPoint("RIGHT", root, "RIGHT", 0, 0)
	root.status:SetJustifyH("LEFT")
	root.statusHit = CreateFrame("Frame", nil, root)
	root.statusHit:SetAllPoints(root.status)
	root.statusHit:EnableMouse(true)
	Widgets.TruncatedTip(root.statusHit, root.status)
	root.message = Theme.NewText(root, "Small", "text-2")
	root.message:SetPoint("TOPLEFT", root.status, "BOTTOMLEFT", 0, -2)
	root.message:SetPoint("RIGHT", root, "RIGHT", 0, 0)
	root.message:SetJustifyH("LEFT")
	root.message:SetWordWrap(false)

	root.adjust = Widgets.Button(root, { text = L["COUNCIL_ADJUST_BUTTON"], style = "secondary", width = 170, height = 32,
		onClick = function() CouncilWindow:OpenDialog("adjust") end })
	root.adjust:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -4)

	self:BuildTable(root)
	root.view = Widgets.Segmented(root, {
		{ id = "awards", text = L["COUNCIL_VIEW_AWARDS"] }, { id = "audit", text = L["COUNCIL_VIEW_AUDIT"] },
		{ id = "legendary", text = L["COUNCIL_VIEW_LEGENDARY"] },
	}, function(id) CouncilWindow:ShowView(id) end)
	root.view:SetPoint("TOPLEFT", root, "TOPLEFT", self.CARD_W + 16, -92)
	root.panes = {}
	for _, id in ipairs(self.VIEWS) do
		local p = CreateFrame("Frame", nil, root)
		p:SetPoint("TOPLEFT", root, "TOPLEFT", self.CARD_W + 16, -132)
		p:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
		p:Hide()
		root.panes[id] = p
	end
	self:BuildAwards(root.panes.awards)
	self:BuildAudit(root.panes.audit)
	self:BuildLegendary(root.panes.legendary)
	root.view:Select("awards")
	self:Refresh()
	return root
end

function CouncilWindow:ShowView(id)
	if not self.root then return end
	for pid, p in pairs(self.root.panes) do p:SetShown(pid == id) end
	self:Refresh()
end

function CouncilWindow:SelectView(id)
	if not self.root then return false end
	return self.root.view:Select(id)
end

-- The card of the item on the table: the proposal, the flags, the votes, the vote and the shortcuts.
-- locale-key: COUNCIL_TABLE_EYEBROW COUNCIL_VOTE_LABEL COUNCIL_VOTE_BUTTON ML_MODIFY ML_CORRECT
function CouncilWindow:BuildTable(root)
	local c = Widgets.Card(root, { width = self.CARD_W, height = 300 })
	c:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -92)
	c:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
	c:SetWidth(self.CARD_W)
	self.card = c
	-- the one neon element of the view (docs/specs/ui-style.md §2.1): the card of the item whose vote is open
	c.glow = Theme.Glow(c, "glow_l", "neon", { alpha = 0.25 })
	c.glow:SetPoint("TOPLEFT", c, "TOPLEFT", -30, 30)
	c.glow:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 30, -30)
	Theme.GlowShow(c.glow, false)
	c.eyebrow = Theme.NewText(c, "Eyebrow", "accent-text")
	c.eyebrow:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -16)
	c.eyebrow:SetText(L["COUNCIL_TABLE_EYEBROW"]:upper())
	c.item = Theme.NewText(c, "H2", "text-1")
	c.item:SetPoint("TOPLEFT", c.eyebrow, "BOTTOMLEFT", 0, -6)
	c.item:SetWidth(self.CARD_W - 40)
	c.item:SetJustifyH("LEFT")
	c.proposal = Theme.NewText(c, "Small", "text-2")
	c.proposal:SetPoint("TOPLEFT", c.item, "BOTTOMLEFT", 0, -6)
	c.proposal:SetWidth(self.CARD_W - 40)
	c.proposal:SetJustifyH("LEFT")
	c.flags = Theme.NewText(c, "Small", "warn")
	c.flags:SetPoint("TOPLEFT", c.proposal, "BOTTOMLEFT", 0, -8)
	c.flags:SetWidth(self.CARD_W - 40)
	c.flags:SetJustifyH("LEFT")
	c.votes = Theme.NewText(c, "Small", "text-1")
	c.votes:SetPoint("TOPLEFT", c.flags, "BOTTOMLEFT", 0, -8)
	c.votes:SetWidth(self.CARD_W - 40)
	c.votes:SetJustifyH("LEFT")

	c.voteLabel = Theme.NewText(c, "Eyebrow", "accent-text")
	c.voteLabel:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 20, 64 + self.VOTE_ROWS * 24 + 16)
	c.voteLabel:SetText(L["COUNCIL_VOTE_LABEL"]:upper())
	c.voteHint = Theme.NewText(c, "Small", "text-3")
	c.voteHint:SetPoint("LEFT", c.voteLabel, "RIGHT", 10, 0)
	c.choices = Widgets.ChoiceList(c, { rows = self.VOTE_ROWS, width = self.CARD_W - 40 })
	c.choices:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 20, 60)
	c.vote = Widgets.Button(c, { text = L["COUNCIL_VOTE_BUTTON"], style = "primary", width = 110, height = 36,
		onClick = function() CouncilWindow:OnVote() end })
	c.vote:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -20, 16)
	c.modify = Widgets.Button(c, { text = L["ML_MODIFY"], style = "secondary", width = 100, height = 36,
		onClick = function() CouncilWindow:OnIntervene("modify") end })
	c.modify:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 20, 16)
	c.correct = Widgets.Button(c, { text = L["ML_CORRECT"], style = "secondary", width = 100, height = 36,
		onClick = function() CouncilWindow:OnIntervene("correct") end })
	c.correct:SetPoint("LEFT", c.modify, "RIGHT", 8, 0)
	c.penalize = Widgets.Button(c, { text = "", style = "secondary", width = 150, height = 36,
		onClick = function() CouncilWindow:OnPenalize() end })   -- possible roll cheating (M7-5d)
	c.penalize:SetPoint("LEFT", c.correct, "RIGHT", 8, 0)
	c.penalize:Hide()
end

-- The "Penalize +2" button (M7-5d, App/CheatService.lua): one click arms, the second writes the penalty.
-- locale-key: ML_PENALIZED
function CouncilWindow:OnPenalize()
	local CheatS = ns.CheatService
	local board = SC() and SC():Board(ML() and ML().selected or nil)
	local target = board and board.cheat
	if not CheatS or not target then return end
	local r, code = CheatS:Click(target)
	if r == "ARMED" then
		self.card.penalize:SetLabel(CheatS:Label(target))
		return
	end
	if not r then return self:SetMessage(L["COUNCIL_REFUSED"]:format(SB().ErrorText(code)), true) end
	self:SetMessage(L["ML_PENALIZED"]:format(tostring(target.amount or CheatS:Amount()), short(target.member)))
	self:Refresh()
end

-- A table whose rows can be selected: the selected one carries an accent bar.
local function selectableTable(parent, columns, isSelected, onSelect)
	local t = Widgets.DataTable(parent, columns, {
		rowHeight = 30, headerHeight = 26, pool = 40,
		onRowClick = function(d) onSelect(d) end,
		rowSetup = function(r)
			r.bar = r:CreateTexture(nil, "ARTWORK")
			Theme.Fill(r.bar, "accent")
			r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
			r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
			r.bar:SetWidth(2)
			r.bar:Hide()
			for _, fs in ipairs(r.cells) do fs:SetWordWrap(false) end
		end,
		rowUpdate = function(r, d) r.bar:SetShown(isSelected(d)) end,
	})
	return t
end

-- The awards a void can cancel.
-- locale-key: COUNCIL_COL_ITEM COUNCIL_COL_WINNER COUNCIL_COL_CREDITS COUNCIL_VOID_BUTTON COUNCIL_AWARDS_EMPTY COUNCIL_AWARDS_HELP
function CouncilWindow:BuildAwards(pane)
	local a = {}
	self.awards = a
	a.help = Theme.NewText(pane, "Small", "text-2")
	a.help:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
	a.help:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
	a.help:SetJustifyH("LEFT")
	a.help:SetText(L["COUNCIL_AWARDS_HELP"])
	a.table = selectableTable(pane, {
		{ id = "item", title = L["COUNCIL_COL_ITEM"], flex = 1, sortable = false, text = function(r) return itemName(r.item) end,
			render = function(fs, r)
				fs:SetText(itemName(r.item))
				Theme.TextRGB(fs, itemColor(r.item))
			end },
		{ id = "winner", title = L["COUNCIL_COL_WINNER"], width = 120, sortable = false, text = function(r) return short(r.member) end,
			render = function(fs, r)
				fs:SetText(short(r.member))
				Theme.ClassText(fs, ns.RosterWindow.ClassColor(SC() and SC():ClassOf(r.member)))
			end },
		{ id = "cost", title = L["COUNCIL_COL_CREDITS"], width = 80, sortable = false, align = "RIGHT", mono = true,
			text = function(r) return num(r.cost) end },
	}, function(d) return CouncilWindow.awardSel == d.id end, function(d)
		CouncilWindow.awardSel = d.id
		CouncilWindow:SetMessage("")
		CouncilWindow:Refresh()
	end)
	a.table:SetPoint("TOPLEFT", a.help, "BOTTOMLEFT", 0, -8)
	a.table:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 52)
	a.table:SetEmptyText(L["COUNCIL_AWARDS_EMPTY"])
	a.void = Widgets.Button(pane, { text = L["COUNCIL_VOID_BUTTON"], style = "secondary", width = 190, height = 36,
		onClick = function() CouncilWindow:OpenDialog("void") end })
	a.void:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
end

-- The audit: every intervention of the open season, newest first.
-- locale-key: COUNCIL_COL_INTERVENTION COUNCIL_AUDIT_HELP
function CouncilWindow:BuildAudit(pane)
	local a = {}
	self.audit = a
	a.help = Theme.NewText(pane, "Small", "text-2")
	a.help:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
	a.help:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
	a.help:SetJustifyH("LEFT")
	a.help:SetText(L["COUNCIL_AUDIT_HELP"])
	a.table = Widgets.DataTable(pane, {
		{ id = "line", title = L["COUNCIL_COL_INTERVENTION"], flex = 1, sortable = false, text = function(r) return r.text end,
			token = function(r) return r.voided and "text-3" or "text-1" end },
	}, { rowHeight = 30, headerHeight = 26, pool = 40, rowSetup = function(r)
		for _, fs in ipairs(r.cells) do fs:SetWordWrap(false) end
	end })
	a.table:SetPoint("TOPLEFT", a.help, "BOTTOMLEFT", 0, -8)
	a.table:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
	a.table:SetEmptyText(L["COUNCIL_AUDIT_EMPTY"])
end

-- The legendary projects.
-- locale-key: COUNCIL_COL_PROJECT COUNCIL_COL_BUILDER COUNCIL_COL_PIECES COUNCIL_COL_STATE COUNCIL_PROJECT_OPEN
-- locale-key: COUNCIL_PROJECT_COMPLETE COUNCIL_PROJECT_ABANDON
function CouncilWindow:BuildLegendary(pane)
	local g = {}
	self.legendary = g
	g.mode = Theme.NewText(pane, "Small", "text-2")
	g.mode:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
	g.mode:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
	g.mode:SetJustifyH("LEFT")
	g.table = selectableTable(pane, {
		{ id = "name", title = L["COUNCIL_COL_PROJECT"], flex = 1, sortable = false, text = function(p) return p.name end },
		{ id = "builder", title = L["COUNCIL_COL_BUILDER"], width = 100, sortable = false,
			text = function(p) return p.builder and short(p.builder) or L["LEGENDARY_NOBODY"] end },
		{ id = "pieces", title = L["COUNCIL_COL_PIECES"], width = 64, sortable = false, align = "RIGHT", mono = true,
			text = function(p) return ("%d/%d"):format(#p.paid, #p.pieces) end },
		{ id = "state", title = L["COUNCIL_COL_STATE"], width = 90, sortable = false,
			text = function(p) return p.open and L["LEGENDARY_STATE_OPEN"] or ns.Reasons.Text("OUTCOME", p.outcome) end,
			token = function(p) return p.open and "accent-text" or "text-3" end },
	}, function(p) return CouncilWindow.projectSel == p.id end, function(p)
		CouncilWindow.projectSel = p.id
		CouncilWindow:SetMessage("")
		CouncilWindow:Refresh()
	end)
	g.table:SetPoint("TOPLEFT", g.mode, "BOTTOMLEFT", 0, -8)
	g.table:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 52)
	g.table:SetEmptyText(L["LEGENDARY_EMPTY"])
	g.open = Widgets.Button(pane, { text = L["COUNCIL_PROJECT_OPEN"], style = "primary", width = 150, height = 36,
		onClick = function() CouncilWindow:OpenDialog("project") end })
	g.open:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
	g.abandon = Widgets.Button(pane, { text = L["COUNCIL_PROJECT_ABANDON"], style = "ghost", width = 110, height = 36,
		onClick = function() CouncilWindow:OnClose("ABANDONED") end })
	g.abandon:SetPoint("RIGHT", g.open, "LEFT", -8, 0)
	g.complete = Widgets.Button(pane, { text = L["COUNCIL_PROJECT_COMPLETE"], style = "secondary", width = 130, height = 36,
		onClick = function() CouncilWindow:OnClose("COMPLETED") end })
	g.complete:SetPoint("RIGHT", g.abandon, "LEFT", -8, 0)
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing

function CouncilWindow:SetMessage(text, isError)
	local r = self.root
	if not r then return end
	r.message:SetText(text or "")
	Theme.Text(r.message, isError and "warn" or "text-2")
end

-- locale-key: COUNCIL_AWARD_MODE COUNCIL_AWARD_MODE_CONFIRM COUNCIL_AWARD_MODE_AUTO COUNCIL_AWARD_MODE_COUNCIL
-- locale-key: COUNCIL_AWARD_VOTE_ADVICE COUNCIL_STATE_MEMBER COUNCIL_STATE_NOT_MEMBER COUNCIL_STATE_LIST COUNCIL_STATE_RANK
local function statusLine()
	local cs = CS()
	local parts = {}
	parts[#parts + 1] = L[cs:IsMember(nil, true) and "COUNCIL_STATE_MEMBER" or "COUNCIL_STATE_NOT_MEMBER"]
	parts[#parts + 1] = L[ns.Council.HasList(cs:Rules()) and "COUNCIL_STATE_LIST" or "COUNCIL_STATE_RANK"]
	local mode, vote = cs:AwardMode()
	local text = L["COUNCIL_AWARD_MODE"]:format(L["COUNCIL_AWARD_MODE_" .. tostring(mode):upper()])
	if vote and mode ~= "council" then text = text .. " " .. L["COUNCIL_AWARD_VOTE_ADVICE"] end
	parts[#parts + 1] = text
	return table.concat(parts, " · ")
end

-- The choices of the vote: the proposal's winner first, then the candidates (the names the board knows).
local function voteChoices(board)
	local out, seen = {}, {}
	local function add(player, extra)
		if type(player) ~= "string" or seen[player] then return end
		seen[player] = true
		out[#out + 1] = { id = player, text = extra and (short(player) .. " · " .. extra) or short(player) }
	end
	local p = board.proposal
	if p and p.winner and p.target ~= "bank" and p.target ~= "disenchant" then add(p.winner, L["COUNCIL_VOTE_PROPOSED"]) end
	for _, c in ipairs(board.candidates or {}) do
		add(c.player, c.response and ns.Reasons.Text("RESPONSE", c.response) or nil)
	end
	return out
end

-- locale-key: COUNCIL_NO_SESSION COUNCIL_ITEM_NONE COUNCIL_FLAGS_NONE COUNCIL_VOTE_MINE COUNCIL_VOTE_NO_VOTE COUNCIL_VOTE_NOT_MEMBER
-- locale-key: COUNCIL_VOTE_PROPOSED
local function paintTable(self, board)
	local c = self.card
	local cs = CS()
	local member = cs:IsMember(nil, true)
	if not board then
		c.item:SetText(L["COUNCIL_NO_SESSION"])
		Theme.Text(c.item, "text-3")
		c.proposal:SetText(""); c.flags:SetText(""); c.votes:SetText("")
		Theme.GlowShow(c.glow, false)
		Theme.Tint(c.parts.ring, "border-subtle")
		c.choices:SetChoices({})
		c.voteHint:SetText("")
		for _, b in ipairs({ c.vote, c.modify, c.correct }) do enable(b, false) end
		c.penalize:Hide()
		return
	end
	local sel = board.selectedItem
	if sel then
		c.item:SetText(itemName(sel.itemID))
		Theme.TextRGB(c.item, itemColor(sel.itemID, sel.quality))
	else
		c.item:SetText(L["COUNCIL_ITEM_NONE"])
		Theme.Text(c.item, "text-3")
	end
	local p = board.proposal
	if p then
		c.proposal:SetText(SB().ProposalText(p))
	elseif sel and sel.winner then
		c.proposal:SetText(SB().AwardText(sel))
	else
		c.proposal:SetText("")
	end
	local lines = SB().FlagLines(board.flags)
	c.flags:SetText(#lines > 0 and table.concat(lines, "\n") or "")
	Theme.Text(c.flags, #lines > 0 and "warn" or "text-3")
	if #lines == 0 and sel then c.flags:SetText(L["COUNCIL_FLAGS_NONE"]) end
	c.votes:SetText(SB().VoteText(board.votes))
	local CheatS = ns.CheatService
	local cheat = CheatS and board.cheat and (board.cheat.amount or 0) > 0 and CheatS:CanPenalize() and board.cheat or nil
	c.penalize:SetShown(cheat ~= nil)
	if cheat then c.penalize:SetLabel(CheatS:Label(cheat)) end
	-- the vote
	local open = cs:CanVote(board)
	Theme.GlowShow(c.glow, open)
	Theme.Tint(c.parts.ring, open and "neon" or "border-subtle")
	local mine = board.votes and board.votes.voters and board.votes.voters[me() or ""] or nil
	c.choices:SetChoices(open and voteChoices(board) or {})
	if mine then c.choices:Select(mine) end
	if not member then
		c.voteHint:SetText(L["COUNCIL_VOTE_NOT_MEMBER"])
	elseif not open then
		c.voteHint:SetText(L["COUNCIL_VOTE_NO_VOTE"])
	elseif mine then
		c.voteHint:SetText(L["COUNCIL_VOTE_MINE"]:format(short(mine)))
	else
		c.voteHint:SetText("")
	end
	enable(c.vote, member and open)
	local a = board.actions or {}
	enable(c.modify, board.host and a.modify == true)
	enable(c.correct, board.host and a.correct == true)
end

local function paintAwards(self)
	local a = self.awards
	local list = CS():Voidable()
	local found
	for _, r in ipairs(list) do if r.id == self.awardSel then found = r end end
	found = found or list[1]
	self.awardSel = found and found.id or nil
	a.table:SetData(list)
	enable(a.void, found ~= nil)
end

local function paintAudit(self)
	local list = CS():Audit()
	local rows = {}
	for i = #list, 1, -1 do rows[#rows + 1] = { text = CS().AuditLine(list[i]), voided = list[i].voided } end
	self.audit.table:SetData(rows)
end

-- locale-key: LEGENDARY_MODE LEGENDARY_MODE_COUNCIL LEGENDARY_MODE_VOTE LEGENDARY_MODE_ROLL LEGENDARY_MODE_QUEUE
local function paintLegendary(self)
	local g = self.legendary
	local rules = LS():Rules()
	g.mode:SetText(L["LEGENDARY_MODE"]:format(L["LEGENDARY_MODE_" .. tostring(rules.mode):upper()], num(rules.chainPieceCost)))
	local list = LS():Projects()
	local found
	for _, p in ipairs(list) do if p.id == self.projectSel then found = p end end
	found = found or list[1]
	self.projectSel = found and found.id or nil
	g.table:SetData(list)
	enable(g.complete, found ~= nil and found.open)
	enable(g.abandon, found ~= nil and found.open)
end

function CouncilWindow:Refresh()
	local root = self.root
	if not root or not root:IsVisible() then return end
	local board = SC() and SC():Board(ML() and ML().selected or nil) or nil
	self.board = board
	root.status:SetText(statusLine())
	paintTable(self, board)
	local view = root.view:Active()
	if view == "awards" then paintAwards(self) elseif view == "audit" then paintAudit(self) else paintLegendary(self) end
end

---------------------------------------------------------------------------------------------------------------------
-- Actions

-- The member's vote: the chosen name goes to the council service (the master looter sees it before confirming).
function CouncilWindow:OnVote()
	local choice = self.card.choices:Selected()
	if not choice then return self:SetMessage(SB().ErrorText("BAD_CHOICE"), true) end
	local ok, code = CS():Vote(choice)
	if not ok then return self:SetMessage(L["COUNCIL_REFUSED"]:format(SB().ErrorText(code)), true) end
	self:SetMessage(L["COUNCIL_VOTED"]:format(short(choice)))
	self:Refresh()
end

-- Modify / Correct: the Session tab's reason dialogs (the master looter's commands), opened from here.
function CouncilWindow:OnIntervene(mode)
	local ml = ML()
	if not ml or not ml.root then return false end
	local board = self.board
	if not board or not board.host or not (board.actions and board.actions[mode]) then return false end
	ml.root.sub:Select("session")
	return ml:OpenDialog(mode)
end

-- Complete or abandon the selected project.
function CouncilWindow:OnClose(outcome)
	local id = self.projectSel
	if not id then return false end
	local e, code = LS():Close(id, outcome)
	if not e then self:SetMessage(L["LEGENDARY_REFUSED"]:format(SB().ErrorText(code)), true); return false end
	self:SetMessage(L["LEGENDARY_CLOSED"]:format(self:ProjectName(id), ns.Reasons.Text("OUTCOME", outcome)))
	self:Refresh()
	return true
end

function CouncilWindow:ProjectName(id)
	for _, p in ipairs(LS():Projects()) do if p.id == id then return p.name end end
	return "?"
end

---------------------------------------------------------------------------------------------------------------------
-- The dialog: cancel an award, adjust credits and open a project share one card

local function label(card, x, y)
	local fs = Theme.NewText(card, "Eyebrow", "accent-text")
	fs:SetPoint("TOPLEFT", card, "TOPLEFT", x, y)
	return fs
end

local function place(widget, card, x, y)
	widget:ClearAllPoints()
	widget:SetPoint("TOPLEFT", card, "TOPLEFT", x, y)
end

-- locale-key: ML_DLG_SAVE ML_DLG_CANCEL
function CouncilWindow:BuildDialog()
	if self.dlg then return self.dlg end
	local d = {}
	d.frame = Widgets.Dialog(self.frame, "FDCPCouncilDialog", { width = 620, height = 520 })
	local card = d.frame.card
	d.card = card
	d.title = Theme.NewText(card, "H1", "text-1")
	d.title:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -20)
	d.hint = Theme.NewText(card, "Small", "text-2")
	d.hint:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -6)
	d.hint:SetWidth(572)
	d.hint:SetJustifyH("LEFT")
	d.listLabel = label(card, 24, -84)
	d.list = Widgets.ChoiceList(card, { rows = 6, width = 272 })
	place(d.list, card, 24, -102)
	d.reasonLabel = label(card, 324, -84)
	d.reasons = Widgets.ChoiceList(card, { rows = 6, width = 272 })
	place(d.reasons, card, 324, -102)
	d.aLabel = label(card, 24, -268)
	d.a = Widgets.EditBox(card, { width = 272, maxLetters = 40 })
	place(d.a, card, 24, -286)
	d.bLabel = label(card, 324, -268)
	d.b = Widgets.EditBox(card, { width = 272, maxLetters = 120 })
	place(d.b, card, 324, -286)
	d.cLabel = label(card, 24, -326)
	d.c = Widgets.EditBox(card, { width = 572, maxLetters = 250 })
	place(d.c, card, 24, -344)
	d.dLabel = label(card, 24, -384)
	d.d = Widgets.EditBox(card, { width = 572, maxLetters = 250 })
	place(d.d, card, 24, -402)
	d.error = Theme.NewText(card, "Small", "warn")
	d.error:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24, 28)
	d.error:SetWidth(380)
	d.error:SetJustifyH("LEFT")
	d.save = Widgets.Button(card, { text = L["ML_DLG_SAVE"], style = "primary", width = 130, height = 36,
		onClick = function() CouncilWindow:DialogSave() end })
	d.save:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -24, 20)
	d.cancel = Widgets.Button(card, { text = L["ML_DLG_CANCEL"], style = "secondary", width = 100, height = 36,
		onClick = function() d.frame:Close() end })
	d.cancel:SetPoint("RIGHT", d.save, "LEFT", -8, 0)
	self.dlg = d
	return d
end

local function reasonChoices(order)
	local out = {}
	for _, code in ipairs(order) do out[#out + 1] = { id = code, text = ns.Reasons.Text("CORRECTION", code) } end
	return out
end

local function show(d, names, on)
	for _, n in ipairs(names) do d[n]:SetShown(on) end
end

-- Opens the dialog: "void" (the selected award), "adjust" (a member's credits) or "project" (a new legendary project).
-- locale-key: COUNCIL_DLG_VOID_TITLE COUNCIL_DLG_VOID_HINT COUNCIL_DLG_ADJUST_TITLE COUNCIL_DLG_ADJUST_HINT
-- locale-key: COUNCIL_DLG_PROJECT_TITLE COUNCIL_DLG_PROJECT_HINT COUNCIL_DLG_MEMBER COUNCIL_DLG_DELTA COUNCIL_DLG_NAME
-- locale-key: COUNCIL_DLG_FINAL COUNCIL_DLG_PIECES COUNCIL_DLG_BUILDER COUNCIL_DLG_QUEUE COUNCIL_DLG_NO_BUILDER ML_DLG_REASON
function CouncilWindow:OpenDialog(mode)
	if not self.root then return false end
	local d = self:BuildDialog()
	local card = d.card
	local award
	if mode == "void" then
		for _, r in ipairs(CS():Voidable()) do if r.id == self.awardSel then award = r end end
		if not award then return false end
	elseif mode ~= "adjust" and mode ~= "project" then
		return false
	end
	d.mode, d.award = mode, award
	d.error:SetText("")
	d.list:Clear(); d.reasons:Clear()
	for _, key in ipairs({ "a", "b", "c", "d" }) do
		d[key].edit:ClearFocus()
		d[key]:SetText("")
	end
	show(d, { "list", "listLabel", "reasons", "reasonLabel", "a", "aLabel", "b", "bLabel", "c", "cLabel", "d", "dLabel" }, false)
	d.reasonLabel:SetText(L["ML_DLG_REASON"]:upper())
	if mode == "void" then
		d.title:SetText(L["COUNCIL_DLG_VOID_TITLE"])
		d.hint:SetText(L["COUNCIL_DLG_VOID_HINT"]:format(itemName(award.item), short(award.member), SB().CreditsText(award.cost)))
		d.reasons:SetChoices(reasonChoices(ns.Council.VOID_ORDER))
		place(d.reasons, card, 24, -102); place(d.reasonLabel, card, 24, -84)
		show(d, { "reasons", "reasonLabel" }, true)
	elseif mode == "adjust" then
		d.title:SetText(L["COUNCIL_DLG_ADJUST_TITLE"])
		d.hint:SetText(L["COUNCIL_DLG_ADJUST_HINT"])
		d.listLabel:SetText(L["COUNCIL_DLG_MEMBER"]:upper())
		local list = {}
		for _, name in ipairs(CS():Pool()) do list[#list + 1] = { id = name, text = short(name) } end
		d.list:SetChoices(list)
		d.aLabel:SetText(L["COUNCIL_DLG_DELTA"]:upper())
		d.reasons:SetChoices(reasonChoices(ns.Council.ADJUST_ORDER))
		place(d.reasons, card, 324, -102); place(d.reasonLabel, card, 324, -84)
		show(d, { "list", "listLabel", "reasons", "reasonLabel", "a", "aLabel" }, true)
	else
		d.title:SetText(L["COUNCIL_DLG_PROJECT_TITLE"])
		d.hint:SetText(L["COUNCIL_DLG_PROJECT_HINT"])
		d.listLabel:SetText(L["COUNCIL_DLG_BUILDER"]:upper())
		local list = { { id = "@none", text = L["COUNCIL_DLG_NO_BUILDER"], token = "text-3" } }
		for _, name in ipairs(CS():Pool()) do list[#list + 1] = { id = name, text = short(name) } end
		d.list:SetChoices(list)
		d.list:Select("@none")
		d.aLabel:SetText(L["COUNCIL_DLG_NAME"]:upper())
		d.bLabel:SetText(L["COUNCIL_DLG_FINAL"]:upper())
		d.cLabel:SetText(L["COUNCIL_DLG_PIECES"]:upper())
		d.dLabel:SetText(L["COUNCIL_DLG_QUEUE"]:upper())
		show(d, { "list", "listLabel", "a", "aLabel", "b", "bLabel", "c", "cLabel", "d", "dLabel" }, true)
	end
	d.frame:Open()
	return true
end

function CouncilWindow:CloseDialog()
	if self.dlg then self.dlg.frame:Close() end
end

function CouncilWindow:DialogOpen() return self.dlg ~= nil and self.dlg.frame:IsShown() end

-- "−2", "+1,5", "3" -> a number, or nil.
local function parseDelta(text)
	text = (text or ""):gsub("%s", ""):gsub(",", "."):gsub("\226\136\146", "-")
	if text == "" then return nil end
	local n = tonumber(text)
	if not n or n ~= n then return nil end
	return n
end
CouncilWindow.ParseDelta = parseDelta

local function trim(text) return ((text or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- Save: every refusal of the services (a missing reason, the rank, the season, a bad item) is shown in the dialog.
-- locale-key: COUNCIL_VOIDED COUNCIL_ADJUSTED LEGENDARY_OPENED
function CouncilWindow:DialogSave()
	local d = self.dlg
	if not d or not d.frame:IsShown() then return end
	local function fail(code)
		d.error:SetText(SB().ErrorText(code))
		return false, code
	end
	if d.mode == "void" then
		local reason = d.reasons:Selected()
		if not reason then return fail("REASON_REQUIRED") end
		local e, code = CS():Void(d.award.id, reason)
		if not e then return fail(code) end
		d.frame:Close()
		self:SetMessage(L["COUNCIL_VOIDED"]:format(itemName(d.award.item), short(d.award.member)))
		self:Refresh()
		return true
	elseif d.mode == "adjust" then
		local member = d.list:Selected()
		if not member then return fail("NOT_MEMBER") end
		local delta = parseDelta(d.a:GetText())
		if not delta then return fail("BAD_DELTA") end
		local reason = d.reasons:Selected()
		if not reason then return fail("REASON_REQUIRED") end
		local e, code = CS():Adjust(member, delta, reason)
		if not e then return fail(code) end
		d.frame:Close()
		self:SetMessage(L["COUNCIL_ADJUSTED"]:format(short(member), num(delta), ns.Reasons.Text("CORRECTION", reason)))
		self:Refresh()
		return true
	elseif d.mode == "project" then
		local final = LS().ParseItems(d.b:GetText())
		if #final ~= 1 then return fail("BAD_ITEM") end
		local builder = d.list:Selected()
		if builder == "@none" then builder = nil end
		local queue
		local names = trim(d.d:GetText())
		if names ~= "" then
			queue = {}
			for name in names:gmatch("[^%s,;]+") do queue[#queue + 1] = name end
		end
		local e, code = LS():Open({ name = trim(d.a:GetText()), item = final[1], pieces = LS().ParseItems(d.c:GetText()),
			builder = builder, queue = queue })
		if not e then return fail(code) end
		d.frame:Close()
		self.projectSel = e.id
		local who = e.payload.builder and short(e.payload.builder) or L["LEGENDARY_NOBODY"]
		self:SetMessage(L["LEGENDARY_OPENED"]:format(e.payload.name, ML() and ML().ItemName(e.payload.item,
			ML():ItemInfo(e.payload.item)) or tostring(e.payload.item), who))
		self:Refresh()
		return true
	end
	return false, "MODE"
end

-- Shift-clicking an item link while the final item or the chain pieces field has the keyboard writes the link in it (the
-- game's own function does the same for the chat box; the hook only reads it). Returns true when a field took it.
function CouncilWindow.InsertLink(text)
	local d = CouncilWindow.dlg
	if not d or d.mode ~= "project" or not d.frame:IsShown() or type(text) ~= "string" then return false end
	for _, key in ipairs({ "b", "c" }) do
		local box = d[key]
		if box.edit:HasFocus() then
			local now = box:GetText()
			box:SetText(now == "" and text or (now .. " " .. text))
			return true
		end
	end
	return false
end

if type(_G.hooksecurefunc) == "function" and type(_G.ChatEdit_InsertLink) == "function" then
	_G.hooksecurefunc("ChatEdit_InsertLink", function(text) CouncilWindow.InsertLink(text) end)
end

---------------------------------------------------------------------------------------------------------------------
-- Events

if ns.Bus then
	for _, ev in ipairs({ "SESSION_CHANGED", "SESSION_STARTED", "SESSION_HELD", "SESSION_VIEW", "COUNCIL_CORRECTED",
		"LEGENDARY_CHANGED", "GUILD_KEY_CHANGED", "ROSTER_UPDATED", "THEME_CHANGED" }) do
		ns.Bus:On(ev, function() CouncilWindow:Refresh() end, CouncilWindow)
	end
end
