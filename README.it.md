# Finland Dragon Credit Points

<img src="assets/logo-source.webp" alt="Logo di Finland Dragon Credit Points" width="160" align="right">

**Un sistema di loot a crediti per le gilde di World of Warcraft: Forever.** Finland Dragon Credit Points (FDCP, comando `/fdcp`) gestisce le serate di loot della gilda direttamente nel gioco: il master looter apre un roll per ogni drop, ogni raider risponde main-spec o off-spec da un popup e rolla, e l'addon calcola il vincitore secondo le regole della gilda — meno crediti vince, poi il roll più alto, poi un reroll fra i pari — e scrive a chi va il pezzo, quanti crediti costa e perché. Il master looter conferma, rifiuta o modifica la proposta; il council può intervenire con una motivazione; tutto finisce in un registro di crediti, serate e assegnazioni consultabile da ogni membro.

> **Stato: in sviluppo, nessun download ancora.** L'analisi è pronta ([docs/ANALISI.md](docs/ANALISI.md)) e il flusso di sviluppo è attivo; l'addon si costruisce un passo della roadmap alla volta, a partire da una sonda per le verifiche in gioco (M0) e dalle fondamenta (M1). Lo scheletro dell'addon e il pacchetto esistono (M1-1): si installa per i test con `tools/install_addon.py` (vedi la pagina [Installazione](docs/wiki/Installation-it.md)) e `/fdcp help` è per ora l'unico comando. `Core/Compat.lua` (M1-3) è l'unica porta protetta verso le API del gioco e `/fdcp debug` stampa cosa offre il client (vedi la pagina [Comandi](docs/wiki/Commands-it.md)). Impostazioni, dati per gilda e migrazioni dello schema stanno in `Core/Config.lua` (M1-4). I messaggi fra i giocatori passano da un codec versionato e da una coda di invio protetta che aspetta la fine del lockdown della chat e degli incontri con i boss (`Net/`, M1-6). Lo stile dell'interfaccia (quello del sito della community) e i file esportati per il sito sono specificati in [docs/specs/](docs/specs/ui-style.md) con le anteprime delle schede (M1-6b). Il tema e la finestra principale vuota esistono (M1-7): `/fdcp` apre una finestra con le sei schede, tre temi (`/fdcp theme`), un pulsante della minimappa e i font inclusi. La verifica in gioco di M1 è descritta in [docs/checklists/M1.md](docs/checklists/M1.md) (M1-8). Nulla è ancora stato provato in gioco.

[English](README.md) · [Roadmap](ROADMAP.md) · [Analisi](docs/ANALISI.md) · [Decisioni](docs/adr/README.md) · [Manuale](docs/wiki/Home-it.md) · [Changelog](CHANGELOG.md)

## Funzioni previste

| Area | Cosa offre |
|---|---|
| **Sessioni di loot** | Drop letti dal corpo, categoria e costo annunciati prima del roll, un popup sul client di ogni raider, `/roll` dal server, tier (prima main-spec, off-spec solo se nessuno lo vuole), reroll automatici fra i pari |
| **Motore delle regole** | Costi per categoria e qualità, eccezioni per oggetto, nuovi arrivati alla media del roster, progetti leggendari, BoE alla banca di gilda; il preset "Patto" della gilda più altri; tutto configurabile dal Guild Master |
| **Registro** | I crediti si calcolano da un registro di eventi firmati: storico, log e audit gratis, e gli officer si sincronizzano senza sovrascriversi |
| **Roster e serate** | Pool della season con main-spec e off-spec dichiarate, main e alt, lineup, rotazione equa della panchina, presenze per boss (solo officer) |
| **Addon obbligatorio** | Chi nel raid non ha l'addon, e un avviso in `/raid` con i nomi in un clic |
| **Indizi di upgrade** | Il client di ogni raider confronta il drop con il pezzo indossato; il council vede "upgrade grande, ha passato" o "possibile spreco" — un indizio, mai una decisione automatica |
| **Council** | Interventi con motivazione obbligatoria, voto facoltativo, annullamenti come eventi di compensazione |
| **Progress** | Prima uccisione di ogni boss per fazione della gilda, come nella scheda Progress del sito della community |
| **Esportazione** | La tabella dei crediti per Discord, CSV, JSON, e i file `roster.json`, `loot.json` e `progress.json` del sito della community pronti da mettere nel sito ([specifica](docs/specs/site-export.md)) |
| **Interfaccia** | Lo stile del sito della community (tema scuro "Nebula", più un tema chiaro e i colori del logo), schede Roster · Crediti · Progress · Loot · Storico · Impostazioni ([stile e anteprime](docs/specs/ui-style.md)); italiano e inglese, altre lingue aggiungendo un file |

## Requisiti

- Client di World of Warcraft: Forever (Interface 16001).
- Ogni raider deve avere l'addon per rollare.

## Sviluppo

- Un passo della roadmap per sessione e per pull request, pubblicato da `tools/ship_step.py` quando i controlli sono verdi ([ADR 0001](docs/adr/0001-git-flow-and-automated-shipping.md)); vedi [CLAUDE.md](CLAUDE.md) e [ROADMAP.md](ROADMAP.md).
- Controlli: `python -I -X utf8 tools/check_docs.py`.
- La checklist di verifica in gioco di ogni milestone sta in [docs/checklists/](docs/checklists/M1.md) (per ora M1).
- Il manuale utente è in [docs/wiki/](docs/wiki/Home-it.md) in italiano e inglese e va sulla wiki di GitHub in automatico ([ADR 0002](docs/adr/0002-github-wiki-generated-from-docs-wiki.md)).
- Le fondamenta si copiano e si adattano dal progetto gemello Azeroth Accord (stesso autore, GPL-3.0); in gioco i due addon restano indipendenti.

## Aggiungere una lingua

Una lingua è **un file più una riga in ciascun file TOC**; nessuna modifica al codice:

1. Copia `FinlandDragonCreditPoints/Locale/enUS.lua` in `FinlandDragonCreditPoints/Locale/<codice>.lua` (per esempio `deDE.lua`; il codice è quello della lingua del gioco), cambia la prima riga in `local L = select(2, ...).NewLocale("deDE", "Deutsch")` e traduci ogni stringa. Tieni i segnaposto `%s` / `%d` nello stesso ordine. Le ultime chiavi (`NUMBER_DECIMAL`, `NUMBER_GROUP`, `DATE_SHORT`, `DATE_LONG`, `DATETIME`) stabiliscono i separatori dei decimali e delle migliaia e i formati della data della lingua.
2. Aggiungi `Locale\<codice>.lua` dopo `Locale\itIT.lua` in `FinlandDragonCreditPoints.toc` e in `FinlandDragonCreditPoints_Camelot.toc`.
3. Esegui `python -I -X utf8 tools/check_locale.py`: segnala le chiavi mancanti, quelle che non esistono in inglese, i segnaposto diversi e un file assente dal TOC. Una stringa mancante non rompe l'addon (ricade sull'inglese), ma il controllo vuole ogni chiave tradotta.

Ogni giocatore sceglie la propria lingua con `/fdcp language` (serve un `/reload`); il capogilda sceglie la lingua dei testi mandati a tutti.

## Licenza

[GNU General Public License v3.0](LICENSE). Addon amatoriale, non affiliato a Blizzard Entertainment.

### Crediti dei font

L'addon include tre famiglie di font con la [SIL Open Font License 1.1](https://openfontlicense.org/) (i testi delle licenze stanno accanto ai file in `FinlandDragonCreditPoints/Media/Fonts/`): **Outfit** (The Outfit Project Authors), **JetBrains Mono** (The JetBrains Mono Project Authors) e **Orbitron** (Matt McInerney, incluso senza modifiche perché dichiara un Reserved Font Name).
