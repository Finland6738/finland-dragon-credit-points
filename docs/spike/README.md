# Spike procedure (M0) / Procedura dello spike

The probe addon `FDCP_Probe` answers, in the real WoW Forever client, the questions the analysis cannot answer offline ([`docs/ANALISI.md`](../ANALISI.md) §1 "Non ancora verificato", §11, §12). It is **never distributed**, wraps every call in `pcall`, never compares a secret value, uses the test prefix `FDCPP` (never `FDCP1`) and never prints or stores player or guild names (counts and shapes only).

La sonda `FDCP_Probe` risponde, nel client reale di WoW Forever, alle domande a cui l'analisi non sa rispondere offline. **Non viene mai distribuita**, protegge ogni chiamata con `pcall`, non confronta mai un valore secret, usa il prefisso di test `FDCPP` (mai `FDCP1`) e non stampa né salva mai nomi di giocatori o di gilda (solo conteggi e forme).

> Status / Stato: **probe ready, results pending owner run** / **sonda pronta, risultati in attesa dell'esecuzione del proprietario**. The skeleton (M0-1) has the baseline checks `B1`–`B4`; the checks of the spike areas S1–S8 arrive with M0-2 … M0-6 (S1–S3 are in), and M0-6 finalises this procedure.

## 1. Install / Installazione

1. Copy `tools/local.example.ini` to `tools/local.ini` (git-ignored) and set `folder` to your WoW folder (the one that contains `_forever_`). / Copia `tools/local.example.ini` in `tools/local.ini` (ignorato da git) e imposta `folder` con la cartella di WoW (quella che contiene `_forever_`).
2. Run / Esegui:

   ```bash
   python tools/install_probe.py
   ```

   It links `tools/probe/FDCP_Probe/` into `<WoW folder>/_forever_/Interface/AddOns/` (a junction on Windows; use `--copy` to copy, `--uninstall` to remove). / Collega `tools/probe/FDCP_Probe/` in `<WoW folder>/_forever_/Interface/AddOns/` (una junction su Windows; `--copy` per copiare, `--uninstall` per rimuovere).
3. Start the game, enable **FDCP Probe** in the add-on list, log in. / Avvia il gioco, abilita **FDCP Probe** nella lista degli addon, entra.

## 2. Commands / Comandi

| Command | What it does / Cosa fa |
|---|---|
| `/fdcpp list` | Lists the checks and their last result. / Elenca i check e l'ultimo risultato. |
| `/fdcpp run <id>` | Runs one check (for example `/fdcpp run B2`) and records the result. / Esegue un check e ne registra il risultato. |
| `/fdcpp runall` | Runs every check that needs no manual setup. / Esegue ogni check che non richiede preparazione. |
| `/fdcpp setml` | S1: tries to set the loot method to master loot with you as master looter (changes the group; raid leader only). / S1: prova a impostare il bottino su master loot con te come master looter (modifica il gruppo; solo capo raid). |
| `/fdcpp give <slot> <candidate#>` | S2: calls `GiveMasterLoot` on a **test drop** and records the events. / S2: chiama `GiveMasterLoot` su un drop **di prova** e registra gli eventi. |
| `/fdcpp roll` | S3: rolls 1-100 with `RandomRoll` and records whether the system messages come back readable. / S3: tira 1-100 con `RandomRoll` e registra se i messaggi di sistema tornano leggibili. |
| `/fdcpp export` | Opens a frame with every result (and the recorded events) as selected text: copy it with Ctrl+C. / Apre una finestra con tutti i risultati (e gli eventi registrati) come testo selezionato: copialo con Ctrl+C. |
| `/fdcpp reset` | Clears results and events. / Cancella risultati ed eventi. |

Results are stored in `FDCP_ProbeDB` as `{id, result, details, build, time}` (result: `ok`, `fail`, `partial`, `info` or `error`). The event recorder logs event name, time, encounter state, restriction state and which arguments are secret values: never names or message text.

I risultati sono salvati in `FDCP_ProbeDB` come `{id, result, details, build, time}`. Il registratore di eventi annota nome dell'evento, tempo, stato dell'incontro, stato delle restrizioni e quali argomenti sono valori secret: mai nomi o testo dei messaggi.

## 3. Baseline checks / Check di base

| Id | What it checks / Cosa verifica |
|---|---|
| `B1` | Build, interface and locale. / Build, interface e locale. |
| `B2` | The guarded APIs the addon relies on exist (secret values, restrictions, chat lockdown, `C_EncodingUtil`, loot, calendar, guild). / Esistono le API protette su cui l'addon fa affidamento. |
| `B3` | Group and instance context (counts only). / Contesto di gruppo e istanza (solo conteggi). |
| `B4` | The test prefix `FDCPP` registers. / Il prefisso di test `FDCPP` si registra. |

## 4. Spike areas / Aree dello spike

### S1, S2 — Master loot and the loot window (M0-2)

Checks: `S1a` (APIs, loot method, master looter state), `S1b` (`/fdcpp setml`), `S2a` (loot window slots, links, sources), `S2b` (master loot candidates), `S2c` (`/fdcpp give`), `S2d` (`ADDON_ACTION_BLOCKED` / `FORBIDDEN` log). The loot window is captured automatically on `LOOT_OPENED` as shapes only: item link and name are recorded as `string(n)`, the source GUID as type, segment count and the npc id of a creature (which maps a source to a boss), never the GUID, item names or player names.

**Procedure (English)**

1. Form a raid (as raid leader, with at least a second character or player) in a Forever raid instance. Repeat in the sizes and difficulties you can reach: 10, 20 and 40 players, Normal and Veteran.
2. `/fdcpp run S1a` before and `/fdcpp setml` to try to set master loot with you as master looter; wait a second and `/fdcpp run S1a` again. **S1 answers**: is master loot selectable, and is the method kept in every size and difficulty?
3. Kill a boss (or any creature that drops loot) and open its loot window. Then `/fdcpp run S2a` and `/fdcpp run S2b`. **S2 answers**: are slots, sources (boss mapping) and candidates readable?
4. On a **test drop** (an item you do not mind giving to a second character), `/fdcpp give <slot> <candidate#>` (slot as shown by `S2a`, candidate between 1 and the `candidates` count). After two seconds the result shows the events seen (`LOOT_SLOT_CLEARED`, `CHAT_MSG_LOOT`). **S2 answers**: does `GiveMasterLoot` deliver when called from an addon command?
5. `/fdcpp run S2d` for any blocked or forbidden action, then `/fdcpp export` and report the text.

**Procedura (italiano)**

1. Forma un raid (come capo raid, con almeno un secondo personaggio o giocatore) in un'istanza raid di Forever. Ripeti nelle dimensioni e difficoltà che riesci a raggiungere: 10, 20 e 40 giocatori, Normale e Veterano.
2. `/fdcpp run S1a` prima, poi `/fdcpp setml` per provare a impostare il master loot con te come master looter; aspetta un secondo e rilancia `/fdcpp run S1a`. **S1 risponde**: il master loot è selezionabile e il metodo resta in ogni dimensione e difficoltà?
3. Uccidi un boss (o una creatura che lascia bottino) e apri la finestra del bottino. Poi `/fdcpp run S2a` e `/fdcpp run S2b`. **S2 risponde**: slot, fonti (collegamento al boss) e candidati sono leggibili?
4. Su un **drop di prova** (un oggetto che puoi dare a un secondo personaggio), `/fdcpp give <slot> <candidato#>` (slot come mostrato da `S2a`, candidato tra 1 e il numero `candidates`). Dopo due secondi il risultato mostra gli eventi visti (`LOOT_SLOT_CLEARED`, `CHAT_MSG_LOOT`). **S2 risponde**: `GiveMasterLoot` consegna se chiamato da un comando dell'addon?
5. `/fdcpp run S2d` per eventuali azioni bloccate o vietate, poi `/fdcpp export` e riporta il testo.

Plan B if negative: delivery by trade (M4-7). / Piano B se negativo: consegna con scambio (M4-7).

### S3 — Rolls, system messages and encounters (M0-3)

Checks: `S3a` (the roll and loot patterns are built from the game globals `RANDOM_ROLL_RESULT` and `LOOT_ITEM*`, never written by hand, with a self-test), `S3b` (`/fdcpp roll`), `S3c` (the answer: per context, how many `CHAT_MSG_SYSTEM` messages arrived, how many were secret values and how many were readable rolls), `S3d` (restriction state and `ENCOUNTER_START/END` timeline), `S3e` (`CHAT_MSG_LOOT` messages matched by the `LOOT_ITEM` patterns). The probe counts messages per context: `outside` an instance, `instance` between bosses, `encounter` (`IsEncounterInProgress`) and `after` (the 10 seconds following `ENCOUNTER_END`). A secret message is only counted, never compared or matched; names, roll texts and item links are never stored.

**Procedure (English)**

1. `/fdcpp run S3a` (self-test of the patterns; it should be `ok`).
2. Outside an instance, in a party or raid with at least one other player, both of you `/roll` (or you `/fdcpp roll` and the other player `/roll`). `/fdcpp run S3c`: look at the `outside` counters.
3. Inside the raid instance **between bosses** repeat the rolls (the other player rolls too), then `/fdcpp run S3c` (`instance` counters).
4. **During a boss fight** you and the other player `/roll` once; after the kill (within 10 seconds of `ENCOUNTER_END`) roll again. `/fdcpp run S3c` (`encounter` and `after` counters). **S3 answers**: are the rolls of other raiders readable (`rolls` > 0 with `secret=0`) after `ENCOUNTER_END` and between bosses, and are they secret during the fight?
5. After a kill, loot something so a `CHAT_MSG_LOOT` arrives, then `/fdcpp run S3e` and `/fdcpp run S3d`, then `/fdcpp export` and report the text.

**Procedura (italiano)**

1. `/fdcpp run S3a` (auto-test dei pattern; deve essere `ok`).
2. Fuori da un'istanza, in gruppo o raid con almeno un altro giocatore, fate entrambi `/roll` (oppure tu `/fdcpp roll` e l'altro `/roll`). `/fdcpp run S3c`: guarda i contatori `outside`.
3. Dentro l'istanza raid **tra un boss e l'altro** ripeti i tiri (tira anche l'altro giocatore), poi `/fdcpp run S3c` (contatori `instance`).
4. **Durante il combattimento con un boss** tu e l'altro giocatore fate `/roll` una volta; dopo l'uccisione (entro 10 secondi da `ENCOUNTER_END`) tirate ancora. `/fdcpp run S3c` (contatori `encounter` e `after`). **S3 risponde**: i tiri degli altri raider sono leggibili (`rolls` > 0 con `secret=0`) dopo `ENCOUNTER_END` e tra un boss e l'altro, e sono secret durante il combattimento?
5. Dopo un'uccisione, raccogli un oggetto così arriva un `CHAT_MSG_LOOT`, poi `/fdcpp run S3e` e `/fdcpp run S3d`, poi `/fdcpp export` e riporta il testo.

Plan B if negative: rolls read once the lockdown ends (M4-3). / Piano B se negativo: tiri letti a fine lockdown (M4-3).

### All areas / Tutte le aree

Added by the next steps, each with its in-game procedure in both languages: / Aggiunte dai passi successivi, ognuna con la procedura in gioco nelle due lingue:

| Area | Step | Question / Domanda |
|---|---|---|
| S1, S2 | M0-2 | Master loot and the loot window. |
| S3 | M0-3 | Rolls, system messages and encounters. |
| S4 | M0-4 | Addon messages in raid (needs a second client). |
| S5, S6 | M0-5 | Items, stats and specializations. |
| S7, S8 | M0-6 | Guild ranks, calendar, chat from a click. |

## 5. Reporting / Come riportare i risultati

Run `/fdcpp export`, copy the text and paste it into `docs/spike/M0-results.md` (or send it to whoever folds it in, step M0-7). / Esegui `/fdcpp export`, copia il testo e incollalo in `docs/spike/M0-results.md` (o consegnalo a chi esegue il passo M0-7).
