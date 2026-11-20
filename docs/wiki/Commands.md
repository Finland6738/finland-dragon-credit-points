# Commands

> **In development.** Only the commands below exist so far; every new command is added here when it arrives. [Italiano](Commands-it)

Everything starts with `/fdcp`. Until the main window exists, `/fdcp` on its own shows the help.

| Command | What it does |
|---|---|
| `/fdcp help` | Lists the commands. |
| `/fdcp debug` | Shows what this game client offers to the addon: the client version and build, then the **features** the addon needs (master loot, loot window, roll messages, item stats, specializations, guild ranks, calendar, group roster, addon messages) and every **API** it uses, each with its state. |

## Reading `/fdcp debug`

The first line names the client build. Then each feature and each API is shown as `[state] name`, with a short note after it when there is one:

| State | Meaning |
|---|---|
| `available` | The client has it and it answered. |
| `missing` | The client does not have it: the addon turns that one feature off and goes on. |
| `unknown` | The client has the API, but nothing has shown yet whether it fills in real data (for example the loot window before the first corpse is opened). It is settled by real use. |
| `restricted` | The client is hiding the answer (a *secret value*) or a restriction is active right now, for example during a boss fight. |
| `error` | The call failed. |

`/fdcp debug` never prints player names, guild names or item names, so you can paste its output in a bug report. It checks the client again each time you run it.
