-- The "Addon in the raid" panel and the /raid notice (M3-6): Domain/Notice.lua (the text and the splitting at 255
-- characters), App/AddonNotice.lua (the guards: raid, permission, encounter, throttle, log), UI/AddonPanel.lua (the rows,
-- the chip, the buttons), docs/ANALISI.md §4.1.
local REALM = "Camelot"
local function full(name) return name .. "-" .. REALM end
local function N() return FDCP.Notice end
local function AN() return FDCP.AddonNotice end
local function AC() return FDCP.AddonCheck end
local function P() return FDCP.Protocol end

local function sent() return Mock.chat.messages end

-- A raid of Aurel (the player, Guild Master) and `others`; `answers` = { name = av } who say HELLO; the rest stay silent
-- until the timeout passes.
local function raidWith(others, answers)
	local members = {}
	for i, n in ipairs(others) do members[i] = { name = n } end
	Mock.group.Set{ raid = true, members = members }
	Mock.guild.Set{ name = "Dragons", myRank = 0 }
	Mock.Advance(3)
	AC():Request()   -- asked by hand: nobody runs a night here
	Mock.Advance(2)
	for name, av in pairs(answers or {}) do
		Mock.chat.Receive("FDCP1", FDCP.Codec:Encode("HELLO", { av = av, pv = P().VERSION }), "RAID", full(name))
	end
	Mock.Advance(AC().TIMEOUT + 1)
end

local function boot(extra)
	T.boot(function(M) M.player.name, M.player.realm = "Aurel", REALM; if extra then extra(M) end end)
end

describe("the text", function()
	before_boot(function(M) M.player.name, M.player.realm = "Aurel", REALM end)

	it("fills the placeholders and starts with the tag", function()
		local t = N().Template(N().DefaultConfig(), "MISSING", "{names}: get {addon} at {link}", "Loot")
		eq(t, "[FDCP] {names}: get Loot at " .. N().DEFAULT_LINK)
		local lines = N().Compose(t, { "Aurel-Camelot", "Bryn" })
		eq(#lines, 1)
		eq(lines[1], "[FDCP] Aurel, Bryn: get Loot at " .. N().DEFAULT_LINK)
	end)

	it("the guild's text and link win over the default; a text without {names} gets them in front", function()
		local cfg = N().DefaultConfig()
		cfg.text, cfg.link = "install the addon: {link}", "https://example.org/x"
		local t = N().Template(cfg, "MISSING", "default {names}", "Loot")
		eq(t, "[FDCP] install the addon: https://example.org/x {names}")
		cfg.outdatedText = "update {names}"
		eq(N().Template(cfg, "OUTDATED", "d", "Loot"), "[FDCP] update {names}")
	end)

	it("splits the names over several lines of at most 255 characters, no name cut", function()
		local names = {}
		for i = 1, 40 do names[i] = string.format("Raider%02d-Camelot", i) end
		local t = N().Template(N().DefaultConfig(), "MISSING", "{names}: missing {addon}, see {link}", "Loot")
		local lines = N().Compose(t, names)
		truthy(#lines > 1)
		local seen = {}
		for _, line in ipairs(lines) do
			truthy(#line <= 255, "a line has " .. #line)
			truthy(line:find("^%[FDCP%] Raider"))
			for n in line:gmatch("Raider%d%d") do seen[#seen + 1] = n end
		end
		eq(#seen, 40)
		eq(seen[1], "Raider01"); eq(seen[40], "Raider40")
	end)

	it("answers NOBODY for an empty list and TEXT_TOO_LONG when the template leaves no room", function()
		local t = N().Template(N().DefaultConfig(), "MISSING", "{names}", "Loot")
		local lines, code = N().Compose(t, {})
		isNil(lines); eq(code, "NOBODY")
		lines, code = N().Compose(string.rep("x", 252) .. "{names}", { "Aurel" })
		isNil(lines); eq(code, "TEXT_TOO_LONG")
	end)

	it("validates the rules' section and the whole rules still validate", function()
		local ok, problems = N().ValidateConfig({ text = string.rep("a", 121), outdatedText = "", link = "a|b", whisper = "no", minutes = 61, x = 1 })
		falsy(ok)
		deepEq(problems, { "link", "minutes", "text", "unknown:x", "whisper" })
		truthy(N().ValidateConfig(N().DefaultConfig()))
		truthy(FDCP.Rules.Validate(FDCP.Rules.DefaultConfig()))
	end)

	it("the defaults exist in both languages and carry the three placeholders", function()
		for _, lang in ipairs({ "enUS", "itIT" }) do
			for _, kind in ipairs({ "MISSING", "OUTDATED" }) do
				local text = FDCP.Locale.Text(lang, "NOTICE_TEXT_" .. kind)
				contains(text, "{names}"); contains(text, "{addon}"); contains(text, "{link}")
			end
		end
	end)
end)

describe("sending the notice", function()
	before_boot(function(M) M.player.name, M.player.realm = "Aurel", REALM end)

	it("names who did not answer in one /raid line and logs it", function()
		raidWith({ "Bryn", "Corin", "Dara" }, { Bryn = "dev" })
		local entry = AN():Send("MISSING")
		truthy(entry)
		eq(#sent(), 1)
		eq(sent()[1].chatType, "RAID")
		contains(sent()[1].message, "Corin, Dara")
		falsy(sent()[1].message:find("Bryn"), "Bryn has the addon")
		eq(entry.mode, "RAID"); eq(entry.lines, 1)
		deepEq(entry.names, { full("Corin"), full("Dara") })
		eq(#AN():History(), 1)
		eq(AN():History()[1].kind, "MISSING")
	end)

	it("the outdated variant names only the members with an older version", function()
		P().addonVersion = "1.4.0"
		raidWith({ "Bryn", "Corin" }, { Bryn = "1.1.0", Corin = "1.5.0" })
		eq(AC():StateOf(full("Bryn")), "OUTDATED")
		local entry = AN():Send("OUTDATED")
		truthy(entry)
		contains(sent()[1].message, "Bryn")
		falsy(sent()[1].message:find("Corin"))
		local _, code = AN():Send("MISSING")
		eq(code, "NOBODY")
	end)

	it("is refused during a boss encounter and works after it", function()
		raidWith({ "Bryn" }, {})
		Mock.encounter.Start(601, "Boss")
		local entry, code = AN():Send("MISSING")
		isNil(entry); eq(code, "ENCOUNTER")
		eq(#sent(), 0)
		Mock.encounter.End(601, "Boss", true)
		truthy(AN():Send("MISSING"))
		eq(#sent(), 1)
	end)

	it("is refused while the chat is blocked", function()
		raidWith({ "Bryn" }, {})
		Mock.chat.lockdown = true
		local _, code = AN():Send("MISSING")
		eq(code, "CHAT_BLOCKED")
		Mock.chat.lockdown = false
	end)

	it("lets one notice out every N minutes", function()
		raidWith({ "Bryn" }, {})
		truthy(AN():Send("MISSING"))
		local entry, code, wait = AN():Send("MISSING")
		isNil(entry); eq(code, "THROTTLED")
		truthy(wait > 0 and wait <= 300)
		Mock.Advance(299)
		eq((select(2, AN():Send("MISSING"))), "THROTTLED")
		Mock.Advance(2)
		truthy(AN():Send("MISSING"))
		eq(#sent(), 2)
	end)

	it("splits a long list over several /raid lines", function()
		local others = {}
		for i = 1, 39 do others[i] = string.format("Raider%02d", i) end
		raidWith(others, {})
		local entry = AN():Send("MISSING")
		truthy(entry)
		truthy(#sent() > 1)
		eq(entry.lines, #sent())
		for _, m in ipairs(sent()) do truthy(#m.message <= 255); eq(m.chatType, "RAID") end
	end)

	it("whispers each name when the rules say so", function()
		raidWith({ "Bryn", "Corin" }, {})
		truthy(AN():SaveConfig({ whisper = true }))
		local entry = AN():Send("MISSING")
		truthy(entry)
		eq(entry.mode, "WHISPER")
		eq(#sent(), 2)
		eq(sent()[1].chatType, "WHISPER"); eq(sent()[1].target, full("Bryn"))
		eq(sent()[2].target, full("Corin"))
	end)

	it("needs a raid and a permission", function()
		local _, code = AN():Send("MISSING")
		eq(code, "NOT_IN_RAID")
		raidWith({ "Bryn" }, {})
		Mock.guild.SetMyRank(3)
		Mock.Advance(3)
		_, code = AN():Send("MISSING")
		eq(code, "RANK_TOO_LOW")
		eq(#sent(), 0)
	end)

	it("the Guild Master changes the wording through the rules, with the audit", function()
		raidWith({ "Bryn" }, {})
		truthy(AN():SaveConfig({ text = "{names}: install {addon} ({link})", link = "https://example.org/a", minutes = 0 }))
		truthy(AN():Send("MISSING"))
		eq(sent()[1].message, "[FDCP] Bryn: install Finland Dragon Credit Points (https://example.org/a)")
		truthy(AN():Send("MISSING"), "minutes = 0: no limit")
		local ok, code = AN():SaveConfig({ minutes = 99 })
		isNil(ok); eq(code, "NOTICE:minutes")
	end)
end)

describe("the panel", function()
	before_boot(function(M) M.player.name, M.player.realm = "Aurel", REALM end)

	local function frame() return FDCP.MainWindow:Build() end
	local function visibleRows()
		local out = {}
		for _, r in ipairs(FDCP.AddonPanel.root.rows) do
			if r:IsShown() then out[#out + 1] = { r.name:GetText(), r.state:GetText() } end
		end
		return out
	end

	it("shows one row per raid member, the missing ones first, and the summary", function()
		raidWith({ "Bryn", "Corin", "Dara" }, { Bryn = "dev", Dara = "dev" })
		Mock.Slash("/fdcp")
		local root = FDCP.AddonPanel.root
		eq(root.summary:GetText(), "3/4 with the addon")
		local rows = visibleRows()
		eq(#rows, 4)
		deepEq(rows[1], { "Corin", "Addon not active" })
		eq(rows[4][2], "Active")
		truthy(FDCP.AddonPanel.chip:IsShown())
	end)

	it("every text of the panel exists in both languages", function()
		for _, lang in ipairs({ "enUS", "itIT" }) do
			for _, key in ipairs({ "ADDON_PANEL_TITLE", "ADDON_PANEL_ASK", "ADDON_PANEL_NOTIFY", "ADDON_PANEL_NOTIFY_OUTDATED",
				"ADDON_PANEL_FORBIDDEN", "ADDON_PANEL_NO_RAID", "NOTICE_SENT", "NOTICE_ERR_ENCOUNTER", "NOTICE_ERR_THROTTLED" }) do
				local text = FDCP.Locale.Text(lang, key)
				truthy(text ~= key and text ~= "", lang .. " " .. key)
			end
		end
	end)

	it("the button writes in /raid and the second click says to wait", function()
		raidWith({ "Bryn" }, {})
		Mock.Slash("/fdcp")
		local root = FDCP.AddonPanel.root
		root.notify:Click()
		eq(#sent(), 1)
		contains(root.message:GetText(), "/raid")
		root.notify:Click()
		eq(#sent(), 1)
		contains(root.message:GetText(), "Wait")
	end)

	it("refuses during an encounter with a message", function()
		raidWith({ "Bryn" }, {})
		Mock.Slash("/fdcp")
		Mock.encounter.Start(601, "Boss")
		FDCP.AddonPanel.root.notify:Click()
		eq(#sent(), 0)
		contains(FDCP.AddonPanel.root.message:GetText(), "boss fight")
	end)

	it("a member without the permission sees no buttons and no chip", function()
		raidWith({ "Bryn" }, {})
		Mock.guild.SetMyRank(3)
		Mock.Advance(3)
		Mock.Slash("/fdcp")
		FDCP.AddonPanel:Refresh()
		falsy(FDCP.AddonPanel.root.notify:IsShown())
		falsy(FDCP.AddonPanel.chip:IsShown())
		contains(FDCP.AddonPanel.root.empty:GetText(), "officers")
	end)

	it("outside a raid it says so", function()
		Mock.guild.Set{ name = "Dragons", myRank = 0 }
		Mock.Advance(3)
		Mock.Slash("/fdcp")
		FDCP.AddonPanel:Refresh()
		contains(FDCP.AddonPanel.root.empty:GetText(), "raid group")
	end)
end)
