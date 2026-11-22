-- Automatic response labels (M7-2b): Domain/Labels.lua (the rule `responses.labelMode`, the suggestion, the origin), the rule
-- inside the guild's rules (validated, filled in for older rules, edited from the Settings form), and App/PopupBoard.lua's
-- settling of an answer (the label and who chose it). The popup, the protocol and the master looter's window are in
-- test_ui_popup.lua, test_protocol_session.lua and test_ui_ml_session.lua.
local function LB() return FDCP.Labels end
local function R() return FDCP.Rules end
local function PB() return FDCP.PopupBoard end

local ME = "Bryn-Camelot"

local function view(mode)
	return { s = "S1-1", q = 3, ml = "Aurel-Camelot", e = 663, tiers = { MS = 1, OS = 2 }, mine = {}, responses = {},
		labelMode = mode, items = { { id = 19003, ca = "jewelry", cs = { MS = 1, OS = 0 }, st = "ROLLING" } },
		a = 1, round = { i = 1, r = 1, k = "ROLL", g = "TIER", tr = 1, cl = true, deadline = 130 } }
end

-- An upgrade advice with a main-spec verdict (what UpgradeAdvisor.For returns, reduced to what the board reads).
local function advice(verdict, usable)
	return { ms = { verdict = verdict, usable = usable }, specs = {}, wire = {} }
end

local function build(v, env)
	env = env or {}
	env.me, env.now = env.me or ME, env.now or 100
	return PB().Build(v, env).cards[1]
end

describe("the suggestion", function()
	before_boot(function() end)

	it("is BiS for a wishlist item, whatever the verdict says", function()
		eq(LB().Suggest(true, { verdict = "SMALL", usable = true }), "BIS")
		eq(LB().Suggest(true, nil), "BIS")
	end)

	it("follows the main-spec verdict: big upgrade, small upgrade, otherwise nothing", function()
		eq(LB().Suggest(false, { verdict = "BIG", usable = true }), "BIG_UPGRADE")
		eq(LB().Suggest(false, { verdict = "SMALL", usable = true }), "SMALL_UPGRADE")
		isNil(LB().Suggest(false, { verdict = "NONE", usable = true }))
		isNil(LB().Suggest(false, { verdict = "NOT_COMPARABLE", usable = true }))
		isNil(LB().Suggest(false, { verdict = "BIG", usable = false }), "an item the character cannot use gets no label")
		isNil(LB().Suggest(false, nil))
		isNil(LB().Suggest(nil, "BIG"), "not a verdict table")
	end)

	it("never suggests the situational label", function()
		for _, verdict in ipairs({ "BIG", "SMALL", "NONE", "NOT_COMPARABLE" }) do
			truthy(LB().Suggest(false, { verdict = verdict, usable = true }) ~= "SITUATIONAL")
		end
		truthy(LB().Suggest(true, nil) ~= "SITUATIONAL")
	end)

	it("says where a label comes from", function()
		eq(LB().OriginOf("BIS", "BIS"), "AUTO")
		eq(LB().OriginOf("BIG_UPGRADE", "BIS"), "CHANGED")
		eq(LB().OriginOf("SITUATIONAL", nil), "MANUAL")
		isNil(LB().OriginOf(nil, "BIS"))
		eq(LB().Origin("AUTO"), "AUTO"); eq(LB().Origin("CHANGED"), "CHANGED"); eq(LB().Origin("MANUAL"), "MANUAL")
		isNil(LB().Origin("auto")); isNil(LB().Origin(7)); isNil(LB().Origin(nil))
	end)

	it("leaves the label to the player when the mode is unknown or missing (an older master looter)", function()
		eq(LB().Mode("auto"), "auto"); eq(LB().Mode("suggest"), "suggest"); eq(LB().Mode("manual"), "manual")
		eq(LB().Mode(nil), "manual"); eq(LB().Mode("random"), "manual"); eq(LB().Mode(3), "manual")
	end)

	it("has words for every origin in both languages", function()
		for _, code in ipairs({ "AUTO", "CHANGED", "MANUAL" }) do
			local key = FDCP.Reasons.Key("LABEL_ORIGIN", code)
			truthy(key, code)
			for _, lang in ipairs({ "enUS", "itIT" }) do
				truthy(FDCP.Locale.Text(lang, key) ~= key, lang .. " " .. code)
			end
		end
		eq(FDCP.Locale.Text("itIT", "RC_LABEL_ORIGIN_CHANGED"), "Suggerita dall'addon, cambiata dal giocatore")
	end)
end)

describe("the rule responses.labelMode", function()
	before_boot(function() end)

	it("defaults to suggest and validates", function()
		eq(R().DefaultConfig().responses.labelMode, "suggest")
		truthy(R().Validate(R().DefaultConfig()))
		for _, mode in ipairs({ "auto", "suggest", "manual" }) do
			local c = R().DefaultConfig()
			c.responses.labelMode = mode
			truthy(R().Validate(c), mode)
		end
	end)

	it("names the field at fault", function()
		for _, bad in ipairs({ "random", "", 1, true }) do
			local c = R().DefaultConfig()
			c.responses.labelMode = bad
			local ok, problems = R().Validate(c)
			falsy(ok)
			deepEq(problems, { "responses.labelMode" })
		end
		local c = R().DefaultConfig()
		c.responses.extra = 1
		local ok, problems = R().Validate(c)
		falsy(ok); deepEq(problems, { "responses.unknown:extra" })
		c = R().DefaultConfig()
		c.responses = nil
		ok, problems = R().Validate(c)
		falsy(ok); deepEq(problems, { "responses" })
	end)

	it("is filled in for rules written before it existed", function()
		local old = R().DefaultConfig()
		old.responses = nil
		eq(R().WithDefaults(old).responses.labelMode, "suggest")
		old.responses = {}
		eq(R().WithDefaults(old).responses.labelMode, "suggest")
		local kept = R().DefaultConfig()
		kept.responses.labelMode = "manual"
		eq(R().WithDefaults(kept).responses.labelMode, "manual", "what the guild wrote stays")
	end)

	it("is a field of the Settings form, on the Priority page, read and written like the others", function()
		local f = FDCP.RuleFields.Field("responses.labelMode")
		truthy(f); eq(f.page, "priority"); eq(f.kind, "choice")
		local rules = R().DefaultConfig()
		eq(FDCP.RuleFields.Get(rules, f), "suggest")
		truthy(FDCP.RuleFields.Set(rules, f, "auto"))
		eq(rules.responses.labelMode, "auto")
		truthy(R().Validate(rules))
		eq(FDCP.RuleFields.PageOfCode("responses.labelMode"), "priority")
		for _, o in ipairs(f.options) do truthy(FDCP.L[o.key] ~= o.key, o.key) end
		deepEq(R().Diff(R().DefaultConfig(), rules), { "responses.labelMode" })
	end)

	it("is the same in every preset", function()
		for _, id in ipairs(FDCP.Presets.ORDER) do
			eq(FDCP.Presets.Get(id).responses.labelMode, "suggest", id)
		end
	end)
end)

describe("the popup board's label", function()
	before_boot(function() end)

	it("in manual mode (and for a master looter that says nothing) is the player's own, as before", function()
		for _, mode in ipairs({ "manual", false }) do
			local v = view(mode or nil)
			local c = build(v, { wish = function() return true end, upgrade = function() return advice("BIG", true) end })
			eq(c.labelMode, "manual"); isNil(c.suggestion); isNil(c.label); isNil(c.labelHint); truthy(c.labelsOn)
		end
		local v = view("manual")
		v.responses[1] = { [ME] = { rs = "MS", lb = "BIG_UPGRADE" } }
		local c = build(v)
		eq(c.label, "BIG_UPGRADE"); eq(c.labelOrigin, "MANUAL", "a label with no recorded origin is the player's")
	end)

	it("in suggest mode fills the label in before an answer, from the wishlist first and the verdict second", function()
		local v = view("suggest")
		local c = build(v, { upgrade = function() return advice("BIG", true) end })
		eq(c.labelMode, "suggest"); eq(c.suggestion, "BIG_UPGRADE"); eq(c.label, "BIG_UPGRADE"); eq(c.labelOrigin, "AUTO")
		eq(c.labelHint, "SUGGEST"); truthy(c.labelsOn)
		c = build(v, { upgrade = function() return advice("SMALL", true) end })
		eq(c.label, "SMALL_UPGRADE")
		c = build(v, { upgrade = function() return advice("BIG", true) end, wish = function() return true end })
		eq(c.label, "BIS"); truthy(c.wish)
		c = build(v, { upgrade = function() return advice("NONE", true) end })
		isNil(c.label); isNil(c.labelOrigin); isNil(c.labelHint, "nothing to suggest, nothing to say")
		c = build(v)
		isNil(c.label)
	end)

	it("in suggest mode keeps what the player answered, even without a label", function()
		local v = view("suggest")
		v.responses[1] = { [ME] = { rs = "MS", lb = "SITUATIONAL", lo = "CHANGED" } }
		local env = { upgrade = function() return advice("BIG", true) end }
		local c = build(v, env)
		eq(c.label, "SITUATIONAL"); eq(c.labelOrigin, "CHANGED"); eq(c.suggestion, "BIG_UPGRADE")
		v.responses[1] = { [ME] = { rs = "MS" } }
		c = build(v, env)
		isNil(c.label, "the answer was sent without a label: it stays so"); isNil(c.labelOrigin)
		v.responses[1] = { [ME] = { rs = "OS", lb = "BIS", lo = "AUTO" } }
		isNil(build(v, env).label, "off-spec carries no label")
	end)

	it("in auto mode is always the addon's, with the chips locked and the line that says why", function()
		local v = view("auto")
		local env = { upgrade = function() return advice("SMALL", true) end }
		local c = build(v, env)
		eq(c.label, "SMALL_UPGRADE"); eq(c.labelOrigin, "AUTO"); eq(c.labelHint, "AUTO"); falsy(c.labelsOn)
		truthy(c.canAnswer, "the response itself is still the player's")
		v.responses[1] = { [ME] = { rs = "MS", lb = "BIS", lo = "MANUAL" } }
		c = build(v, env)
		eq(c.label, "SMALL_UPGRADE", "what the player once sent does not count in auto mode")
		v.responses[1] = { [ME] = { rs = "OS" } }
		isNil(build(v, env).label)
		c = build(view("auto"), { upgrade = function() return advice("NONE", true) end })
		isNil(c.label); eq(c.labelHint, "AUTO"); falsy(c.labelsOn)
	end)

	it("has no hint in a round that does not collect the responses", function()
		local v = view("auto")
		v.round.cl = nil
		v.responses[1] = { [ME] = { rs = "MS" } }
		local c = build(v)
		isNil(c.labelHint); isNil(c.labels)
	end)
end)

describe("settling an answer", function()
	before_boot(function() end)

	local function card(mode, suggestion) return { main = "MS", labelMode = mode, suggestion = suggestion } end

	it("sends no label with anything but the main-spec", function()
		for _, mode in ipairs({ "auto", "suggest", "manual" }) do
			for _, rs in ipairs({ "OS", "PASS", "TMOG" }) do
				local d = PB().Settle(card(mode, "BIS"), { rs = rs, lb = "BIS", lo = "AUTO" })
				isNil(d.lb); isNil(d.lo)
			end
		end
	end)

	it("auto: the suggestion, whatever the draft held", function()
		local d = PB().Settle(card("auto", "BIG_UPGRADE"), { rs = "MS", lb = "BIS", lo = "MANUAL" })
		eq(d.lb, "BIG_UPGRADE"); eq(d.lo, "AUTO")
		d = PB().Settle(card("auto", nil), { rs = "MS", lb = "BIS", lo = "MANUAL" })
		isNil(d.lb); isNil(d.lo)
	end)

	it("suggest: the player's label, or the suggestion unless the player cleared it", function()
		local c = card("suggest", "BIS")
		local d = PB().Settle(c, { rs = "MS" })
		eq(d.lb, "BIS"); eq(d.lo, "AUTO")
		d = PB().Settle(c, { rs = "MS", lb = "SITUATIONAL", lo = "CHANGED" })
		eq(d.lb, "SITUATIONAL"); eq(d.lo, "CHANGED")
		d = PB().Settle(c, { rs = "MS", cleared = true })
		isNil(d.lb); isNil(d.lo)
		d = PB().Settle(card("suggest", nil), { rs = "MS" })
		isNil(d.lb)
	end)

	it("manual: the player's label, with an origin", function()
		local c = card("manual", "BIS")
		c.suggestion = nil
		local d = PB().Settle(c, { rs = "MS", lb = "SITUATIONAL" })
		eq(d.lb, "SITUATIONAL"); eq(d.lo, "MANUAL")
		d = PB().Settle(c, { rs = "MS" })
		isNil(d.lb); isNil(d.lo)
	end)

	it("a chip toggles, says whether the player changed the suggestion, and clearing it is final", function()
		local c = card("suggest", "BIS")
		local d = PB().Pick(c, { rs = "MS", lb = "BIS", lo = "AUTO" }, "BIG_UPGRADE")
		eq(d.lb, "BIG_UPGRADE"); eq(d.lo, "CHANGED"); falsy(d.cleared)
		d = PB().Pick(c, d, "BIS")
		eq(d.lo, "AUTO", "the player chose the same label as the suggestion")
		d = PB().Pick(c, d, "BIS")
		isNil(d.lb); isNil(d.lo); truthy(d.cleared)
		d = PB().Settle(c, d)
		isNil(d.lb, "the suggestion does not come back after the player took it off")
		d = PB().Pick(card("manual", nil), { rs = "MS" }, "SITUATIONAL")
		eq(d.lb, "SITUATIONAL"); eq(d.lo, "MANUAL")
	end)
end)
