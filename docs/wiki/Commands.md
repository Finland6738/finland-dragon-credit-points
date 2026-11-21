# Commands

> **In development.** Only the commands below exist so far; every new command is added here when it arrives. [Italiano](Commands-it)

Everything starts with `/fdcp`: on its own it opens (or closes) the main window.

| Command | What it does |
|---|---|
| `/fdcp` or `/fdcp toggle` | Opens the main window, or closes it when it is open. |
| `/fdcp help` | Lists the commands. |
| `/fdcp theme [nebula\|aurora\|drago]` | Shows the theme, or sets it. It changes at once, no `/reload` needed. |
| `/fdcp weights [on\|off\|import <spec> <string>\|show <spec>\|reset <spec\|all>]` | Your own stat weights for the upgrade hints: import them from a Pawn-like string, show, switch on or off, remove. See [Upgrade Hints](Upgrade-Hints). |
| `/fdcp wish [list\|add <item>\|remove <item>\|clear]` | Your own best-in-slot list: the popup reminds you when one of the items is up for grabs. See [Upgrade Hints](Upgrade-Hints). |
| `/fdcp debug` | Shows what this game client offers to the addon: the client version and build, then the **features** the addon needs (master loot, loot window, roll messages, item stats, specializations, guild ranks, calendar, group roster, addon messages) and every **API** it uses, each with its state, then the counters of the addon's own messages (see below). |
| `/fdcp language [auto\|<code>]` | Shows the language of the addon, or sets your personal one (`auto` follows the game client). The change applies after `/reload`. English (`enUS`) and Italian (`itIT`) exist so far. |

## Reading `/fdcp debug`

The first line names the client build. Then each feature and each API is shown as `[state] name`, with a short note after it when there is one:

| State | Meaning |
|---|---|
| `available` | The client has it and it answered. |
| `missing` | The client does not have it: the addon turns that one feature off and goes on. |
| `unknown` | The client has the API, but nothing has shown yet whether it fills in real data (for example the loot window before the first corpse is opened). It is settled by real use. |
| `restricted` | The client is hiding the answer (a *secret value*) or a restriction is active right now, for example during a boss fight. |
| `error` | The call failed. |

### The message counters

The last lines of `/fdcp debug` describe the addon's messages to other players: whether they are being held back (`held (lockdown)`, `held (encounter)`, or a restriction name; `read-only` when the game forbids addon messages), how many wait in the queue per channel (raid, guild, officer, whisper), how many were sent, failed, delayed or dropped, how many arrived, how many were your own echo, and how many were rejected (unknown or newer protocol, damaged). Messages wait during a boss fight and the chat lockdown and go out afterwards; they also survive `/reload`.

The `/fdcp debug` output also has two **UI lines**: the active theme, how many text styles use the addon's own fonts and how many fell back to the game's fonts, how many textures the client refused, and what the client answered to a few interface probes (ScrollBox lists, data providers, rounded 9-slice shapes, additive glow, the icon sheet, the size of one screen pixel and the UI scale). They help the author check the look in the game.

A line **Addon check** sums up who in your raid runs the addon: "37/40 with the addon", then how many are active, need an update, have an incompatible version, have no active addon or are still waited for, your own addon and protocol versions, and how many presence questions and answers arrived. Every raider's addon answers by itself when it joins the raid; the officer running the night asks again when the night opens and when someone joins. Only raiders with a compatible addon can roll.

A **Permissions** line says whether the guild roster has been read this session (`loaded` or `loading`), your guild rank by position (0 is the Guild Master) and how many events from other players wait for the roster.

`/fdcp debug` never prints player names, guild names or item names, so you can paste its output in a bug report. It checks the client again each time you run it.
