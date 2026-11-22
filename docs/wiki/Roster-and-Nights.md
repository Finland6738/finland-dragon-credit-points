# Roster and Nights

> **Built, not yet seen in the game.** The windows work in the offline tests with a simulated client; how they look and feel in the real game is still to be confirmed. [Italiano](Roster-and-Nights-it)

The **Roster** tab has three sub-tabs: **Pool**, **Night** and **Addon** ([[Addon Check|Addon-Check]]). The look follows the community site's roster page.

## Pool

The raiders of the season, as on the site: one card each for **Tank**, **Healer** and **DPS**.

- The top right switch picks the faction (**Horde** / **Alliance**); it starts on your own.
- Each card shows the count against the target, for example **1/2**, a thin gradient bar, and "N free slots" while the role is not full. The targets come from the raid size of the season's pack and the guild's minimum of tanks and healers; the rest of the slots are damage dealers.
- Each row has a square in the class colour, the name (with `+2` when the player has two alts), the declared main spec and a **TRIAL** mark for members on trial. Scroll a long card with the mouse wheel.
- Under the title, a line counts the players, the ones on trial and the ones who have not declared a spec.

### Officers

Anyone with the permission *manage the roster* (officers by default) also sees:

- **Make Trial / Make Raider** on every row: changes the member's status. The change is written in the ledger and logged like every other.
- **Requests to approve**: the declarations to join the pool and the alt links that players ask for. **Approve** writes the member (with the late-joiner credits of the guild's rules) or the alt link; **Reject** drops the request.

Members see the pool but no buttons and no requests.

## Night

The official raid night.

- **Open the night** (anyone with the permission *run the night*, officers by default): pick the instance of the season's pack and the difficulty, then open. When you stand inside the instance it is already selected. The lineup is read from the raid group at once.
- **Close the night** when the raid is over.
- The **lineup** has three columns: **In the raid**, **Bench** and **Absent**. The button on each row moves a player: a raider to the bench, a benched player back into the raid, an absent one into the raid. Only the officer who opened the night or its master looter records changes from the raid group; others' clients leave them alone.
- **Propose the bench** asks the rotation who should sit out (the fewest benches in the season first, the declared and calendar availability respected, the minimum of tanks and healers kept). Nothing is written until the master looter presses **Apply the bench** (when the night is already open) or opens the night with the proposal in place.
- **Bench myself** (every player, M7-5b): you sit out tonight on your own initiative. On the client of the officer running the night it is written at once; from anyone else the request goes to that officer's addon, which writes it as a self-bench. A self-bench **costs +1 credit** (see [[Loot Rules|Loot-Rules]], Absences); a bench decided by the officers never does. To come back, ask the master looter to move you into the raid.
- **Absence penalties (officers)**: after **Close the night** the tab lists the proposed penalties, for example *Absence penalties proposed (2, +1 each): Dara (signed up, did not come), Edda (not signed up)*, and **Confirm the penalties** writes them in one click (+1 credit each, reason *Absence from an official night*). Nothing is written before the click unless the Guild Master turned on the automatic writing. A penalty can be cancelled like any correction.
- **Attendance (officers only)**: a table with, for every player, the nights played, the nights only benched, the bosses attended out of those possible and the percentage. Click a header to sort. Members never see this table, as the guild decided.

Every refusal says why in the window: a rank that is too low, no season open, an instance that is not an official raid of the season, a night already open, and so on.
