# Commands

> **In development.** Only the commands below exist so far; every new command is added here when it arrives. [Italiano](Commands-it)

Everything starts with `/fdcp`. Until the main window exists, `/fdcp` on its own shows the help.

| Command | What it does |
|---|---|
| `/fdcp help` | Lists the commands. |
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

`/fdcp debug` never prints player names, guild names or item names, so you can paste its output in a bug report. It checks the client again each time you run it.
