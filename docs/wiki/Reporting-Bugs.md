# Reporting Bugs

> **Built, not yet seen in the game.** The report works in the offline tests; how the window looks in the real game is still to be confirmed. [Italiano](Reporting-Bugs-it)

Something does not work? A good report is the fastest way to a fix. The addon writes most of it for you.

## 1. Get the bug report

Type `/fdcp debug`. A window opens with the **bug report**, already selected. Press **Ctrl+C** to copy it (an addon cannot write to the clipboard by itself; if the selection was lost, click **Select all**). **Refresh** builds it again. `/fdcp debug chat` writes the same text in the chat instead.

The report holds:

- the addon version, the message protocol and the language;
- the game client (version, build) and what it offers to the addon: each feature and each API with its state (see [[Commands|Commands]]);
- the state of the addon's parts: the message queue and counters, the size of the ledger, the night, the session, the permissions, the sync with the officers, the addon check of the raid;
- **the errors of the addon**: the last ten different Lua errors raised by FDCP's own files, each with how many times it came. Errors of other addons are not kept;
- the addon's own log (the last lines).

## 2. It holds no names

The report is made to be pasted in public:

- no player names, no guild name, no realm, no item names;
- an error message keeps its file and line and its words, but anything between quotes becomes `<text>` and the folders disappear;
- a last pass removes every name the addon knows (you, your guild, the roster of the season) and writes `<name>` in its place.

Read it before you paste it anyway: if you see something you do not want to publish, delete that line.

## 3. Open an issue

Go to the repository's issues (the link is in the **Info** page of Settings, see [[About|About]]), choose **Bug report** and fill the form: what happened, how to repeat it, the addon version and the report. You can write in English or in Italian. A **Feature request** form is there for ideas.

If the game shows a Lua error window (or you use an error display addon), copy its text as well: it helps, but check it for names first, because only the addon's own report is cleaned.

## Tips for a useful report

- Say what you did, what you expected and what you saw.
- Say whether you were the master looter, an officer or a raider, and whether the others had the addon.
- If it happened in a raid, open the report soon after: the log keeps only the last lines.
