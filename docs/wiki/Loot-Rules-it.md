# Regole del loot

> **In sviluppo.** Questa pagina descrive le regole che il motore dell'addon già segue (scritto e provato offline; nulla è ancora stato provato nel gioco). Le finestre che le usano arrivano nelle versioni successive. [English](Loot-Rules)

L'addon fa i conti, il master looter decide. Queste sono le regole della gilda (preset "Patto") come le applica il motore. Ogni valore qui sotto può essere cambiato dal Guild Master nelle regole, tranne dove è scritto "fisso".

## Crediti

- I crediti **non si salvano**: si calcolano dal registro, l'elenco di tutto quello che è successo (assegnazioni, correzioni, nuovi membri). Una correzione è una nuova voce, mai una cancellazione.
- Una season fa partire tutti da **0 crediti**. La season è un pacchetto di raid (10, 20 e 40 giocatori hanno una sola tabella di crediti, anche Normal e Veteran).
- **Solo i main** guadagnano e spendono crediti. Un alt è collegato al suo main e usa i crediti del main.
- Meno crediti significa una posizione migliore: **vince chi ha meno crediti**, e il roll serve solo a sciogliere le parità.
- Il roster è **dinamico**: si può entrare a season iniziata. Un nuovo arrivato parte con **i crediti del giocatore che ne ha meno** (fra i membri che hanno giocato almeno una serata), così non salta la fila e non parte nemmeno dietro all'ultimo. Il numero si scrive una volta e resta stabile.
- **Saltare una serata ufficiale costa +1 credito** (vedi [Assenze](#assenze) più sotto).

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
- Il transmog è disponibile come terzo tier, spento nel preset; il popup non ha un pulsante per lui (solo Passo, Tira Main-spec e Tira Off-spec).
- Conta solo un `/roll` **1-100**, **il primo del round**, fatto da un personaggio nel raid **con l'addon attivo**. Tutto il resto viene messo da parte e mostrato al master looter con il suo motivo.
- Il roll deve venire dal **pulsante Tira del popup** (regola *I roll contano solo dal pulsante Roll del popup*, accesa di norma): un `/roll` scritto a mano viene messo da parte come `NOT_FROM_BUTTON` e non consuma il turno del giocatore. Il pulsante avvisa l'addon del master looter del clic subito prima del roll del gioco; il roll resta quello del gioco. Chi ha un addon più vecchio di questa regola rolla come prima finché non aggiorna.
- Chi non ha l'addon non può rispondere né vincere (il master looter lo sa prima del primo roll).

## Parità e reroll

1. Vince chi ha meno crediti.
2. Stessi crediti: vince il **roll più alto**.
3. Stessi crediti e stesso roll: un **reroll solo fra i pari**, ripetuto finché ne resta uno. Chi è fuori dalla parità e rolla di nuovo viene ignorato. Dopo cinque reroll di fila decide il master looter.

## Oggetti BoE

Un BoE si rolla come gli altri: stessa categoria, stesso costo. Chi lo prende **main-spec** paga i suoi crediti come per ogni altro oggetto. Se **nessuno risponde main-spec** (o chi ha risposto main-spec non rolla), decide il *fallback BoE* delle regole:

| Fallback | Cosa succede |
|---|---|
| **bank** (preset) | Va alla **banca di gilda**: lo riceve il personaggio banca scelto nelle regole, **senza costo**. Il registro lo segna *alla banca di gilda*. |
| **offspec** | Lo rolla il tier off-spec, come ogni oggetto, al costo off-spec. |
| **disenchant** | Lo riceve chi disincanta, scelto nelle regole, senza costo. |
| **freeroll** | Un roll libero fra chi è nel raid; chi vince paga il costo del roll libero delle regole (0 nel preset). |

Un oggetto per la banca **non costa mai crediti a nessuno**, anche quando il master looter manda in banca una proposta o dà l'oggetto della banca a un raider perché lo tenga. Se le regole non indicano un personaggio banca, la proposta non ha vincitore e il master looter sceglie chi lo riceve. Un oggetto che si lega alla raccolta non prende mai questo fallback.

**L'oro della vendita.** Quando la banca vende l'oggetto, un officer registra il prezzo con `/fdcp bank sold <n> <prezzo>` (oro come `120` o `12.5`, o monete come `12o 30a 5r`): la vendita va nel registro e i crediti di nessuno cambiano. Registrarla di nuovo corregge il prezzo; se l'assegnazione alla banca viene annullata, la sua vendita non conta più. `/fdcp bank` mostra il fallback in vigore, il personaggio banca, gli oggetti della banca della season con il prezzo e il totale (vedi [[Comandi|Commands-it]]).

## Leggendari

Nel preset un leggendario **non si rolla**: il council apre un **progetto leggendario** (un nome, l'oggetto finale, gli id degli oggetti della catena e il **costruttore** che sceglie) e quando cade un pezzo della catena l'addon lo riconosce e lo propone direttamente al costruttore a **2 crediti** (il *costo del pezzo della catena* delle regole). Modalità e costo stanno nelle regole della gilda:

| Modalità | Cosa succede a un pezzo della catena |
|---|---|
| **council** (preset) | Nessun roll: va al costruttore del progetto, al costo del pezzo della catena. |
| **vote** | Nessun roll: il council vota (prima viene proposto il costruttore), vince la maggioranza, stesso costo. Il master looter chiude il voto prima di confermare. |
| **roll** | Si rolla come ogni altro oggetto: il costo lo decide la categoria e il progetto non viene consultato. |
| **queue** | Nessun roll: va al primo della lista del progetto, decisa a inizio season, che è nel raid; stesso costo. |

Se il costruttore non è nel raid (o nessuno della lista lo è), o il progetto non ha un costruttore, la proposta non ha un vincitore e una segnalazione dice perché: il master looter sceglie a chi va il pezzo, con un motivo, oppure lo manda in banca. Un pezzo dato a un personaggio finisce nel progetto come **pagato** (i crediti sono quelli dell'assegnazione, quindi annullarla li restituisce e il pezzo non conta più). Un pezzo può appartenere a un solo progetto aperto alla volta. Quando il leggendario è costruito il progetto si chiude come **completato**; se la gilda rinuncia, come **abbandonato**. Un progetto appartiene alla sua season. Finché non arriva la finestra del council, i progetti si gestiscono con `/fdcp legendary` (vedi [[Comandi|Commands-it]]).

## Cosa possono cambiare il master looter e il council

L'addon prepara ogni risultato: a chi, quanti crediti e perché, in parole. Il master looter poi:

- **conferma**: i crediti si addebitano e il risultato si annuncia;
- **rifiuta**: nessun addebito e l'oggetto torna in sessione (riapri il roll, tier successivo, banca o disenchant);
- **modifica**: un altro vincitore o costo, sempre **con un motivo** scelto dall'elenco qui sotto. L'addon mostra come si discosta dalla regola ("fuori fila") e l'evento è segnato come intervento nell'audit.

Il council (gli officer della gilda presenti nel raid, o la lista di personaggi che la gilda scrive nelle sue regole) può, sempre con un motivo che finisce nel log: correggere categoria o costo **prima** dell'apertura del roll (a roll aperto l'addon rifiuta); dare l'oggetto a un altro candidato in caso di **spreco palese**; darlo a chi **non ha rollato ma è passato per fare il furbo**, a costo pieno; assegnare un leggendario; annullare un'assegnazione (l'assegnazione resta nel log, segnata come annullata, e i crediti tornano); correggere a mano i crediti di un membro. Senza motivo non si scrive nulla, e ogni intervento è elencato nell'audit della season (`/fdcp council audit`, o **Loot › Council** nella finestra: [[Council|Council-it]]). Chi è master looter, council o officer lo decidono i **ranghi di gilda**, e solo il **Guild Master** può cambiare cosa può fare ogni rango e le regole stesse.

**Il voto del council.** Spento nel preset. Con la modalità di assegnazione **council** il council vota su ogni proposta e il master looter chiude il voto prima di confermare: decide la maggioranza stretta (parità, o nessun voto, lasciano la decisione al master looter). Con il **voto del council** acceso nelle altre modalità i voti informano soltanto il master looter, che li vede prima di confermare; in modalità automatica un voto per un altro giocatore ferma l'assegnazione automatica. Ognuno vota solo per sé, dal proprio gioco; i voti finiscono scritti con l'assegnazione. Vedi la [[Guida del master looter|Master-Looter-Guide-it]], "Il council: interventi e voto".

**Segnalazioni del council.** Per rendere visibili in tempo i casi evidenti, l'addon alza due segnalazioni appena arrivano le risposte: **upgrade ignorato** (un raider passa su un pezzo che per la sua main-spec è un upgrade grande) e **possibile spreco** (il primo in fila ha un upgrade piccolo o nessuno, un altro candidato main-spec uno grande). Guardano solo la main-spec (MS1), non cambiano mai il vincitore da sole e fermano l'assegnazione automatica finché il master looter non guarda; intervenire è una modifica con il suo motivo. Le regole della gilda dicono se le segnalazioni sono accese, il rapporto dello spreco (preset 2) e chi oltre al master looter vede badge e segnalazioni (preset: il council). Vedi la [[Guida del master looter|Master-Looter-Guide-it]], "Segnalazioni del council".

## Come si svolge una sessione di loot

La sessione gira solo sul client del master looter; gli altri devono solo rispondere e rollare.

- **Dopo l'uccisione.** Una sessione di loot si apre appena muore un boss, mai durante il combattimento, e solo sul client del master looter.
- **Il cadavere.** Quando il master looter apre il cadavere, gli oggetti dalla soglia di loot in su entrano nella sessione con la loro categoria e il loro costo. Se in quel momento la chat è bloccata o è in corso un altro boss, l'addon aspetta e prende gli oggetti appena finisce.
- **Da sola.** L'addon annuncia gli oggetti e apre i roll un oggetto alla volta. Apre anche il reroll fra i pari, il round off-spec quando nessuno vuole un oggetto per la main spec, e il fallback. Un round si chiude quando tutti hanno rollato o quando scade il suo timer. **Pausa** ferma ogni timer.
- **Roll trattenuti dal gioco.** Mentre il gioco nasconde i messaggi dei roll (in istanza, durante un lockdown), un round non si chiude mai per il timer: i roll fatti in tempo contano lo stesso.
- **Decide il master looter.** L'addon scrive la proposta: chi, quanto e perché. L'oggetto si addebita solo quando il master looter lo conferma. Ogni assegnazione entra nel registro con i suoi motivi e le sue segnalazioni.
- **/reload o disconnessione.** La sessione si salva a ogni passo. Dopo un `/reload` o una disconnessione riparte esattamente da dove era, e le finestre del raid si rimettono in pari.
- **Il boss successivo.** Quando muore il boss successivo, la sessione precedente si chiude se nessun oggetto è in corso. I suoi oggetti mai rollati restano elencati per il master looter.
- **Gli altri officer.** Vedono la sessione in sola lettura; i raider vedono il popup del loro oggetto.

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

## Assenze

Un membro del roster della season riceve **+1 credito** (vince chi ne ha meno, quindi è una penalità) per una serata ufficiale in cui:

- **non si è iscritto** al raid nel calendario del gioco (nessuna risposta, oppure "no") e non ha giocato;
- **si è iscritto ma non è venuto** ("sì" o "forse", e non ha giocato);
- **si è messo in panchina da solo**, di sua iniziativa (il pulsante **Mettimi in panchina** nella scheda Serata).

**Nessuna penalità** per chi era nel raid (anche per un solo boss) e per chi è stato **messo in panchina dagli officer**: la rotazione non costa mai crediti.

Alla chiusura della serata l'addon elenca le penalità proposte e un officer le conferma con **un clic**; prima non si scrive nulla, a meno che il Guild Master non accenda *Scrivi le penalità di assenza alla chiusura, senza conferma*. Ogni penalità è una correzione dei crediti con il motivo *Assenza da una serata ufficiale*: si vede nel log e nell'audit, e un officer la può annullare come ogni correzione (i crediti tornano quelli di prima). Se il calendario non ha un evento raid per la serata, l'assente è penalizzato lo stesso (*assente, iscrizioni non note*). L'importo (1) e la conferma sono regole della gilda, in Impostazioni › Regole › Membri.

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
| `LEGENDARY_BUILDER` | Un pezzo di una catena leggendaria: va al costruttore del progetto, senza roll. |
| `LEGENDARY_QUEUE` | Un pezzo di una catena leggendaria: va al primo della lista del progetto che è presente. |

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
| `UPGRADE_IGNORED` | Upgrade ignorato: qualcuno ha passato un upgrade grande per la sua main-spec. |
| `POSSIBLE_WASTE` | Possibile spreco: il primo in fila ci guadagna poco, un altro candidato molto. |
| `NO_BUILDER` | Pezzo leggendario: il progetto non ha un costruttore. Scegli a chi va. |
| `BUILDER_ABSENT` | Pezzo leggendario: il costruttore non è nel raid. Scegli a chi va. |
| `QUEUE_EMPTY` | Pezzo leggendario: nessuno della lista del progetto è nel raid. Scegli a chi va. |

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
| `NOT_FROM_BUTTON` | Scritto a mano: conta solo il pulsante Roll del popup. |
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
| `DUPLICATE_AWARD` | Lo stesso oggetto è stato assegnato due volte. |
| `PENALTY` | Una penalità decisa dal council. |
| `BONUS` | Un bonus deciso dal council. |
| `ABSENCE` | Assenza da una serata ufficiale. |

Gli ultimi quattro, e alcuni degli altri, sono i motivi di un'assegnazione annullata o di una correzione dei crediti a mano.

### Perché una serata saltata è penalizzata

| Codice | Frase |
|---|---|
| `NOT_SIGNED_UP` | non iscritto |
| `NO_SHOW` | iscritto, non presente |
| `SELF_BENCH` | si è messo in panchina da solo |
| `ABSENT` | assente, iscrizioni non note |

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
| `NOT_COUNCIL_MODE` | Il council non vota in questa sessione. |
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
| `NOT_COUNCIL` | Solo un membro del loot council può farlo. |
| `NO_PROPOSAL` | Non c'è nessuna proposta da votare. |
| `BAD_CHOICE` | Scrivi il giocatore che voti. |
| `BAD_DELTA` | Scrivi i crediti come numero diverso da zero (al massimo 1000 in più o in meno). |
| `NO_SEASON` | Nessuna season è aperta. |
| `NOT_READY` | I dati della gilda non sono ancora caricati. |
| `PROJECT_UNKNOWN` | Questo progetto leggendario non esiste. |
| `PROJECT_CLOSED` | Il progetto leggendario è già chiuso. |
| `NOT_A_PIECE` | L'oggetto non è un pezzo di quella catena leggendaria. |
| `PIECE_TAKEN` | Un altro progetto leggendario aperto ha già uno di questi pezzi. |
| `BAD_NAME` | Dai un nome al progetto (al massimo 48 caratteri). |
| `BAD_ITEM` | L'oggetto finale non è un oggetto valido. |
| `BAD_PIECES` | Elenca i pezzi della catena: da 1 a 40 oggetti diversi. |
| `BAD_OUTCOME` | Un progetto finisce completato o abbandonato. |
| `NOT_BANK_ITEM` | Quell'oggetto non è andato alla banca di gilda. |
| `BANK_ITEM_VOIDED` | Quell'assegnazione alla banca di gilda è stata annullata. |
| `BAD_GOLD` | Il prezzo deve essere una somma in oro, 0 o più. |

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

### Badge di upgrade

Come un oggetto si confronta con quello che un giocatore indossava durante lo scontro col boss (vedi [[Suggerimenti di upgrade|Upgrade-Hints-it]]).

| Code | Frase |
|---|---|
| `MAJOR` | Upgrade grande |
| `MEDIUM` | Upgrade medio |
| `MINOR` | Upgrade piccolo |
| `NONE` | Nessun upgrade |
| `NOT_COMPARABLE` | Non confrontabile |
| `UNUSABLE` | Non usabile |

### Perché un oggetto non si può usare o confrontare

| Code | Frase |
|---|---|
| `ARMOR_TYPE` | La tua classe non può indossare questo tipo di armatura. |
| `WEAPON_TYPE` | La tua classe non può usare questo tipo di arma. |
| `DUAL_WIELD` | La tua classe o spec non può impugnare due armi. |
| `CLASS_RESTRICTED` | Questo oggetto è per altre classi. |
| `SPEC_RESTRICTED` | Questo oggetto non è per la tua specializzazione. |
| `UNKNOWN_CLASS` | L'addon non conosce la tua classe. |
| `NOT_EQUIPPABLE` | Non è un pezzo di equipaggiamento: l'addon non può confrontarlo. |
| `COSMETIC` | Una camicia o un tabard: non c'è nulla da confrontare. |
| `TWO_HAND_EQUIPPED` | Indossi un'arma a due mani: questo oggetto va nell'altra mano. |
| `NO_ITEM_LEVEL` | Il gioco non ha dato il livello di questo oggetto. |
| `NO_QUALITY` | Il gioco non ha ancora caricato la qualità dell'oggetto: il badge arriva appena la carica. |
| `EMPTY_SLOT` | Non indossi niente in quello slot. |
| `OLD_SEASON` | Il tuo pezzo è un epico di una season precedente: conta come un raro. |
| `ITEM_OLD_SEASON` | Questo oggetto è un epico di una season precedente: conta come un raro. |

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
| `SEASON_BAND_SET` | Fascia di item level della season |
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
| `BANK_ITEM_SOLD` | Oggetto della banca di gilda venduto |
| `CONFIG_CHANGED` | Regole cambiate |
| `PERMISSIONS_CHANGED` | Permessi cambiati |

### Come è finito un progetto leggendario

| Codice | Frase |
|---|---|
| `COMPLETED` | completato |
| `ABANDONED` | abbandonato |

### Preset delle regole

| Code | Frase |
|---|---|
| `PATTO` | Patto (il regolamento attuale della gilda) |
| `ROLL_ONLY` | Solo roll |
| `LOOT_COUNCIL` | Loot council puro |
| `EPGP_SIMPLE` | EPGP semplice |

