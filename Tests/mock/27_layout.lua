-- Mock client, part 3d (fix/settings-layout): where a frame is on the screen, computed from its anchors like the client.
--
-- Imitates (dump: ../WoW-Addons/docs/api.json, ScriptRegion / FontString API): GetWidth and GetHeight of a region whose
-- anchors fix both edges, GetStringHeight of a wrapped FontString, IsTruncated, GetUnboundedStringWidth and GetNumLines.
-- Mock.Rect(region) gives left, bottom, width, height in UIParent coordinates (nil when the region has no usable anchor);
-- the scale of the frames is ignored (the addon does not scale its frames).
--
-- Text metrics: by default a character is 6 points wide and a line 12 points high (what the older tests expect). A test that
-- checks a layout sets Mock.textScale (points of width per point of font size and per character, 0.55 is close to the
-- Outfit font of the addon): then the width follows the font size of the FontString and the line height is size + 3.
-- A FontString with a width wraps its text word by word (unless SetWordWrap(false), which truncates it).
local Mock, H = ...

local Widget = getmetatable(UIParent).__index

Mock.textScale = nil

local FRAC = {
	TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
	LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
	BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

local function fontSize(fs)
	local f = fs._font or (fs._fontObject and fs._fontObject._font)
	return (f and f[2]) or 12
end

-- The printable characters of a text: colour codes and textures removed, UTF-8 sequences counted once.
local function chars(text)
	text = (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "M")
	return #(text:gsub("[\128-\191]", ""))
end

local function charWidth(fs)
	if not Mock.textScale then return 6 end
	return fontSize(fs) * Mock.textScale
end

local function lineHeight(fs)
	if not Mock.textScale then return 12 end
	return fontSize(fs) + 3
end

local function textWidth(fs, text)
	if not Mock.textScale then return #(text or "") * 6 end
	return chars(text) * charWidth(fs)
end

-- The lines a text takes in `width` points (greedy word wrap; a word longer than the line is cut).
local function wrapLines(fs, text, width)
	local n = 0
	text = text or ""
	if text == "" then return 0 end
	local cw = charWidth(fs)
	for para in (text .. "\n"):gmatch("(.-)\n") do
		if not width or width <= 0 or fs._wordWrap == false then
			n = n + 1
		else
			local used, lines = 0, 1
			for word in para:gmatch("%S+") do
				local w = textWidth(fs, word)
				local need = used == 0 and w or used + cw + w
				if need <= width + 0.01 then
					used = need
				elseif used == 0 then
					lines = lines + math.ceil(w / width) - 1
					used = w - (math.ceil(w / width) - 1) * width
				else
					lines = lines + 1
					if w > width then
						lines = lines + math.ceil(w / width) - 1
						used = w - (math.ceil(w / width) - 1) * width
					else
						used = w
					end
				end
			end
			n = n + lines
		end
	end
	return n
end

local function naturalWidth(fs)
	local best = 0
	for line in ((fs._text or "") .. "\n"):gmatch("(.-)\n") do
		local w = textWidth(fs, line)
		if w > best then best = w end
	end
	return best
end

local resolve

-- The two edges (or centre) an axis of `w` gets from its anchors.
local function edges(w, seen)
	local L, R, CX, T, B, CY
	for _, p in ipairs(w._points) do
		local rel = p[2]
		if type(rel) == "string" then rel = _G[rel] end
		local rl, rb, rw, rh = resolve(rel, seen)
		if rl then
			local rf, f = FRAC[p[3]] or FRAC.CENTER, FRAC[p[1]] or FRAC.CENTER
			local x, y = rl + rf[1] * rw + (p[4] or 0), rb + rf[2] * rh + (p[5] or 0)
			if f[1] == 0 then L = x elseif f[1] == 1 then R = x else CX = x end
			if f[2] == 1 then T = y elseif f[2] == 0 then B = y else CY = y end
		end
	end
	return L, R, CX, T, B, CY
end

local function isText(w) return w._type == "FontString" end

-- The width of a region: from two anchors, else the one it was given, else (a FontString) the width of its text.
local function widthOf(w, L, R)
	if L and R then return R - L end
	if w._width and w._width > 0 then return w._width end
	if isText(w) then return naturalWidth(w) end
	return 0
end

local function heightOf(w, T, B, width)
	if T and B then return T - B end
	if w._height and w._height > 0 then return w._height end
	if isText(w) then
		local limit = (w._width and w._width > 0 or #w._points > 1) and width or nil
		local lines = wrapLines(w, w._text, limit)
		if w._maxLines and w._maxLines > 0 and lines > w._maxLines then lines = w._maxLines end
		return lines * lineHeight(w)
	end
	return 0
end

function resolve(w, seen)
	if not w then return nil end
	if w == UIParent then return 0, 0, UIParent._width, UIParent._height end
	if (not w._points or #w._points == 0) and w._parent and w._parent._scrollChild == w then
		-- the scroll child of a ScrollFrame: at the frame's top left, with its own size
		local pl, pb, pw, ph = resolve(w._parent, seen)
		if not pl then return nil end
		local width, height = widthOf(w), heightOf(w, nil, nil, w._width)
		return pl, pb + ph - height, width, height
	end
	if not w._points or #w._points == 0 then return nil end
	seen = seen or {}
	if seen[w] then return nil end
	seen[w] = true
	local L, R, CX, T, B, CY = edges(w, seen)
	seen[w] = nil
	local width = widthOf(w, L, R)
	local height = heightOf(w, T, B, width)
	local left = L or (R and R - width) or (CX and CX - width / 2)
	local bottom = B or (T and T - height) or (CY and CY - height / 2)
	if not left or not bottom then return nil end
	return left, bottom, width, height
end

-- left, bottom, width, height of a region in UIParent coordinates, or nil.
function Mock.Rect(w) return resolve(w) end

-- The width and the height follow the anchors when two of them fix the edges (the client does the same).
local plainWidth, plainHeight = Widget.GetWidth, Widget.GetHeight
function Widget:GetWidth()
	if #self._points > 1 then
		local L, R = edges(self, {})
		if L and R then return R - L end
	end
	return plainWidth(self)
end
function Widget:GetHeight()
	if #self._points > 1 then
		local _, _, _, T, B = edges(self, {})
		if T and B then return T - B end
	end
	if isText(self) and (not self._height or self._height == 0) and Mock.textScale then return self:GetStringHeight() end
	return plainHeight(self)
end
function Widget:GetSize() return self:GetWidth(), self:GetHeight() end

-- The text: its width on one line, and its height wrapped in the FontString's width.
local plainStringWidth = Widget.GetStringWidth
function Widget:GetStringWidth()
	if not Mock.textScale then return plainStringWidth(self) end
	return naturalWidth(self)
end
function Widget:GetUnboundedStringWidth() return self:GetStringWidth() end
function Widget:GetNumLines()
	local width = self:GetWidth()
	return wrapLines(self, self._text, width and width > 0 and width or nil)
end
function Widget:GetStringHeight()
	if not Mock.textScale then return 12 end
	local width = self:GetWidth()
	local lines = wrapLines(self, self._text, width and width > 0 and width or nil)
	if self._maxLines and self._maxLines > 0 and lines > self._maxLines then lines = self._maxLines end
	return lines * lineHeight(self)
end
function Widget:SetMaxLines(n) self._maxLines = n end
function Widget:GetMaxLines() return self._maxLines or 0 end
function Widget:GetWordWrap() return self._wordWrap ~= false end
-- A text cut by its width or its lines.
function Widget:IsTruncated()
	local width = self:GetWidth()
	if not width or width <= 0 then return false end
	if self._wordWrap == false then return naturalWidth(self) > width + 0.01 end
	local lines = wrapLines(self, self._text, width)
	return self._maxLines ~= nil and self._maxLines > 0 and lines > self._maxLines
end
