-- NightsWindow: the Roster > Night sub-tab (docs/ANALISI.md §2, §6, §9.3, docs/specs/ui-style.md §6, M3-7): open and close the
-- official night, the lineup in three columns (raid, bench, absent), the proposed bench of Domain/Rotation.lua that the
-- master looter applies, and the attendance per member **for the officers only** (`view.attendance`, §6: a member never
-- sees it, the table is not even built for them to find). Reads and writes through App/NightController.lua. Lua 5.1.
local ADDON_NAME, ns = ...
ns = ns or {}
local NightsWindow = {}
ns.NightsWindow = NightsWindow
if ns.addon then ns.addon.NightsWindow = NightsWindow end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

NightsWindow.LINEUP_ROWS, NightsWindow.ROW_H = 7, 24
NightsWindow.STATES = { "raid", "bench", "absent" }

local function NC() return ns.NightController end
local function short(name) return (tostring(name):gsub("%-.*$", "")) end

-- The message of a refused action.
-- locale-key: NIGHT_ERR_NOT_READY NIGHT_ERR_NO_SEASON NIGHT_ERR_PENDING NIGHT_ERR_NOT_IN_GUILD NIGHT_ERR_RANK_TOO_LOW
-- locale-key: NIGHT_ERR_NOT_IN_PACK NIGHT_ERR_DIFFICULTY NIGHT_ERR_NIGHT_ALREADY_OPEN NIGHT_ERR_NO_NIGHT_OPEN
-- locale-key: NIGHT_ERR_NOT_MEMBER NIGHT_ERR_NO_CHANGE NIGHT_ERR_READ_ONLY NIGHT_ERR_SIZE NIGHT_ERR_NOT_RUNNER NIGHT_ERR_NOT_GM
function NightsWindow.ErrorText(code)
	local key = "NIGHT_ERR_" .. tostring(code)
	if L[key] ~= key then return L[key] end
	return L["NIGHT_ERR_OTHER"]:format(tostring(code))
end

-- locale-key: DIFFICULTY_normal DIFFICULTY_veteran
function NightsWindow.DifficultyName(code) return L["DIFFICULTY_" .. tostring(code)] end

local function instanceName(id)
	local inst = ns.Instances and ns.Instances.Get(id)
	return inst and inst.name or tostring(id)
end
NightsWindow.InstanceName = instanceName

-- The attendance as a list of rows for the table: { name, played, benched, bosses, possible, percent }.
function NightsWindow.AttendanceRows(att)
	local rows = {}
	for name, m in pairs(att and att.members or {}) do
		rows[#rows + 1] = { name = name, played = m.played, benched = m.benched, bosses = m.bosses, possible = m.possible,
			percent = m.possible > 0 and math.floor(m.bosses * 100 / m.possible + 0.5) or 0 }
	end
	table.sort(rows, function(a, b) return a.name < b.name end)
	return rows
end

---------------------------------------------------------------------------------------------------------------------
-- Build

local function lineupRow(col)
	local r = CreateFrame("Frame", nil, col)
	r:SetHeight(NightsWindow.ROW_H)
	r.name = Theme.NewText(r, "BodyMedium", "text-1")
	r.name:SetPoint("LEFT", r, "LEFT", 0, 0)
	r.act = Widgets.Button(r, { text = "", style = "ghost", width = 84, height = 20 })
	r.act:SetPoint("RIGHT", r, "RIGHT", 0, 0)
	r:Hide()
	return r
end

function NightsWindow:Build(pane)
	if self.root then return self.root end
	local root = CreateFrame("Frame", nil, pane)
	root:SetAllPoints(pane)
	self.root = root

	root.eyebrow = Theme.NewText(root, "Eyebrow", "accent-text")
	root.eyebrow:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -4)
	root.eyebrow:SetText(L["NIGHT_TITLE"]:upper())
	root.status = Theme.NewText(root, "MonoMedium", "text-1")
	root.status:SetPoint("TOPLEFT", root.eyebrow, "BOTTOMLEFT", 0, -6)
	root.message = Theme.NewText(root, "Small", "text-2")
	root.message:SetPoint("TOPLEFT", root.status, "BOTTOMLEFT", 0, -6)

	-- the choice of the night to open (while none is open): the pack's instance and the difficulty
	root.pick = CreateFrame("Frame", nil, root)
	root.pick:SetSize(10, 32)
	root.pick:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
	root.diff = Widgets.Segmented(root.pick, {
		{ id = "normal", text = L["DIFFICULTY_normal"] }, { id = "veteran", text = L["DIFFICULTY_veteran"] },
	}, function(id) NightsWindow.difficulty = id end)
	root.diff:SetPoint("RIGHT", root.pick, "RIGHT", 0, 0)
	root.diff:Select("normal")
	NightsWindow.difficulty = "normal"

	root.open = Widgets.Button(root, { text = L["NIGHT_OPEN"], style = "primary", width = 150, onClick = function() NightsWindow:OnOpen() end })
	root.close = Widgets.Button(root, { text = L["NIGHT_CLOSE"], style = "secondary", width = 150, onClick = function() NightsWindow:OnClose() end })
	root.propose = Widgets.Button(root, { text = L["NIGHT_PROPOSE"], style = "secondary", width = 170, onClick = function() NightsWindow:OnPropose() end })
	root.apply = Widgets.Button(root, { text = L["NIGHT_APPLY_BENCH"], style = "neon", width = 170, onClick = function() NightsWindow:OnApply() end })
	root.close:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
	root.open:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -40)
	root.propose:SetPoint("RIGHT", root.close, "LEFT", -8, 0)
	root.apply:SetPoint("RIGHT", root.propose, "LEFT", -8, 0)
	root.instances = {}

	-- the lineup: three columns
	root.cols = {}
	for i, state in ipairs(self.STATES) do
		local col = Widgets.Card(root, { height = self.LINEUP_ROWS * self.ROW_H + 44 })
		col.state, col.offset = state, 0
		col.title = Theme.NewText(col, "Eyebrow", state == "raid" and "ok" or state == "bench" and "warn" or "text-3")
		col.title:SetPoint("TOPLEFT", col, "TOPLEFT", 16, -12)
		col:EnableMouseWheel(true)
		col:SetScript("OnMouseWheel", function(_, delta) NightsWindow:Scroll(state, -delta * 3) end)
		col.rows = {}
		for ri = 1, self.LINEUP_ROWS do
			local r = lineupRow(col)
			r:SetPoint("TOPLEFT", col, "TOPLEFT", 16, -36 - (ri - 1) * self.ROW_H)
			r:SetPoint("TOPRIGHT", col, "TOPRIGHT", -16, -36 - (ri - 1) * self.ROW_H)
			r.act:SetScript("OnClick", function() NightsWindow:OnMove(r.member, state) end)
			col.rows[ri] = r
		end
		root.cols[state] = col
	end

	-- the attendance (officers): built only when the player may see it
	root.attTitle = Theme.NewText(root, "Eyebrow", "accent-text")
	root.attTitle:SetText(L["NIGHT_ATTENDANCE"]:upper())
	root.attTitle:Hide()
	root:SetScript("OnSizeChanged", function() NightsWindow:Layout() end)
	self:Layout()
	return root
end

function NightsWindow:Layout()
	local root = self.root
	if not root then return end
	local width = (root:GetWidth() or 0) > 100 and root:GetWidth() or 920
	local gap = 14
	local w = math.floor((width - gap * 2) / 3)
	for i, state in ipairs(self.STATES) do
		local col = root.cols[state]
		col:SetWidth(w)
		col:ClearAllPoints()
		col:SetPoint("TOPLEFT", root, "TOPLEFT", (i - 1) * (w + gap), -96)
	end
	root.attTitle:ClearAllPoints()
	root.attTitle:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -96 - (self.LINEUP_ROWS * self.ROW_H + 44) - 12)
	if root.table then
		root.table:ClearAllPoints()
		root.table:SetPoint("TOPLEFT", root.attTitle, "BOTTOMLEFT", 0, -6)
		root.table:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
	end
end

-- The table of the attendance, built the first time an officer opens the tab.
function NightsWindow:BuildTable()
	local root = self.root
	if root.table then return root.table end
	local function num(key) return function(d) return d[key] end end
	root.table = Widgets.DataTable(root, {
		{ id = "name", title = L["NIGHT_COL_MEMBER"], flex = 1, text = function(d) return short(d.name) end,
			value = function(d) return d.name:lower() end },
		{ id = "nights", title = L["NIGHT_COL_NIGHTS"], width = 110, align = "RIGHT", mono = true, text = num("played") },
		{ id = "benched", title = L["NIGHT_COL_BENCHED"], width = 110, align = "RIGHT", mono = true, text = num("benched") },
		{ id = "bosses", title = L["NIGHT_COL_BOSSES"], width = 130, align = "RIGHT", mono = true,
			text = function(d) return d.bosses .. "/" .. d.possible end, value = num("bosses") },
		{ id = "percent", title = L["NIGHT_COL_PERCENT"], width = 100, align = "RIGHT", mono = true,
			text = function(d) return L["NIGHT_PERCENT"]:format(d.percent) end, value = num("percent"),
			token = function(d) return d.percent >= 75 and "ok" or d.percent >= 40 and "warn" or "text-2" end },
	}, { rowHeight = 24, pool = 12 })
	root.table:SetEmptyText(L["NIGHT_ATTENDANCE_EMPTY"])
	self:Layout()
	return root.table
end

function NightsWindow:Scroll(state, delta)
	local col = self.root and self.root.cols[state]
	if not col then return end
	col.offset = math.min(math.max(col.offset + delta, 0), math.max((col.total or 0) - self.LINEUP_ROWS, 0))
	self:Refresh()
end

function NightsWindow:SetMessage(text, isError)
	if not self.root then return end
	self.root.message:SetText(text or "")
	Theme.Text(self.root.message, isError and "warn" or "text-2")
end

---------------------------------------------------------------------------------------------------------------------
-- Actions

function NightsWindow:Instance()
	local root = self.root
	return root and root.instanceId
end

function NightsWindow:OnOpen()
	local args = { instanceID = self.instanceId, difficulty = self.difficulty }
	if self.proposal and self.proposal.instanceID == self.instanceId then args.bench = self.proposal.bench end
	local night, code = NC():Open(args)
	if night then
		self.proposal = nil
		self:SetMessage(L["NIGHT_OPENED"])
	else
		self:SetMessage(self.ErrorText(code), true)
	end
	self:Refresh()
end

function NightsWindow:OnClose()
	local night, code = NC():Close()
	if night then self.proposal = nil; self:SetMessage(L["NIGHT_CLOSED"]) else self:SetMessage(self.ErrorText(code), true) end
	self:Refresh()
end

function NightsWindow:OnPropose()
	local p, code = NC():ProposeBench({ instanceID = self.instanceId })
	if not p then
		self.proposal = nil
		self:SetMessage(self.ErrorText(code), true)
	else
		p.instanceID = self.instanceId
		self.proposal = p
		if #p.bench == 0 then
			self:SetMessage(L["NIGHT_PROPOSAL_NONE"])
		else
			local names = {}
			for i, n in ipairs(p.bench) do names[i] = short(n) end
			self:SetMessage(L["NIGHT_PROPOSAL"]:format(#p.bench, table.concat(names, ", ")))
		end
	end
	self:Refresh()
end

function NightsWindow:OnApply()
	local p = self.proposal
	if not p or #p.bench == 0 then return end
	local e, code = NC():ApplyBench(p.bench)
	if e then self.proposal = nil; self:SetMessage(L["NIGHT_BENCH_APPLIED"]) else self:SetMessage(self.ErrorText(code), true) end
	self:Refresh()
end

-- The button of a lineup row: a raider goes to the bench, a benched one back, an absent one into the raid.
function NightsWindow:OnMove(member, from)
	if not member then return end
	local e, code
	if from == "raid" then e, code = NC():Bench(member)
	elseif from == "bench" then e, code = NC():Unbench(member)
	else e, code = NC():SetState(member, "RAID") end
	if not e then self:SetMessage(self.ErrorText(code), true) end
	self:Refresh()
end

---------------------------------------------------------------------------------------------------------------------
-- Draw

-- The instances of the season's pack as chips (rebuilt when the season changes).
function NightsWindow:RefreshPick(season)
	local root = self.root
	local key = season and season.id or ""
	for _, inst in ipairs(season and season.instances or {}) do key = key .. ":" .. inst.id end
	if root.pickKey == key then return end
	root.pickKey = key
	if root.instSeg then root.instSeg:Hide() end
	if not season or #season.instances == 0 then root.instSeg, self.instanceId = nil, nil; return end
	local items = {}
	for _, inst in ipairs(season.instances) do items[#items + 1] = { id = inst.id, text = instanceName(inst.id) } end
	root.instSeg = Widgets.Segmented(root.pick, items, function(id) NightsWindow.instanceId, NightsWindow.proposal = id, nil end)
	root.instSeg:SetPoint("RIGHT", root.diff, "LEFT", -8, 0)
	local inInstance = ns.Compat and ns.Compat.Encounter and ns.Compat.Encounter.Instance()
	local chosen = items[1].id
	for _, it in ipairs(items) do if inInstance and inInstance.instanceID == it.id then chosen = it.id end end
	root.instSeg:Select(chosen)
	self.instanceId = chosen
end

local function fillColumn(col, names, runner, label, offset, rows)
	col.total = #names
	col.offset = math.min(offset, math.max(#names - rows, 0))
	col.title:SetText((col.titleText or ""):upper() .. "  " .. #names)
	for i, row in ipairs(col.rows) do
		local name = names[col.offset + i]
		if name then
			row.member = name
			row.name:SetText(short(name))
			row.act:SetLabel(label)
			row.act:SetShown(runner)
			row:Show()
		else
			row:Hide()
		end
	end
end

function NightsWindow:Refresh()
	local root = self.root
	if not root then return end
	local nc = NC()
	local L_, s = nc:Ledger(), nc:Season()
	local night = nc:Current()
	local mayRun = nc:Can("night.run") == true
	self:RefreshPick(s)

	if not s then
		root.status:SetText(L[L_ and "NIGHT_NO_SEASON" or "NIGHT_NOT_READY"])
	elseif night then
		root.status:SetText(L["NIGHT_STATUS_OPEN"]:format(instanceName(night.instanceID), self.DifficultyName(night.difficulty),
			night.size, night.date))
	else
		root.status:SetText(L["NIGHT_STATUS_NONE"])
	end

	root.open:SetShown(mayRun and s ~= nil and night == nil)
	root.close:SetShown(mayRun and night ~= nil)
	root.pick:SetShown(mayRun and s ~= nil and night == nil and root.instSeg ~= nil)
	root.propose:SetShown(mayRun and s ~= nil)
	root.apply:SetShown(mayRun and self.proposal ~= nil and #self.proposal.bench > 0 and night ~= nil)
	root.propose:ClearAllPoints()
	if night then root.propose:SetPoint("RIGHT", root.close, "LEFT", -8, 0) else root.propose:SetPoint("RIGHT", root.open, "LEFT", -8, 0) end
	root.apply:ClearAllPoints()
	root.apply:SetPoint("RIGHT", root.propose, "LEFT", -8, 0)

	-- the lineup
	-- locale-key: NIGHT_COL_RAID NIGHT_COL_BENCH NIGHT_COL_ABSENT
	local lists = nc:Lineup() or { raid = {}, bench = {}, absent = {} }
	local runner = mayRun and night ~= nil
	local labels = { raid = L["NIGHT_TO_BENCH"], bench = L["NIGHT_TO_RAID"], absent = L["NIGHT_TO_RAID"] }
	for _, state in ipairs(self.STATES) do
		local col = root.cols[state]
		col.titleText = L["NIGHT_COL_" .. state:upper()]
		fillColumn(col, lists[state], runner, labels[state], col.offset, self.LINEUP_ROWS)
	end

	-- the attendance: only who may see it
	local att = nc:Attendance()
	if att then
		self:BuildTable()
		root.attTitle:Show()
		root.table:Show()
		root.table:SetData(self.AttendanceRows(att))
	else
		root.attTitle:Hide()
		if root.table then root.table:Hide() end
	end
end

if ns.Bus then
	for _, ev in ipairs({ "NIGHT_OPENED", "NIGHT_CLOSED", "NIGHT_LINEUP_CHANGED", "NIGHT_ENCOUNTER_RECORDED" }) do
		ns.Bus:On(ev, function() NightsWindow:Refresh() end, NightsWindow)
	end
end
