# Finland Dragon Credit Points (FDCP): analisi tecnica e funzionale

> Stato: **analisi v0.1, 19/11/2026**. Nessuna riga di codice scritta. Il documento serve a decidere scope,
> architettura e milestone prima di iniziare. Le domande aperte sono in fondo (§13).

Nome: **Finland Dragon Credit Points (FDCP)**, comando `/fdcp`.

---

## 0. Sintesi

Un addon per **WoW: Forever** che gestisce il sistema di loot a crediti della gilda: il master looter apre le
sessioni di roll, l'addon calcola il vincitore secondo le regole (meno crediti vince, a parità il roll più alto,
a parità ancora si rirolla fra i pari), il council può intervenire, e tutto finisce in un registro consultabile
(crediti, serate, chi ha preso cosa).

Quattro scelte reggono tutto il resto:

1. **Il motore delle regole è codice Lua puro, senza API del gioco**: costi, categorie, ordinamento, nuovi
   arrivati, leggendari. È configurabile da profilo ed è testabile offline con i tre esempi del regolamento.
   **L'addon calcola, il master looter decide**: a fine roll l'addon scrive a chi va il pezzo, quanti crediti
   costa e perché (crediti + roll + fase); il ML conferma, rifiuta o modifica. Crediti e motivazione li scrive
   sempre l'addon, nessuno li calcola a mano.
2. **I crediti non si salvano: si calcolano da un registro di eventi** (event sourcing). Ogni assegnazione,
   correzione o annullamento è un evento firmato da chi l'ha fatto. Lo storico, il log e l'audit sono gratis, e
   due officer possono sincronizzarsi senza sovrascriversi.
3. **I roll arrivano dal server, non dall'addon.** Il pulsante "Rolla" chiama `RandomRoll(1, 100)` e il ML legge
   il risultato dal messaggio di sistema. Un addon modificato non può inventarsi un 100.
4. **Il rilevamento upgrade è un indizio per il council, mai una decisione automatica.** L'addon del giocatore
   confronta il pezzo con quello indossato e manda il risultato al ML. Il ML vede "upgrade evidente, non ha
   rollato" e decide.

---

## 1. Contesto tecnico verificato

Verificato su disco e nel dump API del client (`../WoW-Addons/docs/api.json`, build 1.60.1.70170,
esportato il 01/10/2026). Il client installato è `<cartella WoW>/_forever_`, versione 1.60.1.70959.

| Aspetto | Valore | Conseguenza |
|---|---|---|
| Interface TOC | `16001` | Come Azeroth Accord. Suffisso TOC flavor: `_Camelot` |
| Motore | moderno, basato su 12.0 | API moderne (`C_Item`, `C_ChatInfo`, `C_EncodingUtil`, ScrollBox, mask texture) **e** le restrizioni 12.0 (secret values, lockdown) |
| Lua | 5.1 | Niente `goto`, niente interi a 64 bit |
| Master loot | presente: `GiveMasterLoot`, `GetMasterLootCandidate`, `IsMasterLooter`, `OPEN_MASTER_LOOT_LIST`, `UPDATE_MASTER_LOOT_LIST`, `C_PartyInfo.GetLootMethod/SetLootMethod`, `C_Loot.IsLegacyLootModeEnabled` | Le funzioni esistono; **che funzionino davvero nei raid Forever va provato in gioco** (M0) |
| Loot window | `GetNumLootItems`, `GetLootSlotLink`, `GetLootSlotInfo`, `GetLootSourceInfo`, `LOOT_OPENED/READY/SLOT_CLEARED/CLOSED` | Lettura automatica dei drop all'apertura del corpo |
| Roll | `RandomRoll`, `CHAT_MSG_SYSTEM` | Roll server-side, letti dal messaggio di sistema (pattern localizzato `RANDOM_ROLL_RESULT`) |
| Oggetti | `C_Item.GetItemInfo`, `GetItemInfoInstant`, `GetDetailedItemLevelInfo`, `GetItemStats`, **`GetItemStatDelta`**, `IsEquippableItem`, `DoesItemContainSpec`, `GetItemSpecInfo` | Base del confronto upgrade. Le globali vecchie (`GetItemInfo`, `GetItemStats`) **non** ci sono: si usa `C_Item.*` |
| Specializzazioni | `C_SpecializationInfo.GetSpecialization`, `GetSpecializationInfo` | Presenti nell'API; se Forever le usa davvero va verificato |
| Messaggi addon | `C_ChatInfo.SendAddonMessage`, `InChatMessagingLockdown`, `AreOutgoingAddonChatMessagesRestricted` | In istanza e durante un boss i messaggi possono essere rifiutati: serve una coda |
| Restrizioni | `issecretvalue`, `C_Secrets.*`, `C_RestrictedActions.*`, `ADDON_RESTRICTION_STATE_CHANGED`, `IsEncounterInProgress` | Mai leggere o confrontare un valore segreto. Le sessioni si aprono **dopo** `ENCOUNTER_END` |
| Serializzazione | `C_EncodingUtil` (CBOR, JSON, compressione, Base64) | Niente LibSerialize/LibDeflate: le fa il client |
| Calendario | `C_Calendar.*` | Possibile legare una serata all'evento "raid ufficiale" del calendario |
| Storico nativo | `C_LootHistory.*` | Probabilmente vuoto con master loot; da non considerare fonte primaria |

Riferimenti interni già pronti e da riusare (stesso autore, GPL-3.0):

- **`../azeroth-accord`**: stessa piattaforma. In gioco i due addon restano indipendenti (nessuna
  dipendenza); dal codice sorgente si copiano `Core/Compat.lua` (chiamate protette,
  secret values, restrizioni), la coda di invio con attesa del lockdown, il protocollo versionato, l'impianto dei
  test offline con `lupa` e il client finto, ADR, CI e `check_docs`.
- **`../WoW-Addons`**: dump API, definizioni LSP (`types/WowForeverAPI.lua`), `deploy.ps1` per
  collegare l'addon alla cartella del gioco, `src/SuicideKings` come esempio (vecchio, TBC) di addon a lista di loot.

**Compat (M1-3).** `Core/Compat.lua` è l'unica porta verso queste API. Nel dump **non ci sono** le globali `GetLootMethod`,
`GetItemInfo` / `GetItemStats` / `GetItemInfoInstant`, `GetSpecialization*` e `GetGuildRankOrder` (ci sono solo le
versioni `C_Item.*`, `C_SpecializationInfo.*`, `C_GuildInfo.*`): Compat usa quelle e tiene le globali come ripiego
marcato `[verify]`. Ogni chiamata è protetta (`pcall`): un'API mancante, che solleva un errore o che risponde con un
valore segreto spegne **quella** funzione e mai l'addon. `/fdcp debug` stampa lo stato di ogni funzione
(`available` / `missing` / `unknown` / `restricted` / `error`), senza nomi.

**Non ancora verificato** (lo spike M0 serve a questo, §12): master loot in un raid Forever; se `CHAT_MSG_SYSTEM`
dei roll è leggibile (o segreto) dentro l'istanza; se i messaggi addon `RAID` passano fra un boss e l'altro; se
`GetItemStats` riflette i bonus "contestuali" dell'equipaggiamento raid di Forever.

---

## 2. Modello di dominio

```
Guild ─┬─ Config profile (regole, costi, UI)
       └─ Season ─┬─ Members (main dichiarato, alt collegati, crediti calcolati)
                  ├─ Nights (serate settimanali) ─┬─ Lineup (in raid / panchina / assente)
                  │                               ├─ Encounters (boss uccisi)
                  │                               └─ Loot sessions ─ Items ─ Responses ─ Rolls ─ Award
                  ├─ Legendary projects (catena, costruttore, pezzi pagati)
                  └─ Ledger (registro eventi: unica fonte di verità)
```

| Termine | Significato |
|---|---|
| **Season** | Un **pacchetto di raid**: tutte le istanze uscite con lo stesso aggiornamento di contenuto (da 10, 20 e 40), con **una sola tabella crediti** condivisa. Quando esce il pacchetto nuovo si apre una season nuova e tutti ripartono da 0 (configurabile). |
| **Istanza della season** | Un raid del pacchetto, con la sua dimensione (10/20/40) e i suoi boss. Una serata si svolge in una di queste. |
| **Main** | L'unico personaggio che accumula crediti. Gli alt sono collegati al main, non hanno crediti propri. |
| **Night** | Una serata di raid ufficiale. Ha una data, un'istanza, una lineup, i boss uccisi, i drop. |
| **Session** | Insieme di oggetti messi in palio dopo un boss (o a fine serata). |
| **Tier di risposta** | Main-spec, off-spec, ecc.: un tier si apre solo se nessuno ha risposto al tier prima. |
| **Council** | Gli officer presenti alla serata (rango e presenza configurabili). |
| **Award** | L'assegnazione di un oggetto: a un giocatore, alla banca di gilda, al disenchanter. |

---

## 3. Regole: dal regolamento al motore configurabile

### 3.1 Il regolamento attuale espresso come configurazione ("preset Patto")

| Regola | Parametro | Valore preset |
|---|---|---|
| Solo raid ufficiali | `night.requiresOfficialStart` | sì: la serata la apre il ML/officer dall'addon |
| Solo main | `members.mainOnly` | sì |
| Reset a ogni season | `season.startCredits` | 0 |
| Season = pacchetto di raid | `season.instances` | lista delle istanze del pacchetto (10/20/40), tabella crediti unica |
| Costo uguale per dimensione del raid | `cost.raidSizeMultiplier` | 10 = × 1, 20 = × 1, 40 = × 1 (modificabile per chi vuole pesare diversamente un raid da 10) |
| Difficoltà | `season.difficultyTables` | **una tabella** per Normal e Veteran; costo × 1 per entrambe (`cost.difficultyMultiplier`, modificabile) |
| Spec per risposta | `responses.specMap` | **MS1 = MS** (tier 1, costo pieno); **MS2 = OS** (tier 2, 0 crediti, solo se nessuno MS). La terza voce "OS" del canale Roster (la spec che ti piacerebbe) non dà diritto al roll |
| Priorità | `priority.metric` | crediti crescenti |
| Spareggio 1 | `priority.tieBreak[1]` | roll più alto |
| Spareggio 2 | `priority.tieBreak[2]` | reroll solo fra i pari |
| Costo arma, trinket, oggetto di quest | `cost.category.*` | 2 |
| Costo resto | `cost.category.default` | 1 |
| Off-spec | `responses.OS` | tier 2, costo × 0, solo se nessuno MS |
| Categoria annunciata prima del roll | `session.lockCategoryOnOpen` | sì: dopo l'apertura del roll la categoria non si cambia |
| BoE senza richieste MS | `boe.fallback` | banca di gilda |
| Leggendari | `legendary.mode` | assegnati dal council, senza roll; 2 crediti per ogni pezzo della catena |
| Nuovo arrivato | `members.lateJoin` | i crediti del membro che ne ha **meno** (`min`, regola del proprietario del 22/11/2026, M7-5b) |
| Assenza da una serata ufficiale | `penalties.absence`, `penalties.autoApply` | **+1 credito** a chi non si iscrive, si iscrive e non viene, o si mette in panchina da solo; confermato da un officer (§6, M7-5b) |
| Rotazione | `bench.creditEffect` | nessuno (chi gioca meno accumula meno crediti, quindi ha la precedenza); `bonus` / `malus` + `bench.creditAmount` per altre gilde |

### 3.2 Costo di un oggetto

Il costo si risolve in quest'ordine, e il primo che risponde vince:

1. **Override per oggetto** (`itemID → costo` o `itemID → categoria`): per i casi che il council chiarisce prima
   del roll e vuole fissare per tutta la season.
2. **Matrice categoria × qualità**:

   | Categoria | Verde | Blu | Viola | Arancione |
   |---|---|---|---|---|
   | Arma (mano destra, sinistra, due mani, a distanza, bacchetta) | non tracciato | 2 | 2 | council |
   | Scudo / mano secondaria | non tracciato | 1 | 1 | council |
   | Trinket | non tracciato | 2 | 2 | council |
   | Oggetto di quest / token | non tracciato | 2 | 2 | council |
   | Gioielli (anello, collo) | non tracciato | 1 | 1 | council |
   | Armatura (ogni slot), mantello | non tracciato | 1 | 1 | council |
   | Ricette, cavalcature, cosmetici | non tracciato | 0 | 0 | - |
   | Altro | non tracciato | 1 | 1 | - |

   Ogni cella è un numero modificabile (anche decimale, se una gilda vuole 1,5). "Non tracciato" significa che
   l'oggetto non entra nelle sessioni: si sincronizza con la soglia di loot del gruppo (`GetLootThreshold`).
3. **Moltiplicatore della risposta**: MS × 1, OS × 0, transmog × 0 (configurabili).

Classificazione automatica: `classID` / `subclassID` / `equipLoc` da `C_Item.GetItemInfoInstant`. Una tabella
`equipLoc → categoria` (modificabile) decide la categoria. "Oggetto di quest" = `classID` Quest **oppure** un
oggetto che avvia una quest **oppure** un `itemID` nella lista "token" della season, perché il gioco non sempre
marca come quest un pezzo che fa parte di una catena.

**Come è fatto (M2-1).** `Domain/Classifier.lua` e `Domain/Pricing.lua`, Lua puro (l'adapter passa `classID`, `subclassID`, `equipLoc`, qualità e "avvia una quest"). Ordine delle regole di classificazione: oggetto di quest → tabella `classID:subclassID` (bacchette, scudi, armature cosmetiche, cavalcature, mascotte) → tabella `equipLoc` → tabella `classID` (ricette) → "altro". Scelte fatte dove il testo sopra non decideva (tutte modificabili):

- la soglia di qualità viene **prima** di tutto: un override non fa entrare in sessione un oggetto sotto soglia;
- i moltiplicatori (risposta, dimensione del raid, difficoltà) valgono anche per un costo fissato con override, quindi un off-spec costa sempre 0;
- una cella mancante (il "-" della tabella, o il verde quando il gruppo abbassa la soglia) va al **council**, come l'arancione; un off-spec su un oggetto "council" costa comunque 0;
- in una stessa voce di override, `cost` vince su `category`; una categoria sconosciuta si ignora;
- reliquie (libram, idoli, totem) come mano secondaria; camicie e tabard come cosmetici;
- i costi decimali si arrotondano a 2 cifre; `Pricing.Validate` rifiuta costi negativi (il sito della community li rifiuta) e categorie sconosciute.

### 3.3 Risposte (tier)

Lista modificabile; ogni voce ha nome, colore, icona, tier, moltiplicatore di costo, se conta come "vuole il pezzo".

| Risposta | Tier | Costo | Note |
|---|---|---|---|
| Main-spec | 1 | × 1 | con etichetta facoltativa: *BiS*, *Upgrade grande*, *Upgrade piccolo*, *Situazionale* (informativa, non cambia la priorità) |
| Off-spec | 2 | × 0 | si apre solo se nessuno risponde al tier 1 |
| Transmog / greed | 3 | × 0 | facoltativo, disattivato nel preset |
| Passo | - | - | |

Le etichette servono al council e al rilevamento dei "furbi" (§5), non all'algoritmo.

### 3.4 Algoritmo di assegnazione (funzione pura)

```
per ogni tier, dal più basso:
    candidati = risposte del tier con roll valido (1-100, primo roll del round, dal personaggio presente)
    se vuoto: passa al tier successivo
    ordina per (metrica crescente, roll decrescente)
    se in testa ci sono più candidati con stessa metrica e stesso roll:
        round di reroll solo fra loro (ripeti finché uno resta solo)
    altrimenti: vincitore = primo
se nessun tier ha candidati: fallback (BoE -> banca, altrimenti disenchant / free roll / ML)
```

`metrica` è configurabile: crediti (preset), crediti divisi per serate giocate, solo roll (per chi vuole
disattivare i crediti in una serata speciale).

**L'addon calcola e scrive, il master looter decide.** Quando il round si chiude l'addon:

1. sceglie il vincitore da crediti della tabella + valore del roll, secondo la fase (tier) in corso;
2. se serve, apre da solo il reroll fra i pari, o il tier off-spec, o il fallback;
3. prepara la **proposta di assegnazione**, già compilata:
   - **a chi**: il vincitore;
   - **quanto**: il costo in crediti (categoria × qualità × moltiplicatore della risposta: MS paga, OS 0);
   - **perché**: la motivazione in chiaro, per esempio *"Bryn — main-spec, 0 crediti, roll 76: stessi crediti di
     Aurel e Corin, roll più alto"* oppure *"Aurel — main-spec, 0 crediti contro 2 e 3: meno crediti, il roll non
     conta"*, con le eventuali segnalazioni (§5.2);
4. il ML sceglie:
   - **Conferma** → crediti addebitati, evento `ITEM_AWARDED` nel registro con la motivazione scritta
     dall'addon, risultato annunciato al raid, consegna del pezzo;
   - **Rifiuta** → nessun addebito; il pezzo torna in sessione (riapri il roll, passa al tier successivo, banca o
     disenchant);
   - **Modifica** → il ML cambia il vincitore e/o il costo; l'addon ricalcola e mostra la differenza rispetto
     alla regola ("fuori fila: Bryn era primo"), la motivazione del ML è obbligatoria e l'evento finisce
     nell'audit come intervento.

Il ML non calcola mai crediti a mano e non scrive mai la motivazione di un'assegnazione normale: lo fa l'addon. Il
ML scrive solo quando si discosta dalla regola. Gli altri membri del council vedono la stessa proposta e possono
segnalare al ML il loro parere (voto facoltativo, §3.6).

Modalità (`session.awardMode`): `confirm` (preset, vale per tutti), `auto` (l'addon assegna da solo dopo una
finestra di intervento configurabile), `council` (decide sempre il council a voto).

I tre esempi del regolamento diventano test automatici del motore: anello (stessi crediti, vince 76), spallina
(meno crediti, vince 34), mantello (pari crediti e roll, reroll fra Bryn e Corin).

**Come è fatto (M2-2).** `Domain/Priority.lua`, Lua puro: `Priority.Evaluate(stato, config)` rigioca i round
tenuti finora (risposte, roll in ordine di arrivo, crediti) e restituisce il prossimo round da tenere (`ROLL` di un
tier o del free roll, `REROLL` solo fra i pari) oppure la proposta `{kind, winner, cost, reasons, flags}` con codici
neutri (`MAIN_SPEC_TIER`, `OFFSPEC_TIER`, `LOWER_CREDITS`, `HIGHER_ROLL`, `REROLL_WON`, `ONLY_CANDIDATE`, `BOE_BANK`,
`FALLBACK_*`, `TIE_ML`), mai frasi. Ogni roll scartato ha un codice (`NOT_1_100`, `DUPLICATE`, `NOT_PRESENT`,
`NO_ADDON`, `NOT_ELIGIBLE`, `BEFORE_OPEN`, `AFTER_CLOSE`, `BAD_VALUE`). Scelte fatte dove il testo sopra non decideva
(tutte modificabili):

- ogni tier ha il **suo round**: chi ha risposto off-spec rolla solo quando si apre il tier 2; un tier senza
  risposte non chiede nessun round; un roll di chi non è candidato del round viene scartato (`NOT_ELIGIBLE`);
- "primo roll del round" = il primo roll **1-100**: un `/roll 1000` viene scartato e non consuma il turno;
- al reroll, chi fra i pari non rolla perde; se nessuno rolla, il reroll si ripete fra gli stessi; dopo
  `maxRerolls` (preset 5) reroll di fila decide il ML (`REROLL_LIMIT`);
- senza `reroll` in `tieBreak`, la parità totale va al ML (`TIE_UNRESOLVED`); senza `roll`, a parità di metrica si
  va subito al reroll;
- metrica "crediti per serata": crediti / serate giocate, con 0 serate contate come 1;
- un BoE senza candidati main-spec va a `boe.fallback` (preset banca) **prima** del tier off-spec, salvo
  `boe.fallback = offspec`; senza personaggio banca configurato la proposta resta "banca" con il segnale
  `NO_BANK_CHARACTER`;
- fallback per gli altri oggetti senza candidati: **ML** nel preset (`ml` | `disenchant` | `freeroll`); il free roll
  è aperto a tutti i presenti con l'addon, vince il roll più alto (pari: reroll), costo `freeRollCost` (preset 0);
- un costo deciso dal council (cella "council" di §3.2) lascia `cost` vuoto con il segnale `COST_BY_COUNCIL`.

I tre esempi sono in `Tests/test_priority.lua`: anello (Aurel, Bryn, Corin a 0 crediti; roll 45, 76, 12: vince Bryn
con 76), spallina (crediti 0, 2, 3; roll 34, 90, 99: vince Aurel con 34), mantello (tutti a 1 credito; Bryn e Corin
88, Aurel 40: reroll solo fra Bryn e Corin, il roll di Aurel nel reroll è scartato, vince Corin).

**Come è fatto (M2-7).** Il manuale (`docs/wiki/Loot-Rules.md` e `Loot-Rules-it.md`) riscrive §3 e i tre esempi per i giocatori, con i numeri di `Tests/test_priority.lua`. `Domain/Reasons.lua` associa a ogni codice neutro che il dominio emette (motivi, segnalazioni, roll scartati, origine del costo, regola del nuovo arrivato, motivi del ML, rifiuti, risposte, tipi di proposta, stati, tipi di evento, preset) la chiave `RC_<GRUPPO>_<CODICE>` di una frase nelle traduzioni; un codice vale solo nel suo gruppo (`NOT_PRESENT` è un roll scartato in uno e un'azione rifiutata in un altro). `Reasons.Text(gruppo, codice)` dà la frase nella lingua attiva, o il codice stesso se l'addon non lo conosce. La tabella della pagina del manuale è generata dalle stesse frasi.

### 3.5 Nuovi arrivati a season iniziata

Il roster è **dinamico**: un giocatore può entrare a season iniziata. Chi entra **riceve i crediti del giocatore che
ne ha meno** (regola del proprietario del 22/11/2026, che sostituisce la "media del roster arrotondata per difetto":
preset Patto `members.lateJoin.method = min`). Così il nuovo arrivato non scavalca chi c'era già (vince chi ha meno
crediti) ma nemmeno parte svantaggiato rispetto all'ultimo della fila.

`members.lateJoin` = `min` (Patto) | `average` | `median` | `zero` | `fixed`; arrotondamento `floor` | `round` | `ceil`;
base di calcolo = "membri con almeno N serate nella season" (preset N = 1). Il valore iniziale viene scritto
nel registro come evento `MEMBER_JOINED{initialCredits}`: resta stabile anche se il minimo cambia dopo.

**Come è fatto (M7-5b).** Il preset Patto (`Rules.DefaultConfig`) sceglie `min`; `Domain/Members.lua` tiene
`average` come proprio default per chi lo chiama senza regole, e gli altri preset restano com'erano (Solo roll e Loot
council `zero`, EPGP semplice `average`). Il nome nella finestra della season è "Meno crediti del gruppo". La base è
quella di sempre: i membri con almeno `minNights` serate giocate (preset 1), della stessa fazione se il nuovo
arrivato la dichiara; un membro che non ha mai giocato non abbassa il minimo. Le penalità di assenza (§6) contano: il
minimo si legge dai crediti del registro nel momento in cui il membro entra.

**Come è fatto (M2-4).** `Domain/Members.lua`: `MEMBER_JOINED{member, faction?, initialCredits, rule, basis?}`, dove `rule` è il codice del calcolo (`START`, `AVERAGE`, `MEDIAN`, `MIN`, `ZERO`, `FIXED`, `EMPTY_BASIS`) e `basis` quanti membri ha usato; arrotondamento a 0-2 decimali (preset 0). Default scelti dove l'analisi taceva: si è "nuovo arrivato" quando la season ha già almeno una serata ufficiale (`NIGHT_OPENED`), prima si parte da `season.startCredits`; le serate per membro le dà la lineup (M3), senza quel dato la base è tutto il pool; se il nuovo arrivato dichiara una fazione la base sono i membri di quella fazione (o senza fazione); base vuota = `startCredits`. `Domain/Season.lua`: `SEASON_OPENED{label?, instances = {{id, size}}, startCredits}` e `SEASON_CLOSED`; una sola season aperta alla volta, un id non si riusa; `startCredits` resta scritto nell'evento.

### 3.6 Council

- **Chi è**: rango di gilda ≤ X **e** presente nel raid (preset), oppure lista esplicita di personaggi. Il rango è il
  permesso `council.member` di §3.9; la presenza e il voto sono `council.requirePresent` e `council.vote` delle regole
  (M2-5). Le segnalazioni di §5.2 e chi vede i verdetti sono `council.flags`, `council.wasteRatio` e `council.verdicts`
  (M5-4).
- **Cosa può fare**, sempre con una motivazione obbligatoria che finisce nel log:
  - correggere la categoria o il costo **prima** dell'apertura del roll (dopo è bloccato, come dice il regolamento);
  - *spreco palese*: assegnare a un altro candidato invece del primo in fila;
  - *passa per fare il furbo*: assegnare d'ufficio a chi non ha rollato, con il costo pieno;
  - assegnare un leggendario;
  - annullare un'assegnazione (evento di compensazione, non una cancellazione);
  - correggere a mano i crediti di un membro.
- **Voto** (facoltativo, spento nel preset): sugli interventi, ogni membro del council vota dalla propria finestra
  e il ML vede i voti prima di confermare.

**Come è fatto (M5-5).** `Domain/Council.lua` (puro) più il voto nella `SessionFSM` e `App/CouncilService.lua` (la colla
con ranghi, raid, protocollo e registro). Scelte fatte dove il testo sopra non decideva (tutte reversibili):

- **Chi è.** Nuova chiave `council.members` (lista di personaggi `Nome-Reame`, al massimo 40, vuota nel preset): se non
  è vuota **sostituisce** il rango (è "oppure lista esplicita"); vuota, decide il permesso `council.member`. Con
  `council.requirePresent` conta solo chi è nel raid: sul client del ML la presenza è quella della sessione, altrove
  l'ultima lettura del raid; presenza sconosciuta = fuori. La finestra in sola lettura e la visibilità dei verdetti
  (M5-4) usano la stessa appartenenza, senza chiedere il raid (la vista arriva solo ai membri del raid).
- **Interventi sulla proposta.** Restano gli input del ML di M2-6, sempre con un codice motivo: `CORRECT_ITEM`
  (categoria o costo, rifiutato a roll aperto con `CATEGORY_LOCKED`), `MODIFY` con `OBVIOUS_WASTE` (un altro candidato,
  paga il costo della sua risposta) o `PASSED_TO_GAME` (chi non ha rollato, costo pieno). Le correzioni fatte prima del
  roll ora viaggiano con l'assegnazione (`ITEM_AWARDED.corrections`: categoria, costo, motivo, chi), così finiscono
  nell'audit; una correzione di un pezzo mai assegnato resta solo nel log della sessione (non muove crediti). I membri
  del council che non sono il ML non comandano la sessione: votano, e il ML esegue (§3.9, "le correzioni del council le
  scrive il ML").
- **Annullare e correggere i crediti.** `Council.Void` scrive `AWARD_VOIDED{ref, reason, member?, item?}` (stessa season
  dell'evento annullato) e `Council.Adjust` `CREDITS_ADJUSTED{member, delta, reason}` (un main del pool della season;
  delta diverso da 0 e al massimo 1000 in valore assoluto; positivo pesa come un costo). Motivi propri: annullamento
  `MISTAKE`, `DUPLICATE_AWARD`, `OBVIOUS_WASTE`, `PASSED_TO_GAME`, `COUNCIL_VOTE`, `LEGENDARY`, `OTHER`; correzione
  `MISTAKE`, `PENALTY`, `BONUS`, `COUNCIL_VOTE`, `OTHER` (nuovi codici del gruppo `CORRECTION`). Entrambi passano dal
  cancello di `Ledger.Append`: `night.run` mentre una serata della season è aperta, `credits.adjust` fuori (M2-5).
- **Audit.** `Council.Audit(L, season)` rilegge dal registro, in ordine canonico, ogni intervento: `MODIFY`
  (assegnazione fuori regola, con vincitore e costo della regola, motivo, segnalazioni, voti), `CORRECT` (una per
  correzione prima del roll), `VOTE` (assegnazione con voti che ha tenuto il vincitore della regola), `VOID`, `ADJUST`;
  un evento poi annullato è segnato. `/fdcp council audit` ne stampa gli ultimi.
- **Voto.** In `awardMode = council` come in M2-6 (`CONFIRM` aspetta `CLOSE_VOTE`, maggioranza stretta, parità o
  nessun voto: decide il ML). Con `council.vote` acceso nelle altre modalità i voti **informano** il ML: può confermare
  subito, chiudere il voto per applicare la maggioranza o modificare; in `auto` un voto per un altro giocatore ferma
  l'assegnazione automatica (`AUTO_HELD`). Il votante deve essere del council (`env.isCouncil`, rifiuto `NOT_COUNCIL`),
  la scelta un presente all'apertura del roll (`NOT_PRESENT`); l'ultimo voto di un membro sostituisce il precedente; i
  voti (anche quelli consultivi) finiscono nell'`ITEM_AWARDED` (`votes`). La finestra del ML li mostra nella striscia e
  offre **Chiudi il voto**.
- **Protocollo 4.** Nuovo `SVOTE` su RAID (`i`, `c`): sempre il voto del mittente (un `p` o un `by` che nomina un altro
  è falso, `FORGED`), contato solo da un membro del council su ogni client e di nuovo dalla macchina a stati del ML;
  `SPROP` porta `vc` (voto chiuso), `SSTATE` i voti già dati (`vt`). Retrocompatibile: un client di protocollo 2 o 3
  scarta il tipo nuovo senza leggerlo e continua a seguire la sessione (`Protocol.MIN` resta 2); semplicemente non vota.
- **Interfaccia.** Il comando `/fdcp council` (stato, `vote`, `awards`, `void`, `adjust`, `audit`), parole tutte da
  chiavi di traduzione, resta come interfaccia da tastiera accanto alla finestra del council (M5-8, sotto).
- **Da verificare in gioco:** il messaggio `SVOTE` sul canale del raid durante una sessione vera (spike S4, come
  `SRESP`), la riga dei voti e il pulsante *Chiudi il voto* nella striscia della finestra, e l'output di `/fdcp council`
  nella chat.

**Come è fatto (M5-8).** La sotto-scheda **Loot › Council** è `UI/Windows/Council.lua`, agganciata a `UI/Windows/MLSession.lua`
(terza voce del selettore dopo *Sessione* e *Da consegnare*). Non decide niente: legge la plancia
(`SessionController:Board()`, la stessa della scheda Sessione e con la stessa selezione del pezzo), `CouncilService`
(appartenenza, voto, annullamento, correzione, audit) e `LegendaryService` (i progetti), e rimanda i clic a quei servizi, di cui
mostra a parole i rifiuti (rango, motivo, season, oggetto). Scelte fatte dove il testo non decideva (tutte reversibili):

- **Scheda "Sul tavolo".** A sinistra: il pezzo, la proposta, le segnalazioni che nominano un giocatore (`SessionBoard.FlagLines`,
  in tempo reale a roll aperto), i voti (`SessionBoard.VoteText`), l'elenco **Il tuo voto** (il proposto per primo, poi i candidati
  che la plancia conosce) con **Vota**, e le scorciatoie **Modifica** / **Correggi**, solo sul client del ML: aprono le finestre con
  motivo della scheda Sessione (`MLSession:OpenDialog`), che restano l'unico posto dove si scrive `MODIFY` / `CORRECT_ITEM`, e solo se
  la plancia dice che l'azione è ammessa (`board.actions`).
- **Quando si può votare.** Nuovo `CouncilService:CanVote(board)`: il pezzo è in proposta, le regole chiedono il voto
  (`awardMode = council`, oppure `council.vote`) e il voto non è chiuso. La vista in sola lettura non dice se qualcuno ha già votato,
  quindi decidono le regole in vigore sul client (come sul ML, `SessionFSM.VoteDecides`); un voto fuori da questi casi il ML lo
  ignorerebbe, e il pulsante resta spento con la riga *nessun voto aperto su questo pezzo*. Nuovo anche `CouncilService:AwardMode()`
  (la modalità di assegnazione e se il voto è consultivo) per la riga di stato, e `CouncilService:Pool()` (i personaggi del pool
  della season per **Correggi crediti**).
- **Tre viste a destra.** *Assegnazioni* (`Council.Voidable`, dalla più recente, **Annulla assegnazione...**), *Audit*
  (`Council.Audit` letto al contrario, una riga per intervento con `CouncilService.AuditLine`, gli annullati attenuati) e *Leggendari*
  (`Legendary.Projects`, con la modalità e il costo del pezzo, **Apri progetto...**, **Segna come costruito**, **Abbandona**).
  *Correggi crediti...* sta in alto a destra.
- **Finestre con motivo obbligatorio.** Annulla e correggi hanno una finestra sola (velo e card come le altre, Esc chiude): la lista
  dei motivi è quella del dominio (`Council.VOID_ORDER` / `ADJUST_ORDER`, parole del gruppo `CORRECTION`), mai testo libero; senza
  motivo non si scrive, e il rifiuto del cancello dei permessi (`RANK_TOO_LOW`...) resta nella finestra, aperta. Il numero dei
  crediti accetta la virgola e il meno tipografico. Il progetto leggendario chiede nome, oggetto finale, pezzi (link o id), costruttore
  (il pool, o nessuno) e coda; i link si possono inserire con Maiusc+clic ascoltando `ChatEdit_InsertLink` (solo se la funzione c'è, mai
  sostituita: `hooksecurefunc`).
- **Cosa non c'è.** Nessuna finestra per la banca di gilda (`/fdcp bank`, M5-7 resta il comando) e nessuna per il voto "in alto":
  il ML chiude il voto dalla scheda Sessione.
- **Da verificare in gioco:** la pagina in un raid vero (layout accanto alle altre schede, leggibilità, scorrimento con la
  rotella), il voto e il suo messaggio `SVOTE`, le finestre di dialogo, il Maiusc+clic dei link nei campi (la funzione la definisce il
  gioco in Lua e non è nel dump delle API), la vista in sola lettura di un membro del council. Tutto è nella checklist
  `docs/checklists/M5.md`.

### 3.7 Leggendari

`legendary.mode` configurabile:

| Modalità | Comportamento |
|---|---|
| `council` (preset) | Nessun roll. Il council sceglie il costruttore del **progetto leggendario**; ogni pezzo della catena va a lui e costa `legendary.chainPieceCost` (preset 2) |
| `vote` | Il council vota, vince la maggioranza, il costo è come sopra |
| `roll` | Si rolla come un oggetto normale, con la categoria che decide il costo |
| `queue` | Lista di priorità decisa a inizio season: il pezzo va al primo della lista che è presente |

Un **progetto leggendario** ha: nome, oggetto finale, `itemID` dei pezzi della catena, costruttore, pezzi già
pagati. Quando un pezzo della catena cade, l'addon lo riconosce e propone direttamente il costruttore.

**Come è fatto (M5-6).** `Domain/Legendary.lua` (puro), il riconoscimento nella `SessionFSM` e `App/LegendaryService.lua`
(la colla con season, regole e registro). Scelte fatte dove il testo sopra non decideva (tutte reversibili):

- **Il progetto nel registro.** Tre eventi della season, tutti dal cancello dei permessi (`night.run`, gli officer nel
  preset): `LEGENDARY_PROJECT_OPENED{name, item, pieces, builder?, queue?}` (l'id del progetto è l'id di questo evento;
  `name` è un dato come l'etichetta di una season, non una frase), `LEGENDARY_PROJECT_PAID{ref, item, member, cost,
  award}` e `LEGENDARY_PROJECT_CLOSED{ref, outcome, reason?}` con esito `COMPLETED` o `ABANDONED`. I controlli dei payload
  li registra il modulo in `Ledger.CHECKS`. Il costruttore e i nomi della lista devono essere nel pool della season
  (`NOT_MEMBER`); un pezzo appartiene a un solo progetto aperto (`PIECE_TAKEN`), così un `itemID` nomina un progetto. Un
  progetto vive nella sua season: in una season nuova si riapre.
- **I crediti restano dell'assegnazione.** Il pezzo si addebita con il solito `ITEM_AWARDED` (che porta `legendary` = il
  progetto); subito dopo, con la stessa firma e lo stesso cancello, la conferma scrive `PAID` con il riferimento
  all'assegnazione. `PAID` non muove crediti: segna il progresso. Se l'assegnazione viene annullata (`AWARD_VOIDED`) il
  pezzo non conta più. I progetti si ricostruiscono leggendo prima le aperture e poi pagamenti e chiusure, perché la
  sessione timbra i suoi eventi con il proprio orologio; un `PAID` o un `CLOSED` dopo la chiusura, o per un progetto
  sconosciuto, resta nel registro ma non conta.
- **Il pezzo nella sessione.** A `LOOT_OPENED` la sessione riceve i pezzi dei progetti aperti (`env.legendary`, letto dal
  registro solo quando si apre un corpo) e, se `legendary.mode` non è `roll`, segna l'oggetto: costa
  `legendary.chainPieceCost` per ogni risposta (anche un pezzo sotto la soglia del loot entra nella sessione). Quando
  arriva il suo turno non si apre nessun round: la proposta nomina chi lo riceve (`Legendary.Recipient`). `council`: il
  costruttore; `vote`: il costruttore proposto, poi il voto del council decide (`CONFIRM` aspetta `CLOSE_VOTE`, anche con
  `awardMode = auto`); `queue`: il primo della lista presente nel raid (senza lista, il costruttore); `roll`: un oggetto
  normale, il progetto non c'entra. Senza nessuno da proporre la proposta non ha vincitore e porta una segnalazione
  (`NO_BUILDER`, `BUILDER_ABSENT`, `QUEUE_EMPTY`): il ML sceglie con `MODIFY` e un motivo (il costo resta quello della
  catena) o manda il pezzo in banca (niente `PAID`). Con `awardMode = auto` e nessuna segnalazione il pezzo va al
  costruttore da solo. Il ML può correggere il costo prima del turno del pezzo (`CORRECT_ITEM`).
- **Interfaccia.** Fino alla finestra del council (M5-8) il comando `/fdcp legendary` (elenco con modalità e costo,
  dettagli di un progetto, `open`, `complete`, `abandon`), parole tutte da chiavi di traduzione; gli oggetti si scrivono
  come link o come id.
- **Da verificare in gioco:** l'output di `/fdcp legendary` nella chat e i link degli oggetti scritti nel comando (il resto
  è la sessione di M4).

### 3.8 BoE

Un BoE si rolla come gli altri oggetti (stessa categoria, stesso costo). Se nessuno risponde main-spec,
`boe.fallback` = `bank` (preset) | `offspec` | `disenchant` | `freeroll`. Con `bank`, l'oggetto viene assegnato al
personaggio "banca" configurato, il log lo segna "Banco dell'Oste", e un officer può aggiungere poi l'oro ricavato
dalla vendita.

**Come è fatto (M5-7).** I quattro fallback c'erano già: `Domain/Priority.lua` (M2-2) li calcola, `Domain/SessionFSM.lua`
scrive l'assegnazione e la consegna di M4-7 porta l'oggetto. Lo step aggiunge `Domain/GuildBank.lua` (puro),
`App/BankService.lua` (la colla con season, regole e registro) e il comando `/fdcp bank`. Scelte fatte dove il testo
sopra non decideva (tutte reversibili):

- **Le quattro modalità.** `bank` (preset): proposta `BANK` al `priority.bankCharacter` a costo 0, motivo `BOE_BANK`; senza
  personaggio banca la proposta non ha vincitore e porta il flag `NO_BANK_CHARACTER`, e il master looter sceglie (con
  `MODIFY`, sempre verso la banca e a costo 0). `offspec`: si apre il turno off-spec come per ogni oggetto, al costo
  off-spec. `disenchant`: proposta `DISENCHANT` a chi disincanta, a costo 0. `freeroll`: un roll libero fra chi può
  rollare, al costo `priority.freeRollCost` (preset 0). Un BoE che qualcuno prende main-spec costa come ogni oggetto
  della sua categoria. Un oggetto che si lega alla raccolta non prende mai il fallback BoE.
- **"Il log lo segna banca".** La conferma scrive `ITEM_AWARDED{target = "bank", member = il personaggio banca, cost =
  0}`: il registro e l'annuncio dicono "alla banca di gilda" (le parole sono chiavi di traduzione, `RC_KIND_BANK`). Il
  calcolo dei crediti conta solo le assegnazioni con `target = "member"`, quindi un oggetto della banca non muove i
  crediti di nessuno, qualunque costo porti; vale anche per un oggetto mandato in banca dal master looter (`REJECT` poi
  `BANK`, `MODIFY` verso la banca). Il nome "Banco dell'Oste" resta il nome che la gilda dà alla banca: l'addon non lo
  scrive nel codice (nessun testo visibile fuori dalle traduzioni) e mostra il personaggio banca configurato.
- **L'oro della vendita.** Un evento nuovo della season, `BANK_ITEM_SOLD{ref, copper}`: `ref` è l'`ITEM_AWARDED` alla
  banca, `copper` il prezzo in rame (un intero da 0 al tetto dell'oro del gioco). Passa dal cancello dei permessi con
  `night.run` (gli officer nel preset, come i progetti leggendari: nessun permesso nuovo). Non muove crediti. Una
  seconda vendita dello stesso oggetto corregge la prima (conta l'ultima in ordine canonico); un'assegnazione alla banca
  annullata esce dall'elenco e la sua vendita non conta più; una vendita di un oggetto non della banca o annullato è
  rifiutata (`NOT_BANK_ITEM`, `BANK_ITEM_VOIDED`, `BAD_GOLD`).
- **Interfaccia.** Fino alla finestra del council (M5-8) il comando `/fdcp bank`: la modalità in vigore, il personaggio
  banca, gli oggetti della banca della season con il prezzo e il totale; `sold <n> <prezzo>` registra una vendita (oro
  `120`, `12.5`, o monete `12g 30s 5c`, anche con le lettere italiane `12o 30a 5r`). Legge la season aperta, o la più
  recente se nessuna è aperta, perché la vendita arriva spesso dopo.
- **Da verificare in gioco:** l'output di `/fdcp bank` nella chat; che il client dia `bindType` 2 ai BoE quando si apre il
  cadavere; il master loot al personaggio banca in un raid vero (la stessa strada di ogni assegnazione, M4-7).

### 3.9 Permessi per rango di gilda (li decide solo il GM)

Chi può fare cosa è **configurabile per rango di gilda**, e **solo il Guild Master** può cambiare questa
configurazione. L'addon legge il rango dal gioco, non da una lista scritta a mano:

| Dato | API (presenti nel dump Forever) |
|---|---|
| Sono io il GM? | `IsGuildLeader()` |
| Rango di un membro | `GetGuildRosterInfo(i)` → `rankName`, `rankIndex` (0 = GM) |
| Nomi e numero dei ranghi | `GuildControlGetNumRanks()`, `GuildControlGetRankName(i)` |
| Officer secondo il gioco | `C_GuildInfo.IsGuildOfficer()`, `CanEditOfficerNote()` |

Permessi configurabili (ognuno con il rango minimo che lo ottiene; preset fra parentesi):

| Permesso | Cosa consente | Preset |
|---|---|---|
| `config.rules` | Cambiare costi, categorie, risposte, modalità di assegnazione, leggendari, nuovi arrivati | solo GM (fisso) |
| `config.permissions` | Cambiare questa tabella dei permessi | **solo GM (fisso, non modificabile)** |
| `season.manage` | Aprire e chiudere una season, definire il pacchetto di raid | solo GM |
| `night.run` | Aprire una serata ufficiale e guidare le sessioni come master looter | officer |
| `award.confirm` | Confermare, rifiutare, modificare una proposta in serata | il master looter della serata, se ha `night.run` |
| `council.member` | Far parte del council (vedere verdetti upgrade, votare, segnalare) | officer presenti nel raid |
| `credits.adjust` | Correggere crediti o annullare un'assegnazione **fuori dalla serata** | solo GM (preset); il GM può abbassarlo a "officer" |
| `roster.manage` | Modificare il pool, collegare alt, correggere MS1/MS2 a season aperta | officer |
| `export.public` | Esportare la tabella per il sito e Discord | officer |
| `view.attendance` | Vedere presenze e panchine | officer |
| `raid.addonCheck` | Vedere chi non ha l'addon attivo e mandare l'avviso in `/raid` (§4.1) | officer (e il master looter della serata) |
| `progress.edit` | Inserire, correggere o togliere a mano la prima uccisione di un boss (`PROGRESS_SET`, §7.1) | officer |

Come si rende sicuro:

- La configurazione è un evento del registro (`CONFIG_CHANGED`, `PERMISSIONS_CHANGED`) come gli altri. Ogni client
  lo accetta **solo se l'autore è il GM** secondo il proprio roster di gilda (`rankIndex == 0`). Un officer con
  un addon modificato non può cambiare le regole: gli altri client scartano l'evento.
- Allo stesso modo ogni evento (assegnazione, correzione, season) è accettato solo se, al momento in cui è stato
  scritto, l'autore aveva il rango richiesto dal permesso in vigore.
- I permessi si riferiscono all'**indice del rango**, non al nome: se il GM rinomina un rango nulla si rompe; se
  riordina o elimina ranghi, l'addon lo segnala al GM e chiede di ricontrollare la tabella.
- **Cambio di GM**: il nuovo GM eredita il potere di configurazione appena il gioco lo riconosce; le modifiche
  del GM precedente restano valide.
- Il roster di gilda arriva in modo asincrono: finché non è caricato, l'addon non accetta eventi che richiedono
  un rango e li rimette in coda.
- Ogni modifica della configurazione finisce nell'audit con data e autore; a season aperta l'addon chiede al GM
  una conferma esplicita (§10).

**Come è fatto (M2-5).** Tre moduli di Lua puro in `Domain/`:

- `Rules.lua`: la configurazione di §3 in sezioni (`night`, `members`, `season`, `cost`, `priority`, `session`,
  `council`, `legendary`, `bench`); le sezioni dei moduli precedenti restano loro (`Members`, `Season`, `Pricing`,
  `Priority`) e `Rules.Validate` usa i loro controlli (codici `sezione.campo`, ordinati). I valori predefiniti sono il
  preset "Patto". Le regole stanno nel registro: `CONFIG_CHANGED{rules, preset?, confirmed?}` porta **l'intera
  configurazione** validata (non una differenza), così le regole in vigore quando un evento è stato scritto sono quelle
  dell'ultimo `CONFIG_CHANGED` prima di lui (`Rules.Current`); `Rules.Diff` dà i percorsi cambiati per l'audit;
  `Rules.WithDefaults` completa le regole scritte da una versione più vecchia (una sezione o una chiave mancante, mai
  dentro una chiave presente).
- `Presets.lua`: `PATTO` (= i valori predefiniti), `ROLL_ONLY` ("Solo roll": metrica roll, costi a 0, free roll come
  fallback, nuovi arrivati a 0, leggendari a roll), `LOOT_COUNCIL` ("Loot council puro": `awardMode = council`, voto
  attivo, costi a 0, leggendari a voto), `EPGP_SIMPLE` ("EPGP semplice": i crediti sono i GP e le serate giocate l'EP,
  metrica crediti per serata, costi come Patto). Codici, mai nomi: i nomi li danno le traduzioni. `Presets.Match` dice
  se le regole sono ancora quelle di un preset.
- `Permissions.lua`: permesso → **indice** del rango più basso che lo ha (0 = GM); chi ha indice `r` ha il permesso
  se `r <= tabella[permesso]`. `config.rules` e `config.permissions` sono fissi a 0 (una tabella che li cambia non è
  valida). Preset: `season.manage` e `credits.adjust` al GM, il resto agli officer, cioè **indice 1** (scelta
  predefinita, il GM la cambia). La tabella è l'evento `PERMISSIONS_CHANGED{table, confirmed?}`, salvato completo.
  Ogni tipo di evento ha il suo permesso (`EVENT_PERMISSION`): season → `season.manage`; membri, alt, roster →
  `roster.manage`; serate, uccisioni, drop, assegnazioni, progressi, leggendari → `night.run`; `AWARD_VOIDED` e
  `CREDITS_ADJUSTED` → `credits.adjust` fuori dalla serata e `night.run` mentre una serata della season è aperta
  (le correzioni del council le scrive il ML, §3.6); configurazione e permessi → solo GM. Un tipo sconosciuto (addon
  più nuovo) chiede il permesso di scrittura più largo: chi può scrivere qualcosa può inoltrarlo, tanto non viene letto.

La fiducia è un cancello passato a `Ledger.Append` e `Ledger.Merge` (`Permissions.Gate`): un evento entra solo se
l'autore aveva il rango richiesto **quando l'ha scritto**, secondo la tabella in vigore **in quel momento**; gli eventi di
un lotto si valutano in ordine canonico, quindi un `PERMISSIONS_CHANGED` del lotto vale per gli eventi successivi dello
stesso lotto, in qualunque ordine arrivino. Il rango "al momento" viene da una **storia dei ranghi** (`RecordRank` /
`RankAt`: i cambi di rango visti nel roster con la loro ora; prima del primo cambio visto vale il primo rango visto);
l'adapter di M3-1 la tiene e la salva. Così il cambio di GM funziona da solo: il nuovo GM ha il potere dal momento in cui
il roster lo mostra GM, le modifiche del GM precedente restano valide. Esiti del cancello: `RANK_TOO_LOW`, `NOT_GM`
(configurazione da un non GM), `NOT_IN_GUILD`, `PENDING` (roster non ancora caricato: `Merge` restituisce l'evento in
`pending`, il chiamante lo rimette in coda). Un evento rifiutato non si salva e lascia un buco nella sequenza del suo
autore, quindi la sincronizzazione (M6) lo richiederà e verrà rivalutato. Un evento già presente è un doppione e non
passa di nuovo dal cancello. Senza cancello il registro accetta ogni evento valido (i test di M2-3 e M2-4).
`Permissions.RanksChanged` confronta i nomi dei ranghi prima e dopo: `RENAMED` (nulla da fare), `REORDERED`, `REMOVED`,
`ADDED` (il GM ricontrolla la tabella); `Permissions.CheckRanks` elenca i permessi che puntano a un rango che non esiste
più. La conferma esplicita a season aperta la chiedono gli scrittori (`Rules.Change`, `Permissions.Change`:
`CONFIRM_REQUIRED`) e il segnale `confirmed` resta nell'evento per l'audit; il cancello non la ricontrolla (l'evento è
comunque del GM).

**Come è fatto (M3-1).** I ranghi veri arrivano da `Adapters/GuildRanks.lua` (tutto attraverso `Core/Compat.lua`; nomi
controllati nel dump: `IsGuildLeader`, `GetGuildInfo`, `GetNumGuildMembers`, `GetGuildRosterInfo`,
`GuildControlGetNumRanks`, `GuildControlGetRankName`, `C_GuildInfo.GuildRoster` / `IsGuildOfficer` /
`CanEditOfficerNote`, eventi `GUILD_ROSTER_UPDATE`, `GUILD_RANKS_UPDATE`, `PLAYER_GUILD_UPDATE`): sono io il GM (indice
0), l'indice di un membro, nomi e numero dei ranghi, officer secondo il gioco (solo informativo: i permessi usano
sempre l'indice). L'adapter chiede il roster all'ingresso nel mondo e di nuovo ogni 15 s finché non ne ha letto uno che
contiene il giocatore; ogni raffica di eventi del roster produce una sola lettura 1 s dopo. I nomi sono sempre
`Nome-Reame` con il reame normalizzato (senza spazi, trattini, apostrofi), come gli autori del registro.
`App/PermissionService.lua` tiene la storia dei ranghi e la salva per gilda (`guilds[chiave].ranks`): ogni cambio di
rango con l'ora del server in cui è stato visto, `false` per chi non è più in un roster completo (uscito dalla gilda).
La storia salvata **non vale come "caricata"** alla sessione dopo: finché questa sessione non ha letto un roster il
cancello risponde `PENDING`. Gli eventi ricevuti (`PermissionService:Merge`) che restano `PENDING` aspettano in una coda
(senza doppioni, al massimo 2000: oltre si scartano, tanto la sincronizzazione li richiede) e sono rivalutati appena
arriva il roster: accettati o rifiutati (`PERMISSIONS_QUEUE_DRAINED` sul bus). **Scelta:** le scritture locali non vanno
in coda: ricevono `PENDING` e le finestre tengono spenti i pulsanti finché `PermissionService:IsReady()` è falso (un
pulsante premuto e "eseguito più tardi" sarebbe una sorpresa). Il potere di configurazione è di chi ha **indice 0 nel
roster** (`CanConfigure`, decisione del proprietario); quando il roster mostra un altro GM la storia lo registra (il
nuovo GM scrive dal momento in cui il gioco lo mostra, le modifiche del vecchio restano valide), `GUILD_LEADER_CHANGED`
va sul bus e i due giocatori lo leggono in chat. I nomi dei ranghi sono confrontati con quelli salvati l'ultima volta:
un riordino, un'eliminazione o un'aggiunta (non una semplice rinomina) diventa una **revisione in sospeso** per il GM
(`GUILD_RANKS_CHANGED`, con i permessi che puntano a un rango che non esiste più), detta in chat al GM subito e a ogni
accesso finché il GM non la conferma (`AcknowledgeRanks`, dalla finestra dei permessi di M7-2). Limite noto: un autore
mai visto in un roster di questo client (uscito prima che l'addon girasse) risulta `NOT_IN_GUILD`; la storia dei ranghi
non si scambia fra client (eventualmente M6).

---

## 4. Flusso di una sessione di loot

```
 ENCOUNTER_END ─► [In attesa]  (lockdown o boss in corso: l'addon aspetta)
                     │ il ML apre il corpo (LOOT_OPENED, è master looter)
                     ▼
               [Raccolta]  l'addon legge gli slot ≥ soglia, la sorgente (boss), propone categoria e costo
                     │ il ML conferma/corregge la lista ("Avvia sessione")
                     ▼
               [Annuncio]  la categoria e il costo di ogni pezzo vanno al raid (addon + messaggio /raid)
                     │ il ML apre il roll del pezzo N
                     ▼
               [Roll tier 1] popup sui client: dettagli, confronto, risposta, pulsante "Rolla"
                     │ timer (configurabile) o tutti hanno risposto
                     ▼
               [Calcolo]   vincitore calcolato (crediti + roll), segnalazioni per il council (§5)
                │   │ parità totale ─► [Reroll fra i pari] (automatico) ─► [Calcolo]
                │   │ nessun MS ─► [Roll tier 2] (automatico) ─► ...
                │   ▼
                │ [Proposta]  a chi · quanti crediti · perché (scritti dall'addon)
                │   │ Rifiuta ─► il pezzo torna in sessione
                │   │ Modifica ─► nuovo vincitore/costo + motivazione del ML ─► [Proposta]
                ▼   ▼ Conferma
               [Assegnato] crediti addebitati, evento ITEM_AWARDED con la motivazione, risultato al raid
                     │
                     ▼
               [Consegna] GiveMasterLoot(slot, vincitore) ─► CHAT_MSG_LOOT conferma la ricezione
                     ▼
               pezzo successivo … fine sessione
```

Dettagli importanti:

- **Roll**: valgono solo i roll 1-100 fatti dopo l'apertura del round, il primo per giocatore, dal personaggio nel
  raid, **con l'addon attivo**. Chi non ha l'addon è escluso (§4.1). Da M7-2d (richiesta del proprietario del
  22/11/2026) vale **solo il roll fatto con il pulsante "Rolla" del popup**, una volta per pezzo: un `/roll` scritto a mano
  non conta, nemmeno da chi ha l'addon (regola `session.buttonRollsOnly`, preset sì; "Come è fatto (M7-2d)", sotto).
- **Consegna rimandata**: se il ML preferisce rollare tutto a fine serata, la sessione resta aperta e la consegna
  avviene poi per scambio (l'addon traccia l'oggetto finché non cambia di mano).
- **Disconnessioni e /reload**: lo stato della sessione è salvato a ogni passaggio; il ML riprende da dov'era.
- **Più officer con l'addon**: solo il master looter guida la sessione; gli altri vedono in sola lettura e possono
  intervenire come council.
- **Conferma e consegna nello stesso clic**: "Conferma" addebita i crediti e chiama `GiveMasterLoot` insieme
  (il clic del ML soddisfa anche un eventuale obbligo di azione fisica del gioco). "Conferma tutto" varrebbe per le
  proposte senza segnalazioni, ma con un pezzo alla volta (M2-6) non c'è nulla da raggruppare: non è costruito (vedi
  "Come è fatto (M4-5)").
- **Fasi automatiche**: apertura del roll, timer, chiusura, reroll e passaggio al tier off-spec possono partire da
  soli (`session.autoAdvance`, preset sì); il ML può sempre mettere in pausa la sessione.

**Come è fatto (M2-6).** `Domain/SessionFSM.lua`, Lua puro. La sessione è una sola tabella di dati semplici, salvata
così com'è nelle SavedVariables: dopo un `/reload` riprende identica (`SessionFSM.Restore`). Si cambia solo con
`SessionFSM.Step(sessione, input, env)`: applica un input (`LOOT_OPENED`, `CORRECT_ITEM`, `START`, `OPEN_ROLL`,
`RESPONSE`, `ROLL`, `CLOSE_ROUND`, `ADVANCE`, `CONFIRM`, `REJECT`, `MODIFY`, `VOTE`, `CLOSE_VOTE`, `PAUSE`, `RESUME`,
`TICK`, `DELIVERED`, `END`, …), poi le fasi automatiche, e restituisce gli **effetti** da eseguire (annuncio, apertura
del popup, `GiveMasterLoot`, avviso "senza addon"): la sessione non agisce mai da sola. Un input rifiutato non cambia
nulla. Stati: `WAITING` → `COLLECTING` → `ANNOUNCING` → `ROLLING` → `COMPUTING` → `PROPOSAL` → `ENDED`; ogni pezzo ha
`PENDING` → `ROLLING` → `COMPUTING` → `PROPOSAL` → `ASSIGNED` → `DELIVERED`. Il calcolo (reroll, tier successivo,
fallback) è sempre `Priority.Evaluate`; `CONFIRM` scrive `ITEM_AWARDED` nel registro con i codici della proposta e
passa dal cancello dei permessi (§3.9). Scelte fatte dove il testo sopra non decideva (tutte modificabili):

- il dominio non legge l'orologio: ogni input porta l'ora e i timer sono scadenze assolute controllate da `TICK`;
  durata del roll nuova regola `session.rollSeconds` (preset 30 secondi, 5-600);
- **un pezzo alla volta**: il roll successivo si apre solo dopo l'assegnazione del precedente, così i suoi crediti
  sono già addebitati; la consegna invece può restare in sospeso (`ASSIGNED`) e arrivare anche dopo `END`;
- all'apertura del roll il pezzo congela **raid, addon e crediti** (i crediti della season dal registro): il risultato
  è quello contro cui il raid ha rollato e una sessione ripresa calcola lo stesso; chi attiva l'addon rientra dal pezzo
  dopo (§4.1);
- il primo round del pezzo raccoglie anche le **risposte**; la risposta si può cambiare finché il giocatore non ha
  rollato in quel round; se nessuno del tier 1 può rollare, i roll di quel round si scartano (`TIER_EMPTY`) e si apre il
  round del tier che chiede `Priority`;
- §4.1: la risposta di chi non ha l'addon (o non è nel raid) è rifiutata; il suo `/roll` resta nel round e `Priority`
  lo scarta come `NO_ADDON`, così il ML lo vede; all'avvio della sessione l'effetto `NO_ADDON` elenca chi non può
  rollare; senza `requireAddon` rollano tutti i presenti;
- con `autoAdvance` il round si chiude al timer **o** quando tutti i presenti con l'addon hanno risposto e rollato,
  il reroll e il tier successivo si aprono da soli e dopo un'assegnazione si apre il pezzo successivo; senza, il timer
  scaduto è solo segnalato e il ML chiude e avanza a mano;
- **pausa**: ferma tutte le fasi automatiche e conserva il tempo che restava (timer e finestra di `auto`); i comandi
  del ML e i roll continuano a funzionare;
- `awardMode = auto`: dopo `session.interventionSeconds` l'addon conferma da solo, ma solo una proposta "pronta"
  (vincitore, costo, nessuna segnalazione tranne `DISCARDED_ROLLS`) e mai dopo un intervento del ML; se il registro
  rifiuta l'evento torna al ML (`AUTO_FAILED`);
- `awardMode = council`: `CONFIRM` è bloccato finché il ML non chiude il voto (`CLOSE_VOTE`); vince la maggioranza
  stretta (parità o nessun voto: decide il ML con `MODIFY`); se il voto sceglie un altro, è un intervento con motivo
  `COUNCIL_VOTE`; i voti finiscono nell'evento;
- **Rifiuta** sceglie cosa succede al pezzo: `PENDING` (il ML lo riapre quando vuole; l'avanzamento automatico non lo
  riapre), `REOPEN` (roll nuovo subito), `NEXT_TIER` (salta i tier fino a quello della proposta), `BANK`,
  `DISENCHANT`; le proposte successive portano il segnale `AFTER_REJECT`;
- **Modifica**: motivo obbligatorio da una lista di codici (`WRONG_CATEGORY`, `COUNCIL_COST`, `OBVIOUS_WASTE`,
  `PASSED_TO_GAME`, `COUNCIL_VOTE`, `LEGENDARY`, `MISTAKE`, `OTHER`); un nuovo vincitore paga il costo della propria
  risposta, il costo pieno se non ha risposto (§3.6); segnali `OUT_OF_ORDER` (vincitore diverso dalla regola),
  `COST_CHANGED`, `ML_DECIDED` (la regola non aveva vincitore o costo); l'evento porta `intervention`, `mlReason`,
  `ruleWinner`, `ruleCost`;
- la correzione di categoria o costo (`CORRECT_ITEM`) vuole un motivo ed è bloccata dopo l'apertura del roll con
  `session.lockCategoryOnOpen`;
- la sessione scrive solo `ITEM_AWARDED` (destinatario `member`, `bank` o `disenchant`); `DROP_SEEN` e gli altri eventi
  della serata arrivano con gli adapter (M3, M4). "Conferma tutto" non serve: c'è una sola proposta aperta alla volta.

**Come è fatto (M4-3).** `Adapters/RollListener.lua` legge i risultati di `/roll` da `CHAT_MSG_SYSTEM` con il pattern
costruito dalla stringa globale `RANDOM_ROLL_RESULT` del client (`Compat.Roll`, mai scritto a mano: ogni lingua del
client legge i suoi messaggi; il dump delle API elenca solo funzioni ed eventi, quindi un client senza la stringa non
legge nessun roll). I nomi diventano `Nome-Reame` come nel registro. Il listener classifica e consegna, la sessione
decide: ogni roll visto mentre un round è aperto diventa un input `ROLL` della `SessionFSM` (che li tiene tutti e
`Priority` scarta quelli non validi con un codice, così il ML li vede); la classificazione immediata del listener usa gli
stessi codici e lo stesso ordine (`VALID`, `NOT_1_100`, `BAD_VALUE`, `BEFORE_OPEN`, `AFTER_CLOSE`, `NOT_PRESENT`,
`NO_ADDON`, `NOT_ELIGIBLE`, `DUPLICATE`) più il nuovo `NO_ROUND` (nessun round aperto: il roll non va alla sessione).
Scelte fatte (modificabili): i duplicati si giudicano dai roll già salvati nel round, quindi un `/reload` del ML non li
azzera; un roll con un altro intervallo non consuma il turno (come in `Priority`). **Piano B (§11 rischio 2):** un
messaggio segreto non viene mai letto né confrontato; resta in un buffer (al massimo 200) con l'ora di arrivo e si
rilegge quando il lockdown finisce (`ADDON_RESTRICTION_STATE_CHANGED`, `ENCOUNTER_END`, `PLAYER_REGEN_ENABLED` o un
controllo ogni secondo); l'ora di arrivo è l'ora del roll, quindi conta per il round in cui è stato fatto. Ciò che resta
segreto dopo il lockdown si scarta e si conta (`hidden`); un roll letto dopo la chiusura del suo round è `NO_ROUND`
(`held`), quindi il controller (M4-4) non deve chiudere un round mentre `Pending()` è maggiore di zero. Da verificare nel
gioco (spike S3): che il messaggio sia leggibile in istanza o diventi leggibile dopo il lockdown.

**Come è fatto (M4-4).** `App/SessionController.lua` collega la `SessionFSM` al gioco e **non decide nulla**: vincitore,
costo, reroll, tier successivo e fallback restano nella `SessionFSM`, nella fase automatica `settle`.
- **Apertura.** Su `ENCOUNTER_END` con successo, e solo sul client del master looter (`Compat.Loot.IsMasterLooter`), il
  controller crea la sessione in `WAITING`: season aperta, regole in vigore (`Rules.Current`), contesto di prezzo
  (dimensione del raid, difficoltà, soglia di loot). Poi tutto procede così:
  - `LOOT_COLLECTED` diventa `LOOT_OPENED`; durante un lockdown la raccolta resta in attesa e si consegna quando finisce;
  - lo stato del lockdown arriva alla sessione come `LOCKDOWN` (boss, restrizione addon, lockdown della chat);
  - `GROUP_SCANNED` e `ADDON_CHECK_CHANGED` diventano `SET_RAID`;
  - i roll arrivano da `RollListener` (`ROLL`) e le risposte da `SESSION_INPUT` (`RESPONSE`);
  - un ticker di un secondo manda `TICK`, ma non finché il buffer dei roll nascosti non è vuoto.
- **Effetti e registro.** Ogni input accettato passa da `Step`: ledger e cancello dei permessi, `Protocol.Session:Publish`
  verso il raid, evento `SESSION_CHANGED`; `DELIVER` diventa `SESSION_DELIVER` per M4-7. `CONFIRM` scrive `ITEM_AWARDED`
  con motivi e segnalazioni.
- **Salvataggio.** La sessione è la tabella `session` dei dati della gilda, cambiata sul posto, quindi un `/reload` o una
  disconnessione la ritrovano. `Resume` la riadotta, la ospita sul protocollo e riattacca il listener; una sessione di un
  addon più nuovo riparte in sola lettura.
- **Altri officer.** Gli officer con `award.confirm` vedono la vista del raid in sola lettura (`View`).
- **Boss successivo.** Alla morte del boss successivo la sessione precedente si chiude (`END`) se nessun oggetto è in corso.
  Se un oggetto è in corso, la nuova sessione viene rifiutata (`SESSION_RUNNING`).
- **Test.** `Tests/test_session_controller.lua` copre un boss con cinque oggetti, un reroll, un tier MS vuoto, un fallback
  al ML, il timer, la pausa, il lockdown, il `/reload` a metà reroll e la sola lettura.
- **Da verificare nel gioco (M4-9).**

**Come è fatto (M4-5).** La finestra del master looter è la sotto-scheda **Loot › Sessione** (`UI/Windows/MLSession.lua`,
anteprima `fdcp-loot-session.webp`). Non decide nulla: disegna la **bacheca** (`App/SessionBoard.lua`, dati semplici letti
dalla sessione o, sul client di un altro officer, dalla vista in sola lettura del protocollo) che dà
`SessionController:Board()`, e manda i clic come comandi (`SessionController:Command`). Le frasi sono tutte chiavi di
traduzione; i codici passano da `Domain/Reasons.lua`. Scelte fatte dove il testo non decideva (tutte modificabili):

- **Niente "Conferma tutto".** I dettagli di §4 e la roadmap lo prevedono "per le proposte
  senza segnalazioni", ma M2-6 ha scelto **un pezzo alla volta** (il roll successivo si apre dopo l'assegnazione del
  precedente), quindi c'è sempre una sola proposta aperta e nulla da raggruppare. Il suo scopo, non fare un clic per pezzo
  quando tutto è pulito, lo danno già `session.autoAdvance` (il pezzo dopo si apre da solo) e `awardMode = auto` (conferma
  da sola dopo la finestra di intervento). Se un giorno i pezzi si rollassero in parallelo, il pulsante si aggiunge sopra
  `Board().items` senza toccare la macchina a stati.
- **Un pulsante principale** a destra che cambia con lo stato: *Avvia la sessione* (Raccolta), *Apri il roll* (pezzo in
  attesa, quando nessun pezzo è in corso), *Chiudi il round* (round aperto), *Apri il round successivo* (reroll o tier dopo
  senza avanzamento automatico), *Conferma e assegna* (proposta con vincitore e costo; con `awardMode = council` solo a voto
  chiuso). Accanto: **Modifica** e **Rifiuta** sulla proposta, **Correggi** e **Togli** sulla lista, **Pausa/Riprendi** e
  **Chiudi sessione** in alto. Un pulsante compare solo quando la macchina a stati accetterebbe l'input (`Board().actions`);
  ogni rifiuto che passa comunque è mostrato a parole (`Reasons` gruppo `REFUSAL`).
- **Modifica** è una scheda (la base `Widgets.Dialog`) con la lista dei vincitori possibili (prima i candidati con risposta e
  crediti, poi il resto del raid presente, poi banca e disincantatore; niente `UIDropDownMenu`), il costo, e il **motivo
  obbligatorio** scelto da un elenco di codici (`WRONG_CATEGORY`, `COUNCIL_COST`, `OBVIOUS_WASTE`, `PASSED_TO_GAME`,
  `LEGENDARY`, `MISTAKE`, `OTHER`; `COUNCIL_VOTE` lo scrive solo il voto): mai testo libero, perché il registro tiene codici.
  Mentre il ML sceglie, la scheda mostra la proposta che ne risulterebbe e la **differenza dalla regola** ("fuori fila: Bryn
  era primo"; "costo: 2 invece di 1"), calcolata con la stessa `SessionFSM.Step` su una copia della sessione
  (`SessionController:PreviewModify`): la finestra non ricalcola nulla. Senza motivo, **Salva** è rifiutata con la frase
  `REASON_REQUIRED`, prima di toccare la sessione; la macchina a stati la rifiuterebbe comunque.
- **Rifiuta** apre la scelta di cosa succede al pezzo (i cinque esiti di `REJECT_THEN`, di preset "rimettilo in gioco");
  il motivo del rifiuto non è richiesto. **Correggi** (categoria o costo base, motivo obbligatorio) è disponibile finché il
  pezzo non ha una proposta e, con `session.lockCategoryOnOpen`, solo prima dell'apertura del suo roll.
- **Candidati.** Solo sul client del master looter: chi ha risposto, chi ha rollato, e finché un round raccoglie le risposte
  anche chi è presente con l'addon e non ha ancora risposto ("non ha ancora risposto"). Ordine: tier della risposta, crediti,
  roll decrescente. Ogni roll di chi non ha l'addon compare subito con la nota "l'addon non è attivo" (§4.1); gli altri roll
  scartati compaiono con il loro codice quando il round si chiude. In un reroll i non pari sono attenuati. Gli altri officer
  vedono i pezzi, il round e la proposta, non l'elenco dei candidati: le risposte non viaggiano verso di loro (§8.4).
- **Avviso "N membri non possono rollare"** (§4.1): un'etichetta nell'intestazione, dagli stessi dati di `SET_RAID`, con il
  pulsante **Avvisa in /raid** (`AddonNotice:Send("MISSING")`, solo per chi può gestire il controllo dell'addon).
- **Apertura.** Quando il ML apre il corpo (`COLLECTED`) la finestra si apre sulla scheda Loot; un `/fdcp` mentre una
  sessione è in corso apre la finestra sulla scheda Loot (§6 della specifica).
- **Dati.** `SessionController:Step` ora emette `SESSION_CHANGED` per ogni input accettato (anche un roll o una risposta,
  senza effetti), non solo per quelli con effetti: la finestra si aggiorna a ogni roll. Il timer si ridisegna ogni secondo
  solo mentre la scheda è visibile.
- **Non fatto qui:** la consegna del pezzo (`GiveMasterLoot`, scambio: M4-7), l'annuncio in `/raid` (M4-8, fatto: vedi
  sotto), il voto del
  council (M5-8); il popup del giocatore è M4-6, qui sotto.
- **Test.** `Tests/test_ui_ml_session.lua`: un boss di cinque pezzi giocato solo dai pulsanti della finestra, Modifica senza e
  con motivo, la differenza dalla regola, Rifiuta, Correggi, Pausa, i roll senza addon, l'avviso, la vista in sola lettura.
- **Da verificare nel gioco (M4-9).** La finestra in un raid vero (disposizione, leggibilità a 40 giocatori), i nomi degli
  oggetti mentre la cache li carica.

**Come è fatto (M4-6).** Il popup del giocatore (`UI/Windows/MemberLootPopup.lua`, anteprima `fdcp-roll-popup.webp`) è una
finestra a sé, non una scheda: si apre quando un round chiede qualcosa a questo giocatore e si chiude quando il round si
chiude (`SCLOSE`), la fine della sessione o l'uscita dal raid. Come la finestra del ML non decide nulla: disegna la bacheca di
`App/PopupBoard.lua` (dati semplici, letti dalla **vista** di `Net/Protocol.lua`, la stessa sul client del ML e su quello di
ogni raider) e manda la risposta con `Protocol.Session:Respond`, che spedisce solo la risposta **del mittente** (§8.4).
Scelte fatte dove il testo non decideva (tutte modificabili):

- **Una card per round aperto, impilabili.** La sessione tiene un pezzo alla volta (M2-6), quindi di norma c'è una card sola;
  la finestra impila fino a `PopupBoard.MAX_CARDS` card se la bacheca ne dà di più. Nel primo round (`cl`: raccoglie le
  risposte) la card c'è sempre; nei round successivi solo per chi rolla: il tier successivo per chi ha risposto quel tier, il
  reroll per i pari (`am`), il roll libero per tutti. Gli altri non vedono nulla: il popup "si chiude" per loro.
- **La risposta parte subito**, intera (risposta, etichetta, nota), a ogni cambiamento: la coda tiene l'ultima in attesa
  (`key = "SRESP"`), il ML ne tiene una per giocatore. L'etichetta (BiS, upgrade grande, upgrade piccolo, situazionale: §3.3)
  vale per la risposta del tier migliore (main-spec) e la sceglie da sola se manca; con off-spec o passo si toglie. La nota
  (80 byte, tagliata senza spezzare un carattere UTF-8) parte quando la casella perde la tastiera, con Invio o con **Tira**.
- **Tira = `RandomRoll(1, 100)`** (`Compat.Roll.Send`; nel dump di Forever è `RandomRoll(min, max)`, nessun valore di
  ritorno), una volta per round: poi il pulsante dice *Tirato* e la risposta si blocca (la macchina a stati rifiuta del resto
  `RESPONSE_LOCKED` dopo un roll). L'addon non scrive mai un valore: il roll lo legge dalla chat il ML (M4-3). Se il gioco
  rifiuta la chiamata, la riga di aiuto dice di scrivere `/roll 1-100`.
- **Etichetta e nota arrivano al ML fino in fondo.** M4-5 aveva lasciato il punto aperto: il protocollo le portava
  (`lb`, `n`) ma la macchina a stati le scartava. Ora `RESPONSE` le tiene per giocatore (`item.labels`, `item.notes`; la
  risposta più recente sostituisce tutto, un'etichetta o una nota non valida si scarta e la risposta conta lo stesso, un
  passo non le ha; si azzerano alla riapertura del roll) e la bacheca dei candidati le dà alla finestra del ML, che mostra
  l'etichetta accanto alla risposta (*Main-spec · BiS*) e la nota nella colonna Note, con le sequenze di escape raddoppiate.
  Il codice dell'etichetta passa da `Reasons` (nuovo gruppo `LABEL`). Il `my` di `SSTATE` porta anche etichetta e nota, così
  un `/reload` ridà la card com'era.
- **Messaggi: `rt`.** `SOPEN` e `SSTATE` portano `rt = { MS = 1, OS = 2 }`, le risposte offerte (quelle abilitate della
  configurazione) con il loro tier: serve al popup per sapere cosa mostrare e chi rolla in un round di tier, perché i costi
  per risposta (`cs`) contengono anche risposte disattivate (TMOG). Un ML più vecchio che non lo manda funziona lo stesso
  (ordine MS, OS, TMOG dai costi). Il protocollo era ancora alla versione 2 (con M5-2 passa alla 3: §5.1).
- **Crediti e posto in fila: solo se il client li conosce.** `PopupBoard.Standing` legge il registro locale
  (`CreditTable.Build`): i crediti del giocatore (o del suo main) e `1 + i membri del raid con meno crediti` (una parità la
  scioglie il roll, da qui il "~"). Finché i membri non ricevono la tabella (M6-6) la riga resta vuota sui client senza
  registro: nessun numero inventato. Il verdetto di upgrade è arrivato con M5-2 (§5.1).
- **Aspetto.** Card raggio 18, segmento Main-spec / Off-spec / Passo, chip di etichetta (`Widgets.Chip`, nuovo), barra sottile
  del timer, pulsante principale; l'**unico elemento neon** è il bagliore e l'anello della card in cima. Il tooltip è quello
  del gioco (`GameTooltip:SetItemByID` o `SetHyperlink`), con il confronto chiesto con `GameTooltip_ShowCompareItem` in
  `pcall`. Posizione e larghezza per personaggio (`CharDB.popup`), larghezza da una maniglia sul bordo destro.
- **Test.** `Tests/test_ui_popup.lua`: la bacheca (offerte, chi rolla, suggerimenti, nota tagliata, posto in fila), la card
  su un client (testi in inglese e in italiano, risposta, etichetta, nota, Tira, round successivi, reroll, roll libero,
  chiusura, timer, pausa, posizione), e sul simulatore di rete il ML che riceve risposte, etichette e note di quattro client,
  una risposta falsificata rifiutata, il `/reload` di un raider e un nuovo arrivato; più i casi nuovi in
  `test_protocol_session.lua`, `test_session_fsm.lua` e `test_ui_ml_session.lua`.
- **Da verificare nel gioco (M4-9).** Il popup in un raid (disposizione, leggibilità), il tooltip con il confronto,
  `RandomRoll` da un clic (anche in istanza, dove potrebbe essere limitato), i nomi degli oggetti mentre la cache li carica,
  il trascinamento e il ridimensionamento.

**Come è fatto (M4-7).** La consegna è `Adapters/MasterLoot.lua` (il lato del gioco) più la parte "Consegna" di
`App/SessionController.lua`; la `SessionFSM` registra solo a che punto è (nuovi input `DELIVERY` e `DELIVERED{via}`), non
chiama mai il gioco. Chiamate e messaggi passano da `Core/Compat.lua` (`Loot.Give`, `Loot.Candidates`, `Roll.ParseLoot`, nuovo
`Compat.Trade`); nel dump di Forever ci sono `GiveMasterLoot`, `GetMasterLootCandidate`, `GetTradePlayerItemLink`,
`GetTradeTargetItemLink` e gli eventi `CHAT_MSG_LOOT`, `TRADE_SHOW`, `TRADE_ACCEPT_UPDATE`, `TRADE_CLOSED`,
`UI_INFO_MESSAGE`; `ERR_TRADE_COMPLETE` è una stringa globale (non nel dump, come le altre). Scelte fatte dove il testo
non decideva (tutte modificabili):

- **Conferma = addebito + consegna nello stesso clic.** L'effetto `DELIVER` di `CONFIRM` chiama `SessionController:Deliver`.
  Con `awardMode = auto` la conferma non viene da un clic: se il gioco rifiuta la chiamata il pezzo resta nell'elenco con
  `CALL_FAILED` e il master looter lo consegna dal suo clic ("Consegna ora").
- **Il pezzo si ritrova per id, non per posizione.** Lo slot visto alla raccolta è solo un suggerimento: prima di ogni
  chiamata si rilegge la finestra del bottino aperta (alcuni client chiudono il buco di un pezzo uscito). Il candidato si cerca
  per nome completo (`Nome-Reame`) nell'elenco di `GetMasterLootCandidate`.
- **Piano A, ricevuta.** La chiamata riuscita segna la consegna `GIVEN` (metodo `MASTER`); la fine è il messaggio
  `CHAT_MSG_LOOT` del vincitore per quell'oggetto (`Roll.ParseLoot`, formati del client, quindi inglese e italiano). Un
  messaggio segreto non si legge mai (si conta e basta, `stats.hidden`): chi non vede arrivare la ricevuta dopo 20 secondi
  trova "nessun messaggio visto" e può segnare il pezzo **consegnato a mano** (`via = MANUAL`). Lo stesso messaggio vale
  anche per un pezzo consegnato a mano dal ML fuori dall'addon, o già lootato dal vincitore (un messaggio *dopo l'apertura
  della sessione* prima della conferma: consegna immediata). Limite noto: la ricevuta è per oggetto e giocatore, quindi una
  seconda copia dello stesso oggetto lootata dallo stesso giocatore chiude la consegna della prima.
- **Piano B, scambio.** Se il master loot non è disponibile (`NO_MASTER_LOOT`: non è il ML o il metodo è un altro; `NO_WINDOW`:
  finestra chiusa; `NO_SLOT`: il pezzo non c'è più; `NO_CANDIDATE`: il vincitore non è nell'elenco; `CALL_FAILED`: il gioco
  rifiuta) l'assegnazione **resta nel registro** (i crediti sono addebitati comunque, il registro non sa nulla della consegna)
  e la consegna è `PENDING` con quel codice (gruppo `DELIVERY` di `Domain/Reasons.lua`). L'addon **non avvia, non riempie e non
  accetta** mai uno scambio: guarda `TRADE_SHOW`, `TRADE_ACCEPT_UPDATE`, `TRADE_CLOSED` e `UI_INFO_MESSAGE`, legge gli
  oggetti messi nello scambio mentre la finestra è aperta (poi spariscono) e, se lo scambio è andato a buon fine (accettato da
  entrambi, o `ERR_TRADE_COMPLETE`), dà il pezzo per consegnato quando il partner è il vincitore (o quando il ML, vincitore,
  riceve il pezzo). Da chi lo ha in mano si sa solo dai messaggi di bottino ("Lo ha Corin"): uno scambio fra due altri
  giocatori non lo vede nessun client del ML, quindi lì serve **Segna come consegnato**.
- **Consegna rimandata.** Gli oggetti `ASSIGNED` di una sessione chiusa passano, alla morte del boss successivo, in una
  sessione "trasportata" (`carry`, chiusa, nei dati della gilda, solo per il suo ML): l'elenco **Da consegnare** mostra prima
  quelli e poi quelli della sessione in corso, e le ricevute e gli scambi valgono per tutte e due. Quando si riapre un corpo
  (`LOOT_COLLECTED` a sessione già avviata) i pezzi in attesa per `NO_WINDOW`, `NO_SLOT` o `NO_CANDIDATE` sono riprovati da
  soli; quelli rifiutati dal gioco aspettano il clic.
- **Finestra.** Seconda sotto-scheda **Loot › Da consegnare** (`UI/Windows/MLSession.lua`): tabella pezzo / vincitore /
  stato, **Consegna ora (master loot)** (nascosto con `GIVEN`) e **Segna come consegnato**; l'intestazione della scheda
  Sessione conta i pezzi. Il pezzo di un banco senza personaggio impostato non arriva mai alla conferma (serve un vincitore):
  `FSM.Recipient` darebbe comunque il ML. Nessuna richiesta alla rete: la consegna è solo del client del ML.
- **Test.** `Tests/test_delivery.lua` (consegna riuscita e ricevuta, scorrimento degli slot, candidato di un altro reame,
  candidato mancante, chiamata rifiutata o API assente, altro metodo di loot, corpo chiuso e riaperto, scambio riuscito,
  annullato, con un altro, in senso inverso, ricevuta nascosta, consegna rimandata nel `carry` e dopo un `/reload`, scheda
  della finestra) e il mock `Tests/mock/76_trade.lua`; casi nuovi per `Compat.Trade` in `test_compat.lua`.
- **Da verificare nel gioco (spike S2c, S2d, M4-9).** Che un addon possa chiamare `GiveMasterLoot` da un clic (e da una
  conferma automatica), come il client chiude gli slot dopo la consegna, cosa portano `TRADE_ACCEPT_UPDATE`/`TRADE_CLOSED` e
  l'ordine con il messaggio di scambio completato, il nome del partner (`UnitName("NPC")`), la leggibilità di
  `CHAT_MSG_LOOT` in istanza, la raccolta della sessione quando non c'è master loot (non c'è un corpo da leggere: finché lo
  spike non dice come, la sessione parte dal ML con master loot e il piano B riguarda solo la consegna).

**Come è fatto (M4-8).** `Domain/Announce.lua` (Lua puro: i testi, i segnaposto, la divisione in righe) e `App/Announcer.lua`
(la coda e l'invio), che ascolta `SESSION_CHANGED` del controller e riusa quello che M3-6 ha costruito per l'avviso
"addon mancante": `Notice.TAG` ("[FDCP] "), il limite di 255 byte, `Compat.Chat` e il blocco durante un incontro. Scelte fatte
dove il testo non decideva (tutte modificabili):

- **Che cosa si scrive.** Alla partenza della sessione (`ANNOUNCE_ITEMS`) una riga per pezzo con il link, la categoria e il
  costo (regola della gilda: la categoria si annuncia prima del roll, e il primo roll si apre dopo quell'effetto); una riga di
  "Correzione" se il ML corregge un pezzo dopo la partenza; alla conferma (`AWARDED`) una riga con pezzo, vincitore (senza
  reame), costo e la **frase del perché**, composta dai codici di motivo (`Reasons.Text("REASON", codice, lingua)`, gruppo
  `REASON`). Le segnalazioni (`FLAG`) sono per il ML e non vanno al raid. Un pezzo per la banca o da disincantare ha il suo
  testo fisso ("alla banca di gilda", "da disincantare"). Il costo è quello pieno (la risposta di tier più basso, main-spec nel
  preset); "gratis", "1 credito", "N crediti" o "costo deciso dal council".
- **Lingua della gilda (§8.5).** Ogni parola viene da `Locale.Text(Locale.GuildLanguage(), chiave)`, mai dalla lingua del
  client del ML: categorie (`ML_CAT_*`), unità, frasi dei motivi e testi predefiniti; i numeri seguono la lingua della gilda.
  Il registro resta neutro (codici): la frase si compone solo al momento di scrivere in chat.
- **Sezione `announce` delle regole** (`enabled`, `itemText`, `resultText`, `reason`), con gli stessi modi dell'avviso: solo il
  Guild Master la cambia, come un `CONFIG_CHANGED` con l'audit (`AddonNotice.SaveSection`, ora condivisa con
  `AddonNotice:SaveConfig`). Segnaposto: `{item}`, `{category}`, `{cost}` per l'annuncio del pezzo; `{item}`, `{winner}`,
  `{cost}`, `{category}`, `{reason}` per il risultato. Un segnaposto sconosciuto resta com'è; un testo vuoto usa quello
  predefinito. Il preset ha tutto acceso. Non c'è ancora una finestra per modificarla (come per l'avviso, M5).
- **Coda e invio.** Le righe aspettano in una coda (60 al massimo) e escono con `Flush()`: **mai durante un incontro** e solo
  quando la chat le accetta (niente lockdown né restrizioni), quattro per volta; quello che non può uscire resta in coda e
  un ticker di un secondo riprova fino a svuotarla. Fuori da un raid non si scrive niente (i popup e la finestra portano le
  stesse notizie). Una riga che il gioco rifiuta cinque volte di fila svuota la coda (`ANNOUNCE_DROPPED`). Le righe si
  dividono a 255 byte in uno spazio, mai dentro un link di oggetto, e ogni parte riparte con "[FDCP] ".
- **Il clic del ML.** L'annuncio parte dal clic su "Avvia sessione" o "Conferma"; una conferma automatica (`awardMode = auto`)
  non ha un clic dietro: se il gioco chiedesse un'azione fisica, la riga aspetterebbe in coda. Da verificare in gioco (S4).

**Come è fatto (M4-9).** Un boss intero gira offline in `Tests/test_sim_boss.lua` sul simulatore di rete (`Tests/sim/sim.lua`):
un raid da 40, di cui 39 client completi dell'addon (il master looter Guild Master, un officer, 37 raider) e un giocatore
senza addon. **Nulla è sostituito**: il registro della gilda dai dati salvati, il cancello dei permessi sui ranghi letti dal
roster, la serata aperta dal ML (che fa partire il controllo dell'addon), il protocollo, i popup cliccati, la finestra del ML
cliccata, il lettore dei roll, la consegna e gli annunci sono i moduli veri; la season di prova si apre con `Season.Open` sul
registro della gilda, perché nessuna finestra la apre ancora. Il simulatore fa ora anche da **server del raid**: un roll
(anche quello del pulsante del popup, `RandomRoll`), un messaggio di bottino, un incontro e il lockdown della chat arrivano a
tutti i client del raid. La storia: il pull e il combattimento bloccano la chat, il ML apre il corpo durante il blocco (la
raccolta aspetta), l'avviso "1 membro non può rollare" va in `/raid`; il primo pezzo con dieci main-spec, cinque off-spec e
gli altri che passano, un secondo blocco della chat a metà delle risposte (arrivano dopo), un `/roll` a mano del giocatore
senza addon (scartato, "addon non attivo"), un pari a 95 e il reroll fra i due, la conferma con il master loot e la ricevuta;
il secondo pezzo con il `/reload` di un raider e del ML a metà del round (la card torna con la risposta, la sessione torna
com'era, il corpo chiuso dal `/reload` lascia il pezzo in attesa finché il ML non lo riapre); il terzo con un solo candidato e
il round chiuso dal timer, consegnato con il **piano B** (il vincitore non è nella lista del master loot, il ML lo prende e
lo scambia); poi la fine, i popup chiusi ovunque, tre `ITEM_AWARDED` nel registro, i crediti, due righe in `/raid` per pezzo.

Il test ha trovato un **bug di integrazione**, corretto: dopo il `/reload` del master looter, `AddonCheck` riparte da zero e
richiede la presenza a tutto il raid; finché le risposte non tornano, `SessionController:SyncRaid` passava alla sessione un
raid in cui solo il ML aveva l'addon. Un pezzo aperto in quei secondi avrebbe escluso tutto il raid dal roll e la finestra
avvisava "38 membri non possono rollare". Ora un membro che `AddonCheck` sta ancora aspettando (chiesto, non ancora risposto,
online) tiene quello che la sessione sapeva; chi non aveva l'addon resta escluso. Da verificare in gioco: quanto ci mettono
39 risposte dopo il `/reload` in un raid vero. La verifica del proprietario è [`docs/checklists/M4.md`](checklists/M4.md)
(piano A e piano B; senza una season aperta la sessione non parte: la checklist dà una riga `/run` per aprirne una di prova).

**Come è fatto (M7-2d).** Il gioco non distingue un `/roll` scritto a mano da `RandomRoll` chiamato da un pulsante,
quindi il clic su "Rolla" del popup (`UI/Windows/MemberLootPopup.lua`) manda **prima** un piccolo messaggio di sessione,
l'**intento di roll** `SRINT` (pezzo, round, un nonce; **nessun valore**: la regola di fiducia di §8.4 resta) e **poi**
chiama `RandomRoll(1, 100)`. Sul client del ML `Net/Protocol.lua` passa l'intento (il giocatore è il mittente, mai un
campo; solo per il round aperto, altrimenti `STALE`) a `Adapters/RollListener.lua` con l'evento `ROLL_INTENT`. Con la
regola accesa un roll che sarebbe `VALID` conta solo se c'è un intento dello stesso giocatore per lo stesso round:

- un intento arrivato prima vale se non è più vecchio della finestra (`session.buttonRollWindow`, preset 10 secondi,
  da 2 a 60) rispetto al roll, oppure se dopo il suo arrivo c'è stato un lockdown (il roll ha aspettato nella chat);
- un roll arrivato prima (il messaggio addon è spesso più lento del messaggio di sistema) **aspetta** il suo intento fino
  alla finestra, contata **solo fuori dal lockdown** (l'intento aspetta il lockdown di chi l'ha mandato nella sua coda);
  intanto `Pending()` lo conta e il controller non fa scadere il round;
- un intento per giocatore per round: il roll lo consuma; un secondo intento (un altro nonce) si conta come doppione e
  si ignora, la ripetizione dello stesso nonce si ignora; **un intento senza roll non fa nulla**;
- un roll ancora senza intento alla fine dell'attesa va alla sessione segnato `nb`: `Priority` lo scarta con il nuovo
  codice **`NOT_FROM_BUTTON`** ("Scritto a mano: conta solo il pulsante Roll del popup") e, come un roll con un altro
  intervallo, **non consuma il turno**: un clic dopo conta ancora; un roll dopo quello valido resta `DUPLICATE`; un roll
  `nb` non chiude il round "tutti hanno rollato" e non blocca la risposta del giocatore;
- i reroll fra i pari usano il pulsante come il primo round (ogni round ha il suo numero, quindi il suo intento);
- il client del giocatore legge anche il proprio roll: scritto a mano durante un round aperto di una sessione con la
  regola, stampa l'avviso "Usa il pulsante Roll del popup del loot: i roll scritti a mano non contano" (evento
  `ROLL_TYPED`). Il comando `/roll` del gioco **non viene mai sostituito né bloccato**.

Scelte fatte (modificabili): la regola è di sessione (sezione `session`, solo il GM, pagina Sessione delle Impostazioni),
fissata nella sessione quando si apre; una sessione salvata prima di M7-2d non ha la chiave e funziona come prima; un
client con un protocollo di sessione più vecchio di 6 (il suo `HELLO` dice `pv` < 6) non sa mandare intenti, quindi i suoi
roll si giudicano come prima di M7-2d (`legacy` nel registro del listener) invece di scartarli: chi non ha aggiornato
rolla ancora e vede l'invito ad aggiornare. La regola chiede correttezza, non sicurezza: chi sa scrivere una macro può
mandare un intento a mano come fa il pulsante. Con la regola spenta tutto torna come prima. Non verificato nel gioco:
l'ordine e il ritardo fra il messaggio addon e il messaggio di sistema del roll, in istanza e dopo un boss; `RandomRoll`
da un clic; l'avviso.

### 4.1 L'addon è obbligatorio: chi non ce l'ha

Tutti i raider devono avere l'addon attivo. L'addon lo verifica da solo e aiuta GM, officer e master looter a
sollecitare chi manca.

**Come lo sa.** All'apertura della serata, a ogni ingresso nel raid (`GROUP_ROSTER_UPDATE`) e a richiesta, il
client del ML manda sul canale addon `RAID` una richiesta `HELLO?`; ogni client con l'addon risponde con versione
dell'addon e del protocollo. Chi non risponde entro qualche secondo è "senza addon". Distinguere "non installato"
da "installato ma disattivato" non è possibile (in entrambi i casi non risponde nulla): l'addon dice "addon non
attivo".

**Come è fatto (M3-5).** `Net/Protocol.lua` e `App/AddonCheck.lua`. Chi chiede è chi guida la serata aperta
(l'officer che l'ha aperta o il suo master looter): chiede a tutto il raid all'apertura della serata (o quando entra in
un raid durante la serata) e solo ai **nuovi arrivati** a ogni ingresso successivo (chi torna online conta come nuovo);
chi ha `raid.addonCheck` può chiedere di nuovo a mano. Ogni client manda anche il suo `HELLO` da solo quando entra in un
raid e dopo un login o un `/reload` dentro un raid, così chi installa l'addon e ricarica rientra senza che nessuno
chieda. Domande e risposte viaggiano su `RAID`, quindi **ogni client ha la stessa tabella**. Una risposta conta solo se
non è più vecchia dell'ultima domanda che nominava quel giocatore (una risposta di prima di un `/reload` con l'addon
disattivato non lo tiene "attivo"). "Non attivo" scatta 15 secondi dopo che la domanda è **davvero partita**: una domanda
trattenuta da un boss o dal lockdown della chat non fa scadere nessuno. "In attesa" vale per chi è offline, per chi non è
ancora stato interpellato e per chi è stato interpellato da meno di 15 secondi. La regola per M4:
`AddonCheck:Candidates()` restituisce `{[nome] = true}` per chi ha un addon compatibile (attivo o da aggiornare),
`AddonCheck:RaidInput()` il `{present, addon}` che `SessionFSM` riceve con `SET_RAID`.

**Pannello "Addon nel raid"** (visibile a chi ha `raid.addonCheck`), una riga per membro del raid:

| Stato | Significato |
|---|---|
| ✓ attivo | risponde, versione aggiornata |
| ⚠ da aggiornare | risponde con una versione più vecchia di quella del ML; se il protocollo è incompatibile non può rollare dall'addon |
| ✕ non attivo | nessuna risposta |
| … in attesa | fuori portata, offline, in caricamento: si ricontrolla da solo |

In alto un riepilogo ("37/40 con l'addon") che compare anche nella barra della sessione del ML.

**Avviso in `/raid`.** Pulsante "Avvisa in /raid": l'addon scrive in chat raid un messaggio con i nomi di chi non
ha l'addon attivo, per esempio:

> [FDCP] Aurel, Bryn, Corin: vi manca l'addon del loot (Finland Dragon Credit Points). Scaricatelo da <link> prima del
> prossimo boss, serve per rollare.

- Testo e link configurabili dal GM (con i segnaposto `{names}`, `{link}`, `{addon}`); il preset ha il link alla
  pagina di download.
- Se i nomi non stanno in un messaggio (limite 255 caratteri), l'addon li divide su più righe.
- Un pulsante analogo per "da aggiornare", con il suo testo.
- Opzione per mandare invece un **sussurro personale** a ognuno (meno rumore in raid).
- Protezione dallo spam: al massimo un avviso ogni N minuti (preset 5) per serata, e mai durante un boss (l'invio
  aspetta la fine dell'encounter).
- L'invio parte sempre da un clic di chi ha il permesso, mai da solo: il gioco può chiedere un'azione fisica per
  scrivere in chat, e un avviso automatico a ogni ingresso sarebbe fastidioso.
- Ogni avviso finisce nel log della serata (chi, quando, a chi).

**Come è fatto (M3-6).** `Domain/Notice.lua` (testo e divisione), `App/AddonNotice.lua` (invio e protezioni), `UI/AddonPanel.lua` (pannello **Roster › Addon** e chip del riepilogo nella barra del titolo). Il testo sta nella sezione `notice` delle regole (`text`, `outdatedText`, `link`, `whisper`, `minutes`; testo vuoto = quello di default nella lingua di chi preme; solo il GM la cambia, `CONFIG_CHANGED` nell'audit). Ogni riga inizia con `[FDCP] ` e ha al massimo 255 byte; i nomi sono senza reame e non vengono mai tagliati a metà. Il pulsante rifiuta con un codice se non si è in raid, senza permesso, durante un boss (`ENCOUNTER`: l'invio non aspetta, si riclicca dopo), con la chat bloccata, senza nessuno da nominare o prima che passino `minutes` minuti dall'ultimo avviso (un'attesa sola per serata, azzerata all'apertura di una serata). Il registro degli avvisi è nei dati del personaggio (ultimi 30) e sul bus (`ADDON_NOTICE_SENT`), non nel registro eventi della gilda: non cambia i crediti. Il riepilogo nella barra della sessione del ML arriva con M4 (la barra non esiste ancora); la finestra per modificare i testi con la scheda Impostazioni (M5).

**Se qualcuno resta senza addon durante una sessione, è escluso dal roll** (`session.allowNoAddon` = no nel
preset; il GM può riattivare il roll a mano con `ms`/`os` in chat per altre gilde). In pratica:

- i candidati di un pezzo sono solo i membri del raid con l'addon attivo e una versione compatibile;
- un `/roll` fatto a mano da chi non ha l'addon viene **ignorato**, e nella sessione del ML compare come "roll
  scartato: addon non attivo", così nessuno pensa che sia stato perso per errore;
- da M7-2d anche chi ha l'addon rolla **solo con il pulsante del popup**: un `/roll` scritto a mano compare come "roll
  scartato: scritto a mano" (`NOT_FROM_BUTTON`) e il suo client lo avvisa (§4, "Come è fatto (M7-2d)");
- chi ha una versione **troppo vecchia** (protocollo incompatibile) è trattato come chi non ce l'ha; con una
  versione vecchia ma compatibile rolla normalmente e vede solo l'invito ad aggiornare;
- quando si apre una sessione con qualcuno senza addon, il ML vede un avviso ("3 membri del raid non possono
  rollare") con il pulsante "Avvisa in /raid" a portata di mano;
- se il giocatore installa o attiva l'addon e fa `/reload`, risponde al controllo successivo e rientra dal **pezzo
  dopo**: un roll già aperto non si riapre per lui.

---

## 5. Rilevamento upgrade e "chi passa per fare il furbo"

### 5.1 Lato giocatore (popup del pezzo)

Per ogni pezzo in palio, il client del giocatore calcola da solo, con i propri dati:

1. **Può usarlo?** Classe, tipo di armatura e arma (tabella delle competenze per classe), `IsEquippableItem`,
   `DoesItemContainSpec`. Se non può, il popup lo propone già su "Passo" (auto-pass configurabile).
2. **Contro cosa si confronta**: slot da `equipLoc`; anelli e trinket contro il peggiore dei due; armi con la
   logica due mani / mano destra + sinistra.
3. **Quanto migliora**:
   - differenza di item level (`C_Item.GetDetailedItemLevelInfo`);
   - differenza di statistiche (`C_Item.GetItemStatDelta`) pesata con i **pesi della spec dichiarata**:
     `punteggio = Σ peso(stat) × valore`; `upgrade % = (nuovo − indossato) / indossato`;
   - pesi predefiniti per classe/spec, modificabili, importabili da stringa (formato tipo Pawn).
4. **Verdetto**: *Upgrade grande* (≥ soglia, preset 5%), *Upgrade piccolo* (> 0), *Nessun upgrade*, *Non
   confrontabile* (es. trinket con effetto d'uso). Le soglie sono configurabili.
5. **Wishlist / BiS** (facoltativa): il giocatore segna i pezzi che considera BiS; il popup lo ricorda.

Il popup mostra: icona e nome nel colore della qualità, slot, tooltip con confronto, chip "Arma · 2 crediti",
chip del verdetto ("Upgrade +7,4% · ilvl +6" in verde), i propri crediti e la posizione in fila stimata,
i pulsanti di risposta, un campo nota e la barra del timer. Il popup senza il verdetto esiste dal passo M4-6 (§4, "Come è
fatto (M4-6)"); il chip del verdetto è di M5-2 ("Come è fatto (M5-2)", sotto).

**Come è fatto (M5-1).** Il punteggio è `Domain/UpgradeScore.lua`, puro: non chiama mai il gioco. L'adapter
dell'inventario (M5-2) gli passa il pezzo, i pezzi indossati per slot (`INVSLOT_*`) e la spec dichiarata come tabelle
semplici; il risultato sono solo codici e numeri (verdetto, `usable`, codice, base `STATS` / `ILVL`, `pct`, delta di
item level, punteggi, slot confrontati, note), le parole arrivano con il chip di M5-2. I pesi stanno in un file di dati,
`Data/StatWeights.lua`, che si aggancia al punteggio come `Data/Specs.lua` al roster. Scelte fatte dove il testo non
decideva (tutte modificabili):

- **Competenze.** Tabella per le nove classi (tipi di armatura, scudi, libram / idoli / totem, tipi di arma, bacchette,
  doppia arma), modificabile dalla configurazione (`proficiency`). La doppia arma dello sciamano vale solo per
  Enhancement (263). Mantelli (sono "stoffa"), anelli, collane, trinket e oggetti tenuti in mano vanno bene a tutti; una
  sottoclasse che la tabella non conosce non viene mai rifiutata. Le restrizioni di classe e di spec del pezzo (se
  l'adapter le conosce, `DoesItemContainSpec`) vengono prima: un token per un'altra classe è *non usabile*, un token per
  la propria classe è solo *non confrontabile* (`usable` assente), così il popup non lo passa da solo.
- **Non usabile = Nessun upgrade** con `usable = false` e il codice (`ARMOR_TYPE`, `WEAPON_TYPE`, `DUAL_WIELD`,
  `CLASS_RESTRICTED`, `SPEC_RESTRICTED`): è il dato da cui M5-2 preseleziona *Passo*.
- **Coppie (anelli, trinket).** Prima lo stesso oggetto già indossato (si confronta con sé stesso), poi uno slot vuoto
  (sempre *Upgrade grande*, senza percentuale), poi il peggiore dei due (per punteggio, o per item level nel ripiego).
  Un trinket indossato con effetto d'uso non è mai "il peggiore" (lo si tiene); se lo sono entrambi, *Non confrontabile*.
  Un trinket nuovo con effetto d'uso è *Non confrontabile*; su un altro slot l'effetto si ignora con una nota.
- **Armi.** Due mani contro mano destra + sinistra: statistiche sommate, item level medio dei due. Una mano contro la
  peggiore delle due mani solo se il personaggio sta già usando due armi (un'arma nella sinistra) e la classe/spec può;
  altrimenti contro la destra. Una mano contro una due mani indossata: il pezzo da solo (nota `REPLACES_TWO_HAND`, di
  solito *Nessun upgrade*). Sinistra, scudo o oggetto in mano con una due mani indossata: *Non confrontabile*.
- **Punteggio.** `punteggio = Σ peso × valore` con i pesi del personaggio o, senza, quelli predefiniti della spec; le
  chiavi del client (`ITEM_MOD_STRENGTH_SHORT`, `RESISTANCE0_NAME`, …) diventano codici brevi (`STR`, `ARMOR`, `DPS`…);
  le statistiche senza peso si elencano (`unscored`). Se l'indossato vale 0 e il nuovo più di 0: *Upgrade grande*
  (`FROM_ZERO`).
- **Soglie.** `bigThreshold` 5%, `smallThreshold` 0 (piccolo se strettamente sopra), `ilvlBigThreshold` 5% per il
  confronto sul solo item level. Validate da `ValidateConfig`; le soglie stanno nella sezione `upgrade` delle regole (M5-2).
- **Ripiego sul solo item level (piano B di S5).** Quando `useStats` è spento (per tutti), quando le statistiche di una
  delle due parti sono sconosciute (`nil`, diverso da `{}`), quando la spec non ha pesi o quando nessuna delle due parti
  ha una statistica pesata; ogni caso lascia una nota (`STATS_OFF`, `NO_STATS`, `NO_WEIGHTS`, `NO_WEIGHTED_STATS`).
  Senza item level: *Non confrontabile* (`NO_ITEM_LEVEL`).
- **Pesi predefiniti** (default reversibile della domanda 8, §13): una riga per ogni spec di `Data/Specs.lua`, statistica
  principale = 1,0, DPS dell'arma per melee e cacciatori (non per il druido feral). Sono un'approssimazione (§5.3); i
  pesi personali e l'import facoltativo di M5-3 (sotto) sostituiscono una riga intera. Restano da verificare in gioco (S5) le
  chiavi delle statistiche di Forever.

**Come è fatto (M5-2).** Tre pezzi, ognuno con un solo compito:

- **`Adapters/Inventory.lua`** legge il gioco, sempre attraverso `Core/Compat.lua` (nomi controllati nel dump di Forever):
  i pezzi indossati per slot (`GetInventoryItemLink`; camicia e tabard non si confrontano), i dati di un oggetto
  (`C_Item.GetItemInfo` / `GetItemInfoInstant`, livello da `GetDetailedItemLevelInfo`, statistiche da `GetItemStats`,
  `IsEquippableItem`) e le spec per cui è fatto (`GetItemSpecInfo`, altrimenti `DoesItemContainSpec` su ogni spec della
  classe). Se `GetItemStats` non dà nulla da una parte, `GetItemStatDelta(indossato, nuovo)` completa l'altra
  (`nuovo − delta`, `indossato + delta`); un valore segreto si legge come "nessuna statistica". Al dominio arrivano
  tabelle semplici. Non si possono leggere dall'API, e restano fuori: la restrizione di classe di un token e l'effetto
  d'uso di un trinket (solo nel testo del tooltip): vedi i limiti, §5.3.
- **`App/UpgradeAdvisor.lua`** mette insieme regole, spec dichiarate e gioco. Le soglie sono la nuova sezione `upgrade`
  delle regole (`enabled`, `autoPass`, `useStats`, `bigThreshold`, `smallThreshold`, `ilvlBigThreshold`; letta dal
  registro come le altre, riempita coi predefiniti per le regole scritte prima di M5-2), quindi tutto il raid usa gli stessi
  numeri. Il verdetto si calcola **due volte**: coi pesi della **MS1** dichiarata (*Main-spec*) e, se c'è, della **MS2**
  (*Off-spec*); senza dichiarazione la spec che il personaggio gioca ora fa da main-spec e l'off-spec non c'è (una spec
  dichiarata di un'altra classe si ignora). Il risultato (`For(itemID)`) si tiene finché non cambiano equipaggiamento
  (`PLAYER_EQUIPMENT_CHANGED`), spec (`PLAYER_SPECIALIZATION_CHANGED`), registro o regole; un oggetto i cui dati non sono
  ancora caricati non si tiene e il popup lo richiede e si ridisegna. Senza classe nota non si dice nulla.
- **Il popup** mostra sotto il chip del costo una riga per spec, *"Main-spec · Upgrade grande +7,4% · ilvl +6"* (verde per
  grande, accento per piccolo, neutro per nessuno e non confrontabile, ambra per non usabile; la virgola decimale dalla
  lingua), con un tooltip che dice il perché (per un pezzo non usabile il codice, es. "La tua classe non può indossare
  questo tipo di armatura"), su cosa si è confrontato (statistiche o solo item level), cosa si indossa e il limite
  ("un'approssimazione"). Le parole passano da `Reasons` (nuovi gruppi `VERDICT` e `UPGRADE`) e dalle chiavi `UPG_*`.
- **Pezzo non usabile → Passo preselezionato.** Se *ogni* verdetto calcolato dice `usable = false` e le regole lo chiedono
  (`autoPass`, acceso), il popup mostra Passo selezionato con la riga di aiuto che lo dice, **senza mandare nulla**: nessuna
  risposta vale passo per le regole (§3.4), il giocatore può scegliere un'altra risposta, e un clic su Passo lo manda
  davvero. Un pezzo non confrontabile (un token) non fa mai passare da solo.
- **Rete (protocollo 3).** `SRESP` porta `vd` ed `eq` (tabella in §8.4) a ogni invio, anche per un passo: il flag
  *Upgrade ignorato* di M5-4 ne ha bisogno. `Session.ReadResponse` controlla i campi uno per uno e **scarta** quello
  danneggiato senza rifiutare la risposta (come per etichetta e nota); `eq` è solo testo `item:…`, mai un hyperlink.
  `pv` sale a 3 e `pm` resta 2: un client della 2 è capito e capisce, "versione vecchia ma compatibile" come sempre. Il
  `SESSION_INPUT` porta `verdict` ed `equipped`, la macchina a stati li tiene per giocatore (`item.verdicts`,
  `item.equipped`; la risposta più recente sostituisce, si azzerano alla riapertura; le regole non li leggono mai).
- **Lato ML.** La bacheca dei candidati dà a ogni riga `upgrade` (il verdetto della spec della risposta: l'off-spec per
  *Off-spec*, altrimenti la main-spec), `upgradeMS`, `upgradeOS` ed `equipped`; la tabella ha una colonna **Upgrade**
  (ordinabile: grandi prima) e il tooltip della riga mostra i due verdetti e i pezzi indossati. Le segnalazioni e la
  visibilità ai soli council sono di M5-4 (§5.2, "Come è fatto (M5-4)").

Scelte fatte dove il testo non decideva (tutte modificabili): il confronto usa **l'id dell'oggetto** (livello e statistiche
dell'oggetto base: il `SOPEN` non porta il link con i bonus, quindi un drop con livello diverso dal base non si vede); il
verdetto si manda **anche con un passo**; i pezzi indossati nominati sono quelli degli slot confrontati (al massimo 4);
`autoPass` è una regola di gilda, non una preferenza personale. Da verificare in gioco (S5): che `GetItemStats` e
`GetItemStatDelta` rispondano per l'equipaggiamento raid, che `GetItemSpecInfo` elenchi le spec come si presume (se elencasse
solo le spec "da loot" un pezzo valido potrebbe risultare *non usabile per la spec*: è solo una preselezione), e il
livello di un pezzo indossato con aggiornamenti.

**Come è fatto (M5-3).** Pesi personali, import e wishlist, tutto del giocatore e tutto facoltativo:

- **Dove vivono.** In `FinlandDragonCreditPointsCharDB.upgrade` (`personal`, `weights[specID]`, `wish[itemID]`): mai nel registro
  della gilda, mai nei dati condivisi, mai spediti; riletti e puliti a ogni sessione (una riga o un id danneggiato si scarta).
  Nulla è salvato finché il giocatore non importa o non segna un pezzo; i pesi predefiniti di M5-1 restano il default
  (reversibile, domanda 8 ancora aperta, [issue #2](https://github.com/Finland6738/finland-dragon-credit-points/issues/2)).
- **Import (`Domain/WeightImport.lua`, puro).** Stringa di formato tipo Pawn: `( Pawn: v1: "Nome": Strength=1, CritRating=0.85 )`,
  oppure la forma nuda `Strength=1, Agility=0.5`, oppure i codici brevi dell'addon (`STR=1, CRIT=0.85`); nomi senza distinzione
  di maiuscole, qualche sinonimo (`AttackPower`, `SpellPower`), i campi `Class`, `Spec`, `Alpha`, `Beta` si saltano. Le
  statistiche che il punteggio non conosce (castoni, gemme) non sono un errore: si elencano come ignorate; **si rifiuta** la
  stringa vuota o troppo lunga (2000 caratteri), un pezzo che non è `Stat=numero`, un numero che non è un decimale semplice
  (niente esadecimali, esponenti, `inf`, `nan`, oltre ±1000) e una stringa senza nessuna statistica nota. Il rifiuto ha un
  codice (`EMPTY`, `TOO_LONG`, `BAD_FORMAT`, `BAD_VALUE`, `NO_STATS`, gruppo `IMPORT` di `Reasons`) e il pezzo colpevole, e non
  cambia nulla. `Format` riscrive la stringa in ordine fisso (`/fdcp weights show`). Formato e nomi sono quelli pubblici; non c'è
  codice di altri addon.
- **Comandi.** `/fdcp weights [on | off | import <spec> <stringa> | show <spec> | reset <spec | all>]`, con `<spec>` id numerico
  o `ms` / `os` (le spec dichiarate). Importare sostituisce **la riga intera** di quella spec e accende i pesi personali
  (l'import è un atto esplicito del giocatore); `off` li spegne senza perderli, `reset` li toglie.
- **Nel verdetto.** `UpgradeAdvisor.For` passa al punteggio la riga personale della MS1 / MS2 quando i pesi personali sono accesi
  (`advice.personal`), il tooltip del popup lo dice, e il verdetto che va al master looter è quello calcolato con i pesi
  personali: informa il council, non cambia il vincitore. Le regole di gilda non lo vietano (scelta fatta, reversibile: una
  regola `upgrade.personalWeights` si aggiunge senza toccare il resto se il GM la vuole).
- **Wishlist (`Domain/Wishlist.lua`, puro).** `/fdcp wish [list | add <oggetto> | remove <oggetto> | clear]` con link (clic con
  Maiusc) o id, anche più d'uno; al massimo 300 pezzi. Un pezzo in lista porta nel popup il badge **Nella tua lista BiS** sopra
  le righe del verdetto, con un tooltip; il popup segue la lista mentre è aperto. È un promemoria: non manda nulla e non
  cambia nulla per gli altri. Nessuna BiS list di gilda (solo se l'issue #2 la chiede).
- **Da verificare in gioco.** Come sta la riga del badge nel popup in un raid vero, che il link incollato con Maiusc-clic nella
  riga di comando arrivi com'è previsto, e che i nomi delle statistiche delle stringhe Pawn vere corrispondano.

**Come è fatto (M7-2b).** L'etichetta di una risposta main-spec (BiS, upgrade grande, upgrade piccolo, situazionale: §3.3) la sceglieva
il giocatore a mano; ora la sceglie, a seconda di una regola del Guild Master, l'addon con i dati che ha già:

- **La regola `responses.labelMode`** (nuova sezione `responses` delle regole, `Domain/Labels.lua`, puro): `auto` (l'addon imposta
  l'etichetta e il giocatore non può cambiarla), `suggest` (**il predefinito**: l'addon la compila prima della risposta e il giocatore
  può cambiarla o toglierla) e `manual` (la sceglie il giocatore, come prima di M7-2b). La valida `Rules.Validate`
  (`responses.labelMode`), `Rules.WithDefaults` la riempie con `suggest` per le regole scritte prima, e si modifica dalla pagina
  **Priorità** della finestra Impostazioni (M7-2), solo dal Guild Master e con la stessa conferma a season aperta. È congelata sulla
  sessione all'apertura (`session.rules.responses`) come le altre sezioni: una modifica vale dalla sessione dopo.
- **Cosa suggerisce l'addon** (`Labels.Suggest`): il pezzo è nella lista best in slot del giocatore (M5-3) → **BiS**; altrimenti il
  verdetto **main-spec** (MS1, M5-2) è *grande* → **Upgrade grande**, *piccolo* → **Upgrade piccolo**; nessun upgrade, non
  confrontabile, non usabile o nessun verdetto → **nessuna etichetta**. *Situazionale* non si suggerisce mai: è un giudizio del
  giocatore. Il verdetto è quello che il popup già mostra (con i pesi personali, se accesi).
- **Il popup** (`App/PopupBoard.lua`, `UI/Windows/MemberLootPopup.lua`). La carta dà `labelMode`, `suggestion`, `label`,
  `labelOrigin` e `labelHint`. In `suggest`, prima di una risposta il chip suggerito è già selezionato (non si manda nulla: una
  proposta non è una risposta) e parte con la risposta Main-spec; il giocatore può sceglierne un'altra o togliere la stessa, e
  **se la toglie l'addon non la rimette** (`cleared` nella bozza); tornando da Off-spec a Main-spec senza averla toccata, la
  proposta torna. In `auto` i chip sono bloccati (`labelsOn = false`) e l'etichetta è sempre quella dell'addon, ricalcolata a ogni
  invio (`PB.Settle`); la risposta resta del giocatore. Una riga piccola sotto i chip dice chi decide (*«L'addon imposta questa
  etichetta…»* / *«Etichetta suggerita dall'addon…»*). Con off-spec, passo o altro tier l'etichetta si toglie, come prima.
- **Chi l'ha scelta (`lo`).** `AUTO` = quella dell'addon (anche se il giocatore ha cliccato la stessa), `CHANGED` = l'addon ne
  suggeriva una e il giocatore ne ha scelta un'altra, `MANUAL` = non c'era un suggerimento (o la modalità è `manual`). Senza
  etichetta non c'è origine. Il gruppo `LABEL_ORIGIN` di `Domain/Reasons.lua` dà le parole (*«Impostata dall'addon»*, *«Suggerita
  dall'addon, cambiata dal giocatore»*, *«Scelta dal giocatore»*).
- **Rete (protocollo 5).** `SOPEN` e `SSTATE` portano `lm`, `SRESP` e il `my` di `SSTATE` portano `lo` (tabella in §8.4). Sono campi
  **facoltativi**: `pv` sale a 5 e `pm` resta 2, quindi un client del 2–4 continua a seguire la sessione e a essere capito. Un ML
  vecchio non manda `lm` e il popup lascia l'etichetta al giocatore (come prima); un client vecchio non manda `lo` e la tabella del
  ML non mostra nessuna origine. Un `lm` o un `lo` che non è uno dei valori noti si scarta senza rifiutare il messaggio. La
  macchina a stati tiene `item.labelOrigins[giocatore]` accanto a `item.labels` (stesso ciclo di vita: la risposta più recente
  sostituisce, si azzera alla riapertura, sopravvive a `/reload`).
- **Lato ML.** La colonna **Risposta** dice *«Main-spec · Upgrade grande (auto)»* o *«… Situazionale (cambiata)»*; un'etichetta
  scelta dal giocatore o di un client vecchio non ha sigla; il tooltip della riga dice l'origine a parole. Il candidato della
  bacheca ha `labelOrigin`. L'origine **informa** e non cambia mai la proposta, come l'etichetta (§3.3).

Scelte fatte dove il testo non decideva (tutte modificabili): `suggest` è il predefinito (lo ha chiesto il proprietario); la regola
sta nella pagina **Priorità** (con le risposte ammesse) e non in una pagina sua; il verdetto che decide è solo quello della
main-spec (§6); `auto` non è imposto dal ML (un client manomesso potrebbe mandare un'altra etichetta: l'etichetta è solo
un'informazione, §3.3). **Da verificare in gioco:** la riga sotto i chip nel popup vero, i chip bloccati, la colonna più larga
nella finestra del ML.

### 5.2 Lato master looter / council

Ogni risposta arriva al ML con: risposta, etichetta dichiarata, verdetto calcolato, `upgrade %`, item level e link
dei pezzi indossati. La tabella dei candidati mostra crediti, roll, risposta, delta e due segnalazioni:

| Segnalazione | Quando |
|---|---|
| **Upgrade ignorato** | Un giocatore con l'addon passa (o non risponde) su un pezzo che per lui è un *Upgrade grande*. È il caso "passa per tenersi i crediti bassi in attesa del BiS". |
| **Possibile spreco** | Il primo in fila ha un upgrade piccolo, un altro candidato ha un upgrade grande (rapporto configurabile). È il caso "spreco palese". |

Le segnalazioni **non cambiano mai il vincitore da sole**: aprono l'azione del council (§3.6). Il regolamento dice
che i casi evidenti "si dicono prima del roll": per questo il ML vede le segnalazioni *Upgrade ignorato* appena
arrivano le risposte, prima di chiudere il round.

**Come è fatto (M5-4).** Le due segnalazioni sono `Domain/Flags.lua`, puro: riceve risposte, verdetti, chi può rollare e
la fila, e restituisce codici (`UPGRADE_IGNORED`, `POSSIBLE_WASTE`) con i giocatori che nominano, mai frasi.

- **Solo la MS1 (§6).** Si legge solo il verdetto `m` dell'`SRESP` (pesi della MS1), mai `o`. *Grande* si ricontrolla con le
  soglie della gilda (sezione `upgrade`: `bigThreshold`, o `ilvlBigThreshold` per un confronto sul solo item level): un client
  che dice BIG con una percentuale sotto soglia non fa scattare nulla; un BIG senza percentuale (slot vuoto, indossato che vale
  0) resta grande. Un pezzo non usabile (`u = false`) e un verdetto danneggiato non contano mai.
- **Upgrade ignorato.** Un giocatore che può rollare il pezzo (presente e, con `requireAddon`, con l'addon: §4.1) che **passa**,
  o che non ha risposto ma di cui si conosce un verdetto, su un *Upgrade grande* della MS1. Oggi un verdetto arriva solo con una
  risposta, quindi chi non risponde mai non è segnalabile: il caso "non risponde" scatta solo se il client ha già mandato un
  verdetto (resta pronto per un client che lo mandi prima). Rispondere *Off-spec* o *Transmog* non è un passo e non lo fa
  scattare (scelta fatta, reversibile).
- **Possibile spreco.** La fila sono le risposte del tier a costo pieno (MS nel preset). Il primo in fila ha un upgrade
  *piccolo* **o nessuno** (scelta fatta: chi non ci guadagna nulla è lo spreco più evidente) e un altro candidato della stessa
  fila ha un *Upgrade grande* almeno `council.wasteRatio` volte maggiore (preset 2; se il primo è a 0 o sotto basta il grande).
  Si nomina chi ci guadagna di più. Prima della proposta la fila è quella dei crediti congelati e del primo roll valido (poi il
  nome); scritta la proposta, il primo è il vincitore della regola (`item.rule.winner`): se il pezzo è andato al tier
  off-spec, alla banca, al disenchant o al ML non c'è spreco da dire. Un primo *non confrontabile* non fa scattare nulla.
- **Nella sessione.** `SessionFSM.Flags(s, i)` le calcola dal pezzo; la bacheca le mostra **appena arrivano le risposte**, prima
  di chiudere il round (§5.2), e le tiene con la proposta. Alla proposta i codici si aggiungono a `proposal.flags` (quindi
  arrivano nell'`ITEM_AWARDED` e nell'`SPROP`) e i dettagli restano sul pezzo (`item.flagged`); un rifiuto che rimette il pezzo
  in attesa li dimentica. **Non cambiano mai il vincitore, il costo o la fila**: non sono `INFO_FLAGS`, quindi un'assegnazione
  `auto` aspetta il ML (scelta fatta, reversibile: basta aggiungerle a `FSM.INFO_FLAGS`). Intervenire è un `MODIFY` con il
  motivo (`OBVIOUS_WASTE`, `PASSED_TO_GAME`), e la segnalazione resta nell'audit. La sessione congela anche le sezioni `upgrade`
  e `council` delle regole; una sessione salvata prima usa i preset.
- **Regole.** Nella sezione `council`: `flags` (acceso), `wasteRatio` (2, fra 1 e 100), `verdicts` = `council` (preset) |
  `officers` | `ml`: chi vede verdetti e segnalazioni oltre al ML, che li vede sempre. Le regole scritte prima ricevono i
  preset (`Rules.WithDefaults`).
- **Visibilità.** Il ML vede tutto. Su un altro client la finestra in sola lettura mostra candidati, colonna Upgrade e
  segnalazioni solo se `Flags.MaySee` lo permette (`SessionController:SeesVerdicts`): `council` = chi ha `council.member` (che da
  ora apre la finestra in sola lettura anche senza `award.confirm`), `officers` = chi ha `award.confirm`, `ml` = nessuno. La
  presenza nel raid richiesta da `council.requirePresent` è implicita: la vista di una sessione arriva solo ai membri del raid.
  Sulla vista non viaggiano crediti né roll, quindi lì lo spreco si dice solo dopo la proposta. Gli altri vedono i soli codici
  della proposta, senza nomi. **Limite dichiarato:** l'`SRESP` viaggia sul canale `RAID` (M5-2), quindi la visibilità è della
  finestra, non dei dati: un client modificato potrebbe leggerli.
- **Parole.** Gruppo `FLAG` di `Reasons` (`RC_FLAG_UPGRADE_IGNORED`, `RC_FLAG_POSSIBLE_WASTE`) per i codici, e le frasi con nomi e
  verdetti `ML_FLAG_IGNORED_PASS`, `ML_FLAG_IGNORED_SILENT`, `ML_FLAG_WASTE`, `ML_FLAG_SHORT_*` (colonna Note), inglese e italiano.
- **Da verificare in gioco:** come stanno le righe delle segnalazioni nella striscia della finestra in un raid vero (lunghezza,
  a capo), e la finestra in sola lettura di un membro del council che non è officer. Nient'altro è nuovo per il client.

### 5.3 Limiti da dichiarare al raid

- I pesi sono un'approssimazione: proc, effetti d'uso, bonus di set e tenuta non entrano nel punteggio.
- Chi non ha l'addon non rolla (§4.1), quindi ogni candidato manda sempre i propri dati di confronto.
- Se Forever applica bonus "contestuali" all'equipaggiamento raid (vedi proposta di design), le statistiche lette
  dal tooltip possono non coincidere con quelle reali in raid: da verificare in M0.
- Il verdetto calcolato è visibile solo al council (configurabile), per non trasformarlo in una discussione in chat. Dal
  M5-2 il giocatore lo vede anche nel proprio popup (decisione del proprietario: i giocatori vedono se un pezzo è un
  upgrade); la visibilità agli altri nella tabella dei candidati resta quella del ML e dei council.
- Il confronto parte dall'**id** dell'oggetto: il livello e le statistiche sono quelli dell'oggetto base, non di una
  variante con bonus (il `SOPEN` non porta il link); la classe richiesta da un token e l'effetto d'uso di un trinket non
  si leggono dall'API (un token per un'altra classe è *non confrontabile*, non *non usabile*; un trinket con effetto
  d'uso indossato può risultare "il peggiore").

---

## 6. Roster, rotazione, panchina e cambi

**Un solo roster per gilda e per season**, a rotazione: una sola fila di crediti, condivisa da tutti i main del
pool. Più gruppi raid paralleli con crediti separati sono fuori scope per la 1.0 (il modello dati non li esclude:
basterebbe una chiave "roster" sotto la season).

Lo stesso roster gioca raid da **10, 20 e 40** dello stesso pacchetto: la dimensione la decide l'istanza della
serata, quindi il numero di posti (e di panchine) cambia da serata a serata. La tabella crediti è sempre una,
anche fra **Normal e Veteran**: la difficoltà si registra nella serata (per lo storico e il log) ma non separa i
crediti.

- **Pool della season**: main dichiarati come nel canale 📋 Roster: **MS1** (obbligatoria), **MS2**, **OS**,
  ruolo, classe, fazione, note di disponibilità. La dichiarazione vale per tutta la season e si cambia solo al
  cambio di season (l'addon la blocca, salvo correzione di un officer). Chi gioca su entrambe le fazioni ha **due
  main**, uno per fazione, con crediti separati. Alt collegati al main, senza crediti. Stato: attivo, prova,
  inattivo. Import facoltativo dalla nota di gilda. Il collegamento main/alt lo gestisce l'addon da solo (lo
  dichiara il giocatore, lo approva un officer con `roster.manage`): nessuna dipendenza da altri addon.
- **La spec del popup viene dalla dichiarazione**, non dal gioco. Il popup calcola il confronto due volte:
  - con i pesi della **MS1** → pulsante "Main-spec" (tier 1, costo pieno);
  - con i pesi della **MS2** → pulsante "Off-spec" (tier 2, 0 crediti, si apre solo se nessuno rolla
    main-spec).

  Per il loot contano solo due spec: **MS1 = MS, MS2 = OS**. La terza voce del canale Roster ("OS", la spec che
  ti piacerebbe giocare) resta un'informazione del roster e non dà diritto al roll.

  Le segnalazioni del council (§5.2) guardano **solo la MS1**: "Upgrade ignorato" scatta quando qualcuno passa
  su un upgrade grande per la sua main-spec, non per la MS2.
- **Come è fatto (M2-4).** Alt collegati con `MEMBER_LINKED_ALT{alt, main, faction?}`, validi per la season come la dichiarazione; un main non è mai un alt, main e alt hanno la stessa fazione (`FACTION_MISMATCH`), quindi chi gioca su due fazioni ha due main con crediti separati. Dopo una fusione di registri contano il primo `MEMBER_JOINED` e il primo collegamento (ordine canonico) e un membro vince su un collegamento. Fazione = il token del client (`Horde` / `Alliance`); il nome della fazione sul sito (`Nebulah` / `Nebulaa`) lo mette l'esportazione (M6-4).
- **Come è fatto (M3-2).** `Domain/Roster.lua` (puro) legge il pool da `Domain/Members.lua` e ci aggiunge la **dichiarazione**, scritta nello stesso `MEMBER_JOINED` (`Members.Join` ha solo guadagnato `decl`): `class` (le nove classi del sito, token `classFile`), `role` (`TANK` / `HEALER` / `DAMAGER`, il ruolo della MS1), `ms1` (specID, **obbligatoria**: `MS1_REQUIRED`), `ms2`, `os`, `status` (`ACTIVE` / `TRIAL` / `INACTIVE`), `avail` (giorni `MON`..`SUN`), `note` (testo del giocatore, al massimo 80 caratteri: è un dato, non una frase dell'addon) e `twin`. Un membro scritto da `Members.Join` senza dichiarazione resta valido e risulta "non dichiarato". La dichiarazione **non cambia in season**: un secondo `Roster.Join` risponde `ALREADY_JOINED` e l'unico modo è `ROSTER_CHANGED{member, set?, clear?, reason?}` di un officer (`roster.manage`, cancello di §3.9, anche nelle fusioni); `Roster.Change` scrive solo ciò che cambia, non azzera mai la MS1 e ricontrolla l'intera dichiarazione. `Roster.SpecInfo` è l'aggancio alla tabella fissa `specID → classe, ruolo` di `Data/Specs.lua` (M3-3b): con la tabella classe e ruolo si ricavano dalla MS1 e ogni spec deve essere della classe; senza, vanno dichiarati. Le dichiarazioni valgono **tutte nella stessa riga di crediti** del main; il pool lo leggono `Roster.State/Get/List/Counts/SitePlayers` (ordine canonico, quindi stesso risultato in qualunque ordine di fusione; `SitePlayers` dà classe, spec, ruolo, fazione e `Raider` / `Trial` per `roster.json`; il **rango di gilda** dell'esportazione non si salva: lo legge l'adapter dei ranghi al momento).
  - **Chi scrive che cosa.** Il registro accetta `MEMBER_JOINED`, `MEMBER_LINKED_ALT` e `ROSTER_CHANGED` solo da `roster.manage`, quindi un raider non può scrivere né la propria dichiarazione né il collegamento di un alt. Il giocatore **chiede** (`Roster.RequestJoin`, `Roster.RequestAlt`: dati semplici in una tabella di richieste fuori dal registro, che il servizio salverà e il trasporto di M6 porterà agli officer; `Roster.Receive` per quelle arrivate dalla rete) e l'officer **approva** (`Roster.Approve` scrive l'evento attraverso il cancello: un raider che prova ad approvare viene rifiutato e la richiesta resta in attesa) o **rifiuta** (`Roster.Reject`). Una nuova richiesta dello stesso giocatore sostituisce la sua, quella di un altro per lo stesso personaggio è `REQUEST_PENDING`; al massimo 500 in attesa (`REQUEST_LIMIT`); `Roster.Prune` toglie le vecchie.
  - **Un main per fazione.** L'addon non può sapere quali personaggi sono la stessa persona: chi gioca su due fazioni dichiara l'altro main come `twin` (deve essere nel pool, di fazione diversa, con la fazione nota a entrambi, e libero: `TWIN_UNKNOWN`, `TWIN_FACTION`, `FACTION_REQUIRED`, `TWIN_TAKEN`, `TWIN_SELF`). I crediti restano separati; se due main rivendicano lo stesso gemello vale chi è entrato per primo. L'alt non ha mai crediti (`Roster.CreditHolder` lo manda al suo main; un alt non entra come main e un main non diventa alt).
  - **Stati.** `Roster.SetStatus` (`ROSTER_CHANGED`): un inattivo tiene i crediti ma non è contato (`Roster.Counts`) né esportato; `TRIAL` è "Trial" sul sito.
  - **Import dalla nota di gilda (facoltativo).** `Roster.ParseNote(nota, specs, {class})` legge le spec nominate, nell'ordine, come MS1 / MS2 / OS, più una parola di classe, `tank` / `healer` / `dps`, `trial` / `prova`, `inactive` / `inattivo`; un nome valido per due classi (Holy) si risolve con la classe, altrimenti finisce in `ambiguous`. È solo un **suggerimento**: scrive l'officer, dopo averlo letto, con `Roster.Join`.
  - **Scelte fatte dove il testo non decideva (tutte modificabili):** classi limitate alle nove del sito; la fazione si decide all'ingresso e `ROSTER_CHANGED` non la corregge (una fazione sbagliata si sistema in un passo successivo); la nota di disponibilità è testo libero del giocatore, i giorni sono codici; MS2 e OS non possono ripetere un'altra spec della stessa dichiarazione.
- **Come è fatto (M3-3).** `Domain/Nights.lua` (puro) legge dal registro le **serate**, la **formazione** e le **presenze per boss**; `Adapters/Group.lua` legge il raid (`GetRaidRosterInfo` tramite `Compat.Group`, nomi come nel registro) e `ENCOUNTER_END`; `App/NightController.lua` li collega al registro e ai permessi. Nessuno stato a parte: la serata vive negli eventi, quindi un `/reload` la riprende.
  - **Eventi.** `NIGHT_OPENED{date, instanceID, size, difficulty, faction?, ml?}` (`date` = il giorno del calendario del reame, `AAAA-MM-GG`, come lo mostra il sito; `instanceID` deve essere un'istanza del pacchetto della season, **solo i raid ufficiali contano**: `NOT_IN_PACK`; `size` è quella del pacchetto, 10, 20 o 40: `SIZE`; `difficulty` `normal` o `veteran`, registrata per lo storico, la tabella crediti è una sola; `faction` del giocatore che apre, così i main dell'altra fazione non risultano assenti; `ml` se il master looter non è chi apre), `NIGHT_CLOSED{night}`, `ENCOUNTER_KILLED{encounterID, difficulty, time, date, night?, instanceID, size}` e il nuovo **`LINEUP_CHANGED{night, boss?, raid?, bench?, absent?}`** (permesso `night.run`, come gli altri della serata). Una serata aperta per season alla volta (`NIGHT_ALREADY_OPEN`); due istanze nella stessa sera sono due serate, una dopo l'altra.
  - **Formazione.** Tre stati: in raid (`RAID`, nel gruppo e gioca), panchina (`BENCH`, deciso dal ML, non gioca) e assente (`ABSENT`, ciò che resta). Un `LINEUP_CHANGED` contiene **solo i membri che sono cambiati**, tutti in un evento (un raid che si forma costa un evento, non quaranta), e porta l'ora (quella dell'evento) e il **boss di riferimento**: l'ultimo boss ucciso nella serata prima del cambio (nessuno prima della prima uccisione). Solo i main del pool entrano nella formazione (`NOT_MEMBER`); un alt nel raid conta per il suo main.
  - **Il gruppo guida la formazione.** A ogni lettura del gruppo (un secondo dopo una raffica di `GROUP_ROSTER_UPDATE`) e subito prima di scrivere una uccisione, chi è nel gruppo diventa `RAID` e chi se ne è andato `ABSENT`. Un membro in panchina resta in panchina finché non è nel gruppo e, se è nel gruppo, finché non rientra (o il ML lo toglie con `Unbench`). Se il client nasconde un nome dentro l'istanza (spike S7) la lettura **aggiunge soltanto**, non toglie nessuno. Gli sconosciuti (non nel pool) non cambiano nulla.
  - **Presenza per boss = lo stato al momento dell'uccisione.** Per ogni `ENCOUNTER_KILLED` della serata si ripetono i `LINEUP_CHANGED` che lo precedono in ordine canonico: i membri `RAID` sono presenti, quelli `BENCH` in panchina, e gli assenti sono il resto del pool **di quel momento** (già entrati, non inattivi, della fazione della serata). Chi muore o si disconnette ma resta nel raid è presente; chi entra dopo il pull ed è nel raid alla morte del boss è presente. Per membro e season `Nights.Attendance` dà serate giocate (in raid in un momento qualsiasi della serata), panchine (in panchina e mai in raid), boss presenti e boss possibili; `Nights.Played` è la tabella `nights` di `Members.LateJoinCredits` (la base `minNights` dei nuovi arrivati, §3.5). Il risultato non dipende dall'ordine con cui gli eventi arrivano (verificato mescolando).
  - **Uccisioni.** Su `ENCOUNTER_END` con successo, dentro l'istanza della serata, il controller legge il gruppo, scrive la formazione e poi `ENCOUNTER_KILLED` (con `night`, `difficulty` = il `difficultyID` del client, `size` = `groupSize`, `time` e `date`). Un boss si registra **una volta per serata**: se due officer scrivono la stessa uccisione conta la prima (`Nights.Kills`), quindi la fusione è idempotente. Fuori da una serata, o in un'altra istanza, il controller della serata non scrive nulla: lo fa `App/ProgressController.lua` (M3-3b, §7.1); `Nights.Kill` accetta una uccisione senza serata, e `Nights.KillsByEncounter` dà per ogni boss tutte le uccisioni, dentro o fuori da una serata, in ordine canonico.
  - **Chi scrive.** Solo il client dell'officer che ha aperto la serata (o del ML indicato in `ml`) registra formazione e uccisioni; gli altri officer non duplicano. Aprire, chiudere e cambiare la formazione richiedono `night.run`; le presenze si leggono solo con `view.attendance` (`NightController:Attendance`, officer nel preset), e nessuna esportazione pubblica le contiene.
  - **Scelte fatte dove il testo non decideva (tutte modificabili):** la presenza è quella **al momento dell'uccisione** (non al pull); la difficoltà del client diventa `normal` / `veteran` dal nome che il client dà (anche "veterano") e altrimenti da una tabella (`Nights.DIFFICULTY_IDS`: 14 → normal, 15 → veteran) che è una **ipotesi** finché lo spike non dà gli id veri di Forever; l'officer può sempre indicare la difficoltà a mano; il ledger salva il `LINEUP_CHANGED` come differenza e non l'elenco completo a ogni cambio; la serata si apre anche prima di entrare nell'istanza, scegliendo istanza e difficoltà.
- **Come è fatto (M3-4).** `Domain/Rotation.lua` (puro) propone la panchina, `Adapters/Calendar.lua` legge il calendario tramite `Compat.Calendar`, `App/NightController.lua` (`ProposeBench`, `ApplyBench`) li collega. La proposta **non scrive nulla**: il ML decide e scrive la panchina con un solo `LINEUP_CHANGED`.
- **Raccolta del bottino (M4-2).** `Adapters/LootSource.lua` legge la finestra del cadavere come master looter (`LOOT_OPENED`, tramite `Compat.Loot`): gli slot a partire dalla soglia del gruppo, i link, gli id delle creature fonte come boss del cadavere e l'ultimo `ENCOUNTER_ENDED` riuscito come incontro; `Preview` propone categoria e costo base del classificatore perché il ML li confermi o li corregga, `ToInput` produce l'input `LOOT_OPENED` della `SessionFSM` (che blocca la categoria quando il tiro si apre). `Adapters/ItemCache.lua`: un `GetItemInfo` senza risposta chiede l'oggetto e attende `ITEM_DATA_LOAD_RESULT`, con timeout di 10 s; i campi istantanei (classe, sottoclasse, posizione) bastano a classificare nel frattempo.
  - **Chi è in lizza.** I main del pool che giocano (attivi o in prova) della fazione della serata, meno chi ha rifiutato sul calendario, meno chi ha dichiarato disponibili altri giorni della settimana (`avail` del roster; chi non ha dichiarato giorni è disponibile sempre) e meno chi il ML esclude a mano. Chi non c'è non viene messo in panchina e non conta come panchina.
  - **Chi va in panchina.** Il surplus sopra la taglia del raid (10, 20, 40: la `size` della serata). L'ordine: i volontari, chi ha risposto "forse" sul calendario, chi ha **meno panchine nella season**, chi ha **giocato più serate**, il nome (così ogni client propone lo stesso). Una panchina è una serata passata in panchina senza mai giocare, e la serata che si sta pianificando non conta, quindi richiedere la proposta dopo averla scritta dà lo stesso risultato. Con meno candidati che posti nessuno va in panchina e `short` dice quanti posti restano vuoti.
  - **Minimi di ruolo.** Un tank o un healer si salta se metterlo in panchina lascerebbe il raid sotto `bench.minTanks` / `bench.minHealers` (default 2 e 4, limitati a quanti ne esistono tra i candidati; chi non ha un ruolo dichiarato conta come DPS). Se i posti non si riempiono senza rompere un minimo, il minimo cede con una segnalazione (`ROLE_TANK`, `ROLE_HEALER`) e il ML la vede; `keep` (chi deve giocare) non viene mai proposto (`TOO_MANY_KEPT` se non basta). Equità: in una stagione simulata di 24 serate, 14 giocatori per 10 posti, le panchine differiscono al massimo di una dentro ogni ruolo e i minimi reggono ogni sera.
  - **Effetto sui crediti.** `bench.creditEffect`: `none` nel preset (la rotazione non penalizza: chi gioca meno ha già meno crediti), `bonus` (i crediti di chi è stato in panchina **scendono** di `creditAmount` per panchina, mai sotto 0: chi ha meno crediti vince il roll, quindi il bonus è una precedenza, non un pezzo regalato) o `malus` (salgono). `Rotation.CreditEffect` dà il cambio per membro e `Rotation.Credits` i crediti del registro con il cambio sommato; la sessione di loot li userà quando i crediti vengono dalla tabella (M4).
  - **Calendario.** `Adapters/Calendar.lua`: gli eventi di tipo raid del giorno del reame (della gilda, di un giocatore o di una community, quelli della gilda per primi), con `eventID`, e le iscrizioni di un evento come `yes` / `maybe` / `no` (disponibile, confermato, iscritto = sì; in attesa, tentativo = forse; rifiutato, fuori = no; invitato e non iscritto non rispondono e restano candidati). L'addon **legge soltanto**: non crea, non modifica e non risponde a nessun evento. `NIGHT_OPENED` porta un `eventID` facoltativo (un numero, mai il titolo: il registro non salva frasi) e `NightController:Open` collega la serata all'evento raid di oggi, se c'è. Il calendario si carica una volta all'ingresso nel gioco (`OpenCalendar`, come fa l'interfaccia predefinita).
  - **Scelte fatte dove il testo non decideva (tutte modificabili):** il "forse" va in panchina prima della rotazione (chi non ha confermato) ma conta come panchina; i minimi 2 tank e 4 healer valgono per ogni taglia (le gilde li regolano in `bench`); le panchine sono conteggi semplici, senza correggere per chi è entrato a stagione iniziata; con più eventi raid nello stesso giorno si collega il primo, quello della gilda; i codici di stato e di tipo del calendario sono quelli del client originale **[verify S8b]**.
- **Pianificazione della serata**: dall'evento di calendario (se esiste) o creata a mano. L'addon propone chi
  mettere in panchina con criteri configurabili: meno panchine nella season, vincoli di ruolo (minimo tank e
  healer), preferenze dichiarate. Il ML decide.
- **Durante la serata**: l'addon legge il gruppo (`GetRaidRosterInfo`) e registra ogni cambio con l'ora e il boss
  di riferimento, quindi la presenza è per boss, non solo per serata.
- **Effetto sui crediti**: nessuno nel preset (la rotazione non si paga sul loot). Per altre gilde: bonus o malus
  per panchina configurabile.
- **Assenze (regola del proprietario del 22/11/2026, M7-5b).** Un membro del roster della season riceve **+1
  credito** (vince chi ne ha meno, quindi è una penalità) per una serata ufficiale in cui:
  - **non si è iscritto** al raid nel calendario del gioco (nessuna risposta, oppure "no"), e non ha giocato;
  - **si è iscritto ma non è venuto** ("sì" o "forse", e non ha giocato);
  - **si è messo in panchina da solo**, di sua iniziativa.

  **Nessuna penalità** per chi era nel raid (in un momento qualsiasi della serata) e per chi è stato **messo in
  panchina dagli officer**: la rotazione non penalizza mai.
- **Come è fatto (M7-5b).**
  - **Chi ha messo in panchina.** `LINEUP_CHANGED` ha un campo facoltativo `self`: i membri di `bench` che si sono
    messi in panchina da soli; gli altri di `bench` li ha messi un officer. `Nights.Lineup` restituisce anche l'origine
    (`SELF` / `OFFICER`) di chi è in panchina; un officer che rimette in panchina chi si era messo da solo rende la
    panchina sua (e niente penalità), e viceversa.
  - **Mettersi in panchina.** Il giocatore preme "Mettimi in panchina" nella scheda Serata: sul client di chi guida la
    serata è scritto subito, altrove parte un messaggio `NBENCH` (senza campi) sul canale di gilda e il client di chi
    guida la serata lo scrive come panchina volontaria. Chi chiede è il mittente che dice il client, mai un campo del
    messaggio: si può mettere in panchina solo se stessi (o il proprio main, da un alt).
  - **Il calcolo.** `Domain/Absence.lua` (puro), `Absence.Propose`: per ogni membro del pool **al momento
    dell'apertura** della serata (non inattivo, della fazione della serata) che non ha giocato. Chi è in panchina alla
    fine: `SELF_BENCH` se si è messo da solo, niente se l'ha messo un officer. Gli altri: `NO_SHOW` se le iscrizioni
    dicono "sì" o "forse" (anche con un alt), `NOT_SIGNED_UP` altrimenti; `ABSENT` quando le iscrizioni non si
    conoscono (nessun evento raid nel calendario, o calendario non caricato): +1 comunque. Chi è entrato nel pool
    dopo l'apertura non è contato.
  - **La regola.** Nuova sezione `penalties` delle regole: `absence` (crediti per serata saltata, preset 1, 0 =
    spenta, al massimo 100) e `autoApply` (preset **spento**: serve la conferma di un officer). Solo Patto ha la
    penalità; gli altri preset hanno `absence = 0`. Le regole scritte prima ricevono i valori predefiniti.
  - **La conferma.** Alla chiusura il controller della serata tiene le iscrizioni del calendario per quella serata;
    la scheda Serata mostra all'officer "Penalità di assenza proposte" (chi e perché) e il pulsante **Conferma le
    penalità**. Con `autoApply` acceso la chiusura le scrive da sola. Ogni penalità è un
    `CREDITS_ADJUSTED{member, delta, reason = ABSENCE, night, cause}`: passa dal cancello dei permessi, finisce nel
    log e nell'audit e si annulla come ogni correzione (`AWARD_VOIDED`, che rimette i crediti di prima). Il permesso è
    `night.run` (chi guida le serate) anche dopo la chiusura, perché l'evento nomina la serata; una correzione a mano
    fuori serata resta di `credits.adjust`. Un membro già penalizzato per quella serata non viene più proposto, anche
    se la sua penalità è stata annullata (l'officer l'ha tolta apposta).
  - **Scelte fatte dove il testo non decideva (tutte modificabili):** "forse" vale come iscritto; il "no" vale come
    non iscritto; la panchina conta com'è alla **fine** della serata; chi gioca anche un solo boss è presente; senza
    calendario si penalizza comunque l'assente (`ABSENT`); la conferma è per tutta la lista in un clic.
- **Statistiche**: serate giocate, panchine, boss presenti, pezzi vinti, crediti, per membro e per season.
- **Attenzione al tono**: il canale Roster promette "non è un registro di presenze: nessuno conta le serate di
  nessuno". Le presenze servono all'addon solo per ruotare la panchina in modo equo, per la base dei nuovi
  arrivati e (dal 22/11/2026, per scelta del proprietario) per la penalità di assenza; per questo nel preset sono **visibili solo agli officer** e non compaiono in nessuna esportazione
  pubblica.

---

## 7. Storico, log e audit

| Vista | Contenuto |
|---|---|
| **Serate** | Lista settimanale: data, istanza, boss, lineup, panchina, pezzi caduti e assegnati, crediti spesi |
| **Membro** | Pezzi vinti, andamento dei crediti, presenze, panchine, interventi del council che lo riguardano |
| **Oggetto** | Chi lo ha già, quante volte è caduto, a chi è andato |
| **Log del loot** | Tutto ciò che è caduto (anche non assegnato), da quale boss, a chi, per quale risposta, a che costo |
| **Audit** | Interventi del council con motivazione, correzioni manuali, annullamenti, modifiche di configurazione |

**Esportazione**: tabella dei crediti in Markdown pronta per Discord (il "post qui accanto"), CSV, JSON; finestra
di copia con il testo già selezionato. **Importazione**: configurazione (per condividere le regole con altre
gilde) e backup completo del registro.

**Come è fatto (M6-7).** `Domain/Backup.lua` (puro) e `App/BackupService.lua`; la sotto-scheda **Storico › Backup**
(`UI/Windows/Backup.lua`); vedi [ADR 0007](adr/0007-backup-and-season-compaction.md). Tre stringhe, una riga ciascuna,
`!FDCP:<TIPO>:1:` + Base64 di CBOR (deflate quando conviene), senza limite di lunghezza (non viaggiano come messaggi
addon: si copiano fuori dal gioco e si incollano); spazi e a capo si ignorano. **`CFG`**: le regole in vigore senza ciò
che è solo della gilda (l'elenco dei nomi del council e il nome della fazione sul sito), le esporta chiunque (le regole
sono già visibili in sola lettura); le importa **solo il GM** (`config.rules`), con anteprima delle impostazioni che
cambiano e conferma esplicita, ed è un `CONFIG_CHANGED` nell'audit; chi importa tiene i propri valori di quelle due
voci. **`BAK`**: tutti gli eventi del registro in ordine canonico e le lapidi delle compattazioni, per gli officer
(`view.attendance`: contiene le presenze). **Ripristino** (`season.manage`, conferma esplicita): è un **merge** attraverso
il cancello dei permessi (come la sincronizzazione: un autore mai visto è garantito da chi ripristina), quindi aggiunge
solo ciò che manca, non toglie e non sovrascrive niente; ripristinato in un registro vuoto dà lo stesso registro; ogni
ripristino è un evento di gilda `LEDGER_RESTORED{kind, events, added, season?}` e compare nell'audit di ogni season.
**`ARC`**: tutti gli eventi di una season, da generare prima della compattazione (il servizio la rifiuta,
`ARCHIVE_FIRST`, se l'archivio non è stato generato nella sessione); la compattazione chiede poi **due conferme separate**
ed è un evento `LEDGER_COMPACTED` nell'audit della sua season (§8.3). `/fdcp debug` stima la dimensione del registro nei
SavedVariables (eventi, KB, lapidi e season compattate, i quattro tipi più pesanti). Scelte fatte dove il testo non
decideva (tutte reversibili): si compattano solo le formazioni (`DROP_SEEN`, `ROSTER_CHANGED` e il resto restano: il
registro del loot e il roster delle season passate non cambiano); la compattazione vale per la gilda intera, perché un
registro che una parte degli officer compatta e un'altra no non converge (la decisione è del GM, con l'archivio in mano
prima di togliere qualunque cosa); nel gioco non si annulla, l'archivio è la via per tornare ai dettagli; non si
esportano i permessi per rango (dipendono dai ranghi della singola gilda). Non verificato in gioco: `C_EncodingUtil` su un
registro intero (tempo e memoria di una season lunga), l'incolla di una stringa lunga nella casella, la dimensione dei
SavedVariables dopo una season lunga.

**Come è fatto (M6-1).** Le viste sono `Domain/History.lua` (pura, calcolata dal registro come i crediti, niente è memorizzato a parte) e tre finestre che la disegnano: la scheda **Storico** (`UI/Windows/History.lua`, sotto-schede Serate · Log · Audit · Esporta; *Log* e *Audit* da M6-2, *Esporta* da M6-3), `UI/Windows/Member.lua` e `UI/Windows/Item.lua`. Scelte: (1) una serata appartiene alla **settimana** (da lunedì a domenica) della sua data, indicata dal lunedì; le serate sono dalla più recente; (2) un'assegnazione appartiene alla serata come in `Domain/CreditTable.lua` (la `night` del payload, altrimenti la serata aperta in quel momento), e i crediti spesi della serata sono quelli delle assegnazioni valide a un membro; (3) un'assegnazione **annullata resta visibile** e segnata, ma non sposta crediti né conta come proprietà dell'oggetto; (4) la **formazione, la panchina e le presenze sono solo per gli ufficiali** (`view.attendance`): le funzioni li restituiscono solo con `attendance = true`, che le finestre passano solo a chi ha il permesso, quindi per un membro i campi non esistono; le assegnazioni e i crediti restano pubblici come nella tabella dei crediti; (5) la finestra **Membro** mostra gli oggetti, la curva dei crediti (inizio, ogni assegnazione e correzione, termina sul numero del registro), gli interventi del council che lo riguardano (con le frasi dell'audit) e, per gli ufficiali, le presenze; (6) la finestra **Oggetto** conta caduti, assegnati e visti (`DROP_SEEN`) e dice chi lo ha, in tutte le season. L'Esporta arriva con M6-3.

**Come è fatto (M6-2).** `History.Log(L, season)` elenca tutto ciò che è caduto in una season: le assegnazioni (le stesse righe della scheda Serate, con il boss da cui è caduto l'oggetto, la risposta e il costo; una annullata resta, segnata) e i `DROP_SEEN` che nessuno ha ricevuto (`kind = "SEEN"`, destinatario «non assegnato»). `History.Audit(L, season)` rilegge `Council.Audit` (modifiche, correzioni di categoria/costo, voti, annullamenti, rettifiche, ciascuno con il suo codice di motivazione) e vi aggiunge le **modifiche di configurazione**: ogni `CONFIG_CHANGED` con autore, data, preset e l'elenco delle impostazioni cambiate rispetto alle regole precedenti (`Rules.Diff`, dai valori predefiniti la prima volta) e ogni `PERMISSIONS_CHANGED`; sono eventi di gilda, quindi compaiono nell'audit di ogni season. Entrambe sono ordinate dal più vecchio, con filtri puri (`FilterLog`, `FilterAudit`). Le finestre (`UI/Windows/Log.lua`, `Audit.lua`) disegnano una tabella con filtro (tutti · assegnati · non assegnati · annullati; tutto · consiglio · annullamenti · crediti · impostazioni) e ricerca di testo (oggetto, membro, boss; le parole della riga). Log e audit sono pubblici come i crediti. Non verificato in gioco: l'aspetto delle schede.

**Come è fatto (M6-3).** `Domain/Export.lua` (pura) parte da `CreditTable.Build` e ne tiene solo ciò che la scheda Crediti mostra a tutti: posto in fila, nome senza reame, classe, ruolo, totale e crediti spesi per serata, dei main in gioco **della fazione della gilda**; formazione, panchina e presenze non sono nei dati, quindi nessuna esportazione può portarli. Tre forme, tutte deterministiche (stesso registro, stessi byte): **Discord** (titolo in grassetto con la season e la data dell'ultima serata, poi una tabella a larghezza fissa in un blocco di codice, perché Discord non disegna le tabelle Markdown; sopra 1900 caratteri si divide in messaggi, ognuno con la riga delle colonne e «(parte i/n)»), **CSV** (una riga per membro e una colonna per serata; separatore `;` e virgola decimale quando la lingua della gilda scrive la virgola, `,` e punto altrimenti) e **JSON** (la forma per le macchine: date `AAAA-MM-GG`, punto decimale, chiavi in ordine fisso, classi e ruoli come codici; non dipende dalla lingua). Numeri e date di Discord e CSV seguono la lingua della gilda (`NUMBER_DECIMAL`, `NUMBER_GROUP`, `DATE_LONG` del locale, §8.5); il dominio non contiene testo, le etichette gli arrivano dalla finestra. `UI/Windows/Export.lua` è la sotto-scheda *Esporta*: selettore del formato, una casella di copia a sola lettura con **Seleziona tutto** (un addon non scrive negli appunti: il testo si seleziona e si copia con Ctrl+C) e **Parte successiva**; richiede `export.public` (officer nel preset), senza il permesso la scheda lo dice e una chiamata forzata risponde `RANK_TOO_LOW`. I file d'oro dei test sono in `Tests/golden/`. Non verificato in gioco: la casella di copia (EditBox a più righe in uno ScrollFrame, `HighlightText`), la selezione e il Ctrl+C nel client vero, l'allineamento del font a larghezza fissa su Discord e l'aspetto della scheda.

### 7.1 Esportazione per il sito della community

La pagina WoW Forever del sito ([nebula-community.github.io/giochi/wow-forever/#loot](https://nebula-community.github.io/giochi/wow-forever/#loot))
legge tre file di `content/games/wow-forever/`: `roster.json` (scheda Roster), `loot.json` (scheda Loot: il sito
**calcola da solo i totali** dalle assegnazioni) e `progress.json` (scheda Progress: la prima uccisione di ogni boss per
ciascuna delle due gilde, Nebulah in Orda e Nebulaa in Alleanza). L'addon li produce **pronti da mettere nel sito
senza ritocchi**, nel formato attuale; la specifica completa (file esatti, campi, fazioni, che cosa registrare) è
[`docs/specs/site-export.md`](specs/site-export.md) (passo M1-6b).

In breve:

| File | Dall'addon |
|---|---|
| `roster.json` | i main del pool della propria fazione: nome senza reame, classe in minuscolo inglese, spec MS1 in inglese, ruolo, fazione, `Raider` / `Trial` |
| `loot.json` | una season per voce, la più recente in cima; una `raids[]` per serata ufficiale (`GG/MM`, istanza in inglese, `uccisi/totale`); le assegnazioni valide con `cost` 0, 1 o 2 |
| `progress.json` | per ogni boss della tabella fissa delle istanze, la data `AAAA-MM-GG` della prima uccisione della propria fazione (dagli eventi `ENCOUNTER_KILLED` e `PROGRESS_SET`, M3-3b), mai una data più recente di quella già presente |

Lo studio del sito ha corretto un punto di questa analisi: il controllo del sito (`npm run validate`) accetta solo
costi 0, 1 e 2, quindi **niente righe a costo negativo**. L'esportazione è lo stato attuale del registro: le
assegnazioni annullate spariscono, quelle corrette hanno il costo corretto, e i totali del sito coincidono con quelli
dell'addon. I crediti iniziali dei nuovi arrivati diventano righe sintetiche "Crediti iniziali" (costo 2 e 1) finché il
sito non ha un campo `start`; gli oggetti alla banca di gilda non si esportano. Le estensioni `start` / `kind` restano
dietro un'opzione spenta ([issue #3](https://github.com/Finland6738/finland-dragon-credit-points/issues/3)).

**Prime uccisioni (M3-3b).** Le tabelle fisse `Data/Instances.lua` (i raid del pacchetto: `instanceID`, slug del sito,
nome inglese, dimensione, boss nell'ordine del sito con `encounterID` e nome inglese, più gli id dell'Encounter Journal
solo per mostrare i nomi nella lingua del client) e `Data/Specs.lua` (`specID` → classe, nome inglese, ruolo; si
aggancia a `Roster.SpecInfo`) sono dati, non testo. `Domain/Progress.lua` (puro) calcola la prima uccisione per boss e
per **chiave di fazione del sito**:

- la chiave della gilda viene dalla nuova sezione delle regole `site.factionName` (la scrive il GM con le altre regole,
  `CONFIG_CHANGED`); vuota vuol dire il default della fazione del client, `Nebulah` per l'Orda e `Nebulaa` per
  l'Alleanza; una chiave è di 1-32 caratteri fra lettere, cifre, spazio, `_` e `-`;
- `ENCOUNTER_KILLED` registrati (dentro o fuori da una serata) contano solo per la chiave della gilda;
  `PROGRESS_SET{encounterID, faction, date}` o `PROGRESS_SET{encounterID, faction, clear = true}` è il valore inserito a
  mano per una chiave qualsiasi (una prima uccisione precedente all'addon, o la data dell'altra gilda letta sul sito):
  è un evento **di gilda** (la season non serve: un recupero può precedere ogni season), richiede `progress.edit`
  (officer nel preset) e finisce nell'audit; per un boss e una chiave vale **l'ultimo** `PROGRESS_SET` in ordine
  canonico, così una correzione sostituisce il valore precedente (anche con una data più recente: si corregge un
  errore di battitura) e `clear` lo toglie;
- la prima uccisione = la data più vecchia fra il valore a mano e, per la propria chiave, le uccisioni registrate:
  un'uccisione successiva non sposta mai la data in avanti, e una correzione a mano non può superare un'uccisione
  registrata dall'addon (a parità di giorno vale l'uccisione registrata);
- `Progress.Build` dà per ogni istanza della tabella i boss nell'ordine del sito, la data e la fonte (`KILL` / `SET`)
  per chiave e i conteggi `uccisi/totale` per chiave (quello che leggeranno la scheda Progress, M3-8b, e
  l'esportazione, M6-4).

`App/ProgressController.lua` scrive `ENCOUNTER_KILLED` **fuori da una serata ufficiale** su `ENCOUNTER_END` con
successo quando: il giocatore è in un raid della tabella, nessuna serata è aperta in quell'istanza (altrimenti scrive la
serata), il gioco dice che il gruppo è un gruppo di gilda (`InGuildParty` tramite Compat), una season è aperta (l'evento
le appartiene), il giocatore ha `night.run` e il registro non ha ancora un'uccisione di quel boss. Basta la prima: le
uccisioni di farm non riempiono il registro, e due officer nello stesso raid scrivono al più una uccisione ciascuno (la
data più vecchia vince comunque). Fuori da una season non si registra nulla in automatico: si usa `PROGRESS_SET`. I nomi
dei boss e delle istanze si mostrano nella lingua del client con `EJ_GetEncounterInfo` / `EJ_GetInstanceInfo` quando
la voce del diario è proprio quell'incontro o quella mappa, altrimenti quelli inglesi della tabella.

Due modi di esportare: la **finestra di copia** (Storico › Esporta: file completo o frammento, già selezionato,
perché un addon non scrive file né usa la rete) e, consigliato, lo script **`tools/site_export.py`** che legge le
SavedVariables dopo la serata e **unisce** i tre oggetti ai file del sito, conservando l'altra fazione, le season
precedenti all'addon, le copertine e le istanze "in arrivo".

**Come è fatto (M6-4).** `Domain/SiteExport.lua` (pura) costruisce i tre file e li dà come testo JSON, con un codificatore a ordine di chiavi fisso (stesso registro, stessi byte): `roster.json` dai main in gioco della fazione della gilda (`Roster.List` + `Specs.Site`: classe in minuscolo, nome inglese della spec MS1, parola del sito per il ruolo, `Raider` / `Trial`), `loot.json` con **tutte** le season del registro dalla più recente (il roster di una season ha ogni main del pool, anche uscito dopo; una voce di `raids[]` per serata **chiusa**, in ordine di data e poi di apertura, `id` `s<etichetta>-r<n>`, `GG/MM`, nome inglese dell'istanza, `uccisi/totale` dai boss della tabella fissa) e `progress.json` con `Progress.Build` per la sola chiave della gilda (`null` per i boss senza uccisione; la data dell'altra gilda non esce mai). Le assegnazioni sono lo **stato attuale**: una annullata non c'è, una corretta ha il costo corretto, off-spec ha costo 0 e il suffisso ` (off-spec)`; sono fuori, e contate come avvisi con un codice, le assegnazioni a banca / disincanto / master looter (`AWARD_NOT_MEMBER`), a chi non è nel roster esportato (`AWARD_OUTSIDE_ROSTER`), fuori da una serata (`AWARD_NO_NIGHT`) o in una serata ancora aperta (`AWARD_OPEN_NIGHT`, `NIGHT_OPEN`), le correzioni manuali dei crediti (`ADJUSTMENT_NOT_SHOWN`: una riga negativa o frazionaria il sito la rifiuta) e i membri senza specializzazione (`MEMBER_NOT_SHOWN`). Il costo è scritto 0, 1 o 2: un 3 diventa un 2 e un 1, una frazione si arrotonda e dà `COST_ROUNDED`. I crediti iniziali sono righe sintetiche da 2 e da 1 con il testo nella lingua della gilda, nella prima serata il cui orario di chiusura non precede l'ingresso del membro. L'opzione nascosta della issue #3 è la chiave `extended` della sezione `site` delle regole (spenta, in nessuna finestra, `Progress.ValidateConfig`): accesa scrive `start` sulle righe del roster al posto delle righe sintetiche e `kind` (`award` / `adjust`, correzioni comprese) sulle righe.

`App/SiteExportService.lua` dà al dominio ciò che sa solo il gioco (il giorno del reame, il nome dell'oggetto nella lingua del client con `Compat.Item.Info`, le etichette, la chiave del sito) e salva in `guilds[<reame>/<gilda>].siteExport` `{ updated, season, faction, extended, files = { roster, loot, progress }, warnings }` a ogni `NIGHT_CLOSED` e dal pulsante **Salva per lo script** (senza `export.public` non salva nulla). I file sono **testo JSON** e non tabelle Lua, perché una tabella non può contenere il `null` di `progress.json` né distinguere `[]` da `{}`. La sotto-scheda *Esporta* ha la quarta voce **Sito**: scelta del file e della forma (file completo o frammento: il roster dei giocatori, la season corrente da mettere in cima a `seasons`, le righe dei boss con la propria chiave), l'avviso del §6.1 e la riga di ciò che il sito non può mostrare.

`tools/site_export.py` (Python 3, nessuna dipendenza) legge le SavedVariables con un piccolo lettore di tabelle Lua, sceglie la gilda e **unisce** ai file di `content/games/wow-forever/` del sito (§5): roster = i giocatori delle altre fazioni più quelli esportati; loot = per ogni season dell'esportazione, quella del sito con lo stesso nome viene unita (roster e serate della propria fazione sostituiti, quelli degli altri conservati; una serata del sito conta come della gilda quando ogni assegnazione è di un giocatore del suo roster; un `id` già preso dall'altra fazione prende il suffisso `-<fazione>`; le serate si ordinano per giorno e mese), una season nuova si inserisce dopo la più recente che la precede, quelle assenti dall'esportazione restano; progress = la sola chiave della gilda, mai una data più recente di quella già presente e mai un `null` al posto di una data, copertine, `locked`, istanze «in arrivo» e altre chiavi intatte, con le istanze e i boss nuovi inseriti prima delle istanze «in arrivo». Un file d'esempio del sito (`example: true`, segnaposto come `[[AAAA-MM-GG]]`, che nel sito conterebbero come uccisioni) è sostituito e il marcatore tolto. Prima di scrivere applica le regole di `scripts/validate.mjs` (classi, ruoli, giocatore nel roster della season, costo 0-2) più date e fazioni di `game.json`: se una fallisce non scrive nulla (esito 1). Opzioni: `--dry-run` (differenze), `--only`, `--account`, `--guild`, `--saved`, `--csv-dir` (i fogli `roster` e `awards` del percorso Google Sheets del sito). Non usa git. Test: `Tests/test_site_export.lua` (file d'oro `Tests/golden/site_*.json`, regole di validate sugli stessi dati, totali uguali a quelli dell'addon) e `Tests/test_site_export.py` (le stesse prime esportazioni unite a una copia di un sito con le due fazioni, una season precedente, copertine e un'istanza bloccata). Non verificato in gioco: la forma *Sito* nel client vero (la seconda riga, l'avviso, la selezione e il Ctrl+C, il pulsante), i nomi degli oggetti nella lingua del client e l'intera catena su una serata reale (dati salvati dal gioco, script, `npm run validate`, la pagina del sito).

---

## 8. Architettura

### 8.1 Strati

```
UI (Material)      Windows: App, MemberLootPopup, MLSession, Credits, Roster, Nights, Log, Council, Settings
   │               Widgets: Theme, Button, Card, Chip, DataTable, NavRail, Dialog, Snackbar, Progress, Switch
   ▼
App services       SessionController, NightController, RosterService, SyncService
   │
   ├──► Domain (Lua puro, testabile offline)
   │      Rules · Pricing · Classifier · Priority · UpgradeScore · Ledger · Season · Roster · Rotation · SessionFSM
   │
   └──► Adapters (unica porta verso il gioco, tutto via Compat)
          LootSource · MasterLoot · RollListener · Group · Inventory · ItemCache · Calendar · GuildRanks
   │
   ▼
Core / Net         Init · Compat · Bus · Config (AceDB) · Log · Locale · Codec (C_EncodingUtil) · Transport (coda + lockdown) · Protocol
```

Regola: **Domain non chiama mai il gioco**. Riceve dati, restituisce decisioni. È lì che stanno le regole del
regolamento, ed è lì che i test offline (stesso impianto `lupa` di Accord) proteggono la gilda da regressioni.

### 8.2 Struttura del repository proposta

```
FinlandDragonCreditPoints/
  FinlandDragonCreditPoints.toc            ## Interface: 16001
  FinlandDragonCreditPoints_Camelot.toc
  embeds.xml
  Libs/ (Ace3: AceAddon, AceDB, AceDBOptions, AceEvent, AceTimer, AceComm, AceLocale, AceConfig; LibDBIcon, LibDataBroker, ChatThrottleLib)
  Locale/ itIT.lua enUS.lua
  Core/ Init Compat Bus Config Log
  Domain/ Rules Pricing Classifier Priority UpgradeScore Ledger Season Members Roster Rotation SessionFSM Presets Permissions
  Adapters/ LootSource MasterLoot RollListener Group Inventory ItemCache Calendar GuildRanks
  Net/ Codec Transport Protocol Sync
  UI/ Theme Widgets/* Windows/*
  Media/ logo.tga minimap.tga fonts/ icons/ (atlas Material Symbols) shapes/ (9-slice arrotondati, ombre)
Tests/ (lupa + client finto + simulatore di rete, come Accord)
docs/ specs/ adr/ wiki/
tools/ check_docs.py, build/release
```

### 8.3 Dati e registro

- `FinlandDragonCreditPointsDB` (account): profili di configurazione; per ogni gilda le season, il registro, gli snapshot.
- `FinlandDragonCreditPointsCharDB` (personaggio): posizione finestre, spec dichiarata, wishlist, pesi personali.
- **Registro (ledger)**: lista di eventi immutabili `{id, ts, author, season, type, payload}`. Tipi principali:
  `SEASON_OPENED`, `MEMBER_JOINED`, `MEMBER_LINKED_ALT`, `NIGHT_OPENED/CLOSED`, `LINEUP_CHANGED`, `ROSTER_CHANGED`,
  `ENCOUNTER_KILLED`, `DROP_SEEN`, `ITEM_AWARDED{cost, response, reason?}`, `AWARD_VOIDED{ref, reason}`,
  `CREDITS_ADJUSTED{delta, reason}`, `LEGENDARY_PROJECT_*`, `BANK_ITEM_SOLD{ref, copper}` (M5-7), `CONFIG_CHANGED`.
  I crediti sono la somma degli eventi della season; uno snapshot periodico evita di ricalcolare tutto.
- **Come è fatto (M2-3).** `Domain/Ledger.lua`, Lua puro. Ogni evento è `{id, author, seq, ts, season, type, v, payload}`:
  `id` = `autore:seq`, con `seq` = 1, 2, 3… per autore, quindi due officer non collidono mai e unire due registri è
  un'unione di insiemi (lo stesso evento due volte non cambia nulla; un evento diverso con lo stesso id è un
  conflitto: resta quello già salvato e il conflitto viene segnalato). `v` è la versione dello schema del payload: un
  payload vecchio si aggiorna in lettura (`Ledger.UPGRADES`, l'evento salvato non cambia mai), un tipo sconosciuto o
  una versione più nuova si conservano e si inoltrano agli altri officer ma non entrano nei conti. Ordine canonico:
  ora, autore, sequenza. Crediti di un membro nella season = `initialCredits` del **primo** `MEMBER_JOINED` (in ordine
  canonico) + i costi degli `ITEM_AWARDED` a lui + i `CREDITS_ADJUSTED{member, delta, reason}`, tolti quelli annullati;
  arrotondati a 2 decimali; banca e disenchant non muovono crediti. `AWARD_VOIDED{ref, reason}` annulla un
  `ITEM_AWARDED` o un `CREDITS_ADJUSTED` (un annullamento non si annulla: si riscrive l'evento); due annullamenti dello
  stesso evento contano una volta, e un annullamento arrivato prima del suo evento lo annulla comunque. Le motivazioni
  sono codici (`WRONG_WINNER`), mai frasi. Gli **snapshot** coprono esattamente gli eventi fino ai "fin dove sono
  arrivato" per autore (il più alto `seq` senza buchi), quindi gli eventi arrivati dopo, anche se più vecchi, stanno
  sempre nella coda: snapshot + coda = registro completo. Per la sincronizzazione (M6) il registro dà gli stessi segni
  (`Heads`), gli eventi che mancano a chi ha certi segni (`Since`) e i buchi (`Gaps`). La prima uccisione per
  boss (da `ENCOUNTER_KILLED{encounterID, date}` e `PROGRESS_SET{encounterID, faction, date | clear}`, date
  `AAAA-MM-GG` scritte dall'adapter) la calcola `Domain/Progress.lua` (M3-3b, §7.1), per `progress.json`.
- **Compattazione di fine season (M6-7).** Vedi [ADR 0007](adr/0007-backup-and-season-compaction.md).
  `LEDGER_COMPACTED{types, removed, ms, nights}` di una season **chiusa** (permesso `season.manage`, il GM di base) toglie
  gli eventi della season dei tipi compattabili (`Ledger.COMPACTABLE`: oggi solo `LINEUP_CHANGED`, il grosso di una
  season lunga) da **ogni** registro che lo riceve, quello di chi compatta e, con la sincronizzazione, quelli degli altri
  officer. Il payload conserva le **presenze** di ogni serata (`ms` i membri ordinati; per serata `n` = id della serata,
  `p` / `b` gli indici di chi ha giocato / è stato in panchina, `bo` / `po` coppie indice, boss presenti / possibili):
  `Nights.Attendance` e `Nights.Lineup` le leggono al posto delle formazioni, quindi rotazione, bonus/malus di panchina,
  nuovi arrivati e viste dello Storico danno gli stessi numeri; nessun evento che sposta crediti o entra nell'audit viene
  mai tolto. Un evento tolto lascia una **lapide** (`L.gone[autore]` = intervalli `{f, l, season}`): il suo `seq` conta
  ancora nei "fin dove sono arrivato", un merge lo rifiuta (`compacted` nel resoconto) e una nuova scrittura di quel tipo
  nella season risponde `SEASON_COMPACTED`. `Ledger.Seen` (eventi + lapidi) cresce soltanto e sostituisce `Count` come
  `k` della tabella dei crediti in sola lettura (M6-6), così una compattazione non fa sembrare "più vecchio" un officer.
- **Versioni dello schema**: migrazioni esplicite a ogni cambio (come ADR 0011 di Accord). I dati di ogni gilda stanno sotto la chiave `<reame>/<gilda>` (`db.global.guilds`), così gilde diverse non si mescolano mai; un database scritto da una versione più nuova dell'addon si apre in **sola lettura** (nessuna migrazione, nessuna scrittura).

### 8.4 Rete e fiducia

| Canale | Uso |
|---|---|
| `RAID` | Protocollo di sessione: apertura sessione, pezzo aperto, risposte, risultato. Messaggi piccoli. |
| `GUILD` | Tabella dei crediti in sola lettura per tutti i membri (snapshot firmato) |
| `OFFICER` | Sincronizzazione completa del registro fra officer (scambio dei "fin dove sono arrivato" per autore, richiesta dei pezzi mancanti) |
| `WHISPER` | Recupero di un membro che è entrato tardi o ha fatto /reload |

- Prefisso versionato (es. `FDCP1`); messaggi serializzati con `C_EncodingUtil` e spezzati da AceComm.
- **Come è fatto (M1-6).** Il testo è `<versione>|<TIPO>|<payload>`: versione e tipo in chiaro, il payload è CBOR (deflate quando conviene) in Base64 (`Net/Codec.lua`). Una versione più recente o un tipo sconosciuto si ignorano senza decodificare; il prefisso porta la versione del protocollo (`FDCP1`), un protocollo incompatibile userebbe `FDCP2`. `Net/Transport.lua` accoda i messaggi con priorità (ALERT, NORMAL, BULK), un messaggio ogni `GAP` secondi per canale (`RAID` 0,5 · `GUILD` 1 · `OFFICER` 1 · `WHISPER` 0,25), un limite per tipo, l'ultimo messaggio per chiave, e li **tiene in attesa** durante il lockdown della chat, una restrizione addon **o un incontro con un boss** (`IsEncounterInProgress`); un rifiuto di lockdown del client è un'attesa, non un fallimento. Un messaggio `RAID` aspetta anche finché il personaggio non è in un raid e scade dopo 120 secondi (un messaggio di sessione vecchio non arriva mai nel raid successivo). Ogni messaggio porta la chiave della gilda per cui è stato scritto: aspetta se la gilda non è nota e cade se il personaggio è passato a un'altra. La coda si salva al logout (`FinlandDragonCreditPointsCharDB.outbox`) e si ripristina al login, quindi sopravvive a `/reload`. L'eco dei propri messaggi `RAID`, `GUILD` e `OFFICER` è contata e scartata. I tipi dei moduli successivi (protocollo di sessione, sincronizzazione del registro) si registrano con `Codec:RegisterType`; i messaggi in arrivo escono solo come evento `NET_MESSAGE(msg, mittente, canale)` sul bus.
- **Presenza dell'addon (M3-5).** I primi messaggi del protocollo di sessione, solo su `RAID` (da un altro canale si
  ignorano):

  | Tipo | Campi | Significato |
  |---|---|---|
  | `HELLOQ` | `w?` (lista di "Nome-Reame", al massimo 40), `av`, `pv`, `pm` | "chi ha l'addon?" (il `HELLO?` del §4.1: il nome di un tipo ha solo lettere e cifre); senza `w` rispondono tutti, con `w` solo i nominati; porta anche i dati di chi chiede, che ha l'addon anche lui |
  | `HELLO` | `av` (versione dell'addon, `dev` se non pacchettizzato), `pv` (versione del protocollo di sessione), `pm` (il protocollo più vecchio che capisce ancora), `sq?` (M4-1: "non ho nessuna sessione in vista", vale anche in `HELLOQ`) | la risposta, o l'annuncio all'ingresso nel raid |

  Due client sono **compatibili** se il `pv` di ciascuno è almeno il `pm` dell'altro; compatibile con versione più
  vecchia = "da aggiornare", incompatibile = "versione incompatibile" (non rolla). Un client con un formato di rete
  nuovo usa un altro prefisso (`FDCP2`) e non si sente affatto: risulta "addon non attivo". Limite per tipo: quattro
  `HELLO` e quattro `HELLOQ` al minuto (l'ultimo in attesa vince).
- **Sessione di loot (M4-1).** `Net/Protocol.lua` (`Protocol.Session`); il protocollo di sessione passa a **2**
  (`pv = 2`, `pm = 2`: un client del solo controllo di presenza di M3 risulta "versione incompatibile"). Il client del
  master looter esegue `Domain/SessionFSM.lua` e trasforma i suoi **effetti** in messaggi (`Session:Publish`); ogni altro
  client tiene una **vista** in sola lettura (`Session.view`, da cui il popup e la finestra degli officer); le risposte dei
  membri diventano input `RESPONSE` della macchina (evento `SESSION_INPUT`, eseguito dal controller di M4-4). Messaggi
  (oltre a `s`, l'id della sessione):

  | Tipo | Canale | Campi | Significato |
  |---|---|---|---|
  | `SOPEN` | `RAID` | `q`, `ml`, `e?`, `rt?`, `lm?`, `it` = `{ {id, ca, cs, co?}, … }` | sessione aperta: oggetti con categoria e costi per risposta (`cs`); `rt` = le risposte offerte con il loro tier (`{ MS = 1, OS = 2 }`, M4-6); `lm` = chi sceglie l'etichetta di una risposta (`auto`, `suggest` o `manual`, la regola della gilda, M7-2b); rimandato dopo una correzione |
  | `SROLL` | `RAID` | `q`, `i`, `r`, `k`, `g?`, `tr?`, `am?`, `cl?`, `de?`, `rm?` | round `r` del pezzo `i` aperto: tipo, fase, tier, fra chi (reroll), `cl` = raccoglie le risposte, `de` = scadenza in ora del server (`rm` = secondi rimasti, in pausa) |
  | `SRESP` | `RAID` | `i`, `r`, `rs`, `lb?`, `lo?`, `n?`, `vd?`, `eq?` | la risposta di un membro `{risposta, etichetta, nota}` (nota al massimo 80 byte): sempre la propria; il popup (M4-6) la rimanda intera a ogni cambiamento. Da M5-2 porta anche `vd = { m, o? }` (i verdetti per main-spec e off-spec, ognuno `{ v, u?, c?, b?, p?, l? }`) ed `eq` (al massimo quattro stringhe `item:…` dei pezzi indossati usati nel confronto); campi facoltativi, un client più vecchio non li manda e il ML non ne ha bisogno per far contare la risposta. Da M7-2b `lo` (`AUTO`, `CHANGED` o `MANUAL`) dice chi ha scelto l'etichetta, e viaggia solo con un'etichetta |
  | `SCLOSE` | `RAID` | `q`, `i`, `r` | round chiuso |
  | `SPROP` | `RAID` | `q`, `i`, `k`, `tg`, `w?`, `c?`, `rs?`, `tr?`, `rc?`, `f?`, `m?` | la proposta: a chi, quanto, perché (codici di motivo e segnalazioni); `m` = modificata dal ML |
  | `SRESULT` | `RAID` | `q`, `i`, `o`, `w?`, `c?`, `tg?`, `x?` | `AWARDED` (vincitore, costo, destinatario), `REJECTED` (`x` = cosa succede dopo) o `DELIVERED` |
  | `SPAUSE` | `RAID` | `q`, `p`, `de?`, `rm?` | pausa (`p` vero) o ripresa |
  | `SEND` | `RAID` | `q` | sessione chiusa |
  | `SSYNCQ` | `WHISPER` (o `RAID`) | `s?` | "mandami la sessione": dopo un buco nella sequenza, al ML |
  | `SRINT` | `RAID` | `i`, `r`, `n` | l'intento di roll (M7-2d, protocollo 6): il mittente ha cliccato "Rolla" per il round `r` del pezzo `i` e il roll del gioco segue; `n` = nonce del clic. Nessun valore di roll |
  | `SSTATE` | `WHISPER` | `q`, `ml`, `e?`, `rt?`, `it` (+ `st`, `w`, `pc`, `tg`), `a?`, `rd?`, `pr?`, `pz?`, `en?`, `my?` | tutta la vista per un membro: il pezzo attivo, il suo round e la proposta, pausa, fine, la sua risposta (`my` = `{ rs, lb?, n? }`) |

  Regole: **ogni risposta è del mittente** (il ML prende il giocatore dal mittente che dà il client, mai da un campo; una
  risposta che nomina un altro giocatore, `p`, è rifiutata come falsificata e contata); **nessun messaggio porta un
  roll** e niente di quello che arriva via addon diventa un input `ROLL` (i roll arrivano dalla chat, M4-3); i messaggi
  di controllo si accettano solo dal master looter della sessione (chi ha mandato il `SOPEN` nominando se stesso in
  `ml`); un `SOPEN` di chi non è nel raid è rifiutato, e quello di un altro mentre una sessione è in corso solo se ha
  `award.confirm`. Ogni messaggio di controllo porta `q`, il numero di sequenza della sessione (salvato nella sessione,
  `net`, così sopravvive al `/reload` del ML): un doppione si ignora, un **buco** (un messaggio perso, o scaduto dopo i
  120 secondi di vita di un messaggio `RAID` durante un lockdown lungo) fa chiedere `SSTATE` al ML in sussurro, di nuovo
  ogni 5 secondi fino a 3 volte. **Resync**: chi entra nel raid tardi, fa login o `/reload` senza una sessione in vista
  lo dice nel suo `HELLO` (`sq`), e il ML di una sessione in corso gli sussurra `SSTATE` (al massimo uno ogni 3 secondi
  per giocatore), con la sua risposta al pezzo aperto; il ML che fa `/reload` ricostruisce la vista dalla sessione salvata
  (`Session:Host`). I timer viaggiano in ora del server (`GetServerTime`, uguale per tutti), mai nell'orologio locale.
  Tutto passa dalla coda di `Net/Transport.lua` con priorità `ALERT`: aspetta il lockdown, le restrizioni e i boss
  (piano B: sessioni dopo `ENCOUNTER_END`), in ordine; più risposte in attesa dello stesso giocatore → parte l'ultima.
- **Come è fatto (M7-2d).** Il protocollo di sessione passa a **6** (`pm` resta 2): il nuovo tipo `SRINT` (l'intento di
  roll del pulsante "Rolla", §4 "Come è fatto (M7-2d)") e il campo facoltativo `bo` di `SOPEN` / `SSTATE` (la regola
  `session.buttonRollsOnly` è accesa: il client del giocatore sa quando avvisare per un `/roll` scritto a mano). Un client
  di protocollo da 2 a 5 scarta `SRINT` senza leggerlo e ignora `bo`, quindi segue ancora la sessione; i suoi roll (senza
  intento) si giudicano come prima. **La regola di fiducia resta**: l'intento non porta mai un valore e non diventa mai
  un input `ROLL`; dice solo al listener del ML che il prossimo roll di quel mittente in quel round viene da un clic; il
  roll stesso è sempre quello del server, letto nella chat. Un intento che nomina un altro giocatore (`p`) è falsificato.
- **Sincronizzazione del registro fra officer (M6-5).** `Net/Sync.lua`, solo su `OFFICER` (un messaggio di questi tipi
  da un altro canale si ignora); vedi [ADR 0005](adr/0005-officer-ledger-sync.md). Messaggi:

  | Tipo | Campi | Significato |
  |---|---|---|
  | `LHEADS` | `h` = `{ [autore] = segno }` (al massimo 200 autori) | "fin dove sono arrivato": per autore il più alto `seq` senza buchi (`Ledger.Heads`) |
  | `LWANT` | `to`, `r` = `{ {a, f, l}, … }` (al massimo 20 intervalli) | "mandami questi": i `seq` da `f` a `l` dell'autore `a`, chiesti al solo officer `to` |
  | `LEVENTS` | `e` = `{ evento, … }`, `to?`, `d?`, `g?` | gli eventi (senza `id`, che è `autore:seq`), pochi per messaggio; `to` = chi li ha chiesti, `d` = ultimo messaggio della risposta, `g` = `{ {a, f, l, season}, … }` i `seq` chiesti che una compattazione ha tolto (M6-7: lapidi, presi solo per `seq` che mancano e di una season la cui compattazione è già nel registro di chi li riceve); chiunque li sente li unisce (un'unione di insiemi: due volte non fa danni) |

  È un **pull**: un client annuncia i suoi segni 5 secondi dopo aver letto il roster della gilda, 3 secondi dopo che il
  suo registro è cresciuto e almeno ogni 5 minuti, mai due volte in 20 secondi, mai con il registro vuoto (impara
  ascoltando i segni degli altri); chi sente segni più alti dei propri
  chiede all'officer che ha più eventi che gli mancano (una richiesta alla volta, 60 secondi per la risposta, poi chiede
  di nuovo, magari a un altro); chi sente segni più bassi dei propri annuncia i suoi, così l'altro può chiedere.
  **Nessuna sovrascrittura**: un evento già presente con un altro contenuto è un conflitto, vince quello salvato e il
  conflitto si conta (`/fdcp debug`). **Fiducia**: un messaggio di sincronizzazione conta solo da un officer, cioè da un
  mittente (letto dal client, mai da un campo) che **ora**, nel roster di gilda locale, ha un rango che può scrivere
  eventi (il permesso più largo della tabella in vigore); poi ogni evento passa dal cancello dei permessi uno per uno
  (entra solo se il suo autore aveva il rango richiesto quando l'ha scritto). Un evento rifiutato non si salva e non si
  richiede più finché la tabella dei permessi o la storia dei ranghi non cambiano (`GUILD_RANK_HISTORY_CHANGED`);
  quelli che il cancello non sa ancora decidere aspettano nella coda del servizio dei permessi. **Autori mai visti**
  (la storia dei ranghi è locale, M3-1): un autore che non ha nessuna riga nella storia dei ranghi di questo client
  (un officer uscito dalla gilda prima che questo client leggesse il suo primo roster) è **garantito dall'officer che
  inoltra l'evento**: l'evento si giudica con il rango di chi lo inoltra, quindi un officer può portare dentro solo quello
  che avrebbe potuto scrivere lui, e un membro nulla; un autore che la storia conosce si giudica sempre con il suo rango.
  **Budget**: al massimo 200 eventi per richiesta, 600 eventi serviti ogni 5 minuti, 1800 byte di testo per messaggio
  (25 eventi al massimo; `Net/Transport.lua` lo spezza in pezzi da 255), `LHEADS` tre al minuto e `LWANT` dieci al
  minuto, `LEVENTS` in priorità `BULK` (dopo la sessione e gli annunci). Un membro che non è officer non partecipa (riceve la
  tabella in sola lettura, M6-6). Evento sul bus: `LEDGER_SYNCED{from, added, refused, pending, conflict}`.
  Non verificato nel client: chi riceve i messaggi addon `OFFICER`, il ritmo dei testi lunghi e il CBOR di
  `C_EncodingUtil` sui payload del registro.
- **Crediti in sola lettura per i membri (M6-6).** `Net/Snapshot.lua` e `Domain/CreditSnapshot.lua`; vedi
  [ADR 0006](adr/0006-read-only-credits-snapshot.md). Il registro resta solo agli officer: ai membri arriva la **tabella
  dei crediti** della season in corso (quella aperta, altrimenti la più recente), mai gli eventi, le presenze o l'audit.
  Messaggi:

  | Tipo | Canale | Campi | Significato |
  |---|---|---|---|
  | `CSNAP` | `GUILD` (o `WHISPER` in risposta) | `s`, `sl`, `so`, `up`, `nn`, `n` = `{ {d, i}, … }` (le ultime 8 serate), `r` = `{ {m, c, ro, sp, st, f, al?, t, p?}, … }` (al massimo 200 membri, entrambe le fazioni; `p` = coppie serata, crediti), `k`, `ts` | la tabella: `k` = eventi nel registro dell'officer, `ts` = ora del server |
  | `CSNAPQ` | `GUILD` | `k` | "chi ha una tabella più nuova della mia?" (`k` della tabella tenuta, 0 = nessuna) |
  | `CSNAPQ` | `WHISPER` | `k` | "mandami la tua" (all'officer scelto) |
  | `CSNAPO` | `WHISPER` | `k` | l'offerta di un officer con un registro più nuovo |

  **Invio**: il client di un officer manda `CSNAP` su `GUILD` 30 secondi (più qualche secondo suo, dal nome) dopo che il
  suo registro è cresciuto, mai due volte in 60 secondi; se prima sente la tabella di un altro officer nuova almeno
  quanto il suo registro, rinuncia. **Recupero**: il client di un membro, 8 secondi dopo aver letto il roster della gilda
  (login, `/reload`, ingresso in gilda), chiede su `GUILD`; ogni officer con un registro più nuovo offre in sussurro;
  dopo 5 secondi il membro chiede in sussurro la migliore offerta (`k` più grande, poi il nome) e, senza risposta in
  30 secondi, la successiva. **Fiducia** (la "firma"): una tabella conta solo se il mittente, letto dal client e mai da
  un campo, ha **ora** nel roster di gilda del membro un rango che può scrivere eventi del registro (lo stesso controllo
  della sincronizzazione fra officer); quella di chiunque altro, o sentita prima di leggere il roster, si ignora e si
  conta; ogni campo si controlla per tipo e dimensione. **Più nuova**: si tiene una tabella solo se il suo `k` è più
  grande (un registro cresce soltanto), a parità se è più recente, e una tabella tenuta da più di 7 giorni cede a
  qualunque più recente (dal M6-7 `k` conta anche gli eventi compattati, `Ledger.Seen`): un officer rimasto indietro non riporta
  indietro i membri. La tabella tenuta si salva con i dati della gilda (`creditSnapshot`) e sopravvive a `/reload`; la
  scheda **Crediti** (con la nota "sola lettura · inviata da …") e il popup del pezzo la leggono su ogni client che non
  è officer o il cui registro non ha season. Evento sul bus: `CREDIT_SNAPSHOT(from)`. Limite: il membro giudica il
  mittente con la tabella dei permessi del preset (non riceve `PERMISSIONS_CHANGED`). Non verificato nel client: i
  messaggi addon `GUILD` e `WHISPER` fra un membro e un officer e il ritmo di una tabella da 2–5 KB.
- **Coda con lockdown**: se `InChatMessagingLockdown()` o le restrizioni sono attive, i messaggi aspettano
  (riuso del modulo di Accord). Le sessioni partono dopo `ENCOUNTER_END`.
- **Fiducia**: un evento del registro è accettato solo se l'autore ha il rango richiesto dal permesso (§3.9),
  verificato sul roster di gilda locale; configurazione e permessi solo se l'autore è il GM. Un membro può
  mandare solo le proprie risposte. I roll non viaggiano mai via addon.

### 8.5 Localizzazione

L'addon nasce **multilingua**: all'inizio **italiano (`itIT`) e inglese (`enUS`)**, ma aggiungere una lingua
deve voler dire solo aggiungere un file, senza toccare il codice.

- **Nessun testo nel codice.** Ogni stringa visibile (finestre, popup, tooltip, messaggi in chat, motivazioni
  delle proposte, avvisi in `/raid`, nomi di categorie e risposte del preset) passa da una chiave di traduzione
  (AceLocale). Un controllo in CI fallisce se trova testo scritto direttamente in `UI/` o `Domain/`.
- **File di lingua**: `Locale/enUS.lua` è la base e contiene tutte le chiavi; `Locale/itIT.lua` le traduce. Una
  chiave mancante in una lingua ricade sull'inglese, mai su una chiave vuota. Uno script segnala le chiavi non
  tradotte, così una nuova lingua (`deDE`, `frFR`, `esES`…) si aggiunge con un file e una riga nel TOC.
- **Quale lingua si vede.** Di base quella del client (`GetLocale()`); ogni giocatore può sceglierne un'altra
  nelle preferenze personali (serve un `/reload`).
- **Lingua della gilda**: i testi che vanno **a tutti** (annunci e avviso in `/raid`, motivazioni nel registro,
  esportazione per il sito e Discord) usano la lingua scelta dal GM nella configurazione, non quella di chi li
  manda, così il raid legge sempre la stessa lingua. I testi dell'avviso restano modificabili dal GM.
- **Il registro è neutro.** Gli eventi salvano codici e numeri (es. `reason = "LOWER_CREDITS"`, `credits = 0`,
  `roll = 76`), non frasi: ogni client compone la motivazione nella propria lingua. Solo le note scritte a mano da
  ML e council restano nella lingua in cui sono state scritte.
- **Testi della configurazione**: i nomi di categorie, risposte ed etichette creati dal GM possono avere una
  versione per lingua; se manca, si mostra quella che c'è.
- **Messaggi del gioco**: i pattern dei messaggi di sistema (`RANDOM_ROLL_RESULT`, `LOOT_ITEM`, …) si costruiscono
  dalle stringhe globali del client, non scritti a mano, così il riconoscimento di roll e loot funziona in ogni
  lingua del gioco, anche in quelle che l'interfaccia dell'addon non ha ancora.
- **Numeri e date**: separatore decimale e formato della data seguono la lingua (es. "1,5 crediti" e "19/11" in
  italiano, "1.5 credits" e "11/19" in inglese).
- **Test**: la suite offline gira in entrambe le lingue e verifica che nessuna chiave manchi.
- **Come è fatto (M1-5).** `Locale/Boot.lua` tiene in memoria **tutte** le lingue (AceLocale ne tiene solo una, quella
  del client): servono sia la lingua personale sia la lingua della gilda. La lingua personale si legge in `Config:Setup`
  (il client carica le SavedVariables dopo i file dell'addon) e vale al `/reload` successivo; `Locale.Guild(chiave, ...)`
  compone i testi per tutti. `tools/check_locale.py` esegue i controlli di CI di questo paragrafo.

Documentazione: come in Accord, codice, commenti, commit e ADR in inglese; specifiche e analisi in italiano;
README e manuale utente in entrambe le lingue.

---

## 9. Interfaccia: lo stile del sito della community

Lo stile dell'interfaccia segue la pagina WoW Forever del sito della community, dopo lo studio di un gruppo di
esperti (designer web, ingegnere UI di addon per il motore 12.0, ingegnere dati) su che cosa si può riprodurre nel
client, che non ha CSS: solo texture, 9-slice, maschere, font inclusi nell'addon e `AnimationGroup`. **La specifica è
[`docs/specs/ui-style.md`](specs/ui-style.md)** (passo M1-6b): token, componenti e come si costruiscono, verdetto
"identico / approssimato / non fattibile" per ogni elemento, font e licenze, finestra e schede, anteprime generate da
`tools/make_mockups.py`. Questa sezione ne riassume le decisioni; in caso di differenza vale la specifica.

### 9.1 Palette e temi

Gli stessi token (`bg`, `surface-1…3`, `raised`, tre livelli di `border`, `text-1…3`, `accent`, `accent-text`,
`accent-2`, `neon`, `ok` / `warn` / `err`, `grad`) hanno tre valori:

| Tema | Origine | Colori principali |
|---|---|---|
| **Nebula** (predefinito) | tema scuro del sito | fondo `#0B0612`, superfici viola-nere, accento ambra `#FC7E46`, gradiente ambra → corallo → magenta, neon `#C45BC4` |
| **Aurora** | tema chiaro del sito | fondo `#F5F8FA`, accento blu `#0054B6`, gradiente blu → verde acqua |
| **Drago** | logo della gilda (la palette di prima di M1-6b) | fondo `#071715`, superfici verdi, oro `#E9B949`, verde `#3E9E5F`, bagliore `#B8E86A` |

Il tema si cambia nelle Impostazioni senza `/reload`. I colori di classe e di qualità degli oggetti restano quelli
del gioco; le fazioni non hanno colore (nome e lettera O / A, come sul sito). Il logo della gilda resta nella barra
della finestra e nel pulsante della minimappa in ogni tema.

### 9.2 Elementi da costruire

- **Forme**: raggi 8 / 12 / 18 con texture bianche 9-slice tinte dal token; bordi a 1 px netti.
- **Profondità**: una riga di luce in cima alle card e un'ombra morbida; sullo scuro la profondità viene dalla luce.
- **Bagliori**: texture pre-sfocate in fusione additiva, al massimo un elemento neon per vista.
- **Stati**: hover 8%, pressed 12% e pressione in scala 0,97; transizioni 120 / 200 / 320 ms con curva `OUT`.
- **Tipografia**: Outfit (testo) e JetBrains Mono (numeri e date), gli stessi del sito, OFL 1.1; Orbitron (OFL 1.1)
  al posto di Atomed, il carattere del logo del sito, che non ha una licenza che ne permetta la distribuzione; i
  font del gioco come ripiego.
- **Icone**: foglio di icone bianche in TGA (Lucide ISC o Material Symbols Apache-2.0).
- **Componenti**: schede a sottolineatura, selettore a pillole, card, fisarmonica della season, tabella ordinabile
  con colonne fisse (ScrollBox), nome di classe con quadratino, badge e chip, pulsanti (principale a gradiente,
  secondario, ghost, neon), barre sottili a gradiente, card d'istanza con copertina, dialog, toast, switch.
- **Non fattibili**, con l'alternativa nella specifica: sfocatura dello sfondo, spaziatura fra le lettere, curve a
  molla, inclinazione 3D delle card.

### 9.3 Finestre

1. **App principale** con barra del titolo (logo, nome, season e fazione, stato della serata) e **schede orizzontali
   come sul sito**: **Roster** (Pool · Serata · Addon) · **Crediti** · **Progress** (prima uccisione per boss e per
   fazione) · **Loot** (Sessione · Council) · **Storico** (Serate · Log · Audit · Esporta) · **Impostazioni**
   (Personali · Regole · Permessi · Sito). Le schede che un rango non può usare non compaiono. L'apertura e la
   chiusura della season (pacchetto di istanze, taglie, regola dei late joiner, crediti iniziali; permesso
   `season.manage`) hanno una finestra propria, step M6-1b della roadmap (la sotto-scheda **Season** di Impostazioni, M7-2);
   i membri vedono la season in sola lettura.
2. **Popup del pezzo (giocatore)**: una card per pezzo, impilabili; vedi §5.1.
3. **Sessione (ML)**, nella scheda Loot: a sinistra i pezzi della sessione con stato; a destra i candidati con
   crediti, risposta, roll, segnalazioni; sotto la proposta con "Conferma e assegna", "Modifica", "Intervento del
   council". La sotto-scheda **Council** (M5-8, §3.6) raccoglie gli interventi del council: il pezzo sul tavolo con segnalazioni
   e voto, annullamento, correzione dei crediti, audit e progetti leggendari.
4. **Tabella crediti**: come sul sito (season a fisarmonica, una colonna per serata, totale, precedenza), filtri per
   ruolo e classe, la propria riga evidenziata, esportazione.
5. **Progress**: una card per istanza con copertina, barra per fazione e boss con teschio e data.
6. **Pulsante minimappa** e voce nel compartment degli addon con il logo.

Il logo originale è in `assets/logo-source.webp`; per il gioco va convertito in TGA quadrato a potenza di due
(256 per la finestra, 64 per la minimappa).

---

## 10. Cosa è configurabile

Tutto ciò che è in §3 più:

- profili (AceDB) con **preset** pronti: "Patto" (il vostro), "Solo roll", "Loot council puro", "EPGP semplice"
  (`Domain/Presets.lua`, M2-5: cosa cambia ciascuno è in §3.9, "Come è fatto (M2-5)");
- importa/esporta un profilo come stringa da incollare su Discord;
- soglia di qualità, istanze considerate "ufficiali", durata del timer di roll, parole chiave in chat;
- rango del council e degli editor del registro, voto sì/no;
- pesi delle statistiche per spec, soglie di upgrade, auto-pass, visibilità dei verdetti (le soglie, `useStats`, l'auto-pass e l'interruttore dei verdetti sono la sezione `upgrade` delle regole, M5-2; la visibilità ai soli council è `council.verdicts`, M5-4, con `council.flags` e `council.wasteRatio` delle segnalazioni);
- annunci in chat raid (sì/no, testo), suoni, dimensione e posizione dei popup;
- **permessi per rango di gilda** (§3.9), modificabili solo dal GM;
- **nome della fazione sul sito** (`site.factionName`, §7.1): vuoto = `Nebulah` per l'Orda e `Nebulaa` per
  l'Alleanza; lo cambia il GM con le regole;
- **blocco della configurazione durante la season**: solo il GM può modificare costi o regole, a season aperta
  deve confermare esplicitamente e la modifica finisce nell'audit, così nessuno cambia le regole a metà.

Per tutti gli altri membri la pagina Impostazioni mostra le regole in **sola lettura** (con "modificabile dal GM"),
più le preferenze personali: posizione dei popup, suoni, pesi delle statistiche personali, wishlist.

**Come è fatto (M7-2).** La scheda **Impostazioni** è `UI/Windows/Settings.lua` (le sotto-schede Personali · Regole ·
Permessi · Sito · Season; Season è la pagina di M6-1b, `UI/Windows/Season.lua`) sopra `App/SettingsController.lua`;
il modulo di regole è `UI/Windows/RulesForm.lua` sopra `Domain/RuleFields.lua` (puro: per ogni valore delle regole
dice il percorso, il tipo, i limiti e le chiavi di testo; `Get`, `Set`, `Parse`). **Personali**: tema, caratteri,
effetti neon, animazioni, suoni (`sounds`, nuova voce del profilo: un breve suono quando compare il popup), lingua
personale e lingua dei messaggi per tutti, posizione del popup (si rimette al centro), pesi personali e wishlist
(`App/PersonalUpgrade.lua`); nessuna è condivisa. **Regole**: dieci pagine (Serata e sessione · Priorità · Costi ·
Moltiplicatori · Membri e crediti · Loot council · Leggendari e panchina · Messaggi in /raid · Verdetto di upgrade ·
Sito) che coprono **ogni** sezione di `Domain/Rules.lua`, anche quelle senza finestra prima (testo dell'avviso in
`/raid`, annunci, regole di upgrade, council). Le modifiche vanno a una **bozza**; **Salva** controlla tutta la
configurazione con `Rules.Validate` (apre la pagina del campo sbagliato) e scrive **un** `CONFIG_CHANGED`. Con una
season aperta una finestra elenca le modifiche e chiede la conferma esplicita: l'evento tiene `confirmed` per l'audit.
**Permessi**: una riga per permesso con il rango più basso che lo ha (i ranghi del gioco per nome, per indice); i due
fissi restano al GM; Salva scrive un `PERMISSIONS_CHANGED` con la stessa conferma. Qui il GM chiude anche la **revisione
dei ranghi** (M3-1: un rango riordinato, aggiunto o tolto lascia un avviso finché il GM non conferma la tabella).
**Chi può**: solo il GM (indice di rango 0, `config.permissions`). Per gli altri i controlli sono spenti e i pulsanti
non esistono; `SettingsController:ApplyRules` e `ApplyPermissions` rispondono `NOT_GM` **prima** di costruire un evento,
e un evento falsificato (o arrivato da un peer) lo rifiuta il cancello di fiducia del registro (`Permissions.Gate`).
Nella finestra delle impostazioni del gioco c'è una voce AceConfig con gli interruttori personali e un pulsante che
apre la scheda (`SettingsController:GameOptions`). **Scelte**: la scelta dei preset e il profilo come stringa sono
M7-3 (sotto); il campo "Pezzo che nessuno vuole" e simili sono liste di codici chiuse (mai testo libero); i costi per singolo
oggetto (`cost.overrides`) e la lista dei token **non** hanno ancora una pagina (sono elenchi di id, non valori: restano
nel dominio e nell'esportazione delle regole di M6-7); le regole importate che li contengono si conservano intatte
quando il GM salva da qui.

**Come è fatto (M7-3).** La sotto-scheda **Profili** (`UI/Windows/Profiles.lua`, sopra `SettingsController`) riunisce tre
cose, senza duplicare quel che c'era già. **Profili personali (AceDB)**: `Config:ProfileNames / SelectProfile /
NewProfile / CopyProfile / DeleteProfile / ResetProfile` (nome da 1 a 32 caratteri semplici, mai doppio, il profilo in
uso non si elimina, niente scritto su uno schema più recente); al cambio l'aspetto si ridisegna (`CONFIG_PROFILE_CHANGED`).
**Stringa del profilo**: `Domain/Profiles.lua` (puro) e il tipo `PRF` della stessa busta di M6-7
(`!FDCP:PRF:1:<base64>`); viaggiano solo le impostazioni personali (tema, caratteri, effetti, animazioni, suoni,
lingua dei messaggi, secondi del roll; mai `debug` né il minimap); ogni valore si controlla con i validatori di
`Config`, l'anteprima elenca cosa cambierebbe e non si scrive nulla con un valore sbagliato. **Preset**: i quattro di
`Domain/Presets.lua` con quello in vigore segnato (`Presets.Match`); `PresetDiff` conta le regole che cambierebbero
(i valori propri della gilda, nomi del council e chiave del sito, restano) e `ApplyPreset` scrive con lo stesso
`ApplyRules` del modulo (solo il GM, conferma con season aperta, l'audit tiene il codice del preset). Ogni preset si
applica e fa il giro della stringa di configurazione (M6-7) senza cambiare. **Scelte**: la stringa del profilo non porta
regole (hanno la loro stringa e i preset); importare un profilo cambia quello in uso, non ne crea uno.

---

## 11. Rischi

| Rischio | Impatto | Mitigazione |
|---|---|---|
| Master loot non disponibile o limitato nei raid Forever | Alto | Spike M0. Piano B: l'addon gestisce priorità e registro, la consegna avviene per scambio dopo il loot di gruppo |
| Roll (`CHAT_MSG_SYSTEM`) segreti in istanza | Alto | Spike M0. Sessioni fuori dal boss; piano B: il ML legge i roll dopo che il lockdown finisce |
| Messaggi addon `RAID` rifiutati in istanza | **Alto** (l'addon è obbligatorio e non c'è il roll a mano) | Coda che aspetta (già fatta in Accord); sessioni solo fuori dai boss; verifica prioritaria in M0 |
| Statistiche "contestuali" non lette correttamente | Medio | Verifica M0; il verdetto resta un indizio, mai una decisione |
| Due officer che modificano insieme | Medio | Registro a eventi con autore: niente sovrascritture, solo eventi in più |
| Addon modificato che manda dati falsi | Basso | Roll dal server; risposte accettate solo dal mittente stesso; registro accettato solo da ranghi abilitati |
| Cache oggetti vuota (`GetItemInfo` restituisce nil) | Basso | `ItemCache` con attesa di `ITEM_DATA_LOAD_RESULT` |
| SavedVariables troppo grandi in una season lunga | Basso | Snapshot e compattazione del registro a fine season, archivio esportabile (M6-7: le formazioni di una season chiusa; dimensione stimata in `/fdcp debug`; M7-5: budget verificati in CI da `Tests/test_perf.lua` su una season simulata di 20 serate e 40 raider, circa 250 KB stimati contro il limite di 1 MiB, compattazione al 89%) |

---

## 12. Roadmap proposta

| Milestone | Contenuto | Uscita |
|---|---|---|
| **M0 Spike** | Addon sonda: master loot in raid Forever, lettura `LOOT_OPENED`, `GiveMasterLoot`, roll da `CHAT_MSG_SYSTEM` dentro/fuori boss, messaggi `RAID` dopo `ENCOUNTER_END`, `GetItemStatDelta` su pezzi raid, specializzazioni | Rapporto: cosa funziona, cosa serve il piano B |
| **M1 Fondamenta** | TOC, Ace3, Compat (da Accord), Config, Log, Locale (itIT + enUS, controllo chiavi mancanti e testo nel codice), test offline, CI, studio del sito della community (stile e file esportati, M1-6b), tema e finestra con le sei schede | Addon che si carica, `/fdcp` apre una finestra vuota a tema |
| **M2 Motore e registro** | Rules, Pricing, Classifier, Priority, Ledger, Season, preset "Patto", test con i tre esempi | Tutte le regole funzionano offline |
| **M3 Roster e serate** | Pool, main/alt, lineup, panchina, cambi, presenze per boss, calendario, prime uccisioni per boss e per fazione, controllo "addon nel raid" e avviso in `/raid`, schede Roster, Crediti e Progress | Il ML apre e chiude una serata e sa chi non ha l'addon |
| **M4 Sessione di loot** | SessionFSM, raccolta dal corpo, popup del giocatore, roll, reroll, conferma, consegna, protocollo RAID | Un boss intero gestito dall'addon |
| **M5 Upgrade e council** | UpgradeScore, pesi, verdetti, segnalazioni, interventi del council, voto, leggendari, BoE e banca | Il council lavora dall'addon |
| **M6 Storico ed export** | Viste serate/membro/oggetto, log, audit, export Discord/CSV/JSON e i tre file del sito (`roster`, `loot`, `progress`), sync fra officer | La tabella su Discord esce dall'addon |
| **M7 Rifinitura e rilascio** | Stile del sito completo (bagliori, ombre, icone, temi), impostazioni, profili, manuale, versione 1.0 | Prima release per la gilda |

M2 e M3 possono procedere in parallelo dopo M1; M4 dipende da M0, M2 e M3.

I passi di sviluppo di ogni milestone (uno per sessione e per pull request) sono in [`docs/roadmap/`](roadmap/README.md);
l'indice è [`ROADMAP.md`](../ROADMAP.md).

---

## 13. Domande aperte

1. ~~"8roaster"~~ **Risolta (19/11/2026)**: era un refuso. Un solo roster a rotazione per gilda (vedi §6).
2. **Dimensione del raid** **Risolta (19/11/2026)**: raid da 10, 20 e 40; una season = un pacchetto di raid
   (tutte le istanze di un aggiornamento) con una sola tabella crediti (§2, §6). Normal e Veteran usano la
   **stessa tabella**.
3. **Specializzazioni** **Risolta (19/11/2026)**: la spec la dichiara il giocatore per tutta la season, come nel
   canale 📋 Roster. Per il loot **MS1 = MS** e **MS2 = OS** (tier off-spec, 0 crediti). La terza voce "OS" del
   roster non conta per il loot.
4. **Obbligo dell'addon** **Risolta (19/11/2026)**: obbligatorio per tutti i raider. GM, officer e ML vedono chi
   non lo ha attivo e possono mandare l'avviso con i nomi in `/raid` (§4.1). Chi non ha l'addon attivo è
   **escluso dal roll** (configurabile dal GM per altre gilde).
5. **Chi scrive il registro** **Risolta (19/11/2026)**: le assegnazioni le scrive l'addon del master looter
   quando lui conferma. Chi può fare correzioni fuori dalla serata, e ogni altro permesso, è configurabile per
   rango di gilda; la configurazione la cambia **solo il GM** (§3.9).
6. **Integrazione con Azeroth Accord** **Risolta (19/11/2026)**: addon **indipendente**, nessuna dipendenza né
   integrazione in gioco. Da Accord si riusa solo il codice sorgente (Compat, coda dei messaggi, impianto dei
   test), copiato e adattato come Accord ha fatto con Azeroth Guild Finder.
7. **Nome e licenza** **Risolto (19/11/2026)**: Finland Dragon Credit Points, sigla FDCP, comando `/fdcp`;
   licenza **GPL-3.0** (file `LICENSE`), come Accord; repository **pubblico** su GitHub (`Finland6738/finland-dragon-credit-points`).
   Come in Accord: nessun dato personale nel repository (nomi reali, email, percorsi personali) e commit firmati con
   l'indirizzo noreply di GitHub, non con l'email personale.
8. **Pesi delle statistiche**: vi basta l'item level + pesi predefiniti, o avete già pesi/BiS list per spec da
   importare? **Aperta**, opzioni in [issue #2](https://github.com/Finland6738/finland-dragon-credit-points/issues/2).
   Default reversibile finché non decide il GM: item level + pesi predefiniti modificabili, import stile Pawn
   facoltativo e spento (step M5-1 e M5-3). M5-1 ha costruito la prima parte: pesi predefiniti per spec in
   `Data/StatWeights.lua` e ripiego sul solo item level (§5.1, "Come è fatto (M5-1)"); nessuna BiS list di gilda. M5-2 li
   usa nel popup (verdetto per MS1 e per MS2). M5-3 aggiunge i pesi personali per spec, l'import stile Pawn (spento finché il
   giocatore non importa, `/fdcp weights off` lo spegne senza perdere nulla) e la wishlist BiS personale (§5.1, "Come è fatto
   (M5-3)"); ancora nessuna BiS list di gilda. La domanda resta **aperta**.
9. **Lingua** **Risolta (19/11/2026)**: addon multilingua, all'inizio italiano e inglese, con altre lingue
   aggiungibili tramite un file (§8.5). Documentazione come Accord.
10. **Sito della community**: va bene estendere `loot.json` con `start` (crediti iniziali) e `kind` (assegnazione /
    correzione), o l'addon deve restare dentro il formato attuale (§7.1)? **Aperta**, opzioni in
    [issue #3](https://github.com/Finland6738/finland-dragon-credit-points/issues/3). Default reversibile: solo il
    formato attuale, con i campi estesi dietro un'opzione spenta (step M6-4). Dopo lo studio del sito (M1-6b,
    [site-export.md](specs/site-export.md) §8): niente costi negativi (il controllo del sito li rifiuta), crediti
    iniziali come righe sintetiche finché `start` non esiste. Costruito in M6-4: l'opzione è la chiave `site.extended`
    delle regole (spenta, in nessuna finestra); la issue resta aperta.
