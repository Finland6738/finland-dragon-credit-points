# Comandi

> **In sviluppo.** Per ora esistono solo i comandi qui sotto; ogni comando nuovo viene aggiunto a questa pagina quando arriva. [English](Commands)

Tutto parte da `/fdcp`. Finché la finestra principale non esiste, `/fdcp` da solo mostra l'aiuto.

| Comando | Cosa fa |
|---|---|
| `/fdcp help` | Elenca i comandi. |
| `/fdcp debug` | Mostra cosa offre il client di gioco all'addon: versione e build del client, poi le **funzioni** che servono all'addon (master loot, finestra del loot, messaggi dei roll, statistiche degli oggetti, specializzazioni, ranghi di gilda, calendario, roster del gruppo, messaggi addon) e ogni **API** che usa, ciascuna con il suo stato, poi i contatori dei messaggi dell'addon (vedi sotto). |
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

`/fdcp debug` non stampa mai nomi di giocatori, di gilda o di oggetti, quindi puoi incollarne l'output in una segnalazione di errore. Controlla di nuovo il client a ogni esecuzione.
