-- MemberLootPopup: the player's item popup (docs/ANALISI.md §5.1, §6, docs/specs/ui-style.md §3, §6, preview
-- fdcp-roll-popup.webp, M4-6, M7-5c). One card per open round, stackable: icon and name in the quality colour, the slot, the
-- game's own tooltip (with the comparison) on hover, the chip "Weapon · 2 credits", the player's credits and estimated
-- place in the queue, the upgrade badge, the timer bar and three buttons. The popup is a window of its own (not a tab): it
-- opens when a round asks this player something and closes when the round closes. Position and width are remembered per
-- character.
--
-- M7-5c (owner decision of 2026-11-22): the player only chooses with three buttons, Pass, Roll Main-spec and Roll
-- Off-spec. A roll button sends the response and rolls in one click (the roll intent first, M7-2d, then the game's
-- RandomRoll(1, 100)); in a round that does not collect responses (a reroll, a lower tier's turn, a free roll) it only
-- rolls. Everything else is the addon's: there is no label and no note any more, and the upgrade badge ("Medium upgrade ·
-- ilvl +13") is computed from the gear the player wore during the fight (App/UpgradeAdvisor.lua) and goes to the master
-- looter with the answer. An item the character cannot use comes with Pass preselected (nothing is sent by itself).
--
-- It draws what App/PopupBoard.lua gives (the session as this client sees it: Net/Protocol.lua's view) and sends the
-- player's answer back through Protocol.Session:Respond, which only ever sends the player's own response (the master
-- looter takes the name from the sender, §8.4). The roll is the game's: the addon never writes a roll value; the master
-- looter's client reads it from the chat (Adapters/RollListener.lua). With the rule session.buttonRollsOnly the master
-- looter counts a roll only with its intent. A button rolls once per round, rerolls included. Lua 5.1; unprotected frames.
-- Not verified in the real client: how it looks in a raid, the tooltip comparison, RandomRoll from a click.
local ADDON_NAME, ns = ...
ns = ns or {}
local Popup = {}
ns.MemberLootPopup = Popup
if ns.addon then ns.addon.MemberLootPopup = Popup end   -- also reachable from tests

local Theme, Widgets = ns.Theme, ns.Widgets
local L = ns.L
local PB = ns.PopupBoard

Popup.FRAME_NAME = "FDCPLootPopup"
Popup.DEFAULT_W, Popup.MIN_W, Popup.MAX_W = 400, 380, 520
Popup.CARD_GAP = 8
Popup.TICK = 0.25   -- seconds between two redraws of the timer while the popup is on screen
Popup.WARN_SECONDS = 5

-- locale-key: POPUP_HINT_CHOOSE POPUP_HINT_UNUSABLE POPUP_HINT_PASSED POPUP_HINT_LATER POPUP_HINT_ROLL POPUP_HINT_ROLLED POPUP_HINT_REROLL POPUP_HINT_FREE POPUP_HINT_TURN
Popup.HINTS = {
	CHOOSE = "POPUP_HINT_CHOOSE", UNUSABLE = "POPUP_HINT_UNUSABLE", PASSED = "POPUP_HINT_PASSED", LATER = "POPUP_HINT_LATER", ROLL = "POPUP_HINT_ROLL",
	ROLLED = "POPUP_HINT_ROLLED", REROLL = "POPUP_HINT_REROLL", FREE = "POPUP_HINT_FREE", TURN = "POPUP_HINT_TURN",
}

-- The words of the buttons (M7-5c): Pass is the response's own word.
-- locale-key: POPUP_ROLL_MS POPUP_ROLL_OS
Popup.BUTTON_KEYS = { MS = "POPUP_ROLL_MS", OS = "POPUP_ROLL_OS" }
Popup.BUTTON_ORDER = { "PASS", "MS", "OS" }

local function PS() return ns.Protocol and ns.Protocol.Session end
local function me() return ns.GuildRanks and ns.GuildRanks.Me() or nil end
local function now() return ns.Compat.Now() end

local function clock(seconds)
	seconds = math.max(0, math.ceil(tonumber(seconds) or 0))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end
Popup.Clock = clock

-- "2" / "1.5": the credits as a plain number (the ledger rounds to two decimals).
local function number(n) return ("%g"):format(tonumber(n) or 0) end

---------------------------------------------------------------------------------------------------------------------
-- Placement (per character, like the main window)

local function charData() return ns.Config and ns.Config.char end

-- The saved placement: { point, x, y, w } or nil.
function Popup.LoadPlacement()
	local c = charData()
	local p = c and c.popup
	if type(p) ~= "table" or type(p.point) ~= "string" or type(p.x) ~= "number" or type(p.y) ~= "number" then return nil end
	return { point = p.point, x = p.x, y = p.y, w = math.min(Popup.MAX_W, math.max(Popup.MIN_W, tonumber(p.w) or Popup.DEFAULT_W)) }
end

-- Puts the popup back at its starting place and width (Settings > Personal).
function Popup:ResetPlacement()
	local f = self.frame
	self.width = Popup.DEFAULT_W
	if not f then return end
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	f:SetWidth(Popup.DEFAULT_W)
	self:Layout()
end

-- A short chime when the popup appears, unless the player turned the sounds off (Settings > Personal).
Popup.CHIME = 8960   -- the game's "ready check" sound kit
function Popup:Chime()
	if ns.Config and ns.Config.db and ns.Config:Get("sounds") == false then return false end
	local kit = _G.SOUNDKIT and _G.SOUNDKIT.READY_CHECK or Popup.CHIME
	return ns.Compat.Sound.Play(kit)
end

function Popup:SavePlacement()
	local f, c = self.frame, charData()
	if not f or not c then return end
	if ns.Config and ns.Config:IsReadOnly() then return end
	local point, _, _, x, y = f:GetPoint(1)
	if not point then return end
	c.popup = { point = point, x = x, y = y, w = f:GetWidth() }
end

---------------------------------------------------------------------------------------------------------------------
-- Item data

-- What the client knows of an item; a name that is not loaded yet is asked once and the popup redraws when it arrives.
function Popup:ItemInfo(itemID)
	local cache = ns.ItemCache
	if not cache then return {} end
	local entry = cache.Lookup(itemID)
	if (not entry or not entry.loaded) and not (self.asked and self.asked[itemID]) then
		self.asked = self.asked or {}
		self.asked[itemID] = true
		cache.Get(itemID, function() Popup:Refresh() end)
		entry = cache.Lookup(itemID) or entry
	end
	return entry or {}
end

-- "Waist · Cloth · Item level 66": the slot and the kind are the game's own words.
function Popup.ItemLine(info)
	local parts = {}
	local slot = info.equipLoc and _G[info.equipLoc]
	if type(slot) == "string" and slot ~= "" then parts[#parts + 1] = slot end
	local armor = info.classID == 4 and (info.subclassID or 0) > 0 and info.subclassID ~= 5
	if info.subType and info.subType ~= "" and (info.classID == 2 or armor) then parts[#parts + 1] = info.subType end
	if info.level and info.level > 0 then parts[#parts + 1] = L["ML_ITEM_LEVEL"]:format(info.level) end
	return table.concat(parts, " · ")
end

-- "Weapon · 2 credits" (the chip), or "council" when the council prices the item.
function Popup.CostChip(card)
	local cost
	if card.council then cost = L["ML_COST_COUNCIL"] else cost = ns.SessionBoard.CreditsText(card.cost) end
	if card.category and ns.MLSession then return ns.MLSession.CategoryName(card.category) .. " · " .. cost end
	return cost
end

---------------------------------------------------------------------------------------------------------------------
-- Build

local ROW_ITEM, ROW_BADGE, ROW_BUTTONS, ROW_BAR, ROW_HINT = 40, 24, 32, 4, 16
local ROW_VERDICT = 24
local BUTTON_GAP = 8
local PAD = 16

local function buildCard(self, parent)
	local c = CreateFrame("Frame", nil, parent)
	c:SetSize(self.width, 300)
	c.parts = Theme.Panel(c, { radius = 18, fill = "surface-1", border = "border", shadow = true, highlight = true })
	-- the one neon element of the view: a glow behind the top card (docs/specs/ui-style.md §3)
	c.glow = Theme.Glow(c, "glow_l", "neon", { alpha = 0.3 })
	c.glow:SetPoint("TOPLEFT", c, "TOPLEFT", -40, 40)
	c.glow:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 40, -40)
	c:EnableMouse(true)
	c:RegisterForDrag("LeftButton")
	c:SetScript("OnDragStart", function() parent:StartMoving() end)
	c:SetScript("OnDragStop", function() parent:StopMovingOrSizing(); Popup:SavePlacement() end)

	c.eyebrow = Theme.NewText(c, "Eyebrow", "accent-text")
	c.timer = Theme.NewText(c, "Mono", "text-2")
	c.close = CreateFrame("Button", nil, c)
	c.close:SetSize(22, 22)
	c.close.icon = c.close:CreateTexture(nil, "OVERLAY")
	c.close.icon:SetTexture(ns.Assets.textures.icons.path)
	c.close.icon:SetTexCoord(ns.Assets.IconCoords("cross"))
	c.close.icon:SetSize(14, 14)
	c.close.icon:SetPoint("CENTER")
	Theme.Tint(c.close.icon, "text-3")
	c.close:SetScript("OnEnter", function(b)
		Theme.Tint(b.icon, "text-1")
		if GameTooltip then
			GameTooltip:SetOwner(b, "ANCHOR_TOP")
			GameTooltip:SetText(L["POPUP_DISMISS"])
			GameTooltip:Show()
		end
	end)
	c.close:SetScript("OnLeave", function(b)
		Theme.Tint(b.icon, "text-3")
		if GameTooltip then GameTooltip:Hide() end
	end)
	c.close:SetScript("OnClick", function() Popup:Dismiss() end)

	-- icon and name; the whole area shows the game's tooltip
	c.hit = CreateFrame("Button", nil, c)
	c.hit:SetSize(220, ROW_ITEM)
	c.icon = c.hit:CreateTexture(nil, "ARTWORK")
	c.icon:SetSize(ROW_ITEM, ROW_ITEM)
	c.icon:SetPoint("LEFT", c.hit, "LEFT", 0, 0)
	c.iconRing = Theme.Slice(c.hit, "rr_ring_8", nil, "OVERLAY")
	c.iconRing:SetAllPoints(c.icon)
	c.name = Theme.NewText(c.hit, "BodyMedium", "text-1")
	c.name:SetJustifyH("LEFT")
	c.name:SetWordWrap(false)
	c.line = Theme.NewText(c.hit, "Small", "text-3")
	c.line:SetJustifyH("LEFT")
	c.line:SetWordWrap(false)
	c.hit:SetScript("OnEnter", function(b) Popup:ShowTooltip(b, c.itemID) end)
	c.hit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

	c.badge = Widgets.Badge(c, "", "accent")
	c.credits = Theme.NewText(c, "Small", "text-2")
	c.credits:SetJustifyH("RIGHT")

	-- the upgrade badge (M7-5c); the tooltip says how it was read and what is worn
	c.verdict = Widgets.Badge(c, "", "neutral")
	c.verdict:EnableMouse(true)
	c.verdict:SetScript("OnEnter", function(b) Popup:ShowVerdictTip(b, c.data) end)
	c.verdict:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	c.verdict:Hide()

	c.bar = Widgets.ThinBar(c, { height = ROW_BAR })
	c.hint = Theme.NewText(c, "Small", "text-3")
	c.hint:SetJustifyH("LEFT")
	c.hint:SetWordWrap(true)
	-- the three buttons: Pass, Roll Main-spec, Roll Off-spec
	c.buttons = {}
	for _, code in ipairs(Popup.BUTTON_ORDER) do
		local text = Popup.BUTTON_KEYS[code] and L[Popup.BUTTON_KEYS[code]] or ns.Reasons.Text("RESPONSE", code)
		local b = Widgets.Button(c, { text = text, style = "secondary", width = 110, height = ROW_BUTTONS,
			onClick = function() Popup:Press(code) end })
		b.code = code
		b:Hide()
		c.buttons[code] = b
	end
	return c
end

-- Builds the popup frame once (hidden).
function Popup:Build()
	if self.frame then return self.frame end
	if not self.themed then   -- a raider may never have opened the main window
		Theme.SetupFonts()
		Theme.Load()
		self.themed = true
	end
	local placement = Popup.LoadPlacement()
	self.width = placement and placement.w or Popup.DEFAULT_W
	local f = CreateFrame("Frame", Popup.FRAME_NAME, UIParent)
	self.frame = f
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	f:SetResizeBounds(Popup.MIN_W, 100, Popup.MAX_W, 1200)
	f:SetSize(self.width, 300)
	if placement then
		f:SetPoint(placement.point, UIParent, placement.point, placement.x, placement.y)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	end
	-- a thin handle on the right edge: drag it to change the width (remembered)
	f.grip = CreateFrame("Button", nil, f)
	f.grip:SetSize(10, 40)
	f.grip:SetPoint("RIGHT", f, "RIGHT", 6, 0)
	f.grip.mark = f.grip:CreateTexture(nil, "OVERLAY")
	Theme.Fill(f.grip.mark, "border-strong")
	f.grip.mark:SetSize(3, 24)
	f.grip.mark:SetPoint("CENTER")
	f.grip:SetFrameLevel(f:GetFrameLevel() + 20)
	f.grip:SetScript("OnMouseDown", function() f:StartSizing("RIGHT") end)
	f.grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); Popup:SavePlacement() end)
	f:SetScript("OnSizeChanged", function(_, w)
		if w and w > 0 and math.abs(w - (Popup.width or 0)) > 0.5 then
			Popup.width = math.min(Popup.MAX_W, math.max(Popup.MIN_W, w))
			Popup:Layout()
		end
	end)
	f:SetScript("OnShow", function() Popup:Arm(); Popup:Chime() end)
	f:SetScript("OnHide", function() Popup:Disarm() end)
	f:Hide()
	return f
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing

function Popup:ShowTooltip(owner, itemID)
	local tip = GameTooltip
	if not tip or not itemID then return end
	tip:SetOwner(owner, "ANCHOR_RIGHT")
	if tip.SetItemByID then tip:SetItemByID(itemID) elseif tip.SetHyperlink then tip:SetHyperlink("item:" .. itemID) end
	tip:Show()
	-- the comparison with what the player wears: the game's own tooltips next to this one [verify in game]
	if _G.GameTooltip_ShowCompareItem then pcall(_G.GameTooltip_ShowCompareItem, tip) end
end

-- The tooltip of the upgrade badge: the badge for each spec and why, what it was compared with, how it is read.
function Popup:ShowVerdictTip(owner, d)
	local tip, A = GameTooltip, ns.UpgradeAdvisor
	local advice = d and d.upgrade
	if not tip or not advice or not advice.ms or not A then return end
	tip:SetOwner(owner, "ANCHOR_TOP")
	local lines = A.Lines(advice.ms, "MS")
	tip:SetText(lines[1])
	for i = 2, #lines do tip:AddLine(lines[i], 1, 1, 1, true) end
	if advice.os then
		for _, line in ipairs(A.Lines(advice.os, "OS")) do tip:AddLine(line, 1, 1, 1, true) end
	end
	local names = A.EquippedNames(advice.equipped)
	if #names > 0 then tip:AddLine(L["UPG_EQUIPPED"]:format(table.concat(names, ", ")), 0.8, 0.8, 0.8, true) end
	tip:AddLine(L[advice.snapshot and "UPG_FROM_SNAPSHOT" or "UPG_FROM_CURRENT"], 0.8, 0.8, 0.8, true)
	tip:AddLine(L["UPG_RULE"], 0.6, 0.6, 0.6, true)
	tip:Show()
end

-- Puts one card's rows in place (a row that does not apply is hidden and takes no room). Returns the card's height.
local function layoutCard(self, c, d, top)
	local y = 14
	c:SetWidth(self.width)
	c.eyebrow:ClearAllPoints()
	c.eyebrow:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
	c.close:ClearAllPoints()
	c.close:SetPoint("TOPRIGHT", c, "TOPRIGHT", -10, -y + 4)
	c.timer:ClearAllPoints()
	c.timer:SetPoint("TOPRIGHT", c, "TOPRIGHT", -38, -y)
	y = y + 26
	c.hit:ClearAllPoints()
	c.hit:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
	c.hit:SetWidth(self.width - 2 * PAD - 40)
	c.name:ClearAllPoints()
	c.name:SetPoint("TOPLEFT", c.hit, "TOPLEFT", ROW_ITEM + 12, -4)
	c.name:SetPoint("TOPRIGHT", c.hit, "TOPRIGHT", 0, -4)
	c.line:ClearAllPoints()
	c.line:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -4)
	c.line:SetPoint("TOPRIGHT", c.name, "BOTTOMRIGHT", 0, -4)
	y = y + ROW_ITEM + 10
	c.badge:ClearAllPoints()
	c.badge:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
	c.credits:ClearAllPoints()
	c.credits:SetPoint("TOPRIGHT", c, "TOPRIGHT", -PAD, -y - 5)
	c.credits:SetWidth(self.width - 2 * PAD - c.badge:GetWidth() - 8)
	y = y + ROW_BADGE + 12

	if d.badge then
		c.verdict:ClearAllPoints()
		c.verdict:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y + 6)
		c.verdict:Show()
		y = y + ROW_VERDICT + 6
	else
		c.verdict:Hide()
	end

	c.bar:ClearAllPoints()
	c.bar:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
	c.bar:SetPoint("TOPRIGHT", c, "TOPRIGHT", -PAD, -y)
	c.bar:SetWidth(self.width - 2 * PAD)
	y = y + ROW_BAR + 12

	c.hint:ClearAllPoints()
	c.hint:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
	c.hint:SetWidth(self.width - 2 * PAD)
	y = y + ROW_HINT + 10

	-- the buttons share the width: Pass, then the roll buttons the session offers
	local shown = {}
	for _, code in ipairs(Popup.BUTTON_ORDER) do
		if d.buttonsByCode and d.buttonsByCode[code] then shown[#shown + 1] = c.buttons[code] else c.buttons[code]:Hide() end
	end
	local n = #shown
	local w = n > 0 and math.floor((self.width - 2 * PAD - (n - 1) * BUTTON_GAP) / n) or 0
	for i, b in ipairs(shown) do
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", c, "TOPLEFT", PAD + (i - 1) * (w + BUTTON_GAP), -y)
		b:SetWidth(w)
		b:Show()
	end
	y = y + ROW_BUTTONS + 14
	c:SetHeight(y)
	return y
end

-- The text of a card's hint line.
local function hintText(d)
	local key = Popup.HINTS[d.hint]
	if not key then return "" end
	if d.hint == "ROLL" then return L[key]:format(d.rollMin, d.rollMax) end
	return L[key]
end

-- The eyebrow: "ROLL OPEN · LUCIFRON".
local function eyebrowText(d)
	local text
	if d.kind == "REROLL" then text = L["POPUP_EYEBROW_REROLL"]
	elseif d.stage == "FREE_ROLL" then text = L["POPUP_EYEBROW_FREE"]
	else text = L["POPUP_EYEBROW_ROLL"] end
	text = text:upper()
	if d.boss then text = text .. " · " .. d.boss:upper() end
	return text
end

local function applyTimer(self, c, d)
	if d.paused then
		c.timer:SetText(L["POPUP_PAUSED"])
		Theme.Text(c.timer, "text-3")
	elseif d.remaining then
		c.timer:SetText(clock(d.remaining))
		Theme.Text(c.timer, d.remaining <= Popup.WARN_SECONDS and "warn" or "text-2")
	else
		c.timer:SetText("")
	end
	local total = self.totals[d.key]
	if d.remaining and (not total or d.remaining > total) then total = d.remaining; self.totals[d.key] = total end
	c.bar:SetFraction(d.remaining and total and total > 0 and d.remaining / total or 0)
end

local function applyCard(self, c, d, top)
	c.data, c.key, c.itemID = d, d.key, d.itemID
	local info = self:ItemInfo(d.itemID)
	local r, g, b = 1, 1, 1
	if ns.MLSession then r, g, b = ns.MLSession.QualityColor(info.quality or 4) end
	c.name:SetText(info.name or L["ML_ITEM_UNKNOWN"]:format(d.itemID))
	Theme.TextRGB(c.name, r, g, b)
	c.line:SetText(Popup.ItemLine(info))
	if info.icon then c.icon:SetTexture(info.icon) end
	c.iconRing:SetVertexColor(r, g, b, 1)
	c.eyebrow:SetText(eyebrowText(d))
	c.badge:SetBadge(Popup.CostChip(d):upper(), "accent")
	local standing = ""
	if d.credits ~= nil then
		standing = L["POPUP_CREDITS"]:format(number(d.credits))
		if d.position then standing = standing .. " · " .. L["POPUP_QUEUE"]:format(d.position) end
	end
	c.credits:SetText(standing)

	-- the upgrade badge (M7-5c)
	local A = ns.UpgradeAdvisor
	local u = A and A.Badge(d.upgrade) or nil
	d.badge = u ~= nil
	if u then c.verdict:SetBadge(A.Text(u), A.Tone(u)) end

	c.hint:SetText(self.err == d.key and L["POPUP_ERR_SEND"] or self.rollErr == d.key
		and L["POPUP_ERR_ROLL"]:format(d.rollMin, d.rollMax) or hintText(d))
	d.buttonsByCode = {}
	for _, spec in ipairs(d.buttons or {}) do
		d.buttonsByCode[spec.code] = spec
		local b = c.buttons[spec.code]
		if b then
			local text = Popup.BUTTON_KEYS[spec.code] and L[Popup.BUTTON_KEYS[spec.code]] or ns.Reasons.Text("RESPONSE", spec.code)
			if spec.roll and spec.selected and d.rolled then text = L["POPUP_ROLLED"] end
			b:SetLabel(text)
			b:SetEnabled(spec.enabled)
			b.selected = spec.selected
			if b.ring then Theme.Tint(b.ring, spec.selected and "neon" or "border") end
		end
	end

	-- the neon element: the top card only
	Theme.GlowShow(c.glow, top)
	Theme.Tint(c.parts.ring, top and "neon" or "border")
	applyTimer(self, c, d)
	return layoutCard(self, c, d, top)
end

-- Lays the cards out one under the other.
function Popup:Layout()
	local f = self.frame
	if not f then return end
	local y = 0
	for i, c in ipairs(self.cards) do
		if c:IsShown() and c.data then
			c:ClearAllPoints()
			c:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
			local h = layoutCard(self, c, c.data, i == 1)
			y = y + h + Popup.CARD_GAP
		end
	end
	f:SetHeight(math.max(y - Popup.CARD_GAP, 1))
end

---------------------------------------------------------------------------------------------------------------------
-- Board and state

Popup.draft = nil        -- { key, rs }: the player's answer to the round `key`, ahead of what the session knows
Popup.rolled = {}        -- [key] = true: the player rolled in this round
Popup.dismissed = {}     -- [key] = true: the player hid this round's card
Popup.totals = {}        -- [key] = the longest time left seen (the timer bar's full length)
Popup.board = nil
Popup.cards = {}         -- the card frames (built as needed, reused)

local function boardEnv(self)
	return {
		me = me(), now = now(), draft = self.draft,
		rolled = function(key) return self.rolled[key] == true end,
		dismissed = function(key) return self.dismissed[key] == true end,
		standing = function()
			return PB.Standing(me(), PS() and PS().raid)
		end,
		boss = PB.BossName,
		upgrade = function(itemID)
			local A = ns.UpgradeAdvisor
			return A and (A.For(itemID)) or nil
		end,
	}
end

-- The board as it is now.
function Popup:Board()
	local view = PS() and PS().view
	if view and view.s ~= self.sid then   -- another session: the old marks mean nothing
		self.sid = view.s
		self.draft, self.rolled, self.dismissed, self.totals, self.err, self.rollErr = nil, {}, {}, {}, nil, nil
	end
	return PB.Build(view, boardEnv(self))
end

-- The first card (the one the actions act on).
function Popup:Current()
	return self.board and self.board.cards[1] or nil
end

-- Redraws the popup from the session: shows it when a round asks something of this player, hides it otherwise.
function Popup:Refresh()
	local board = self:Board()
	self.board = board
	local cards = board.cards
	if #cards == 0 then
		if self.frame then
			for _, c in ipairs(self.cards) do c:Hide(); c.data = nil end
			self.frame:Hide()
		end
		return
	end
	self:Build()
	for i = 1, math.min(#cards, PB.MAX_CARDS) do
		local c = self.cards[i]
		if not c then
			c = buildCard(self, self.frame)
			self.cards[i] = c
		end
		c:Show()
		applyCard(self, c, cards[i], i == 1)
	end
	for i = #cards + 1, #self.cards do self.cards[i]:Hide(); self.cards[i].data = nil end
	self:Layout()
	self.frame:Show()
	self.frame:Raise()
end

function Popup:IsShown() return self.frame ~= nil and self.frame:IsShown() end

-- A cheaper redraw for the ticker: only the timer, unless the round changed.
function Popup:RefreshTimer()
	local board = self:Board()
	local first = board.cards[1]
	local shown = self.cards[1]
	if not first or not shown or shown.key ~= first.key or #board.cards ~= 1 or not shown.data then return self:Refresh() end
	self.board = board
	shown.data.remaining, shown.data.paused = first.remaining, first.paused
	applyTimer(self, shown, shown.data)
end

function Popup:Arm()
	if self.ticker then return end
	self.ticker = ns.Compat.NewTicker(Popup.TICK, function() Popup:RefreshTimer() end)
end

function Popup:Disarm()
	if self.ticker then self.ticker:Cancel() end
	self.ticker = nil
end

---------------------------------------------------------------------------------------------------------------------
-- The player's actions

-- Sends a response for the card (the master looter keeps the latest) with the badges and the worn pieces. Returns true, or
-- false and a code.
function Popup:Send(card, code)
	local ps = PS()
	if not ps then return false, "NO_SESSION" end
	self.draft = { key = card.key, rs = code }
	local ok, why = ps:Respond(code, card.upgrade and card.upgrade.wire or nil)
	if not ok then
		self.err = card.key
		self:Refresh()
		return false, why
	end
	self.err = nil
	self:Refresh()
	return true
end

-- Pass, or a response on offer without rolling (tests and the Pass button). Returns true, or false and a code.
function Popup:Choose(code)
	local card = self:Current()
	if not card or not card.canAnswer then return false, "LOCKED" end
	local ok = code == "PASS"
	for _, o in ipairs(card.offered) do if o.code == code then ok = true end end
	if not ok then return false, "BAD_RESPONSE" end
	if card.response == code then return true end
	return self:Send(card, code)
end

-- Roll: the game's own RandomRoll(1, 100), once per round.
function Popup:Roll()
	local card = self:Current()
	if not card or not card.canRoll then return false, "LOCKED" end
	-- M7-2d: the intent goes first (it waits out a lockdown in the queue like every message); the roll follows at once.
	-- A refused intent does not stop the roll: the master looter then discards it as NOT_FROM_BUTTON if the rule is on.
	if ns.Protocol and ns.Protocol.Session then ns.Protocol.Session:RollIntent() end
	local state = ns.Compat.Roll.Send(card.rollMin, card.rollMax)
	if state ~= ns.Compat.AVAILABLE then
		self.rollErr = card.key
		self:Refresh()
		return false, state
	end
	self.rollErr = nil
	self.rolled[card.key] = true
	self:Refresh()
	return true
end

-- A click on one of the three buttons (M7-5c). Pass answers. Roll Main-spec / Roll Off-spec answer with that response
-- while the round collects the responses and roll in the same click when the player rolls in this round; a response whose
-- tier rolls later stays sent (the button rolls when its turn comes). Returns true, or false and a code.
function Popup:Press(code)
	local card = self:Current()
	if not card then return false, "LOCKED" end
	local spec
	for _, b in ipairs(card.buttons or {}) do if b.code == code then spec = b end end
	if not spec or not spec.enabled then return false, "LOCKED" end
	if code == "PASS" then return self:Choose("PASS") end
	if card.canAnswer and card.response ~= code then
		local ok, why = self:Choose(code)
		if not ok then return false, why end
		card = self:Current()
		if not card then return true end
	end
	if not card.canRoll then return true, "LATER" end
	return self:Roll()
end

-- Hides this round's card (nothing is sent: no answer is a pass to the rules, §3.4).
function Popup:Dismiss()
	local card = self:Current()
	if not card then return false end
	self.dismissed[card.key] = true
	self:Refresh()
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Events

if ns.Bus then
	ns.Bus:On("SESSION_VIEW", function(_, _, what, _, who)
		if what == "RESPONSE" and who ~= me() then return end   -- other players' answers do not change this popup
		Popup:Refresh()
	end, Popup)
	ns.Bus:On("THEME_CHANGED", function() if Popup.frame then Popup:Refresh() end end, Popup)
	ns.Bus:On("GUILD_KEY_CHANGED", function() if Popup.frame then Popup:Refresh() end end, Popup)
	ns.Bus:On("UPGRADE_ADVICE_CHANGED", function() if Popup.frame then Popup:Refresh() end end, Popup)   -- gear or spec changed
end
