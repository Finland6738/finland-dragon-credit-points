# 0008. An automatic upgrade badge by quality tier, against the gear of the fight

- Status: Accepted
- Date: 2026-11-22 (step M7-5c)

## Context

From M5-1 to M7-2b the popup asked a lot of the player and the addon guessed a lot: a weighted stat score with default weights per spec and percentage thresholds (`Data/StatWeights.lua`), personal weights imported from a Pawn-like string, a best-in-slot wishlist, an optional label (BiS, big or small upgrade, situational) with a Guild Master rule on who picks it, and a free-text note. Open question 8 ([#2](https://github.com/Finland6738/finland-dragon-credit-points/issues/2)) asked the owner whether stat weights or BiS lists were wanted; until an answer, all of it was a reversible default.

The owner answered on 2026-11-22: the player only chooses **Pass, Roll Main-spec, Roll Off-spec**, and the addon handles everything else. The badge must be simple, the same for everybody and hard to game: a player should not look like a bigger upgrade by taking a piece off after the kill.

## Decision

- **Three buttons.** A roll button sends the response and rolls in one click (the roll intent of M7-2d first, then `RandomRoll`), once per round. Labels, notes, personal weights, the import and the wishlist are removed from the code, the rules, the locales, the tests and the protocol.
- **The badge is a quality tier.** A piece's grade: purple (or better) of the current season 3, blue or an older season's purple 2, green or lower 1, empty 0. The step item − worn gives major (2+), medium (1) or minor (0 or less); a lower item level, or the same level without a step up, is no upgrade. The item-level difference always goes with it. Proficiency and slot pairing stay as in M5-1. Pure code in `Domain/UpgradeScore.lua`.
- **Seasons carry an item-level band.** `SEASON_BAND_SET{min, max}` (permission `season.manage`), set in the Season window; an epic worn below the current season's `min` counts as an older season's. The session freezes the band and sends it to the raid (`ib`), so every client reads epics the same way, members without the ledger included.
- **The gear of the fight.** `Adapters/GearSnapshot.lua` keeps the worn links at `ENCOUNTER_START` (at `ENCOUNTER_END` if the start was missed, also across a `/reload`); the badge of that boss's loot uses it for an hour. M7-5d reads the same snapshot.
- **Protocol 7, backward tolerant.** The new fields are optional; an older client's label, note, label mode and BIG / SMALL verdicts are read and ignored. Rules written before keep validating: `Rules.WithDefaults` drops the retired keys on read, and the ledger is never rewritten.

## Alternatives considered

- **Keep the stat score and only hide the inputs.** The owner wants a rule players can predict; stat weights per spec are an approximation (procs, set bonuses, caps) that invites arguments, and the client's stat API on raid gear was never verified (spike S5).
- **Compare by item level only.** Simpler still, but a new raid's purple over last season's purple would look like a small gain while it is a real step; the colour tiers with the season band say that.
- **Take the gear when the roll opens.** That is the moment a player could have swapped pieces; the start of the fight is the honest picture.
- **A guild-wide band in the rules.** A band belongs to a season's raids, not to the guild's rules: a ledger event per season keeps the history right when seasons change.

## Consequences

- Fewer moving parts: four modules, two commands, a rules section and about seventy locale keys are gone; the popup is one row of buttons.
- The badge is less precise than a good stat score for edge cases (two same-season purples with different stats are both "minor"); it only informs, the council decides.
- The Guild Master has one more thing to set per season (the band); without it every purple counts as the current season's.
- The badge is still computed by the player's own client, so a modified client can lie; the snapshot gives M7-5d something to check.
