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
| Nuovo arrivato | `members.lateJoin` | media dei crediti del roster, arrotondata per difetto |
| Rotazione | `bench.creditEffect` | nessuno (chi gioca meno accumula meno crediti, quindi ha la precedenza) |

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

### 3.5 Nuovi arrivati a season iniziata

`members.lateJoin` = `average` | `median` | `min` | `zero` | `fixed`; arrotondamento `floor` | `round` | `ceil`;
base di calcolo = "membri con almeno N serate nella season" (preset N = 1). Il valore iniziale viene scritto
nel registro come evento `MEMBER_JOINED{initialCredits}`: resta stabile anche se la media cambia dopo.

### 3.6 Council

- **Chi è**: rango di gilda ≤ X **e** presente nel raid (preset), oppure lista esplicita di personaggi.
- **Cosa può fare**, sempre con una motivazione obbligatoria che finisce nel log:
  - correggere la categoria o il costo **prima** dell'apertura del roll (dopo è bloccato, come dice il regolamento);
  - *spreco palese*: assegnare a un altro candidato invece del primo in fila;
  - *passa per fare il furbo*: assegnare d'ufficio a chi non ha rollato, con il costo pieno;
  - assegnare un leggendario;
  - annullare un'assegnazione (evento di compensazione, non una cancellazione);
  - correggere a mano i crediti di un membro.
- **Voto** (facoltativo, spento nel preset): sugli interventi, ogni membro del council vota dalla propria finestra
  e il ML vede i voti prima di confermare.

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

### 3.8 BoE

Un BoE si rolla come gli altri oggetti (stessa categoria, stesso costo). Se nessuno risponde main-spec,
`boe.fallback` = `bank` (preset) | `offspec` | `disenchant` | `freeroll`. Con `bank`, l'oggetto viene assegnato al
personaggio "banca" configurato, il log lo segna "Banco dell'Oste", e un officer può aggiungere poi l'oro ricavato
dalla vendita.

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
  raid, **con l'addon attivo**. Chi non ha l'addon è escluso (§4.1).
- **Consegna rimandata**: se il ML preferisce rollare tutto a fine serata, la sessione resta aperta e la consegna
  avviene poi per scambio (l'addon traccia l'oggetto finché non cambia di mano).
- **Disconnessioni e /reload**: lo stato della sessione è salvato a ogni passaggio; il ML riprende da dov'era.
- **Più officer con l'addon**: solo il master looter guida la sessione; gli altri vedono in sola lettura e possono
  intervenire come council.
- **Conferma e consegna nello stesso clic**: "Conferma" addebita i crediti e chiama `GiveMasterLoot` insieme
  (il clic del ML soddisfa anche un eventuale obbligo di azione fisica del gioco). "Conferma tutto" vale per le
  proposte senza segnalazioni.
- **Fasi automatiche**: apertura del roll, timer, chiusura, reroll e passaggio al tier off-spec possono partire da
  soli (`session.autoAdvance`, preset sì); il ML può sempre mettere in pausa la sessione.

### 4.1 L'addon è obbligatorio: chi non ce l'ha

Tutti i raider devono avere l'addon attivo. L'addon lo verifica da solo e aiuta GM, officer e master looter a
sollecitare chi manca.

**Come lo sa.** All'apertura della serata, a ogni ingresso nel raid (`GROUP_ROSTER_UPDATE`) e a richiesta, il
client del ML manda sul canale addon `RAID` una richiesta `HELLO?`; ogni client con l'addon risponde con versione
dell'addon e del protocollo. Chi non risponde entro qualche secondo è "senza addon". Distinguere "non installato"
da "installato ma disattivato" non è possibile (in entrambi i casi non risponde nulla): l'addon dice "addon non
attivo".

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

**Se qualcuno resta senza addon durante una sessione, è escluso dal roll** (`session.allowNoAddon` = no nel
preset; il GM può riattivare il roll a mano con `ms`/`os` in chat per altre gilde). In pratica:

- i candidati di un pezzo sono solo i membri del raid con l'addon attivo e una versione compatibile;
- un `/roll` fatto a mano da chi non ha l'addon viene **ignorato**, e nella sessione del ML compare come "roll
  scartato: addon non attivo", così nessuno pensa che sia stato perso per errore;
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
i pulsanti di risposta, un campo nota e la barra del timer.

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

### 5.3 Limiti da dichiarare al raid

- I pesi sono un'approssimazione: proc, effetti d'uso, bonus di set e tenuta non entrano nel punteggio.
- Chi non ha l'addon non rolla (§4.1), quindi ogni candidato manda sempre i propri dati di confronto.
- Se Forever applica bonus "contestuali" all'equipaggiamento raid (vedi proposta di design), le statistiche lette
  dal tooltip possono non coincidere con quelle reali in raid: da verificare in M0.
- Il verdetto calcolato è visibile solo al council (configurabile), per non trasformarlo in una discussione in chat.

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
- **Pianificazione della serata**: dall'evento di calendario (se esiste) o creata a mano. L'addon propone chi
  mettere in panchina con criteri configurabili: meno panchine nella season, vincoli di ruolo (minimo tank e
  healer), preferenze dichiarate. Il ML decide.
- **Durante la serata**: l'addon legge il gruppo (`GetRaidRosterInfo`) e registra ogni cambio con l'ora e il boss
  di riferimento, quindi la presenza è per boss, non solo per serata.
- **Effetto sui crediti**: nessuno nel preset (la rotazione non si paga sul loot). Per altre gilde: bonus o malus
  per panchina configurabile.
- **Statistiche**: serate giocate, panchine, boss presenti, pezzi vinti, crediti, per membro e per season.
- **Attenzione al tono**: il canale Roster promette "non è un registro di presenze: nessuno conta le serate di
  nessuno". Le presenze servono all'addon solo per ruotare la panchina in modo equo e per la media dei nuovi
  arrivati; per questo nel preset sono **visibili solo agli officer** e non compaiono in nessuna esportazione
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

Due modi di esportare: la **finestra di copia** (Storico › Esporta: file completo o frammento, già selezionato,
perché un addon non scrive file né usa la rete) e, consigliato, lo script **`tools/site_export.py`** che legge le
SavedVariables dopo la serata e **unisce** i tre oggetti ai file del sito, conservando l'altra fazione, le season
precedenti all'addon, le copertine e le istanze "in arrivo".

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
  Domain/ Rules Pricing Classifier Priority UpgradeScore Ledger Season Roster Rotation SessionFSM Presets
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
  `SEASON_OPENED`, `MEMBER_JOINED`, `MEMBER_LINKED_ALT`, `NIGHT_OPENED/CLOSED`, `ROSTER_CHANGED`,
  `ENCOUNTER_KILLED`, `DROP_SEEN`, `ITEM_AWARDED{cost, response, reason?}`, `AWARD_VOIDED{ref, reason}`,
  `CREDITS_ADJUSTED{delta, reason}`, `LEGENDARY_PROJECT_*`, `CONFIG_CHANGED`.
  I crediti sono la somma degli eventi della season; uno snapshot periodico evita di ricalcolare tutto.
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
   (Personali · Regole · Permessi · Sito). Le schede che un rango non può usare non compaiono.
2. **Popup del pezzo (giocatore)**: una card per pezzo, impilabili; vedi §5.1.
3. **Sessione (ML)**, nella scheda Loot: a sinistra i pezzi della sessione con stato; a destra i candidati con
   crediti, risposta, roll, segnalazioni; sotto la proposta con "Conferma e assegna", "Modifica", "Intervento del
   council".
4. **Tabella crediti**: come sul sito (season a fisarmonica, una colonna per serata, totale, precedenza), filtri per
   ruolo e classe, la propria riga evidenziata, esportazione.
5. **Progress**: una card per istanza con copertina, barra per fazione e boss con teschio e data.
6. **Pulsante minimappa** e voce nel compartment degli addon con il logo.

Il logo originale è in `assets/logo-source.webp`; per il gioco va convertito in TGA quadrato a potenza di due
(256 per la finestra, 64 per la minimappa).

---

## 10. Cosa è configurabile

Tutto ciò che è in §3 più:

- profili (AceDB) con **preset** pronti: "Patto" (il vostro), "Solo roll", "Loot council puro", "EPGP semplice";
- importa/esporta un profilo come stringa da incollare su Discord;
- soglia di qualità, istanze considerate "ufficiali", durata del timer di roll, parole chiave in chat;
- rango del council e degli editor del registro, voto sì/no;
- pesi delle statistiche per spec, soglie di upgrade, auto-pass, visibilità dei verdetti;
- annunci in chat raid (sì/no, testo), suoni, dimensione e posizione dei popup;
- **permessi per rango di gilda** (§3.9), modificabili solo dal GM;
- **blocco della configurazione durante la season**: solo il GM può modificare costi o regole, a season aperta
  deve confermare esplicitamente e la modifica finisce nell'audit, così nessuno cambia le regole a metà.

Per tutti gli altri membri la pagina Impostazioni mostra le regole in **sola lettura** (con "modificabile dal GM"),
più le preferenze personali: posizione dei popup, suoni, pesi delle statistiche personali, wishlist.

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
| SavedVariables troppo grandi in una season lunga | Basso | Snapshot e compattazione del registro a fine season, archivio esportabile |

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
   facoltativo e spento (step M5-1 e M5-3).
9. **Lingua** **Risolta (19/11/2026)**: addon multilingua, all'inizio italiano e inglese, con altre lingue
   aggiungibili tramite un file (§8.5). Documentazione come Accord.
10. **Sito della community**: va bene estendere `loot.json` con `start` (crediti iniziali) e `kind` (assegnazione /
    correzione), o l'addon deve restare dentro il formato attuale (§7.1)? **Aperta**, opzioni in
    [issue #3](https://github.com/Finland6738/finland-dragon-credit-points/issues/3). Default reversibile: solo il
    formato attuale, con i campi estesi dietro un'opzione spenta (step M6-4). Dopo lo studio del sito (M1-6b,
    [site-export.md](specs/site-export.md) §8): niente costi negativi (il controllo del sito li rifiuta), crediti
    iniziali come righe sintetiche finché `start` non esiste.
