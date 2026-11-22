-- BackupService: the strings of the configuration, the backup and the archive, the restore and the end-of-season compaction
-- (docs/ANALISI.md §7 "Importazione", §8.3, §11; M6-7). Lua 5.1. The tables are Domain/Backup.lua's; this module is the
-- glue: the guild's ledger (App/NightController.lua), the permissions, the trust gate and the text form.
--
-- The text form: "!FDCP:<KIND>:<v>:" .. Base64(flag .. (flag == "\1" and Deflate(CBOR(data)) or CBOR(data))), one line, no
-- size limit (it never travels as an addon message: the player copies it out of the game and pastes it back). Spaces and
-- line breaks are ignored when it is read, so a string that a chat window wrapped still works.
--
-- Who may do what:
--   * the configuration string: everybody exports it (the rules are shown to every member read-only); only the Guild
--     Master imports it (config.rules), with an explicit confirmation; the import is a CONFIG_CHANGED, audited;
--   * the backup and the archive: `view.attendance` (the officers: they carry the attendance);
--   * a restore: `season.manage` (the Guild Master by default), with an explicit confirmation; it only adds what is
--     missing (a merge through the trust gate, never a deletion or an overwrite) and is written as LEDGER_RESTORED;
--   * a compaction: `season.manage`, a closed season, its archive made first in this session (so what leaves the game is
--     in the player's hands before anything is removed) and two separate confirmations; LEDGER_COMPACTED, audited.
--
-- Bus events: "CONFIG_IMPORTED"(event), "LEDGER_RESTORED"(report), "LEDGER_COMPACTED"(season, removed).
-- Not verified in the real client: C_EncodingUtil on a whole ledger (time and memory of a long season), the paste of a long
-- string into an edit box, and the SavedVariables size after a long season (M6-7 "in game").
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local BackupService = {}
ns.BackupService, ns.modules.BackupService = BackupService, BackupService

local type, tostring, tonumber = type, tostring, tonumber

BackupService.PREFIX = "!FDCP"
BackupService.COMPRESS_OVER = 120
BackupService.MAX_TEXT = 8 * 1024 * 1024   -- a pasted string longer than this is refused

local function NC() return ns.NightController end
local function B() return ns.Backup end
local function log(level, code, ...) if ns.Log then ns.Log[level]("Backup", code, ...) end end
local function emit(event, ...) if ns.Bus then ns.Bus:Emit(event, ...) end end
local function now() return ns.Compat.ServerTime() end

function BackupService:Reset()
	self.archived = {}   -- [season] = true: its archive was made in this session (the compaction asks for it)
end
BackupService:Reset()

function BackupService:Ledger() return NC() and NC():Ledger() or nil end

local function can(p)
	if not NC() then return false, "NOT_READY" end
	return NC():Can(p)
end

---------------------------------------------------------------------------------------------------------------------
-- The text form

-- The string of a table of Domain/Backup.lua. Returns the text, or nil and a code ("ENCODE").
function BackupService.Encode(data)
	local C = ns.Compat
	local cbor = C.CBOR.Encode(data)
	if not cbor then return nil, "ENCODE" end
	local flag, packed = "\0", cbor
	if #cbor > BackupService.COMPRESS_OVER then
		local deflated = C.Compress.Deflate(cbor)
		if deflated and #deflated < #cbor then flag, packed = "\1", deflated end
	end
	local body = C.Base64.Encode(flag .. packed)
	if not body then return nil, "ENCODE" end
	return ("%s:%s:%d:%s"):format(BackupService.PREFIX, data.kind, B().V, body)
end

-- The table of a string, checked (Backup.Validate). `kinds` = { [kind] = true } the kinds accepted here (nil = any).
-- Returns the table, or nil and a code: "EMPTY", "FORMAT", "KIND", "NEWER", "DECODE" or "INVALID:<code>".
function BackupService.Decode(text, kinds)
	if type(text) ~= "string" then return nil, "EMPTY" end
	text = text:gsub("%s+", "")
	if text == "" then return nil, "EMPTY" end
	if #text > BackupService.MAX_TEXT then return nil, "FORMAT" end
	local kind, v, body = text:match("^!FDCP:(%u+):(%d+):([A-Za-z0-9+/=]+)$")
	if not kind then return nil, "FORMAT" end
	if not B().KINDS[kind] or (kinds and not kinds[kind]) then return nil, "KIND" end
	if tonumber(v) > B().V then return nil, "NEWER" end
	local C = ns.Compat
	local raw = C.Base64.Decode(body)
	if not raw or raw == "" then return nil, "DECODE" end
	local flag, packed = raw:sub(1, 1), raw:sub(2)
	if flag == "\1" then
		packed = C.Compress.Inflate(packed)
		if not packed then return nil, "DECODE" end
	elseif flag ~= "\0" then
		return nil, "DECODE"
	end
	local data = C.CBOR.Decode(packed)
	if type(data) ~= "table" then return nil, "DECODE" end
	if data.kind ~= kind then return nil, "KIND" end
	local ok, code = B().Validate(data)
	if not ok then return nil, code == "NEWER" and "NEWER" or ("INVALID:" .. tostring(code)) end
	return data
end

---------------------------------------------------------------------------------------------------------------------
-- The configuration

-- The configuration string of the rules in force (everybody). Returns the text, or nil and a code.
function BackupService:ExportConfig()
	local L = self:Ledger()
	if not L then return nil, "NOT_READY" end
	return BackupService.Encode(B().Config(L))
end

-- What importing `text` would change: { rules, preset?, changes = { paths } }, or nil and a code.
function BackupService:PreviewConfig(text)
	local L = self:Ledger()
	if not L then return nil, "NOT_READY" end
	local data, why = BackupService.Decode(text, { CFG = true })
	if not data then return nil, why end
	return B().ImportedRules(L, data)
end

-- Imports a configuration string: the Guild Master only, args.confirmed. Returns the CONFIG_CHANGED event, or nil and a
-- code: "NOT_READY", "PENDING", "NOT_IN_GUILD", "NOT_GM", "CONFIRM_REQUIRED", a Decode code, "RULES:<code>", "UNCHANGED"
-- or a Ledger code.
function BackupService:ImportConfig(text, args)
	args = args or {}
	local L = self:Ledger()
	if not L then return nil, "NOT_READY" end
	local ok, why = can("config.rules")
	if not ok then return nil, why end
	if args.confirmed ~= true then return nil, "CONFIRM_REQUIRED" end
	local preview, code = self:PreviewConfig(text)
	if not preview then return nil, code end
	if #preview.changes == 0 then return nil, "UNCHANGED" end
	local me = NC():Me()
	if not me then return nil, "NOT_READY" end
	local gate = ns.PermissionService and ns.PermissionService:Gate() or nil
	local e, err = ns.Rules.Change(L, { author = me, ts = now(), rules = preview.rules, preset = preview.preset,
		confirmed = true }, gate)
	if not e then return nil, err end
	log("info", "CONFIG_IMPORTED", #preview.changes)
	emit("CONFIG_IMPORTED", e)
	return e
end

---------------------------------------------------------------------------------------------------------------------
-- Backup, archive, restore

-- The full backup string (view.attendance). Returns the text, or nil and a code.
function BackupService:BackupText()
	local L = self:Ledger()
	if not L then return nil, "NOT_READY" end
	local ok, why = can("view.attendance")
	if not ok then return nil, why end
	return BackupService.Encode(B().Full(L, { ts = now(), by = NC():Me() }))
end

-- The archive string of a season (view.attendance). Remembers that it was made, for the compaction.
function BackupService:ArchiveText(season)
	local L = self:Ledger()
	if not L then return nil, "NOT_READY" end
	local ok, why = can("view.attendance")
	if not ok then return nil, why end
	local data, code = B().Archive(L, season, { ts = now(), by = NC():Me() })
	if not data then return nil, code end
	local text, err = BackupService.Encode(data)
	if not text then return nil, err end
	self.archived[season] = true
	return text
end

-- What restoring `text` would bring: Backup.Preview, or nil and a code.
function BackupService:PreviewRestore(text)
	local L = self:Ledger()
	if not L then return nil, "NOT_READY" end
	local data, why = BackupService.Decode(text, { BAK = true, ARC = true })
	if not data then return nil, why end
	return B().Preview(L, data)
end

-- The gate of a restore: events whose author the rank history never saw are vouched for by the restorer, as in the sync.
local function restoreGate(me)
	if ns.Sync and ns.Sync.Gate and ns.PermissionService then return ns.Sync:Gate(me) end
	return ns.PermissionService and ns.PermissionService:Gate() or nil
end

-- Restores a backup or an archive string (season.manage, args.confirmed). A merge: nothing is removed or overwritten.
-- Returns the report { added, duplicate, compacted, gone, refused, pending, invalid, conflict }, or nil and a code.
function BackupService:Restore(text, args)
	args = args or {}
	local L = self:Ledger()
	if not L then return nil, "NOT_READY" end
	local ok, why = can("season.manage")
	if not ok then return nil, why end
	if args.confirmed ~= true then return nil, "CONFIRM_REQUIRED" end
	local data, code = BackupService.Decode(text, { BAK = true, ARC = true })
	if not data then return nil, code end
	local me = NC():Me()
	if not me then return nil, "NOT_READY" end
	local gate = restoreGate(me)
	local report, err = B().Restore(L, data, {
		merge = function(ledger, events)
			if ns.PermissionService then return ns.PermissionService:Merge(ledger, events, gate) end
			return ns.Ledger.Merge(ledger, events, gate)
		end,
	})
	if not report then return nil, err end
	local audit, aerr = B().RecordRestore(L, { author = me, ts = now(), data = data, report = report },
		ns.PermissionService and ns.PermissionService:Gate() or nil)
	if not audit then log("warn", "RESTORE_AUDIT", tostring(aerr)) end
	report.audit = audit
	log("info", "RESTORED", report.added, report.gone)
	emit("LEDGER_RESTORED", report)
	if report.added > 0 then emit("LEDGER_SYNCED", { from = me, added = report.added, refused = #report.refused,
		pending = #report.pending, conflict = #report.conflict }) end
	return report
end

---------------------------------------------------------------------------------------------------------------------
-- Compaction

-- The closed seasons and whether each was compacted: { { id, label, closedAt, compacted, removable } }, newest first.
function BackupService:Seasons()
	local L = self:Ledger()
	local out = {}
	if not L then return out end
	local done = ns.Ledger.Compactions(L)
	for _, s in ipairs(ns.Season.List(L)) do
		if s.closed then
			local removable = 0
			if not done[s.id] then removable = select(2, B().Summary(L, s.id)) end
			out[#out + 1] = { id = s.id, label = s.label, closedAt = s.closedAt, compacted = done[s.id] ~= nil,
				removable = removable or 0 }
		end
	end
	table.sort(out, function(a, b) return (a.closedAt or 0) > (b.closedAt or 0) end)
	return out
end

-- Compacts a closed season (season.manage; its archive made first; args.confirmed and args.confirmedAgain). Returns the
-- number of events removed, or nil and a code: "NOT_READY", a permission code, "ARCHIVE_FIRST", "CONFIRM_REQUIRED" or a
-- Backup.Compact code.
function BackupService:Compact(season, args)
	args = args or {}
	local L = self:Ledger()
	if not L then return nil, "NOT_READY" end
	local ok, why = can("season.manage")
	if not ok then return nil, why end
	if not self.archived[season] then return nil, "ARCHIVE_FIRST" end
	if args.confirmed ~= true or args.confirmedAgain ~= true then return nil, "CONFIRM_REQUIRED" end
	local me = NC():Me()
	if not me then return nil, "NOT_READY" end
	local e, removed = B().Compact(L, { author = me, ts = now(), season = season },
		ns.PermissionService and ns.PermissionService:Gate() or nil)
	if not e then return nil, removed end
	log("info", "COMPACTED", removed)
	emit("LEDGER_COMPACTED", season, removed)
	return removed
end

---------------------------------------------------------------------------------------------------------------------
-- /fdcp debug: the size of the saved data

function BackupService:SizeLines()
	local L = self:Ledger()
	if not L then return {} end
	local s = B().Size(L)
	local seasons = {}
	for id in pairs(ns.Ledger.Compactions(L)) do seasons[#seasons + 1] = tostring(id) end
	table.sort(seasons)
	local top = {}
	for i, row in ipairs(s.byType) do
		if i > 4 then break end
		top[#top + 1] = ("%s %d (~%d KB)"):format(row.type, row.count, math.floor(row.bytes / 1024 + 0.5))   -- nolocale (debug output)
	end
	return {
		("Ledger size: %d events, ~%d KB; compacted %d (seasons: %s)"):format(s.events, math.floor(s.bytes / 1024 + 0.5),   -- nolocale (debug output)
			s.gone, #seasons > 0 and table.concat(seasons, ", ") or "-"),   -- nolocale
		("Largest: %s"):format(#top > 0 and table.concat(top, "; ") or "-"),   -- nolocale (debug output)
	}
end

if ns.Bus then
	ns.Bus:On("GUILD_KEY_CHANGED", function() BackupService:Reset() end, BackupService)
end
if ns.addon then
	ns.addon.BackupService = BackupService   -- also reachable from tests
	if ns.addon.AddDebugSection then
		ns.addon:AddDebugSection("Backup", function() return BackupService:SizeLines() end)
	end
end
