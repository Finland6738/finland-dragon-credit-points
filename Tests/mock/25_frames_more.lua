-- Mock client, part 3b (Accord, M1.8): the frame methods of movable, resizable and scrolling windows and multi-line
-- edit boxes, added to the generic widget of Tests/mock/20_frames.lua.
--
-- Imitates (dump: ../WoW-Addons/docs/api/UI-Widgets-Frames/): SetMovable, IsMovable, RegisterForDrag, StartMoving,
-- StopMovingOrSizing, SetClampedToScreen, SetResizable, IsResizable, SetResizeBounds, StartSizing, SetToplevel, Raise,
-- SetMultiLine, IsMultiLine, SetTextInsets, SetMaxLetters, SetScrollChild, GetScrollChild, SetVerticalScroll,
-- GetVerticalScroll, GetVerticalScrollRange, SetJustifyV, SetWordWrap, SetNonSpaceWrap, RegisterForClicks, SetMotionScriptsWhileDisabled.
-- Moving and sizing are instant: StartMoving records that the frame is being moved; StopMovingOrSizing keeps the point
-- a test set with SetPoint in between (Mock.Drag does both), and fires nothing.
local Mock, H = ...

local Widget = getmetatable(UIParent).__index

function Widget:SetMovable(v) self._movable = v and true or false end
function Widget:IsMovable() return self._movable == true end
function Widget:RegisterForDrag(...) self._drag = { ... } end
function Widget:StartMoving() self._moving = true end
function Widget:StopMovingOrSizing() self._moving, self._sizing = false, false end
function Widget:SetClampedToScreen(v) self._clamped = v and true or false end
function Widget:SetResizable(v) self._resizable = v and true or false end
function Widget:IsResizable() return self._resizable == true end
function Widget:SetResizeBounds(minW, minH, maxW, maxH) self._bounds = { minW, minH, maxW, maxH } end
function Widget:StartSizing() self._sizing = true end
function Widget:SetToplevel(v) self._toplevel = v and true or false end
function Widget:Raise() self._raised = (self._raised or 0) + 1 end
function Widget:SetMultiLine(v) self._multiLine = v and true or false end
function Widget:IsMultiLine() return self._multiLine == true end
function Widget:SetTextInsets() end
function Widget:SetMaxLetters(n) self._maxLetters = n end
function Widget:SetScrollChild(child) self._scrollChild = child end
function Widget:GetScrollChild() return self._scrollChild end
function Widget:SetVerticalScroll(v) self._vscroll = v end
function Widget:GetVerticalScroll() return self._vscroll or 0 end
function Widget:GetVerticalScrollRange() return 0 end
function Widget:SetJustifyV(v) self._justifyV = v end
function Widget:SetWordWrap(v) self._wordWrap = v end
function Widget:SetNonSpaceWrap(v) self._nonSpaceWrap = v end
function Widget:RegisterForClicks(...) self._clicks = { ... } end
function Widget:SetMotionScriptsWhileDisabled(v) self._motionDisabled = v end

-- The player drags `frame` to a point: OnDragStart, the new point, OnDragStop (the scripts the window installed).
function Mock.Drag(frame, point, x, y)
	Mock.RunScript(frame, "OnDragStart", "LeftButton")
	frame:ClearAllPoints()
	frame:SetPoint(point or "CENTER", UIParent, point or "CENTER", x or 0, y or 0)
	Mock.RunScript(frame, "OnDragStop")
end

-- Show and Hide run the OnShow / OnHide script AND the functions added with HookScript, as the client does (the generic
-- widget ran only the script). A frame that becomes visible or hidden because its parent did also runs its own OnShow /
-- OnHide, children that are themselves shown only (M2.3).
local function cascade(widget, script)
	for _, child in ipairs(widget._children) do
		if child._shown then
			Mock.RunScript(child, script)
			cascade(child, script)
		end
	end
end
function Widget:Show()
	if not self._shown then
		self._shown = true
		Mock.RunScript(self, "OnShow")
		cascade(self, "OnShow")
	end
end
function Widget:Hide()
	if self._shown then
		self._shown = false
		Mock.RunScript(self, "OnHide")
		cascade(self, "OnHide")
	end
end
