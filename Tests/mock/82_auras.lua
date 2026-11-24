-- Mock client, part 9b: the player's own auras (M8-2, the readiness check).
--
-- Imitates: C_UnitAuras.GetBuffDataByIndex(unit, index, filter) and C_UnitAuras.GetAuraDataByIndex(unit, index, filter),
-- which return an AuraData table (the fields the addon reads: spellId, name). Dump: api.json system UnitAuras
-- (C_UnitAuras); the dump also has ShouldUnitAuraIndexBeSecret: an aura may come back as a secret value.
--
-- Configure with Mock.auras (kept across Mock.Reload):
--   Mock.auras.buffs = { { spellId = 17628, name = "Supreme Power" }, ... }   the player's helpful auras, in order
--   Mock.auras.secret = { [index] = true }   that row is a secret value (Mock.SECRET)
--   Mock.auras.failing = true                both functions raise an error
local Mock, H = ...
local W = Mock.world

W.auras = W.auras or { buffs = {}, secret = {} }
local auras = W.auras
Mock.auras = auras

C_UnitAuras = C_UnitAuras or {}

local function row(unit, index, filter)
	if auras.failing then error("aura query failed") end
	if unit ~= "player" then return nil end
	if filter ~= nil and filter ~= "HELPFUL" then return nil end
	if auras.secret and auras.secret[index] then return Mock.SECRET end
	local a = auras.buffs[index]
	if not a then return nil end
	return { spellId = a.spellId, name = a.name or "Aura", isHelpful = true, auraInstanceID = index }
end

function C_UnitAuras.GetBuffDataByIndex(unit, index, filter) return row(unit, index, filter or "HELPFUL") end
function C_UnitAuras.GetAuraDataByIndex(unit, index, filter) return row(unit, index, filter) end
