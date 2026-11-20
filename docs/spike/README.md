# Spike procedure (M0) / Procedura dello spike

The probe addon `FDCP_Probe` answers, in the real WoW Forever client, the questions the analysis cannot answer offline ([`docs/ANALISI.md`](../ANALISI.md) §1 "Non ancora verificato", §11, §12). It is **never distributed**, wraps every call in `pcall`, never compares a secret value, uses the test prefix `FDCPP` (never `FDCP1`) and never prints or stores player or guild names (counts and shapes only).

La sonda `FDCP_Probe` risponde, nel client reale di WoW Forever, alle domande a cui l'analisi non sa rispondere offline. **Non viene mai distribuita**, protegge ogni chiamata con `pcall`, non confronta mai un valore secret, usa il prefisso di test `FDCPP` (mai `FDCP1`) e non stampa né salva mai nomi di giocatori o di gilda (solo conteggi e forme).

> Status / Stato: **probe ready, results pending owner run** / **sonda pronta, risultati in attesa dell'esecuzione del proprietario**. The skeleton (M0-1) has the baseline checks `B1`–`B4`; the checks of the spike areas S1–S8 arrive with M0-2 … M0-6, and M0-6 finalises this procedure.

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
