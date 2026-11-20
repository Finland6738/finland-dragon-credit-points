-- Mock client, part 3c (M1-7): the texture methods of the themed UI, added to the generic widget of 20_frames.lua.
--
-- Imitates (dump: ../WoW-Addons/docs/api.json, Texture / TextureBase API): SetTextureSliceMargins, GetTextureSliceMargins,
-- SetTextureSliceMode, SetSnapToPixelGrid, SetTexelSnappingBias, SetSpriteSheetCell and the screen size.
-- The mock stores what the addon asked for, so tests can check the 9-slice margins and the pixel snapping of a region.
local Mock, H = ...

local Widget = getmetatable(UIParent).__index

function Widget:SetTextureSliceMargins(l, t, r, b) self._slice = { l, t, r, b } end
function Widget:GetTextureSliceMargins() if self._slice then return unpack(self._slice) end return 0, 0, 0, 0 end
function Widget:SetTextureSliceMode(mode) self._sliceMode = mode end
function Widget:SetSnapToPixelGrid(v) self._snap = v and true or false end
function Widget:IsSnappingToPixelGrid() return self._snap ~= false end
function Widget:SetTexelSnappingBias(v) self._texelBias = v end
function Widget:GetTexelSnappingBias() return self._texelBias or 0 end
function Widget:SetSpriteSheetCell(cell) self._cell = cell end

-- The physical screen (dump: C_UI / GetPhysicalScreenSize); a test may change Mock.screen.
Mock.screen = { width = 1920, height = 1080 }
function GetPhysicalScreenSize() return Mock.screen.width, Mock.screen.height end
