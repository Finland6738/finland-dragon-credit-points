# Privacy e dati

> **Costruita, non ancora vista in gioco.** [English](Privacy-and-Data)

## Cosa conserva l'addon

Tutto è salvato dal gioco nel file SavedVariables dell'addon, sul **tuo PC** (`<WTF>/Account/<account>/SavedVariables/FinlandDragonCreditPoints.lua`):

- le tue impostazioni e i profili (tema, lingua, effetti, posizione delle finestre);
- i dati della gilda, tenuti per gilda così due gilde non si mescolano: il **registro** degli eventi (serate, drop, assegnazioni, correzioni con il motivo, cambi di season), il pool della season con le dichiarazioni dei giocatori, le formazioni e le presenze, le regole e l'ultima tabella crediti ricevuta;
- un breve log e gli ultimi errori dell'addon stesso.

I crediti non sono mai salvati: si calcolano dal registro. Il registro contiene codici e numeri, non frasi.

## Cosa manda l'addon

Solo **messaggi dell'addon dentro il gioco**, sui canali che il gioco offre, mai su internet:

| Canale | Cosa | Chi |
|---|---|---|
| Raid | La sessione di loot (oggetti, costi, giri, risposte, esito) e la risposta di presenza con la versione dell'addon | i raider con l'addon |
| Raid e sussurro | Il controllo di preparazione: una richiesta del master looter o di un ufficiale e la tua piccola risposta (quali slot hanno un incantamento, quali buff sono attivi, quanti consumabili hai) sussurrata solo a chi ha chiesto | chi ha chiesto |
| Ufficiali | La sincronizzazione del registro tra ufficiali | gli ufficiali |
| Gilda e sussurro | La tabella crediti in sola lettura | tutta la gilda |

Un raider può mandare solo la propria risposta, e la risposta di preparazione non la salva mai chi la riceve. I roll li fa il gioco. Gli annunci scritti in `/raid` sono normali righe di chat.

## Cosa esce dal gioco

Niente, a meno che non lo porti fuori **tu**: le pagine **Esporta** e **Sito** dello Storico e la sotto-scheda **Backup** producono testo che copi (Ctrl+C) e incolli tu; la tabella crediti per Discord e i file del sito della community sono solo per gli ufficiali, e le presenze non ci sono mai. L'addon non ha accesso alla rete e non raccoglie statistiche.

## Altri addon

Un altro addon che gira nel tuo gioco, come Azeroth Accord, può **leggere** una parte dei dati di FDCP con un'API in sola lettura: la season, il pool, i crediti e i posti in coda, il raid e la panchina della serata aperta, e un riassunto delle regole. Riceve solo quello che FDCP ti mostra già su questo client. Sul client di un membro è la tabella dei crediti che ha mandato un ufficiale. Presenze e assenze non si condividono mai. Nessun altro addon può cambiare i dati di FDCP. FDCP non legge mai i dati degli altri addon. Vedi [[API per altri addon|API-for-Addons-it]].

## Il rapporto sul bug

`/fdcp debug` costruisce un rapporto senza nomi di giocatori, gilda, reame od oggetti, fatto per essere incollato in una issue pubblica. Leggilo prima di incollarlo: [[Segnalare un bug|Reporting-Bugs-it]].

## Cancellare i dati

Elimina il file SavedVariables a gioco chiuso, o la cartella dell'addon per disinstallarlo. Il registro della gilda è nel file di ogni ufficiale: cancellare il tuo non cancella il loro, e l'addon di un ufficiale ti rimanderà la tabella crediti. Solo gli ufficiali ripristinano un registro da una stringa di backup ([[Backup e season|Backup-and-Seasons-it]]).
