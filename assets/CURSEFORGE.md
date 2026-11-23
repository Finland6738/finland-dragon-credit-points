# CurseForge listing: Finland Dragon Credit Points

> **DRAFT for v1.0.0. Do not publish before the owner's in-game checks** ([release checklist](../docs/checklists/release.md)). Nothing has been created or uploaded on CurseForge: this file only holds the texts and the gallery, ready to paste. Models: the listing material of Azeroth Guild Finder (`assets/CURSEFORGE.md`, `docs/curseforge/`) and the release flow of Azeroth Accord. How a version is built and published: [docs/RELEASING.md](../docs/RELEASING.md). Italiano: il testo da incollare in italiano è nelle sezioni 3 e 5.

The CurseForge page is public and in English; the Italian description is appended **after** the English one in the same box (section 2 ends with it) and is also given on its own (section 3). The screenshots are **mockups, not in-game screenshots** and say so in their bottom strip; replace them with real screenshots after the first in-game test.

## 1. Project fields

| Field | Value |
|---|---|
| **Name** | `Finland Dragon Credit Points` |
| **Slug** (URL) | `finland-dragon-credit-points` (keep the proposed one: it is hard to change afterwards) |
| **Game / type** | World of Warcraft, Addons |
| **Game version** | **WoW Forever** (flavor *Forever*, Interface `16001`; the file takes it from the TOC, check it after the first upload) |
| **Licence** | GNU General Public License v3.0 (GPL-3.0), the repository's |
| **Main category** | *Boss Encounters* (loot) |
| **Other categories** | *Guild*, *Chat & Communication*, *Data Export*, *Miscellaneous* (use the names the form offers: the list changes; at most the ones that exist) |
| **Tags** (if the form has them) | `loot`, `loot-council`, `credits`, `master-looter`, `raid`, `roll`, `guild`, `wow-forever`, `italiano` |
| **Logo** | `assets/logo-source.webp` (1254 × 1254): convert it to PNG and scale it to what the form asks (400 × 400 was used for the sister addon): `python -c "from PIL import Image; Image.open('assets/logo-source.webp').resize((400, 400)).save('logo.png')"` |
| **Links** | Source: <https://github.com/Finland6738/finland-dragon-credit-points> · Issues: <https://github.com/Finland6738/finland-dragon-credit-points/issues> · Wiki: <https://github.com/Finland6738/finland-dragon-credit-points/wiki> · Donations (Ko-fi): <https://ko-fi.com/finland6738> |
| **Website** (optional) | The guild's community site: <https://nebula-community.github.io/giochi/wow-forever/> |

### Summary (limit 250 characters)

English (238 characters):

```
A credit-based loot system for WoW Forever guilds: master looter sessions, a three-button roll popup with an automatic upgrade badge, fewest credits wins, a loot council with flags, and a ledger every member can read. English and Italian.
```

Italian, for the Italian text of the description (not a separate field):

```
Sistema di loot a crediti per le gilde di WoW Forever: sessioni del master looter, popup di roll a tre pulsanti con badge di upgrade automatico, vince chi ha meno crediti, loot council con segnalazioni e un registro leggibile da tutti.
```

## 2. Description (English, then Italian)

Paste everything between the two markers. CurseForge's editor is a rich-text editor: if the pasted Markdown shows `#` and `**` as text, apply the headings, lists and bold with the toolbar (the tables of commands can be bulleted lists) and check the preview before saving.

<!-- BEGIN DESCRIPTION EN -->
# Finland Dragon Credit Points: Loot by Credits, Fair and Auditable

> **Unofficial addon.** Finland Dragon Credit Points is a fan-made addon. It is not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft and Warcraft are trademarks of Blizzard Entertainment, Inc.

Finland Dragon Credit Points (**FDCP**, command `/fdcp`) runs a guild's loot nights from inside **World of Warcraft: Forever**. The master looter opens a roll for each drop; every raider answers from a small popup with **three buttons** (*Pass*, *Roll Main-spec*, *Roll Off-spec*); the addon works out the winner by the guild's rules (**fewest credits wins**, then the highest roll, then a reroll among the tied) and writes **who gets the item, how many credits it costs and why**. The master looter confirms, rejects or changes the proposal; the loot council can step in, always with a reason. Everything goes into a **ledger** of nights, drops and awards that every member can read, and credits are **never stored: they are computed from the ledger**, so every client shows the same numbers.

It was made by **Finland** for the Italian guild **NEBULA**, and it follows the look of the guild's community site. It is free and open source.

## Features

- **Loot sessions** that start when a boss dies: drops read from the loot window, a category and a cost for each item announced before the roll, a popup on every raider's client, rolls made by the game itself, off-spec only if nobody needs the item for main-spec, automatic rerolls among ties, and a written reason for every proposal.
- **Three-button roll popup** with your credits, your estimated place in the queue and an **automatic upgrade badge** (minor, medium or major, with the item-level difference) computed by your own addon against the gear you wore during the boss fight. It informs; it never changes who wins. A roll counts only when it comes from the popup's button.
- **A rules engine the Guild Master controls**: costs per category and quality, multipliers, tie-breaks, off-spec, BoE items (guild bank, off-spec, disenchanter or free roll), legendary projects, late joiners, +1 credit for a missed official night, **+2 credits for proven roll cheating**. Four presets (the guild's *Patto*, *Roll only*, *Pure loot council*, *Simple EPGP*), permissions by guild rank, and a confirmation dialog for every change while a season is open.
- **A ledger you can trust**: credits come from signed events, awards are cancelled by compensating events instead of being deleted, officers keep one ledger between them without overwriting each other, and every member gets the credits table from an officer's addon.
- **Roster and nights**: the season's pool by role (tank, healer, DPS), trial members, main and alt links, official raid nights with the lineup (raid, bench, absent), a fair bench rotation, a **Bench myself** button, absence penalties proposed at the close and confirmed by an officer, and the attendance for officers only.
- **Loot council**: flags that name a player (*upgrade ignored*, *possible waste*, *possible cheating* with evidence and an inspection), a vote, cancelling an award, correcting credits, a full audit of every intervention, and legendary projects.
- **Progress** of the guild's first kills per boss, as on the community site, and a **Credits** tab with a column per night, your total and your place in the queue.
- **Exports**: the credits table for Discord, CSV and JSON, and the community site's `roster.json`, `loot.json` and `progress.json`; backups, season archives and a bug report that contains no player, guild or item names.
- **A modern interface** in the style of the community site: three themes (Nebula, Aurora, Drago), neon effects and animations you can turn off, profiles, and English and Italian (one file per language, so more can be added).

## How it works

**Raiders.** When a roll opens you get a popup with the item, its cost and the upgrade badge. Press **Roll Main-spec** to answer and roll in one click, **Roll Off-spec** to say you would take it if nobody needs it for main-spec, or **Pass**. You roll once per item. You need the addon active to take part, and a `/roll` typed by hand does not count (the Guild Master can change that rule).

**Master looters.** Set the loot method to *Master Looter*. Open the body: the **Loot › Session** window lists the items with their cost, you press **Start the session**, and for each item the answers, the rolls, the upgrade column and the **proposal** appear. You press **Confirm and assign** (the item is handed over by master loot in the same click, or waits in a *To deliver* list for a trade), **Reject**, or **Modify** with a reason. The addon also writes the categories and results in `/raid`.

**Officers and the council.** Officers run the roster and the nights, confirm absence penalties and, on the council, watch the flags, vote, cancel awards, correct credits and manage legendary projects, always with a reason that lands in the audit. Officers' addons sync the ledger between them on the officer channel.

**The Guild Master.** Only the Guild Master changes the rules and the permissions, opens and closes the season (with an item-level band that drives the upgrade badge) and chooses the presets. Every change is an event in the ledger with the Guild Master's name.

There is **no server and no website**: everything travels as addon messages inside the game, and nothing leaves the game unless you copy it out yourself.

## Installation

1. Install the addon from the CurseForge app, or download the zip and unpack the `FinlandDragonCreditPoints` folder into `World of Warcraft/_forever_/Interface/AddOns/`. The libraries are included.
2. Enable the addon on the character screen, log in and type `/fdcp` (or click the minimap button).
3. **Every raider needs the addon** to answer and roll. The **Roster › Addon** page shows who in the raid lacks it and writes a notice in `/raid` for you.

## Commands

| Command | What it does |
|---|---|
| `/fdcp` | Open or close the main window |
| `/fdcp help` | List the commands |
| `/fdcp theme [nebula\|aurora\|drago]` | Show or set the theme |
| `/fdcp effects [on\|off]` · `/fdcp animations [on\|off]` | Neon effects and transitions |
| `/fdcp council` · `/fdcp legendary` · `/fdcp bank` | The council, the legendary projects and the guild bank, from the chat box |
| `/fdcp about` | The Info page: author, licence and links to copy |
| `/fdcp language [auto\|enUS\|itIT]` | Your own language (needs `/reload`) |
| `/fdcp debug` | A bug report to paste in a GitHub issue (no player, guild or item names) |

## Requirements

- **World of Warcraft: Forever** (Interface 16001). Other clients are not supported.
- No other addon is needed. The libraries (Ace3, LibDataBroker, LibDBIcon) are included.

## Development status and known limits

The addon is **written and tested offline on a simulated client. It has not been verified in the real game yet**, so some things may need fixing, and the screenshots on this page are **mockups, not in-game captures**. What still has to be confirmed in the game:

- that the addon may hand an item over with master loot from a click, and that the loot window, the master loot list and the loot messages read as expected;
- that a roll can be made from a button, and that the small "I clicked" message reaches the master looter around the roll, also behind a boss's chat lockdown;
- the item quality and item level of worn pieces, the gear snapshot at the start of a boss fight and the inspection used as evidence;
- the calendar sign-ups used for absence penalties, load time and memory over a long season, and the packaged zip itself.

If a step does not work, the addon says so and the item waits in a list for a trade: nothing is lost. The upgrade badge reads colour and item level, not stats; it is a hint, never a decision. Only English and Italian exist for now. Bug reports are very welcome.

## Links

- Source code: <https://github.com/Finland6738/finland-dragon-credit-points>
- User manual (wiki): <https://github.com/Finland6738/finland-dragon-credit-points/wiki>
- Bugs and ideas: <https://github.com/Finland6738/finland-dragon-credit-points/issues>
- The NEBULA community site: <https://nebula-community.github.io/giochi/wow-forever/>
- Support the project: <https://ko-fi.com/finland6738>

## Credits and licence

Conceived and made by **Finland** for the Italian guild **NEBULA**. Libraries: **Ace3**, **LibDataBroker-1.1** and **LibDBIcon-1.0**, each under its own free licence. Fonts: **Outfit**, **JetBrains Mono** and **Orbitron**, under the SIL Open Font License 1.1. The guild's logo is used with the owner's permission; the interface art is original. The full list is in `docs/third-party.md` of the repository.

Finland Dragon Credit Points is free software under the **GNU General Public License v3.0**: you may use, study, change and share it under the terms of that licence. Full text: <https://www.gnu.org/licenses/gpl-3.0.html>

---

# Finland Dragon Credit Points: il loot a crediti, equo e verificabile

> **Addon non ufficiale.** Finland Dragon Credit Points è un addon creato da fan. Non è affiliato né approvato da Blizzard Entertainment. World of Warcraft e Warcraft sono marchi di Blizzard Entertainment, Inc.

Finland Dragon Credit Points (**FDCP**, comando `/fdcp`) gestisce dall'interno di **World of Warcraft: Forever** le serate di loot di una gilda. Il master looter apre un roll per ogni drop; ogni raider risponde da un piccolo popup con **tre pulsanti** (*Passo*, *Tira Main-spec*, *Tira Off-spec*); l'addon calcola il vincitore secondo le regole della gilda (**vince chi ha meno crediti**, poi il roll più alto, poi un reroll fra i pari) e scrive **chi prende l'oggetto, quanti crediti costa e perché**. Il master looter conferma, rifiuta o modifica la proposta; il loot council può intervenire, sempre con un motivo. Tutto finisce in un **registro** di serate, drop e assegnazioni che ogni membro può leggere, e i crediti **non sono mai salvati: si calcolano dal registro**, così ogni client mostra gli stessi numeri.

L'ha creato **Finland** per la gilda italiana **NEBULA** e ne segue lo stile del sito della community. È libero e open source.

## Funzioni

- **Sessioni di loot** che partono alla morte di un boss: drop letti dalla finestra del loot, categoria e costo di ogni oggetto annunciati prima del roll, un popup su ogni client dei raider, tiri fatti dal gioco, off-spec solo se nessuno lo vuole per main-spec, reroll automatici fra i pari e un motivo scritto per ogni proposta.
- **Popup del roll a tre pulsanti** con i tuoi crediti, la tua posizione stimata in fila e un **badge di upgrade automatico** (piccolo, medio o grande, con la differenza di item level) calcolato dal tuo addon rispetto all'equipaggiamento che indossavi durante il boss. Informa, non cambia mai chi vince. Un tiro conta solo se arriva dal pulsante del popup.
- **Un motore di regole in mano al Guild Master**: costi per categoria e qualità, moltiplicatori, spareggi, off-spec, oggetti BoE (banca di gilda, off-spec, disenchanter o roll libero), progetti leggendari, chi entra in ritardo, +1 credito per una serata ufficiale saltata, **+2 crediti per imbroglio sul tiro provato**. Quattro preset (il *Patto* della gilda, *Solo roll*, *Loot council puro*, *EPGP semplice*), permessi per grado di gilda e una finestra di conferma per ogni modifica a season aperta.
- **Un registro di cui fidarsi**: i crediti vengono da eventi firmati, le assegnazioni si annullano con eventi di compensazione invece di cancellarle, gli officer tengono un registro unico senza sovrascriversi e ogni membro riceve la tabella dei crediti dall'addon di un officer.
- **Roster e serate**: il pool della season per ruolo (tank, healer, DPS), membri in prova, legami fra main e alt, serate ufficiali con la formazione (nel raid, in panchina, assenti), rotazione equa della panchina, il pulsante **Mettimi in panchina**, penalità di assenza proposte alla chiusura e confermate da un officer, e le presenze solo per gli officer.
- **Loot council**: segnalazioni che indicano un giocatore (*upgrade ignorato*, *possibile spreco*, *possibile imbroglio* con prove e ispezione), voto, annullamento di un'assegnazione, correzione dei crediti, audit completo di ogni intervento e progetti leggendari.
- **Progress** delle prime uccisioni della gilda per boss, come sul sito della community, e scheda **Crediti** con una colonna per serata, il tuo totale e la tua posizione in fila.
- **Esportazioni**: la tabella dei crediti per Discord, CSV e JSON, e i file `roster.json`, `loot.json` e `progress.json` del sito della community; backup, archivi delle season e un rapporto d'errore senza nomi di giocatori, gilde od oggetti.
- **Un'interfaccia moderna** nello stile del sito della community: tre temi (Nebula, Aurora, Drago), effetti neon e animazioni disattivabili, profili, italiano e inglese (un file per lingua, quindi se ne possono aggiungere altre).

## Come funziona

**Raider.** Quando si apre un roll ti compare un popup con l'oggetto, il suo costo e il badge di upgrade. Premi **Tira Main-spec** per rispondere e tirare con un clic, **Tira Off-spec** per dire che lo prenderesti se nessuno lo vuole per main-spec, oppure **Passo**. Tiri una volta per oggetto. Serve l'addon attivo per partecipare e un `/roll` scritto a mano non conta (il Guild Master può cambiare la regola).

**Master looter.** Imposta il metodo di loot su *Master Looter*. Apri il cadavere: la finestra **Loot › Sessione** elenca gli oggetti con il loro costo, premi **Avvia la sessione** e per ogni oggetto compaiono le risposte, i tiri, la colonna Upgrade e la **proposta**. Premi **Conferma e assegna** (l'oggetto viene consegnato col master loot nello stesso clic, oppure aspetta nella lista *Da consegnare* uno scambio), **Rifiuta** oppure **Modifica** con un motivo. L'addon scrive anche categorie e risultati in `/raid`.

**Officer e council.** Gli officer gestiscono roster e serate, confermano le penalità di assenza e, nel council, guardano le segnalazioni, votano, annullano assegnazioni, correggono i crediti e gestiscono i progetti leggendari, sempre con un motivo che finisce nell'audit. Gli addon degli officer sincronizzano il registro fra loro sul canale degli officer.

**Il Guild Master.** Solo il Guild Master cambia regole e permessi, apre e chiude la season (con una fascia di item level che guida il badge di upgrade) e sceglie i preset. Ogni modifica è un evento del registro con il suo nome.

**Non c'è nessun server né sito web**: tutto viaggia come messaggi di addon dentro il gioco e nulla esce dal gioco se non lo copi tu.

## Installazione

1. Installa l'addon dall'app di CurseForge, oppure scarica lo zip e scompatta la cartella `FinlandDragonCreditPoints` in `World of Warcraft/_forever_/Interface/AddOns/`. Le librerie sono incluse.
2. Attiva l'addon nella schermata dei personaggi, entra in gioco e scrivi `/fdcp` (o clicca il pulsante sulla minimappa).
3. **Ogni raider ha bisogno dell'addon** per rispondere e tirare. La pagina **Roster › Addon** mostra chi nel raid non ce l'ha e scrive per te un avviso in `/raid`.

## Comandi

Gli stessi della tabella inglese: `/fdcp` (apre o chiude la finestra), `/fdcp help`, `/fdcp theme`, `/fdcp effects`, `/fdcp animations`, `/fdcp council`, `/fdcp legendary`, `/fdcp bank`, `/fdcp about`, `/fdcp language` e `/fdcp debug` (rapporto d'errore da incollare in una issue). L'elenco completo è nella wiki.

## Requisiti

- **World of Warcraft: Forever** (Interface 16001). Altri client non sono supportati.
- Nessun altro addon è necessario. Le librerie (Ace3, LibDataBroker, LibDBIcon) sono incluse.

## Stato di sviluppo e limiti noti

L'addon è **scritto e provato offline su un client simulato. Non è ancora stato verificato nel gioco vero**, quindi qualcosa potrebbe richiedere correzioni, e gli screenshot di questa pagina sono **mockup, non catture del gioco**. Da confermare ancora in gioco:

- che l'addon possa consegnare un oggetto con il master loot da un clic e che la finestra del loot, la lista del master loot e i messaggi di loot si leggano come previsto;
- che un tiro si possa fare da un pulsante e che il piccolo messaggio «ho cliccato» arrivi al master looter intorno al tiro, anche dietro il blocco della chat di un boss;
- qualità e item level dei pezzi indossati, la fotografia dell'equipaggiamento all'inizio di un boss e l'ispezione usata come prova;
- le iscrizioni del calendario usate per le penalità di assenza, tempo di caricamento e memoria con una season lunga, e lo zip del pacchetto.

Se un passo non funziona, l'addon lo dice e l'oggetto aspetta in una lista per uno scambio: non si perde nulla. Il badge di upgrade legge colore e item level, non le statistiche: è un suggerimento, mai una decisione. Per ora esistono solo italiano e inglese. Le segnalazioni di errori sono molto gradite.

## Link

- Codice: <https://github.com/Finland6738/finland-dragon-credit-points>
- Manuale (wiki): <https://github.com/Finland6738/finland-dragon-credit-points/wiki>
- Errori e idee: <https://github.com/Finland6738/finland-dragon-credit-points/issues>
- Il sito della community NEBULA: <https://nebula-community.github.io/giochi/wow-forever/>
- Sostieni il progetto: <https://ko-fi.com/finland6738>

## Crediti e licenza

Ideato e realizzato da **Finland** per la gilda italiana **NEBULA**. Librerie: **Ace3**, **LibDataBroker-1.1** e **LibDBIcon-1.0**, ciascuna con la propria licenza libera. Font: **Outfit**, **JetBrains Mono** e **Orbitron**, con licenza SIL Open Font License 1.1. Il logo della gilda è usato con il permesso del proprietario; la grafica dell'interfaccia è originale. L'elenco completo è in `docs/third-party.md` del repository.

Finland Dragon Credit Points è software libero con licenza **GNU General Public License v3.0**: puoi usarlo, studiarlo, modificarlo e condividerlo alle condizioni di quella licenza. Testo completo: <https://www.gnu.org/licenses/gpl-3.0.html>
<!-- END DESCRIPTION EN -->

## 3. Italian description on its own

Use it only if the owner wants a separate Italian text (for example as a pinned comment or on the guild's Discord). It is the part of section 2 after the line `---`, from "# Finland Dragon Credit Points: il loot a crediti, equo e verificabile" to the end.

## 4. Changelog of the first file: v1.0.0 (draft)

Paste it in the *Changelog* field of the first upload (Markdown). The GitHub Release gets the `CHANGELOG.md` section built by `tools/release_notes.py`; this is the short, player-facing version. Release type: **Release** if the in-game checks pass; otherwise upload a **Beta** first (`v1.0.0-beta.1`).

<!-- BEGIN CHANGELOG EN -->
## 1.0.0: first release

First public version. Nothing here replaces an older version.

- Loot sessions run by the master looter: drops, category and cost per item, a roll popup with three buttons (Pass, Roll Main-spec, Roll Off-spec), the proposal with its reason, confirm / reject / modify, and delivery by master loot or by trade.
- Credits computed from a ledger of signed events: fewest credits wins, then the highest roll, then rerolls among ties; credits are never stored.
- Automatic upgrade badge (minor, medium, major, with the item-level difference) from the gear worn during the boss fight; rolls count only from the popup's button.
- Rules the Guild Master controls: costs, multipliers, tie-breaks, BoE, legendary projects, late joiners, +1 for a missed night, +2 for proven roll cheating; four presets and permissions by guild rank.
- Roster and nights: pool by role, trial members, lineup and bench, Bench myself, absence penalties confirmed by an officer, attendance for officers.
- Loot council: flags (upgrade ignored, possible waste, possible cheating with evidence), vote, cancel awards, correct credits, audit, legendary projects.
- Credits and Progress tabs, history with a member's and an item's page, exports (Discord, CSV, JSON, the community site's files), backups and season archives.
- Settings with profiles, three themes (Nebula, Aurora, Drago), effects and animations, Info page, bug report (`/fdcp debug`); English and Italian.
- **Known limits:** not yet verified in the real game; see the description.
<!-- END CHANGELOG EN -->

<!-- BEGIN CHANGELOG IT -->
## 1.0.0: prima versione

Prima versione pubblica.

- Sessioni di loot condotte dal master looter: drop, categoria e costo per oggetto, popup del roll a tre pulsanti (Passo, Tira Main-spec, Tira Off-spec), proposta con il suo motivo, conferma / rifiuto / modifica e consegna con master loot o scambio.
- Crediti calcolati da un registro di eventi firmati: vince chi ha meno crediti, poi il roll più alto, poi reroll fra i pari; i crediti non sono mai salvati.
- Badge di upgrade automatico (piccolo, medio, grande, con la differenza di item level) dall'equipaggiamento indossato durante il boss; i tiri contano solo dal pulsante del popup.
- Regole in mano al Guild Master: costi, moltiplicatori, spareggi, BoE, progetti leggendari, chi entra in ritardo, +1 per una serata saltata, +2 per imbroglio sul tiro provato; quattro preset e permessi per grado di gilda.
- Roster e serate: pool per ruolo, membri in prova, formazione e panchina, Mettimi in panchina, penalità di assenza confermate da un officer, presenze per gli officer.
- Loot council: segnalazioni (upgrade ignorato, possibile spreco, possibile imbroglio con prove), voto, annullamento di assegnazioni, correzione dei crediti, audit, progetti leggendari.
- Schede Crediti e Progress, storico con la pagina di un membro e di un oggetto, esportazioni (Discord, CSV, JSON, i file del sito della community), backup e archivi delle season.
- Impostazioni con profili, tre temi (Nebula, Aurora, Drago), effetti e animazioni, pagina Info, rapporto d'errore (`/fdcp debug`); italiano e inglese.
- **Limiti noti:** non ancora verificato nel gioco vero; vedi la descrizione.
<!-- END CHANGELOG IT -->

## 5. Screenshots (gallery)

Upload in this order; CurseForge shows the first as the cover. The files are in [`docs/specs/mockups/`](../docs/specs/mockups/), WebP, 1200 × 754. Titles are at most 50 characters and descriptions at most 160, to stay under the limits (check the figure shown in the upload form if it is stricter). If the form refuses WebP, convert them: `python -c "from PIL import Image; Image.open('x.webp').convert('RGB').save('x.png')"`. Upload the `-en` file for the English page; the `-it` file (same name) is the Italian twin, for an Italian gallery or the guild's Discord. Every description ends with "Mockup" so nobody takes the image for a game screenshot.

All the mockups are generated by `tools/make_mockups.py` (see [docs/specs/ui-style.md](../docs/specs/ui-style.md), section 8).

### 1. `fdcp-roll-popup-en.webp` (Italian: `fdcp-roll-popup-it.webp`)

- **Title** (EN): Roll with three buttons
- **Description** (EN): Pass, Roll Main-spec or Roll Off-spec: one click answers and rolls. Your credits, your queue place and an automatic upgrade badge. Mockup.
- **Titolo** (IT): Il roll con tre pulsanti
- **Descrizione** (IT): Passo, Tira Main-spec o Tira Off-spec: un clic risponde e tira. I tuoi crediti, la fila e un badge di upgrade automatico. Mockup.

### 2. `fdcp-loot-session-en.webp` (Italian: `fdcp-loot-session-it.webp`)

- **Title** (EN): The master looter's session
- **Description** (EN): Candidates with credits, answer, roll and upgrade; the addon's proposal with its reason. Confirm, Reject or Modify. Mockup.
- **Titolo** (IT): La sessione del master looter
- **Descrizione** (IT): Candidati con crediti, risposta, tiro e upgrade; la proposta dell'addon con il suo motivo. Conferma, Rifiuta o Modifica. Mockup.

### 3. `fdcp-council-en.webp` (Italian: `fdcp-council-it.webp`)

- **Title** (EN): The loot council
- **Description** (EN): Flags with evidence (possible cheating, upgrade ignored), a vote, Penalize +2, cancel awards and adjust credits, with a reason. Mockup.
- **Titolo** (IT): Il loot council
- **Descrizione** (IT): Segnalazioni con prove (possibile imbroglio, upgrade ignorato), voto, Penalizza +2, annulla assegnazioni e correggi crediti, con motivo. Mockup.

### 4. `fdcp-credits-en.webp` (Italian: `fdcp-credits-it.webp`)

- **Title** (EN): Credits: fewer means more priority
- **Description** (EN): One accordion per season, one column per night, your total and your place in the loot queue, as on the community site. Mockup.
- **Titolo** (IT): Crediti: meno crediti, più precedenza
- **Descrizione** (IT): Una fisarmonica per season, una colonna per serata, il tuo totale e la tua posizione in fila, come sul sito della community. Mockup.

### 5. `fdcp-roster-en.webp` (Italian: `fdcp-roster-it.webp`)

- **Title** (EN): The season's roster
- **Description** (EN): Tank, healer and DPS columns with the targets, free slots and members on trial. Officers manage the pool from here. Mockup.
- **Titolo** (IT): Il roster della season
- **Descrizione** (IT): Colonne tank, healer e DPS con gli obiettivi, posti liberi e membri in prova. Gli officer gestiscono il pool da qui. Mockup.

### 6. `fdcp-night-en.webp` (Italian: `fdcp-night-it.webp`)

- **Title** (EN): Raid nights and absences
- **Description** (EN): The lineup (raid, bench, absent), a self-bench, and the absence penalties proposed at the close for an officer to confirm. Mockup.
- **Titolo** (IT): Serate di raid e assenze
- **Descrizione** (IT): La formazione (nel raid, panchina, assenti), la panchina da soli e le penalità di assenza proposte alla chiusura per la conferma di un officer. Mockup.

### 7. `fdcp-progress-en.webp` (Italian: `fdcp-progress-it.webp`)

- **Title** (EN): Guild progress
- **Description** (EN): The first kill of every boss per guild, with its date, as on the community site's Progress page. Mockup.
- **Titolo** (IT): Il progress di gilda
- **Descrizione** (IT): La prima uccisione di ogni boss per gilda, con la data, come nella pagina Progress del sito della community. Mockup.

### 8. `fdcp-permissions-en.webp` (Italian: `fdcp-permissions-it.webp`)

- **Title** (EN): Permissions by guild rank
- **Description** (EN): For each action, the lowest guild rank allowed. Only the Guild Master edits the rules and the permissions. Mockup.
- **Titolo** (IT): Permessi per grado di gilda
- **Descrizione** (IT): Per ogni azione, il grado di gilda più basso che la può fare. Solo il Guild Master modifica regole e permessi. Mockup.

### 9. `fdcp-season-en.webp` (Italian: `fdcp-season-it.webp`)

- **Title** (EN): Seasons and the item-level band
- **Description** (EN): The open season, its raids and late-join rule, and the item-level band that drives the upgrade badge. Mockup.
- **Titolo** (IT): Season e fascia di item level
- **Descrizione** (IT): La season aperta, i suoi raid e la regola di chi entra in ritardo, e la fascia di item level che guida il badge di upgrade. Mockup.

### 10. `fdcp-settings-en.webp` (Italian: `fdcp-settings-it.webp`)

- **Title** (EN): Themes and settings
- **Description** (EN): Nebula, Aurora or Drago, neon effects, animations, sounds and language. The guild's rules have their own pages. Mockup.
- **Titolo** (IT): Temi e impostazioni
- **Descrizione** (IT): Nebula, Aurora o Drago, effetti neon, animazioni, suoni e lingua. Le regole della gilda hanno pagine proprie. Mockup.

### 11. `fdcp-site-export-en.webp` (Italian: `fdcp-site-export-it.webp`)

- **Title** (EN): Export for the community site
- **Description** (EN): roster.json, loot.json and progress.json ready to copy, plus Discord, CSV and JSON tables of the credits. Mockup.
- **Titolo** (IT): Esporta per il sito della community
- **Descrizione** (IT): roster.json, loot.json e progress.json pronti da copiare, più tabelle dei crediti per Discord, CSV e JSON. Mockup.

### 12. `fdcp-about-en.webp` (Italian: `fdcp-about-it.webp`)

- **Title** (EN): Info and credits
- **Description** (EN): Who made it, the licence and the links to copy (source, issues, the NEBULA site, Ko-fi). Free and open source. Mockup.
- **Titolo** (IT): Info e crediti
- **Descrizione** (IT): Chi l'ha fatto, la licenza e i link da copiare (codice, issue, sito NEBULA, Ko-fi). Libero e open source. Mockup.

Spare images (not in the list above): `fdcp-credits-aurora-*` (the light theme), `fdcp-roster-drago-*` (the logo's theme) and `fdcp-design-system-*` (tokens and components).

## 6. What to fill in at upload time

Do this only after the in-game checks of [docs/checklists/release.md](../docs/checklists/release.md) have passed and `v1.0.0` is tagged (or for a `-beta` first).

1. **Create the project** (CurseForge → Create → World of Warcraft → Addons) with the fields of section 1; paste the summary and the description of section 2; upload the logo and the gallery of section 5 (titles and descriptions as listed); fill the links; save. The project stays a draft until a file is uploaded; CurseForge moderates it before it goes public.
2. **Project ID.** Copy the number from the project's *About* panel into the TOC, in a normal pull request: in both `FinlandDragonCreditPoints.toc` and `FinlandDragonCreditPoints_Camelot.toc` add `## X-Curse-Project-ID: <number>`. Without it the release workflow says "CurseForge skipped".
3. **API token.** Create it at <https://www.curseforge.com/account/api-tokens> and add it yourself as the repository secret `CF_API_KEY` (Settings → Secrets and variables → Actions). Never paste it in an issue, a pull request or a chat.
4. **First file.** Either push the tag and let the `Release` workflow upload the zip, or upload `FinlandDragonCreditPoints-1.0.0.zip` by hand from the GitHub Release. For a by-hand upload fill:
   - **File** = the zip (the folder inside must be `FinlandDragonCreditPoints/` with the TOC in it);
   - **Display name** = `Finland Dragon Credit Points 1.0.0`;
   - **Release type** = *Release* (or *Beta* for `v1.0.0-beta.1`; never *Alpha* for the public one);
   - **Game version** = *WoW Forever* (Interface 16001; check the flavor and version the form lists, for example `1.60.1` as for the sister addons);
   - **Changelog** = section 4 (Markdown);
   - **Relations** (dependencies) = none: the libraries are embedded.
5. **Check after upload.** Open the file page: the game version must say *Forever*, the changelog must render, the description must show no stray `#` or `**`. Download the zip once and install it.
6. **Create the first wiki page by hand** on GitHub (the `Wiki sync` workflow warns and does nothing until the wiki exists), so the *Wiki* link works. Then put the real screenshots in the gallery when they exist.
7. **Never** upload before the GitHub Release exists, and never reuse a tag that was public ([docs/RELEASING.md](../docs/RELEASING.md)).
