-- AddonNotice: the notice in /raid for the members without the addon (docs/ANALISI.md §4.1, M3-6). Lua 5.1. The text and
-- the splitting are Domain/Notice.lua; who lacks the addon is App/AddonCheck.lua; the guild's wording is the rules' section
-- "notice" (only the Guild Master changes it: SaveConfig).
--
-- Send(kind) is called by a click of someone with `raid.addonCheck` (or the runner of the night), never by itself.
--   kind "MISSING"   the members who did not answer (MISSING) or answered with an incompatible protocol
--   kind "OUTDATED"  the members with an older version
-- It writes one line per 255 characters in /raid, or one whisper to each name when the rules say `whisper`. Refused:
--   "NOT_IN_RAID", a permission code, "ENCOUNTER" (a boss fight runs: the click is lost, the player tries again after
--   it), "CHAT_BLOCKED" (lockdown or an addon restriction), "THROTTLED" (plus the seconds left: at most one notice every
--   `minutes` minutes per night), "NOBODY" (nobody to name), "TEXT_TOO_LONG", "SEND_FAILED".
-- Every notice that left is logged (who, when, kind, to whom, how many lines) in the character's data and on the bus
-- ("ADDON_NOTICE_SENT"). The wait of the throttle starts at the first notice of a night and is cleared when a night opens.
-- Not verified in the real client: SendChatMessage to RAID from a click, whispers to "Name-Realm".
local ADDON_NAME, ns = ...
ns = ns or {}
ns.modules = ns.modules or {}
local AddonNotice = {}
ns.AddonNotice, ns.modules.AddonNotice = AddonNotice, AddonNotice

local type, ipairs, tostring = type, ipairs, tostring

AddonNotice.HISTORY_MAX = 30
AddonNotice.lastAt = nil

local function log(level, code, ...) if ns.Log then ns.Log[level]("AddonNotice", code, ...) end end
local function now() return ns.Compat.Now() end
local function L() return ns.L end

function AddonNotice:Reset() self.lastAt = nil end

-- The rules' section "notice" in force (the defaults without a ledger).
function AddonNotice:Config()
	local ledger = ns.NightController and ns.NightController:Ledger()
	local rules = ledger and ns.Rules.Current(ledger) or ns.Rules.DefaultConfig()
	return rules.notice
end

-- The names a notice of `kind` would name: raid members in that state, sorted (realms kept).
function AddonNotice:Names(kind)
	local out = {}
	for _, row in ipairs(ns.AddonCheck:Rows()) do
		if kind == "OUTDATED" then
			if row.state == "OUTDATED" then out[#out + 1] = row.name end
		elseif row.state == "MISSING" or row.state == "INCOMPATIBLE" then
			out[#out + 1] = row.name
		end
	end
	return out
end

-- The lines a notice of `kind` would write now: a list of lines, or nil and a code.
-- locale-key: NOTICE_TEXT_MISSING NOTICE_TEXT_OUTDATED
function AddonNotice:Preview(kind)
	if not ns.Notice.KINDS[kind] then return nil, "KIND" end
	local default = L()["NOTICE_TEXT_" .. kind]
	local template = ns.Notice.Template(self:Config(), kind, default, L()["ADDON_TITLE"])
	return ns.Notice.Compose(template, self:Names(kind))
end

-- Seconds before the next notice may leave (0 = now).
function AddonNotice:Wait()
	local cfg = self:Config()
	if not self.lastAt or cfg.minutes <= 0 then return 0 end
	local left = self.lastAt + cfg.minutes * 60 - now()
	return left > 0 and left or 0
end

local function history()
	local c = ns.Config and ns.Config.char
	if type(c) ~= "table" then return nil end
	c.addonNotices = type(c.addonNotices) == "table" and c.addonNotices or {}
	return c.addonNotices
end

-- The logged notices, oldest first: { ts, by, kind, mode = "RAID" | "WHISPER", names = {...}, lines }.
function AddonNotice:History() return history() or {} end

local function record(self, kind, mode, names, lines)
	local entry = { ts = ns.Compat.ServerTime(), by = ns.GuildRanks and ns.GuildRanks.Me() or nil, kind = kind, mode = mode,
		names = names, lines = lines }
	local h = history()
	if h and not (ns.Config and ns.Config:IsReadOnly()) then
		h[#h + 1] = entry
		while #h > self.HISTORY_MAX do table.remove(h, 1) end
	end
	log("info", "NOTICE", ns.Log and ns.Log.Plain(kind), ns.Log and ns.Log.Plain(mode), #names, lines)
	if ns.Bus then ns.Bus:Emit("ADDON_NOTICE_SENT", entry) end
	return entry
end

-- Writes the notice. Returns the log entry, or nil and a code (see the top of the file), plus the seconds left for
-- "THROTTLED".
function AddonNotice:Send(kind)
	if not ns.Notice.KINDS[kind] then return nil, "KIND" end
	local AC = ns.AddonCheck
	if not AC.raid.inRaid then return nil, "NOT_IN_RAID" end
	local ok, code = AC:CanManage()
	if not ok then return nil, code end
	local Compat = ns.Compat
	if Compat.Encounter.InProgress() then return nil, "ENCOUNTER" end
	if not Compat.Chat.CanSend() then return nil, "CHAT_BLOCKED" end
	local names = self:Names(kind)
	if #names == 0 then return nil, "NOBODY" end
	local wait = self:Wait()
	if wait > 0 then return nil, "THROTTLED", wait end
	local cfg = self:Config()
	local template = ns.Notice.Template(cfg, kind, L()["NOTICE_TEXT_" .. kind], L()["ADDON_TITLE"])
	local sent, mode
	if cfg.whisper then
		mode = "WHISPER"
		local lines, why = {}, nil
		for _, name in ipairs(names) do
			local one
			one, why = ns.Notice.ComposeWhisper(template, name)
			if not one then return nil, why end
			lines[#lines + 1] = { name = name, text = one[1] }
		end
		sent = 0
		for _, line in ipairs(lines) do
			if not Compat.Chat.Send(line.text, "WHISPER", line.name) then
				if sent == 0 then return nil, "SEND_FAILED" end
				break
			end
			sent = sent + 1
		end
	else
		mode = "RAID"
		local lines, why = ns.Notice.Compose(template, names)
		if not lines then return nil, why end
		sent = 0
		for _, line in ipairs(lines) do
			if not Compat.Chat.Send(line, "RAID") then
				if sent == 0 then return nil, "SEND_FAILED" end
				break
			end
			sent = sent + 1
		end
	end
	self.lastAt = now()
	return record(self, kind, mode, names, sent)
end

-- The Guild Master edits the wording: `fields` is a table with some of text, outdatedText, link, whisper, minutes. Written
-- as a CONFIG_CHANGED (the whole rules, the audit says who and when). Returns true, or nil and a code ("NOT_READY",
-- "NOTICE:<field>", "UNCHANGED", the permission code "NOT_GM"/... from the ledger gate).
function AddonNotice:SaveConfig(fields)
	local ledger = ns.NightController and ns.NightController:Ledger()
	local me = ns.GuildRanks and ns.GuildRanks.Me()
	if not ledger or not me or type(fields) ~= "table" then return nil, "NOT_READY" end
	local rules = ns.Rules.Current(ledger)
	for k, v in pairs(fields) do rules.notice[k] = v end
	local ok, problems = ns.Notice.ValidateConfig(rules.notice)
	if not ok then return nil, "NOTICE:" .. problems[1] end
	local gate = ns.PermissionService and ns.PermissionService:Gate() or nil
	-- the wording is not a rule of the game: the confirmation a season asks for is given by the click on Save
	local event, why = ns.Rules.Change(ledger, { author = me, ts = ns.Compat.ServerTime(), rules = rules, confirmed = true }, gate)
	if not event then return nil, why end
	if ns.Bus then ns.Bus:Emit("ADDON_NOTICE_CONFIG", rules.notice) end
	return true
end

if ns.Bus then
	ns.Bus:On("NIGHT_OPENED", function() AddonNotice:Reset() end, AddonNotice)
end
if ns.addon then ns.addon.AddonNotice = AddonNotice end   -- also reachable from tests
