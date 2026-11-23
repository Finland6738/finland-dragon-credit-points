# Release checklist / Checklist di rilascio (v1.0.0)

This is the owner's path to **v1.0.0**. A session cannot run the game, so everything below is **not verified** until the owner ticks it. All milestones are done offline; the release waits for these in-game checks. Each item is written in English and then in Italian.

Questo è il percorso del proprietario verso **v1.0.0**. Una sessione non può avviare il gioco, quindi tutto qui sotto è **non verificato** finché il proprietario non lo spunta. Tutte le milestone sono fatte offline; il rilascio aspetta queste verifiche in gioco. Ogni voce è scritta in inglese e poi in italiano.

> Status / Stato: **all milestones done offline; release pending the owner's in-game checks** / **tutte le milestone fatte offline; rilascio in attesa delle verifiche in gioco del proprietario**.

> **Never tag before every box is ticked. / Non creare il tag prima di aver spuntato tutte le voci.**

## 1. Spike (M0-7)

- [ ] Run the spike procedure in [`docs/spike/README.md`](../spike/README.md) with the probe addon (`tools/probe/`) and write the results in [`docs/spike/M0-results.md`](../spike/M0-results.md); say which plan (A or B, [`docs/ANALISI.md`](../ANALISI.md) §11) each result confirms.
- [ ] Esegui la procedura dello spike in [`docs/spike/README.md`](../spike/README.md) con l'addon probe (`tools/probe/`) e scrivi i risultati in [`docs/spike/M0-results.md`](../spike/M0-results.md); indica quale piano (A o B, [`docs/ANALISI.md`](../ANALISI.md) §11) ogni risultato conferma.

## 2. Milestone checklists / Checklist delle milestone

Run them in this order; each one assumes the previous ones are done. / Eseguile in quest'ordine; ognuna presuppone fatte le precedenti.

- [ ] [`M1.md`](M1.md): skeleton, `Compat`, configuration, locale, transport, theme. / scheletro, `Compat`, configurazione, locale, trasporto, tema.
- [ ] [`M3.md`](M3.md): roster, nights, presence, rotation, credits and progress windows. / roster, serate, presenze, rotazione, finestre crediti e progressi.
- [ ] [`M4.md`](M4.md): a whole boss, plan A and plan B (loot source, rolls, controller). / un boss intero, piano A e piano B (fonte del loot, tiri, controller).
- [ ] [`M5.md`](M5.md): the council works from the window (legendaries, BoE, council UI). / il council lavora dalla finestra (leggendari, BoE, UI del council).
- [ ] [`M6.md`](M6.md): history, exports, officers' sync, member credits, backup. / storico, esportazioni, sync degli officer, crediti dei membri, backup.

(M2 is pure rules and has no in-game checklist. / M2 sono solo regole e non ha una checklist in gioco.)

## 3. M7 in-game items / Voci in gioco di M7

The open "in game" items of [`docs/roadmap/M7-release.md`](../roadmap/M7-release.md). / Le voci "in game" ancora aperte di [`docs/roadmap/M7-release.md`](../roadmap/M7-release.md).

- [ ] **M7-1**: the look and the speed: glows, the light line, hover and press, transitions and the two preferences, in the three themes. / l'aspetto e la velocità: bagliori, linea di luce, hover e pressione, transizioni e le due preferenze, nei tre temi.
- [ ] **M7-2**: the Settings window as Guild Master and as an officer: sub-tabs, forms, dropdowns, confirmation dialog, entry in the game's settings window. / la finestra Impostazioni come Guild Master e come officer: sotto-schede, moduli, menu a tendina, finestra di conferma, voce nelle impostazioni del gioco.
- [ ] **M7-2b**: the popup and the master looter's window in the three modes, on a real item with a wishlist entry and a verdict (response labels). / il popup e la finestra del master looter nelle tre modalità, su un oggetto vero con wishlist e verdetto (etichette di risposta).
- [ ] **M7-2c**: the Info page and the copy boxes (select and Ctrl+C, the logo, the fit at the minimum window size). / la pagina Info e le caselle da copiare (selezione e Ctrl+C, il logo, l'adattamento alla finestra minima).
- [ ] **M7-2d**: the roll intent reaches the master looter before or shortly after the roll message, in and out of an instance and after a boss (lockdown); the warning on a typed `/roll`; `RandomRoll` from a click. / l'intento di tiro arriva al master looter prima o poco dopo il messaggio del tiro, dentro e fuori da un'istanza e dopo un boss (lockdown); l'avviso su un `/roll` digitato; `RandomRoll` da un click.
- [ ] **M7-4**: the diagnostics window opens, the text is selected, Ctrl+C copies it, the report reads well. / la finestra di diagnostica si apre, il testo è selezionato, Ctrl+C lo copia, il report si legge bene.
- [ ] **M7-5**: load time and memory in game, also with a long season. / tempo di caricamento e memoria in gioco, anche con una stagione lunga.
- [ ] **M7-5b**: the calendar sign-ups read at the close of a real night, the `NBENCH` request over GUILD, the Night window's new line and buttons. / le iscrizioni del calendario lette alla chiusura di una serata vera, la richiesta `NBENCH` su GUILD, la nuova riga e i nuovi pulsanti della finestra Serata.
- [ ] **M7-5c**: the three buttons in a raid (one click answers and rolls), `GetItemQualityByID` and the item level of worn pieces, the snapshot at `ENCOUNTER_START` (also after a `/reload` during the fight), the Season window's band fields. / i tre pulsanti in raid (un click risponde e tira), `GetItemQualityByID` e l'item level dei pezzi indossati, lo snapshot a `ENCOUNTER_START` (anche dopo un `/reload` durante il combattimento), i campi delle fasce nella finestra Stagione.
- [ ] **M7-5d**: the evidence of a real swap after a kill, `CanInspect` / `NotifyInspect` / `INSPECT_READY` in a raid, the confirm button in both windows. / le prove di un vero cambio di equip dopo un kill, `CanInspect` / `NotifyInspect` / `INSPECT_READY` in raid, il pulsante di conferma in entrambe le finestre.
- [ ] **M7-6**: install the zip built by the release workflow ([`docs/RELEASING.md`](../RELEASING.md), "Try it without publishing anything"): the folder is `FinlandDragonCreditPoints/` with the TOC inside, and the addon loads. / installa lo zip costruito dal workflow di rilascio ([`docs/RELEASING.md`](../RELEASING.md), "Try it without publishing anything"): la cartella è `FinlandDragonCreditPoints/` con il TOC dentro, e l'addon si carica.

## 4. A full raid night / Una serata di raid completa

- [ ] With the guild: open a night, run every boss through the addon (popup, rolls, awards, council decisions, legendary and BoE if they drop), close the night. / Con la gilda: apri una serata, fai passare ogni boss dall'addon (popup, tiri, assegnazioni, decisioni del council, leggendario e BoE se cadono), chiudi la serata.
- [ ] Afterwards: the credits match by hand, the history and the audit read right, the officers' ledgers agree, the site export loads in the community site, a backup restores. / Dopo: i crediti tornano a mano, storico e audit sono corretti, i registri degli officer coincidono, l'export per il sito si carica nel sito della community, un backup si ripristina.
- [ ] Report every problem as an issue ([Reporting Bugs](../wiki/Reporting-Bugs.md)); fix them before the release. / Segnala ogni problema come issue ([Reporting Bugs](../wiki/Reporting-Bugs.md)); correggili prima del rilascio.

## 5. Release / Rilascio

Follow [`docs/RELEASING.md`](../RELEASING.md), "Releasing a version". / Segui [`docs/RELEASING.md`](../RELEASING.md), "Releasing a version".

- [ ] Tell the orchestrating session the results; it promotes the changelog (`tools/release_notes.py --promote 1.0.0`), updates the status of both READMEs and the wiki in a normal pull request. / Comunica i risultati alla sessione che coordina; questa promuove il changelog (`tools/release_notes.py --promote 1.0.0`) e aggiorna lo stato dei due README e del wiki in una pull request normale.
- [ ] Tag the merge commit `v1.0.0` with the noreply identity and push the tag. / Crea il tag `v1.0.0` sul commit di merge con l'identità noreply e pubblica il tag.
- [ ] Watch the release workflow, download the zip once and install it. / Guarda il workflow di rilascio, scarica lo zip una volta e installalo.
