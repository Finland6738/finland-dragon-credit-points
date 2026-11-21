-- ProgressWindow: the Progress tab (docs/ANALISI.md §9.3 point 5, docs/specs/ui-style.md §3, §6, M3-8b), as the community site's
-- progress section: one card per instance of Data/Instances.lua (the cover from the Encounter Journal when the client has
-- one, a generated cover otherwise; the size eyebrow and the name in the display font), a `kills/total` thin bar per
-- guild key, the bosses in two columns with index, name, a skull or a dashed circle and the date of the first kill per
-- key, and the legend. The numbers come from App/ProgressController.lua (Domain/Progress.lua, the ledger); the other
-- guild's column shows only what an officer entered with PROGRESS_SET. An officer with `progress.edit` clicks a boss row
-- to enter, correct or remove a date. Lua 5.1; unprotected frames.
local ADDON_NAME, ns = ...
ns = ns or {}
local ProgressWindow = {}
ns.ProgressWindow = ProgressWindow
if ns.addon then ns.addon.ProgressWindow = ProgressWindow end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L

ProgressWindow.COVER_H = 96
ProgressWindow.ROW_H = 26
ProgressWindow.GAP = 12

local function PC() return ns.ProgressController end

-- "2026-10-14" -> "14/10/26"
local function shortDate(d)
	local y, m, dd = tostring(d or ""):match("^(%d+)%-(%d+)%-(%d+)$")
	return y and ("%s/%s/%s"):format(dd, m, y:sub(-2)) or ""
end
ProgressWindow.ShortDate = shortDate

-- The message of a refused action.
-- locale-key: PROGRESS_ERR_DATE PROGRESS_ERR_FUTURE PROGRESS_ERR_UNCHANGED PROGRESS_ERR_NOTHING_TO_CLEAR
-- locale-key: PROGRESS_ERR_UNKNOWN_ENCOUNTER PROGRESS_ERR_NO_FACTION
function ProgressWindow.ErrorText(code)
	local key = "PROGRESS_ERR_" .. tostring(code):upper()
	if L[key] ~= key then return L[key] end
	return ns.NightsWindow.ErrorText(code)
end

-- Whether the player may enter or correct a first kill.
function ProgressWindow:CanEdit()
	local nc = ns.NightController
	if not (nc and nc.Can) then return false end
	return nc:Can("progress.edit") == true
end

---------------------------------------------------------------------------------------------------------------------
-- Build

-- The cover of a card: the journal's image when the client has one, else a generated one (a dark base, a radial glow in
-- the accent colour); a dark gradient on the bottom for the name; the corners masked as the card's.
local function coverArt(card, inst)
	local cover = ns.Compat.Encounter.JournalInstanceCover(inst.journalInstanceID)
	local art = card.cover
	if cover then
		art:SetTexture(cover)
		art:SetVertexColor(1, 1, 1, 1)
		card.glow:Hide()
	else
		Theme.Fill(art, "surface-3")
		card.glow:Show()
	end
	card.hasCover = cover ~= nil
end

function ProgressWindow:Card(slug)
	local root = self.root
	local card = root.cards[slug]
	if card then return card end
	card = Widgets.Card(root.content, { height = 200 })
	card.cover = card:CreateTexture(nil, "ARTWORK")
	card.cover:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
	card.cover:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -1)
	card.cover:SetHeight(self.COVER_H)
	card.glow = card:CreateTexture(nil, "ARTWORK", nil, 1)
	card.glow:SetTexture(ns.Assets.textures.blob_radial.path)
	Theme.Tint(card.glow, "accent", 0.35)
	card.glow:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
	card.glow:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -1)
	card.glow:SetHeight(self.COVER_H)
	card.shade = card:CreateTexture(nil, "ARTWORK", nil, 2)
	Theme.Fill(card.shade, "surface-1")
	Theme.Call(card.shade, function(region)
		if region.SetGradient and CreateColor then
			local r, g, b = Theme.Color("surface-1")
			region:SetGradient("VERTICAL", CreateColor(r, g, b, 0.95), CreateColor(r, g, b, 0))
		end
	end)
	card.shade:SetPoint("BOTTOMLEFT", card.cover, "BOTTOMLEFT", 0, 0)
	card.shade:SetPoint("BOTTOMRIGHT", card.cover, "BOTTOMRIGHT", 0, 0)
	card.shade:SetHeight(self.COVER_H * 0.7)
	-- the corners of the cover follow the card's radius (a mask; the client may refuse it, the cover is then square)
	if card.CreateMaskTexture then
		local ok = pcall(function()
			local mask = card:CreateMaskTexture()
			mask:SetTexture(ns.Assets.textures.rr_fill_18.path)
			mask:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
			mask:SetPoint("BOTTOMRIGHT", card, "TOPRIGHT", -1, -1 - self.COVER_H - 40)
			card.cover:AddMaskTexture(mask)
			card.glow:AddMaskTexture(mask)
			card.shade:AddMaskTexture(mask)
			card.mask = mask
		end)
		card.masked = ok
	end
	card.eyebrow = Theme.NewText(card, "Eyebrow", "accent-text")
	card.eyebrow:SetPoint("BOTTOMLEFT", card.cover, "BOTTOMLEFT", 20, 40)
	card.name = Theme.NewText(card, "H1", "text-1")
	card.name:SetPoint("BOTTOMLEFT", card.cover, "BOTTOMLEFT", 20, 12)
	card.bars = {}
	card.rows = {}
	root.cards[slug] = card
	return card
end

-- A bar of a key (the guild's name, the kills, the thin bar).
local function keyBar(card, i)
	local b = card.bars[i]
	if b then return b end
	b = {}
	b.label = Theme.NewText(card, "Small", "text-2")
	b.count = Theme.NewText(card, "Mono", "text-1")
	b.bar = Widgets.ThinBar(card, { height = 4 })
	card.bars[i] = b
	return b
end

-- A boss row: index, name, per key a skull or a dashed circle and the date; a button over it for the officers.
local function bossRow(card, i, nkeys)
	local r = card.rows[i]
	if not r then
		r = CreateFrame("Button", nil, card)
		r.index = Theme.NewText(r, "Mono", "text-3")
		r.index:SetPoint("LEFT", r, "LEFT", 0, 0)
		r.name = Theme.NewText(r, "Body", "text-1")
		r.name:SetPoint("LEFT", r, "LEFT", 26, 0)
		r.keys = {}
		r.hover = r:CreateTexture(nil, "BACKGROUND")
		Theme.Fill(r.hover, "surface-2")
		r.hover:SetAllPoints(r)
		r.hover:Hide()
		r:SetScript("OnEnter", function(self) if ProgressWindow:CanEdit() then self.hover:Show() end end)
		r:SetScript("OnLeave", function(self) self.hover:Hide() end)
		r:SetScript("OnClick", function(self)
			if self.boss and ProgressWindow:CanEdit() then ProgressWindow:OpenEditor(self.boss) end
		end)
		card.rows[i] = r
	end
	for k = #r.keys + 1, nkeys do
		local cell = {}
		cell.icon = r:CreateTexture(nil, "ARTWORK")
		cell.icon:SetSize(14, 14)
		cell.icon:SetTexture(ns.Assets.textures.icons.path)
		cell.date = Theme.NewText(r, "Mono", "text-2")
		r.keys[k] = cell
	end
	return r
end

local ICON_KILLED, ICON_OPEN = "skull", "dashed"

function ProgressWindow:Build(page)
	if self.root then return self.root end
	local root = CreateFrame("Frame", nil, page)
	root:SetAllPoints(page)
	self.root, self.page = root, page
	root.cards = {}
	root.eyebrow = Theme.NewText(root, "Eyebrow", "accent-text")
	root.eyebrow:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -12)
	root.eyebrow:SetText(L["PROGRESS_EYEBROW"]:upper())
	root.title = Theme.NewText(root, "H1", "text-1")
	root.title:SetPoint("TOPLEFT", root.eyebrow, "BOTTOMLEFT", 0, -6)
	root.title:SetText(L["TAB_PROGRESS"])
	root.hint = Theme.NewText(root, "Small", "text-2")
	root.hint:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -18)
	-- the legend
	root.legend = {}
	local lx = 0
	for i, def in ipairs({ { ICON_KILLED, "PROGRESS_LEGEND_KILLED" }, { ICON_OPEN, "PROGRESS_LEGEND_OPEN" } }) do
		local icon = root:CreateTexture(nil, "ARTWORK")
		icon:SetSize(14, 14)
		icon:SetTexture(ns.Assets.textures.icons.path)
		icon:SetTexCoord(ns.Assets.IconCoords(def[1]))
		Theme.Tint(icon, i == 1 and "accent-text" or "text-3")
		icon:SetPoint("TOPLEFT", root, "TOPLEFT", lx, -84)
		local fs = Theme.NewText(root, "Small", "text-2")
		fs:SetPoint("LEFT", icon, "RIGHT", 6, 0)
		fs:SetText(L[def[2]])
		root.legend[i] = { icon = icon, text = fs }
		lx = lx + 150
	end
	root.empty = Theme.NewText(root, "Body", "text-3")
	root.empty:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -116)
	-- the scrolling area: a clipped view and a content frame moved by the wheel
	root.view = CreateFrame("Frame", nil, root)
	root.view:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -108)
	root.view:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
	root.view:SetClipsChildren(true)
	root.view:EnableMouseWheel(true)
	root.view:SetScript("OnMouseWheel", function(_, delta) ProgressWindow:Scroll(-delta * 40) end)
	root.content = CreateFrame("Frame", nil, root.view)
	root.content:SetPoint("TOPLEFT", root.view, "TOPLEFT", 0, 0)
	root.content:SetPoint("TOPRIGHT", root.view, "TOPRIGHT", 0, 0)
	root.content:SetHeight(10)
	root.offset = 0
	root:SetScript("OnSizeChanged", function() ProgressWindow:Layout() end)
	self:Refresh()
	return root
end

function ProgressWindow:Scroll(dy)
	local root = self.root
	if not root then return end
	local viewH = root.view:GetHeight() or 0
	if viewH <= 1 then viewH = 440 end
	local max = math.max((root.contentH or 0) - viewH, 0)
	root.offset = math.min(math.max((root.offset or 0) + dy, 0), max)
	root.content:ClearAllPoints()
	root.content:SetPoint("TOPLEFT", root.view, "TOPLEFT", 0, root.offset)
	root.content:SetPoint("TOPRIGHT", root.view, "TOPRIGHT", 0, root.offset)
end

-- Lays the cards one under the other and sets the content's height.
function ProgressWindow:Layout()
	local root = self.root
	if not root or not root.order then return end
	local y = 0
	for _, slug in ipairs(root.order) do
		local card = root.cards[slug]
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", root.content, "TOPLEFT", 0, -y)
		card:SetPoint("TOPRIGHT", root.content, "TOPRIGHT", 0, -y)
		y = y + (card.fullH or 200) + self.GAP
	end
	root.contentH = y
	root.content:SetHeight(math.max(y, 10))
	self:Scroll(0)
end

-- The width of the card's body (the page's, with the card's padding).
local function bodyWidth(card)
	local w = card:GetWidth()
	if not w or w < 300 then w = 700 end
	return w
end

function ProgressWindow:Fill(card, inst, keys, own)
	local half = (bodyWidth(card) - 56) / 2
	card.name:SetText(inst.localName or inst.name)
	card.eyebrow:SetText(L["PROGRESS_SIZE"]:format(inst.size))
	coverArt(card, inst)
	-- one bar per key, side by side under the cover
	local barTop = -(self.COVER_H + 14)
	local nk = #keys
	local colW = (bodyWidth(card) - 40 - (nk - 1) * 24) / math.max(nk, 1)
	for i, key in ipairs(keys) do
		local b = keyBar(card, i)
		local x = 20 + (i - 1) * (colW + 24)
		b.label:ClearAllPoints(); b.label:SetPoint("TOPLEFT", card, "TOPLEFT", x, barTop)
		b.label:SetText(key)
		Theme.Text(b.label, key == own and "accent-text" or "text-2")
		b.count:ClearAllPoints(); b.count:SetPoint("TOPRIGHT", card, "TOPLEFT", x + colW, barTop)
		local n = inst.counts[key] or 0
		b.count:SetText(L["PROGRESS_KILLS"]:format(n, inst.total))
		b.bar:ClearAllPoints()
		b.bar:SetPoint("TOPLEFT", card, "TOPLEFT", x, barTop - 18)
		b.bar:SetWidth(colW)
		b.bar:SetFraction(inst.total > 0 and n / inst.total or 0)
		b.label:Show(); b.count:Show(); b.bar:Show()
	end
	for i = nk + 1, #card.bars do
		local b = card.bars[i]
		b.label:Hide(); b.count:Hide(); b.bar:Hide()
	end
	-- the bosses in two columns, the first half on the left
	local perCol = math.ceil(#inst.bosses / 2)
	local top = barTop - 44
	local cellW = 84
	for i, boss in ipairs(inst.bosses) do
		local r = bossRow(card, i, nk)
		local col = i <= perCol and 0 or 1
		local line = (i - 1) % perCol
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", card, "TOPLEFT", 20 + col * (half + 16), top - line * self.ROW_H)
		r:SetSize(half, self.ROW_H)
		r.boss = boss
		r.index:SetText(("%02d"):format(boss.index))
		r.name:SetText(boss.localName or boss.name)
		r.name:SetWidth(math.max(half - 26 - nk * cellW, 60))
		for k = 1, #r.keys do
			local cell = r.keys[k]
			local key = keys[k]
			if key then
				local f = boss.first[key]
				cell.icon:ClearAllPoints()
				cell.icon:SetPoint("RIGHT", r, "RIGHT", -(nk - k) * cellW - 62, 0)
				cell.date:ClearAllPoints()
				cell.date:SetPoint("LEFT", cell.icon, "RIGHT", 6, 0)
				cell.icon:SetTexCoord(ns.Assets.IconCoords(f and ICON_KILLED or ICON_OPEN))
				Theme.Tint(cell.icon, f and "accent-text" or "text-3")
				cell.date:SetText(f and shortDate(f.date) or "")
				cell.icon:Show(); cell.date:Show()
				cell.killed = f and true or false
			else
				cell.icon:Hide(); cell.date:Hide()
			end
		end
		r:Show()
	end
	for i = #inst.bosses + 1, #card.rows do card.rows[i]:Hide() end
	card.fullH = self.COVER_H + 14 + 44 + perCol * self.ROW_H + 18
	card:SetHeight(card.fullH)
end

function ProgressWindow:Refresh()
	local root = self.root
	if not root then return end
	local pc = PC()
	local data, why = pc and pc:Build()
	for _, c in pairs(root.cards) do c:Hide() end
	root.order = {}
	root.data = data
	root.hint:SetText(L[self:CanEdit() and "PROGRESS_HINT_EDIT" or "PROGRESS_HINT_READ"])
	if not data then
		root.empty:SetText(L["ROSTER_NOT_READY"])
		return
	end
	root.empty:SetText("")
	for _, inst in ipairs(data.instances) do
		local card = self:Card(inst.slug)
		root.order[#root.order + 1] = inst.slug
		card:Show()
		card:SetHeight(200)
		self:Fill(card, inst, data.keys, data.own)
		card.instance = inst
	end
	self:Layout()
end

---------------------------------------------------------------------------------------------------------------------
-- The editor of a first kill (officers with progress.edit)

function ProgressWindow:Editor()
	if self.dialog then return self.dialog end
	local d = Widgets.Dialog(self.root, "FDCPProgressEditor", { width = 440, height = 250 })
	local c = d.card
	d.title = Theme.NewText(c, "H2", "text-1")
	d.title:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -20)
	d.guildLabel = Theme.NewText(c, "Small", "text-2")
	d.guildLabel:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -58)
	d.guildLabel:SetText(L["PROGRESS_EDIT_GUILD"])
	d.dateLabel = Theme.NewText(c, "Small", "text-2")
	d.dateLabel:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -108)
	d.dateLabel:SetText(L["PROGRESS_EDIT_DATE"])
	d.edit = CreateFrame("EditBox", nil, c)
	d.edit:SetSize(200, 26)
	d.edit:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -128)
	d.edit:SetAutoFocus(false)
	d.edit:SetMaxLetters(10)
	d.edit:SetFontObject(Theme.Font("Mono"))
	d.edit:SetScript("OnEscapePressed", function() d:Close() end)
	d.status = Theme.NewText(c, "Small", "err")
	d.status:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -164)
	d.save = Widgets.Button(c, { text = L["PROGRESS_SAVE"], style = "primary", width = 100, height = 30,
		onClick = function() ProgressWindow:Save() end })
	d.save:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -20, 20)
	d.cancel = Widgets.Button(c, { text = L["PROGRESS_CANCEL"], style = "ghost", width = 100, height = 30,
		onClick = function() d:Close() end })
	d.cancel:SetPoint("RIGHT", d.save, "LEFT", -8, 0)
	d.clear = Widgets.Button(c, { text = L["PROGRESS_CLEAR"], style = "ghost", width = 170, height = 30,
		onClick = function() ProgressWindow:Remove() end })
	d.clear:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 20, 20)
	self.dialog = d
	return d
end

-- Opens the editor for a boss of the Build table; the date starts with the guild's current first kill.
function ProgressWindow:OpenEditor(boss)
	if not self:CanEdit() then return false end
	local root, d = self.root, self:Editor()
	local keys = root.data and root.data.keys or {}
	local items = {}
	for _, k in ipairs(keys) do items[#items + 1] = { id = k, text = k } end
	if d.seg then d.seg:Hide() end
	d.seg = Widgets.Segmented(d.card, items, function(id) ProgressWindow:PickKey(id) end)
	d.seg:SetPoint("TOPLEFT", d.card, "TOPLEFT", 20, -76)
	d.boss = boss
	d.title:SetText(L["PROGRESS_EDIT_TITLE"]:format(boss.localName or boss.name))
	d.status:SetText("")
	self:PickKey(root.data.own or keys[1])
	d:Open()
	return true
end

function ProgressWindow:PickKey(key)
	local d = self.dialog
	if not d then return end
	d.key = key
	if d.seg then d.seg:Select(key) end
	local f = d.boss and d.boss.first[key]
	d.edit:SetText(f and f.date or "")
	d.status:SetText("")
end

function ProgressWindow:Save()
	local d = self.dialog
	if not d or not d.boss then return nil, "NOT_READY" end
	local own = self.root.data and self.root.data.own
	local event, why = PC():Set(d.boss.encounterID, d.edit:GetText(), d.key ~= own and d.key or nil)
	if not event then
		d.status:SetText(self.ErrorText(why))
		return nil, why
	end
	d:Close()
	return event
end

function ProgressWindow:Remove()
	local d = self.dialog
	if not d or not d.boss then return nil, "NOT_READY" end
	local own = self.root.data and self.root.data.own
	local event, why = PC():Clear(d.boss.encounterID, d.key ~= own and d.key or nil)
	if not event then
		d.status:SetText(self.ErrorText(why))
		return nil, why
	end
	d:Close()
	return event
end

if ns.Bus then
	for _, ev in ipairs({ "PROGRESS_CHANGED", "PROGRESS_KILL_RECORDED", "ROSTER_UPDATED", "GUILD_RANKS_READY", "GUILD_KEY_CHANGED",
			"NIGHT_OPENED", "NIGHT_CLOSED" }) do
		ns.Bus:On(ev, function() ProgressWindow:Refresh() end, ProgressWindow)
	end
end
