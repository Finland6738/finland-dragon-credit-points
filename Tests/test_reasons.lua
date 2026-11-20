-- Reasons (M2-7): every reason code, flag and refusal the domain emits has a sentence in English and in Italian, and the
-- regulation's three examples read the same in game as in the manual (docs/wiki/Loot-Rules.md).
local function R() return FDCP.Reasons end

local function roll(player, value)
	return { player = player, value = value, min = 1, max = 100 }
end

local function evaluate(state)
	state.costs = state.costs or { MS = 1, OS = 0 }
	return FDCP.Priority.Evaluate(state, FDCP.Priority.DefaultConfig())
end

local function sentences(group, codes, lang)
	local out = {}
	for i, code in ipairs(codes) do
		out[i] = FDCP.Locale.Text(lang, R().Key(group, code))
	end
	return out
end

describe("the code table", function()
	it("names every code with a key built from its group and code", function()
		local count = 0
		for _, group in ipairs(R().GROUPS) do
			truthy(R().KEYS[group], group)
			for code, key in pairs(R().KEYS[group]) do
				eq(key, "RC_" .. group .. "_" .. code)
				count = count + 1
			end
		end
		truthy(count > 100)
	end)

	it("has a sentence of its own in both languages for every code", function()
		for _, group in ipairs(R().GROUPS) do
			for code, key in pairs(R().KEYS[group]) do
				for _, lang in ipairs({ "enUS", "itIT" }) do
					local text = FDCP.Locale.Text(lang, key)
					truthy(text ~= key and text ~= "", lang .. " " .. key)
				end
				truthy(FDCP.Locale.Text("itIT", key) ~= FDCP.Locale.Text("enUS", key) or #code < 8, key)
			end
		end
	end)

	it("answers with the code itself for an unknown one", function()
		eq(R().Key("REASON", "NOT_A_CODE"), nil)
		eq(R().Text("REASON", "NOT_A_CODE"), "NOT_A_CODE")
		eq(R().Text("NOT_A_GROUP", "HIGHER_ROLL"), "HIGHER_ROLL")
	end)

	it("covers the codes of every proposal the three examples produce", function()
		local states = {
			{ responses = { Aurel = "MS", Bryn = "MS", Corin = "MS" }, credits = { Aurel = 0, Bryn = 0, Corin = 0 },
			  rounds = { { rolls = { roll("Aurel", 45), roll("Bryn", 76), roll("Corin", 12) } } } },
			{ responses = { Aurel = "MS", Bryn = "MS", Corin = "MS" }, credits = { Aurel = 0, Bryn = 2, Corin = 3 },
			  rounds = { { rolls = { roll("Aurel", 34), roll("Bryn", 90), roll("Corin", 99) } } } },
			{ responses = { Aurel = "MS", Bryn = "MS", Corin = "MS" }, credits = { Aurel = 1, Bryn = 1, Corin = 1 },
			  rounds = { { rolls = { roll("Aurel", 40), roll("Bryn", 88), roll("Corin", 88) } },
			             { rolls = { roll("Aurel", 100), roll("Bryn", 20), roll("Corin", 61) } } } },
		}
		for _, state in ipairs(states) do
			local r = evaluate(state)
			eq(r.status, "PROPOSAL")
			for _, code in ipairs(r.proposal.reasons) do truthy(R().Key("REASON", code), code) end
			for _, code in ipairs(r.proposal.flags) do truthy(R().Key("FLAG", code), code) end
			for _, d in ipairs(r.discarded) do truthy(R().Key("DISCARD", d.code), d.code) end
		end
	end)
end)

describe("the words of the three examples", function()
	it("ring: same credits, the higher roll wins", function()
		local r = evaluate({
			responses = { Aurel = "MS", Bryn = "MS", Corin = "MS" }, credits = { Aurel = 0, Bryn = 0, Corin = 0 },
			rounds = { { rolls = { roll("Aurel", 45), roll("Bryn", 76), roll("Corin", 12) } } },
		})
		deepEq(sentences("REASON", r.proposal.reasons, "enUS"),
			{ "Main-spec: it is asked first, and the cost is paid.", "Same credits as the others, highest roll." })
		deepEq(sentences("REASON", r.proposal.reasons, "itIT"),
			{ "Main-spec: si chiede per primo e il costo si paga.", "Stessi crediti degli altri, roll più alto." })
	end)

	it("shoulder: fewer credits win, the roll does not count", function()
		local r = evaluate({
			responses = { Aurel = "MS", Bryn = "MS", Corin = "MS" }, credits = { Aurel = 0, Bryn = 2, Corin = 3 },
			rounds = { { rolls = { roll("Aurel", 34), roll("Bryn", 90), roll("Corin", 99) } } },
		})
		eq(r.proposal.winner, "Aurel")
		eq(sentences("REASON", r.proposal.reasons, "enUS")[2], "Fewest credits: the roll did not matter.")
		eq(sentences("REASON", r.proposal.reasons, "itIT")[2], "Meno crediti: il roll non conta.")
	end)

	it("cloak: the reroll among the tied, and the roll that was set aside", function()
		local r = evaluate({
			responses = { Aurel = "MS", Bryn = "MS", Corin = "MS" }, credits = { Aurel = 1, Bryn = 1, Corin = 1 },
			rounds = { { rolls = { roll("Aurel", 40), roll("Bryn", 88), roll("Corin", 88) } },
			           { rolls = { roll("Aurel", 100), roll("Bryn", 20), roll("Corin", 61) } } },
		})
		eq(r.proposal.winner, "Corin")
		eq(sentences("REASON", r.proposal.reasons, "enUS")[2], "Tied on credits and roll, won the reroll among the tied.")
		eq(sentences("FLAG", r.proposal.flags, "enUS")[1], "Some rolls were discarded: check the list.")
		eq(sentences("DISCARD", { r.discarded[1].code }, "enUS")[1], "Not part of this round.")
		eq(sentences("DISCARD", { r.discarded[1].code }, "itIT")[1], "Non fa parte di questo round.")
	end)
end)
