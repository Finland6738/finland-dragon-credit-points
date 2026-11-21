# Regole del loot

> **In sviluppo.** Questa pagina descrive le regole che il motore dell'addon già segue (scritto e provato offline; nulla è ancora stato provato nel gioco). Le finestre che le usano arrivano nelle versioni successive. [English](Loot-Rules)

L'addon fa i conti, il master looter decide. Queste sono le regole della gilda (preset "Patto") come le applica il motore. Ogni valore qui sotto può essere cambiato dal Guild Master nelle regole, tranne dove è scritto "fisso".

## Crediti

- I crediti **non si salvano**: si calcolano dal registro, l'elenco di tutto quello che è successo (assegnazioni, correzioni, nuovi membri). Una correzione è una nuova voce, mai una cancellazione.
- Una season fa partire tutti da **0 crediti**. La season è un pacchetto di raid (10, 20 e 40 giocatori hanno una sola tabella di crediti, anche Normal e Veteran).
- **Solo i main** guadagnano e spendono crediti. Un alt è collegato al suo main e usa i crediti del main.
- Meno crediti significa una posizione migliore: **vince chi ha meno crediti**, e il roll serve solo a sciogliere le parità.
- Un nuovo arrivato a season iniziata non parte da 0: parte dalla **media dei crediti del roster, arrotondata per difetto**, così non salta la fila e non resta in fondo. Il numero si scrive una volta e resta stabile.

## Quanto costa un oggetto

Il costo è il primo di questi che risponde:

1. un costo o una categoria fissati dal council per quell'oggetto per tutta la season;
2. la tabella categoria per qualità;
3. il moltiplicatore della risposta: main-spec x 1, off-spec x 0.

| Categoria | Costo (blu e viola) |
|---|---|
| Arma, trinket, oggetto di quest o token | 2 |
| Tutto il resto (armatura, gioielli, scudo, mano secondaria) | 1 |
| Ricette, cavalcature, cosmetici | 0 |
| Arancione (leggendario) | lo decide il council |

Gli oggetti sotto la soglia di loot del gruppo (di norma i verdi) non sono tracciati e non entrano in sessione. Il costo si annuncia **prima** del roll e non si cambia dopo l'apertura del roll.

## Main-spec e off-spec

- **Main-spec (MS)**: ti serve per la tua spec principale. Si chiede per primo e costa il prezzo pieno.
- **Off-spec (OS)**: si chiede **solo se nessuno ha risposto main-spec**. Costa **0 crediti**.
- **Passo**: non rolli.
- Il transmog è disponibile come terzo tier, spento nel preset.
- Conta solo un `/roll` **1-100**, **il primo del round**, fatto da un personaggio nel raid **con l'addon attivo**. Tutto il resto viene messo da parte e mostrato al master looter con il suo motivo.
- Chi non ha l'addon non può rispondere né vincere (il master looter lo sa prima del primo roll).

## Parità e reroll

1. Vince chi ha meno crediti.
2. Stessi crediti: vince il **roll più alto**.
3. Stessi crediti e stesso roll: un **reroll solo fra i pari**, ripetuto finché ne resta uno. Chi è fuori dalla parità e rolla di nuovo viene ignorato. Dopo cinque reroll di fila decide il master looter.

## Oggetti BoE

Un BoE si rolla come gli altri. Se **nessuno risponde main-spec**, va alla **banca di gilda** (un personaggio scelto nelle regole), non al tier off-spec. Le regole possono mandarlo invece a off-spec, disenchant o free roll.

## Leggendari

Un leggendario **non si rolla**: il council sceglie chi costruisce il progetto leggendario e ogni pezzo della catena va a lui a **2 crediti l'uno**. Le regole possono passare al voto del council, al roll normale o a una coda decisa a inizio season.

## Cosa possono cambiare il master looter e il council

L'addon prepara ogni risultato: a chi, quanti crediti e perché, in parole. Il master looter poi:

- **conferma**: i crediti si addebitano e il risultato si annuncia;
- **rifiuta**: nessun addebito e l'oggetto torna in sessione (riapri il roll, tier successivo, banca o disenchant);
- **modifica**: un altro vincitore o costo, sempre **con un motivo** scelto dall'elenco qui sotto. L'addon mostra come si discosta dalla regola ("fuori fila") e l'evento è segnato come intervento nell'audit.

Il council (gli officer della gilda presenti nel raid) può, sempre con un motivo che finisce nel log: correggere categoria o costo **prima** dell'apertura del roll; dare l'oggetto a un altro candidato in caso di **spreco palese**; darlo a chi **non ha rollato ma è passato per fare il furbo**, a costo pieno; assegnare un leggendario; annullare un'assegnazione; correggere a mano i crediti di un membro. Chi è master looter, council o officer lo decidono i **ranghi di gilda**, e solo il **Guild Master** può cambiare cosa può fare ogni rango e le regole stesse.

## I tre esempi del regolamento

Aurel, Bryn e Corin rispondono tutti main-spec per un anello blu, una spallina e un mantello. Sono i casi che i test del motore eseguono.

**L'anello: stessi crediti, vince il roll più alto.** Tutti e tre hanno 0 crediti. Aurel rolla 45, Bryn 76, Corin 12. Vince **Bryn**, paga 1 credito. La proposta dice: *Main-spec: si chiede per primo e il costo si paga. Stessi crediti degli altri, roll più alto.*

**La spallina: meno crediti vince, il roll non conta.** Aurel ha 0 crediti, Bryn 2, Corin 3. Rollano 34, 90 e 99. Vince **Aurel** con il roll più basso. La proposta dice: *Main-spec: si chiede per primo e il costo si paga. Meno crediti: il roll non conta.*

**Il mantello: parità, quindi reroll fra i pari.** Tutti e tre hanno 1 credito. Aurel rolla 40, Bryn e Corin entrambi 88. Rollano di nuovo solo **Bryn e Corin**. Anche Aurel rolla di nuovo, ma non fa parte della parità, quindi quel roll viene scartato (*Non fa parte di questo round*). Bryn fa 20, Corin 61: vince **Corin**. La proposta dice: *Main-spec: si chiede per primo e il costo si paga. Pari per crediti e roll, ha vinto il reroll fra i pari.* con la segnalazione *Alcuni roll sono stati scartati: controlla l'elenco.*

## Il pool, le dichiarazioni e gli alt

Ogni season la gilda ha **un solo roster a rotazione**: il pool dei main. Ogni main si dichiara una volta per tutta la season:

- **MS1**: la spec principale (obbligatoria). È la spec del pulsante **Main-spec** e quella che guarda la segnalazione del council "upgrade ignorato".
- **MS2**: la seconda spec. È il pulsante **Off-spec**: costa 0 crediti e si apre solo se nessuno ha risposto main-spec.
- **OS** (la spec che ti piacerebbe giocare), **ruolo**, **classe**, **fazione** e i **giorni** in cui puoi raidare, con una breve nota, sono informazioni del roster: la terza spec non dà diritto al roll.

La dichiarazione è **bloccata per tutta la season**. Se qualcosa è sbagliato, la corregge un officer, e la correzione resta nel registro con chi l'ha fatta e quando. Un membro può essere **attivo**, **in prova** (sul sito compare come Trial) o **inattivo** (tiene i crediti, non viene contato e non viene esportato).

**Alt.** Un alt è collegato a un main e **non ha mai crediti suoi**: ciò che vince è addebitato al suo main. Il collegamento lo chiedi dall'addon e lo approva un officer, così nessuno può attaccare un personaggio a un altro giocatore. Vale lo stesso per entrare nel pool: mandi la tua dichiarazione e la approva un officer. **Due fazioni:** chi gioca su entrambe ha **due main, uno per fazione**, collegati come lo stesso giocatore, ciascuno con i propri crediti.

Un officer può compilare una dichiarazione partendo dalla **nota di gilda** (per esempio "Fury / Arms"): l'addon si limita a suggerire le spec che riconosce e l'officer conferma.

## La panchina

Quando vengono più giocatori di quanti ne contenga il raid, **decide il master looter** chi sta fuori; l'addon si limita a proporre. La proposta parte da chi può venire (un "no" sul calendario, o un giorno della settimana che non hai dichiarato, ti toglie dal conteggio: nessuno mette in panchina un assente) e mette in panchina il surplus in quest'ordine:

1. chi ha **chiesto** di stare fuori;
2. chi ha risposto **forse** sul calendario;
3. chi ha **meno panchine** in questa season, così tutti stanno fuori più o meno lo stesso numero di volte;
4. poi chi ha **giocato più serate**, poi in ordine di nome.

Il raid tiene sempre il suo **minimo di tank e healer** (2 e 4 di default, regolabili nelle regole); se i posti non si riempiono altrimenti, il minimo cede e il master looter vede un avviso. Una serata è collegata all'**evento raid ufficiale** della gilda sul calendario del gioco, se c'è, e le sue iscrizioni alimentano la proposta. L'addon legge soltanto il calendario.

**La panchina non costa crediti** nel preset della gilda: chi gioca meno guadagna meno crediti e ha quindi già la precedenza. Una gilda che lo vuole può dare un **bonus** (meno crediti per ogni panchina, mai sotto 0) o un **malus**. Quante volte ciascuno è stato in panchina lo vedono solo gli officer.

## Le parole nel gioco

Il motore non scrive mai frasi: registra codici brevi, e l'addon li trasforma nelle frasi qui sotto nella tua lingua, così la proposta, il log e questo manuale dicono la stessa cosa. Il codice si vede nell'audit accanto alla frase.

### Perché ha vinto (motivi)

| Code | Frase |
|---|---|
| `MAIN_SPEC_TIER` | Main-spec: si chiede per primo e il costo si paga. |
| `OFFSPEC_TIER` | Off-spec: nessuno lo voleva come main-spec e costa 0 crediti. |
| `TRANSMOG_TIER` | Transmog: nessuno lo voleva per la propria spec e costa 0 crediti. |
| `ONLY_CANDIDATE` | L'unico che poteva rollare. |
| `LOWER_CREDITS` | Meno crediti: il roll non conta. |
| `LOWER_CREDITS_PER_NIGHT` | Meno crediti per serata giocata: il roll non conta. |
| `HIGHER_ROLL` | Stessi crediti degli altri, roll più alto. |
| `REROLL_WON` | Pari per crediti e roll, ha vinto il reroll fra i pari. |
| `BOE_BANK` | BoE che nessuno ha chiesto come main-spec: va alla banca di gilda. |
| `FALLBACK_ML` | Nessuno poteva rollare: decide il master looter. |
| `FALLBACK_DISENCHANT` | Nessuno poteva rollare: l'oggetto viene disincantato. |
| `FALLBACK_FREE_ROLL` | Nessuno lo voleva: free roll aperto a tutti i presenti, vince il roll più alto. |
| `TIE_ML` | Ancora pari: decide il master looter. |
| `ML_CHOICE` | Scelto dal master looter. |
| `REJECTED_TO_BANK` | La proposta è stata rifiutata: l'oggetto va alla banca di gilda. |
| `REJECTED_TO_DISENCHANT` | La proposta è stata rifiutata: l'oggetto viene disincantato. |

### Segnalazioni su una proposta (cosa controllare)

| Code | Frase |
|---|---|
| `DISCARDED_ROLLS` | Alcuni roll sono stati scartati: controlla l'elenco. |
| `COST_BY_COUNCIL` | Il costo lo decide il council. |
| `NO_BANK_CHARACTER` | Non c'è un personaggio banca: scegli chi lo riceve. |
| `NO_DISENCHANTER` | Non c'è un disincantatore: scegli chi lo riceve. |
| `TIE_UNRESOLVED` | Una parità che le regole non sciolgono: decide il master looter. |
| `REROLL_LIMIT` | Troppi reroll di fila: decide il master looter. |
| `FREE_ROLL_EMPTY` | Nessuno ha rollato nel free roll. |
| `AFTER_REJECT` | Questa è una nuova proposta dopo un rifiuto. |
| `OUT_OF_ORDER` | Fuori fila: il vincitore non è quello scelto dalle regole. |
| `COST_CHANGED` | Il costo non è quello scelto dalle regole. |
| `ML_DECIDED` | Le regole non avevano un vincitore o un costo: ha deciso il master looter. |

### Perché un roll è stato scartato

| Code | Frase |
|---|---|
| `NOT_1_100` | Non è un roll 1-100. |
| `BAD_VALUE` | Il valore del roll non è valido. |
| `BAD_ROLL` | Il roll non si è potuto leggere. |
| `BEFORE_OPEN` | Rollato prima dell'apertura del round. |
| `AFTER_CLOSE` | Rollato dopo la chiusura del round. |
| `NOT_PRESENT` | Non è nel raid. |
| `NO_ADDON` | L'addon non è attivo. |
| `NOT_ELIGIBLE` | Non fa parte di questo round. |
| `DUPLICATE` | Un secondo roll nello stesso round: conta solo il primo. |
| `TIER_EMPTY` | Nessuno di quel tier poteva rollare: questi roll sono stati messi da parte. |

### Da dove viene un costo o una categoria

| Code | Frase |
|---|---|
| `OVERRIDE_COST` | Costo fissato dal council per questo oggetto. |
| `OVERRIDE_CATEGORY` | Categoria fissata dal council per questo oggetto. |
| `MATRIX` | Costo dalla tabella di categorie e qualità. |
| `NOT_TRACKED` | Sotto la soglia di loot: non entra nella sessione. |
| `COUNCIL` | Il costo lo decide il council. |
| `NO_CELL` | La tabella non ha un costo per questo oggetto: lo decide il council. |
| `UNKNOWN_RESPONSE` | Risposta sconosciuta. |
| `QUEST` | Oggetto di quest o token. |
| `SUBCLASS` | Categoria dal tipo di oggetto. |
| `EQUIPLOC` | Categoria dallo slot. |
| `CLASS` | Categoria dalla classe di oggetto. |
| `DEFAULT` | Nessuna regola vale: la categoria è Altro. |

### Come sono stati stabiliti i crediti di un nuovo membro

| Code | Frase |
|---|---|
| `START` | Entrato prima della prima serata: i crediti iniziali della season. |
| `AVERAGE` | Nuovo arrivato: la media dei crediti del roster, arrotondata. |
| `MEDIAN` | Nuovo arrivato: la mediana dei crediti del roster. |
| `MIN` | Nuovo arrivato: i crediti più bassi del roster. |
| `ZERO` | Nuovo arrivato: parte da 0 crediti. |
| `FIXED` | Nuovo arrivato: un numero fisso di crediti. |
| `EMPTY_BASIS` | Nuovo arrivato, ma nessuno con cui confrontarsi: i crediti iniziali della season. |

### Motivi che il master looter sceglie per cambiare una proposta o un oggetto

| Code | Frase |
|---|---|
| `WRONG_CATEGORY` | La categoria o il costo erano sbagliati. |
| `COUNCIL_COST` | Il council ha dato un prezzo all'oggetto. |
| `OBVIOUS_WASTE` | Spreco palese: dato a un altro candidato. |
| `PASSED_TO_GAME` | Passato per fare il furbo: dato a chi non ha rollato, a costo pieno. |
| `COUNCIL_VOTE` | Deciso dal voto del council. |
| `LEGENDARY` | Un pezzo di una catena leggendaria. |
| `MISTAKE` | Un errore del master looter o dell'addon. |
| `OTHER` | Un altro motivo, scritto dal master looter. |

### Fasi automatiche

| Code | Frase |
|---|---|
| `TIMER` | Il round si è chiuso allo scadere del timer. |
| `ALL_ROLLED` | Il round si è chiuso perché tutti avevano rollato. |
| `AUTO_FAILED` | L'assegnazione automatica non è riuscita: decide il master looter. |

### Cambi dei ranghi di gilda

L'addon legge i ranghi dal roster della gilda, per posizione e mai per nome. Dopo l'accesso aspetta il roster: finché non arriva, gli eventi degli altri giocatori che richiedono un rango aspettano e vengono controllati appena arriva, e i pulsanti che scrivono nel registro restano spenti. Quando il Guild Master riordina, elimina o aggiunge ranghi, riceve un messaggio in chat (di nuovo a ogni accesso finché la tabella dei permessi non è stata ricontrollata), con i permessi che puntano a un rango che non esiste più. Quando la gilda ha un nuovo Guild Master, il potere di cambiare le regole passa a lui appena il gioco lo mostra; le modifiche del Guild Master precedente restano valide. Entrambi i giocatori lo leggono in chat.

| Code | Frase |
|---|---|
| `RENAMED` | Un rango di gilda è stato rinominato: nulla da fare. |
| `REORDERED` | I ranghi di gilda sono stati riordinati: il Guild Master deve ricontrollare la tabella dei permessi. |
| `REMOVED` | Un rango di gilda è stato eliminato: il Guild Master deve ricontrollare la tabella dei permessi. |
| `ADDED` | Un rango di gilda è stato aggiunto: il Guild Master deve ricontrollare la tabella dei permessi. |

### Perché un'azione è stata rifiutata

| Code | Frase |
|---|---|
| `BAD_STATE` | Non è possibile in questo punto della sessione. |
| `LOCKDOWN` | Il gioco è in lockdown (combattimento con un boss): aspetta che finisca. |
| `UNKNOWN_INPUT` | Azione sconosciuta. |
| `NOT_ML` | Solo il master looter può farlo. |
| `PAUSED` | La sessione è in pausa. |
| `NOT_PAUSED` | La sessione non è in pausa. |
| `ENDED` | La sessione è finita. |
| `READ_ONLY` | I dati salvati vengono da una versione più recente dell'addon: sono in sola lettura. |
| `REASON_REQUIRED` | Serve un motivo. |
| `ITEM_SETTLED` | Questo oggetto è già stato assegnato. |
| `CATEGORY_LOCKED` | La categoria non si cambia dopo l'apertura del roll. |
| `NOTHING_CHANGED` | Non è cambiato nulla. |
| `ITEM_IN_PROGRESS` | Un altro oggetto è ancora in corso. |
| `ITEM_NOT_PENDING` | Questo oggetto non è in attesa del roll. |
| `RESPONSES_CLOSED` | Le risposte sono chiuse. |
| `BAD_RESPONSE` | Questa risposta non esiste. |
| `RESPONSE_LOCKED` | Hai già rollato: la risposta non si cambia più. |
| `NO_ROUND_OPEN` | Nessun round è aperto. |
| `NO_TIER` | La proposta non ha un tier da cui proseguire. |
| `NO_WINNER` | Non c'è ancora un vincitore. |
| `NO_COST` | Il costo non è ancora stabilito. |
| `NO_LEDGER` | Non c'è un registro su cui scrivere. |
| `VOTE_OPEN` | Il voto del council è ancora aperto. |
| `VOTE_CLOSED` | Il voto del council è chiuso. |
| `NOT_COUNCIL_MODE` | Le assegnazioni non si decidono a voto del council. |
| `NO_VOTES` | Nessuno ha votato. |
| `VOTE_TIE` | Il voto è in parità: decide il master looter. |
| `NOT_ASSIGNED` | Questo oggetto non è ancora stato assegnato. |
| `WRONG_PLAYER` | L'oggetto è andato a un altro giocatore. |
| `NOT_PRESENT` | Non è nel raid. |
| `NO_ADDON` | L'addon non è attivo: non può rollare. |
| `NOT_TRACKED` | Sotto la soglia di loot: non entra nella sessione. |
| `UNKNOWN_TYPE` | Tipo di evento sconosciuto: viene da una versione più recente dell'addon. |
| `REF_MISSING` | L'evento da annullare non è nel registro. |
| `REF_NOT_VOIDABLE` | Si può annullare solo un'assegnazione o una correzione di crediti. |
| `ALREADY_VOIDED` | Già annullato. |
| `DUPLICATE` | Già nel registro. |
| `CONFLICT` | Nel registro c'è già un altro evento con lo stesso id. |
| `REFUSED` | Rifiutato. |
| `PENDING` | In attesa che il roster di gilda si carichi: verrà ricontrollato. |
| `NOT_IN_GUILD` | L'autore non è nella gilda. |
| `NOT_GM` | Solo il Guild Master può cambiarlo. |
| `RANK_TOO_LOW` | Il rango di gilda è troppo basso per questo. |
| `CONFIRM_REQUIRED` | C'è una season aperta: conferma la modifica. |
| `UNCHANGED` | Nulla è cambiato. |
| `UNKNOWN_PRESET` | Preset sconosciuto. |
| `SEASON_UNKNOWN` | Season sconosciuta. |
| `SEASON_CLOSED` | La season è chiusa. |
| `SEASON_EXISTS` | Esiste già una season con questo id. |
| `SEASON_ALREADY_OPEN` | C'è già un'altra season aperta: chiudila prima. |
| `NOT_IN_PACK` | Quel raid non è nel pacchetto della season. |
| `DIFFICULTY` | Difficoltà sconosciuta. |
| `NOT_MEMBER` | Non fa parte del pool. |
| `ALREADY_JOINED` | Già nel pool. |
| `IS_ALT` | È un alt collegato: i crediti sono del suo main. |
| `MAIN_UNKNOWN` | Il main non è nel pool. |
| `ALT_IS_MAIN` | Questo personaggio è un main: non può essere un alt. |
| `ALREADY_LINKED` | Già collegato a un main. |
| `FACTION_MISMATCH` | Main e alt sono di fazioni diverse. |
| `MS1_REQUIRED` | La spec principale (MS1) è obbligatoria. |
| `CLASS_REQUIRED` | La classe è obbligatoria. |
| `ROLE_REQUIRED` | Il ruolo è obbligatorio. |
| `DUPLICATE_SPEC` | La stessa spec è dichiarata due volte. |
| `SPEC_UNKNOWN` | Specializzazione sconosciuta. |
| `SPEC_CLASS` | Una spec dichiarata non appartiene alla classe. |
| `ROLE_MISMATCH` | Il ruolo non è quello della spec principale. |
| `TWIN_SELF` | Un main non può essere il proprio gemello. |
| `TWIN_UNKNOWN` | Il main dell'altra fazione non è nel pool. |
| `FACTION_REQUIRED` | Servono la fazione di entrambi i main per collegarli come un solo giocatore. |
| `TWIN_FACTION` | Un giocatore ha un main per fazione: l'altro main è della stessa fazione. |
| `TWIN_TAKEN` | Quel main fa già parte della coppia di un altro giocatore. |
| `REQUEST_UNKNOWN` | Quella richiesta non esiste. |
| `REQUEST_CLOSED` | Quella richiesta è già stata decisa. |
| `REQUEST_PENDING` | C'è già un'altra richiesta per questo personaggio in attesa di un officer. |
| `REQUEST_LIMIT` | Troppe richieste in attesa di un officer. |

### Stato di un membro del pool

| Code | Frase |
|---|---|
| `ACTIVE` | Attivo |
| `TRIAL` | In prova |
| `INACTIVE` | Inattivo |

### Risposte

| Code | Frase |
|---|---|
| `MS` | Main-spec |
| `OS` | Off-spec |
| `TMOG` | Transmog |
| `PASS` | Passo |

### Cosa fa una proposta con l'oggetto

| Code | Frase |
|---|---|
| `AWARD` | A un giocatore |
| `BANK` | Alla banca di gilda |
| `DISENCHANT` | Da disincantare |
| `ML` | Decide il master looter |

### Cosa succede a un oggetto rifiutato

| Code | Frase |
|---|---|
| `PENDING` | Rimetti l'oggetto in coda: lo riapri dopo |
| `REOPEN` | Riapri subito il roll |
| `NEXT_TIER` | Passa al tier successivo |
| `BANK` | Mandalo alla banca di gilda |
| `DISENCHANT` | Disincantalo |

### Stati di una sessione e di un oggetto

| Code | Frase |
|---|---|
| `WAITING` | In attesa che un boss sia ucciso e il corpo aperto |
| `COLLECTING` | Lettura dei drop |
| `ANNOUNCING` | Annuncio degli oggetti al raid |
| `ROLLING` | Risposte e roll aperti |
| `COMPUTING` | Calcolo del vincitore |
| `PROPOSAL` | In attesa della decisione del master looter |
| `ENDED` | Sessione finita |
| `PENDING` | Non ancora rollato |
| `ASSIGNED` | Assegnato, non ancora consegnato |
| `DELIVERED` | Consegnato |

### Tipi di evento del registro (scheda Cronologia)

| Code | Frase |
|---|---|
| `SEASON_OPENED` | Season aperta |
| `SEASON_CLOSED` | Season chiusa |
| `MEMBER_JOINED` | Membro entrato nel pool |
| `MEMBER_LINKED_ALT` | Alt collegato a un main |
| `NIGHT_OPENED` | Serata aperta |
| `NIGHT_CLOSED` | Serata chiusa |
| `LINEUP_CHANGED` | Formazione cambiata |
| `ROSTER_CHANGED` | Roster cambiato |
| `ENCOUNTER_KILLED` | Boss ucciso |
| `PROGRESS_SET` | Progressi impostati a mano |
| `DROP_SEEN` | Drop visto |
| `ITEM_AWARDED` | Oggetto assegnato |
| `AWARD_VOIDED` | Assegnazione o correzione annullata |
| `CREDITS_ADJUSTED` | Crediti corretti a mano |
| `LEGENDARY_PROJECT_OPENED` | Progetto leggendario aperto |
| `LEGENDARY_PROJECT_PAID` | Pezzo leggendario pagato |
| `LEGENDARY_PROJECT_CLOSED` | Progetto leggendario chiuso |
| `CONFIG_CHANGED` | Regole cambiate |
| `PERMISSIONS_CHANGED` | Permessi cambiati |

### Preset delle regole

| Code | Frase |
|---|---|
| `PATTO` | Patto (il regolamento attuale della gilda) |
| `ROLL_ONLY` | Solo roll |
| `LOOT_COUNCIL` | Loot council puro |
| `EPGP_SIMPLE` | EPGP semplice |

