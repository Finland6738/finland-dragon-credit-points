# Comandi

> **In sviluppo.** Per ora esistono solo i comandi qui sotto; ogni comando nuovo viene aggiunto a questa pagina quando arriva. [English](Commands)

Tutto parte da `/fdcp`: da solo apre (o chiude) la finestra principale.

| Comando | Cosa fa |
|---|---|
| `/fdcp` o `/fdcp toggle` | Apre la finestra principale, oppure la chiude se è aperta. |
| `/fdcp help` | Elenca i comandi. |
| `/fdcp theme [nebula\|aurora\|drago]` | Mostra il tema, oppure lo imposta. Cambia subito, senza `/reload`. |
| `/fdcp effects [on\|off]` | Mostra o imposta gli effetti neon (bagliori e ombre). Vedi il [[Giro dell'interfaccia|Interface-Tour-it]]. |
| `/fdcp animations [on\|off]` | Mostra o imposta le animazioni (le transizioni brevi). |
| `/fdcp weights [on\|off\|import <spec> <stringa>\|show <spec>\|reset <spec\|all>]` | I tuoi pesi delle statistiche per i suggerimenti di upgrade: importali da una stringa tipo Pawn, mostrali, accendili o spegnili, toglili. Vedi [Suggerimenti di upgrade](Upgrade-Hints-it). |
| `/fdcp wish [list\|add <oggetto>\|remove <oggetto>\|clear]` | La tua lista best-in-slot: il popup te lo ricorda quando uno dei pezzi è in palio. Vedi [Suggerimenti di upgrade](Upgrade-Hints-it). |
| `/fdcp council [vote <giocatore>\|awards\|void <n> <motivo>\|adjust <giocatore> <crediti> <motivo>\|audit]` | Il loot council: da solo, se ne fai parte. `vote` manda il tuo voto sulla proposta aperta; `awards` elenca le assegnazioni della season che si possono annullare, `void` ne annulla una; `adjust` corregge a mano i crediti di un membro; `audit` elenca gli interventi della season. Ogni correzione vuole un motivo (il comando li elenca). Vedi [Guida del master looter](Master-Looter-Guide-it#il-council-interventi-e-voto). Le stesse cose dalla pagina **Loot › Council**: [[Council|Council-it]]. |
| `/fdcp legendary [<n>\|open <nome>; <oggetto finale>; <pezzi della catena>; <costruttore o ->[; <lista>]\|complete <n>\|abandon <n>]` | I progetti leggendari della season: da solo, la modalità, il costo di un pezzo e l'elenco; `<n>` mostra i pezzi di un progetto, la sua lista e i pezzi pagati. `open` apre un progetto (oggetti come link, shift-clic, o come id; `-` per nessun costruttore; la lista è un elenco di nomi per la modalità *queue*), `complete` e `abandon` ne chiudono uno. Solo gli officer (il rango del master looter). Vedi [Regole del loot](Loot-Rules-it#leggendari). Le stesse cose dalla pagina **Loot › Council**: [[Council|Council-it]]. |
| `/fdcp bank [sold <n> <prezzo>]` | La banca di gilda: da solo, cosa succede a un BoE che nessuno chiede main-spec, il personaggio banca, gli oggetti della banca della season con il prezzo di vendita e il totale. `sold <n> <prezzo>` registra l'oro per cui è stato venduto l'oggetto `<n>` (oro come `120` o `12.5`, o monete come `12o 30a 5r`); registrarlo di nuovo lo corregge. I crediti di nessuno cambiano. Officer (il rango che guida le serate). |
| `/fdcp about` | Apre la pagina **Info** delle Impostazioni: chi ha fatto l'addon, la licenza e i link da copiare ([[Crediti e info|About-it]]). `/fdcp about chat` la scrive invece in chat. |
| `/fdcp debug [chat]` | Apre il **rapporto bug** in una finestra con il testo selezionato, pronto da copiare in una issue su GitHub ([[Segnalare un bug|Reporting-Bugs-it]]); `chat` lo scrive nella chat. Mostra cosa offre il client di gioco all'addon: versione e build del client, poi le **funzioni** che servono all'addon (master loot, finestra del loot, messaggi dei roll, statistiche degli oggetti, specializzazioni, ranghi di gilda, calendario, roster del gruppo, messaggi addon) e ogni **API** che usa, ciascuna con il suo stato, poi i contatori dei messaggi dell'addon (vedi sotto). |
| `/fdcp language [auto\|<codice>]` | Mostra la lingua dell'addon, oppure imposta quella personale (`auto` segue il client di gioco). La modifica vale dopo `/reload`. Per ora esistono inglese (`enUS`) e italiano (`itIT`). |

## Come leggere `/fdcp debug`

La prima riga indica la build del client. Poi ogni funzione e ogni API compare come `[stato] nome`, con una breve nota quando c'è:

| Stato | Significato |
|---|---|
| `available` | Il client ce l'ha e ha risposto. |
| `missing` | Il client non ce l'ha: l'addon spegne quella sola funzione e va avanti. |
| `unknown` | Il client ha l'API, ma finora nulla ha mostrato se riempie dati reali (per esempio la finestra del loot prima del primo cadavere aperto). Lo stabilisce l'uso reale. |
| `restricted` | Il client nasconde la risposta (un *valore segreto*) o è attiva una restrizione in questo momento, per esempio durante un boss. |
| `error` | La chiamata è fallita. |

### I contatori dei messaggi

Le ultime righe di `/fdcp debug` descrivono i messaggi dell'addon verso gli altri giocatori: se sono trattenuti (`in attesa (lockdown)`, `in attesa (encounter)`, o il nome di una restrizione; `sola lettura` quando il gioco vieta i messaggi addon), quanti aspettano in coda per canale (raid, gilda, officer, sussurri), quanti sono stati inviati, falliti, ritardati o scartati, quanti sono arrivati, quanti erano la tua stessa eco e quanti sono stati respinti (protocollo sconosciuto o più recente, danneggiati). I messaggi aspettano durante un boss e il lockdown della chat e partono dopo; sopravvivono anche a `/reload`.

L'output di `/fdcp debug` ha anche due **righe sull'interfaccia**: il tema attivo, quanti stili di testo usano i font dell'addon e quanti sono ripiegati sui font del gioco, quante texture il client ha rifiutato e cosa ha risposto a qualche prova dell'interfaccia (liste ScrollBox, data provider, forme arrotondate 9-slice, bagliore additivo, foglio di icone, la dimensione di un pixel dello schermo e la scala dell'interfaccia). Servono all'autore per controllare l'aspetto in gioco.

Una riga **Controllo addon** riassume chi nel tuo raid ha l'addon: "37/40 con l'addon", poi quanti sono attivi, da aggiornare, con una versione incompatibile, senza addon attivo o ancora in attesa, le versioni del tuo addon e del protocollo e quante domande e risposte di presenza sono arrivate. L'addon di ogni raider risponde da solo quando entra nel raid; l'officer che guida la serata chiede di nuovo quando la serata si apre e quando entra qualcuno. Rolla solo chi ha un addon compatibile.

Una riga **Permissions** dice se il roster della gilda è stato letto in questa sessione (`loaded` o `loading`), il tuo rango di gilda per posizione (0 è il Guild Master) e quanti eventi degli altri giocatori aspettano il roster.

Una riga **Sync** (officer) descrive la sincronizzazione del registro con gli altri officer: `on` quando il tuo gioco partecipa (il tuo rango può scrivere eventi del registro e il roster della gilda è stato letto), quanti officer ha sentito, quante volte ha chiesto gli eventi mancanti e ha risposto alla richiesta di un altro (con il numero di eventi mandati), quanti eventi ha aggiunto, rifiutato (il loro autore non aveva il rango) o trovato in conflitto (lo stesso evento con un altro contenuto: si tiene quello che hai), e quanti messaggi di sincronizzazione sono arrivati da chi non è officer e sono stati ignorati.

Una riga **Snapshot** descrive la tabella dei crediti in sola lettura: `officer` o `member` (`off` prima che il roster della gilda sia letto), la dimensione `k` del registro della tabella che conservi, quante tabelle il tuo gioco ha mandato alla gilda e in sussurro (officer), quante ne ha ricevute, tenute, trovate più vecchie di quella che aveva, ignorate perché il mittente non è officer, o rifiutate perché malformate.

Due righe **Ledger size** descrivono il registro della gilda nei tuoi dati salvati: quanti eventi contiene e più o meno quanti kilobyte occupano, quanti eventi sono stati compattati e di quali season, e i quattro tipi di evento che occupano più spazio (vedi [[Backup e season|Backup-and-Seasons-it]]). La riga Sync conta anche gli eventi compattati che un altro officer ha segnalato come tolti.

`/fdcp debug` non stampa mai nomi di giocatori, di gilda o di oggetti, quindi puoi incollarne l'output in una segnalazione di errore. Controlla di nuovo il client a ogni esecuzione.
