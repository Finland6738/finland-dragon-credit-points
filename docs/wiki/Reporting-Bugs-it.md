# Segnalare un bug

> **Costruita, non ancora vista in gioco.** Il rapporto funziona nei test offline; come appare la finestra nel gioco vero è ancora da confermare. [English](Reporting-Bugs)

Qualcosa non funziona? Una buona segnalazione è la via più veloce per la correzione. L'addon ne scrive la maggior parte al posto tuo.

## 1. Prendi il rapporto bug

Scrivi `/fdcp debug`. Si apre una finestra con il **rapporto bug**, già selezionato. Premi **Ctrl+C** per copiarlo (un addon non può scrivere negli appunti da solo; se la selezione si è persa, clicca **Seleziona tutto**). **Aggiorna** lo ricostruisce. `/fdcp debug chat` scrive lo stesso testo nella chat.

Il rapporto contiene:

- la versione dell'addon, il protocollo dei messaggi e la lingua;
- il client di gioco (versione, build) e cosa offre all'addon: ogni funzione e ogni API con il suo stato (vedi [[Comandi|Commands-it]]);
- lo stato delle parti dell'addon: la coda e i contatori dei messaggi, la dimensione del registro, la serata, la sessione, i permessi, la sincronizzazione con gli officer, il controllo addon del raid;
- **gli errori dell'addon**: gli ultimi dieci errori Lua diversi, sollevati dai file di FDCP, ciascuno con quante volte è comparso. Gli errori degli altri addon non vengono conservati;
- il log dell'addon (le ultime righe).

## 2. Non contiene nomi

Il rapporto è fatto per essere incollato in pubblico:

- niente nomi di giocatori, nome della gilda, reame o nomi di oggetti;
- un messaggio d'errore conserva file e riga e le sue parole, ma tutto ciò che sta tra virgolette diventa `<text>` e le cartelle spariscono;
- un ultimo passaggio toglie ogni nome che l'addon conosce (tu, la tua gilda, il roster della season) e scrive `<name>` al suo posto.

Rileggilo comunque prima di incollarlo: se vedi qualcosa che non vuoi pubblicare, cancella quella riga.

## 3. Apri una issue

Vai alle issue del repository (il link è nella pagina **Info** delle Impostazioni, vedi [[Crediti e info|About-it]]), scegli **Bug report** e compila il modulo: cosa è successo, come ripeterlo, la versione dell'addon e il rapporto. Puoi scrivere in italiano o in inglese. C'è anche un modulo **Feature request** per le idee.

Se il gioco mostra una finestra di errore Lua (o usi un addon che li mostra), copia anche quel testo: aiuta, ma controlla prima che non contenga nomi, perché solo il rapporto dell'addon è ripulito.

## Consigli per una segnalazione utile

- Scrivi cosa hai fatto, cosa ti aspettavi e cosa hai visto.
- Dì se eri master looter, officer o raider, e se gli altri avevano l'addon.
- Se è successo in raid, apri il rapporto subito dopo: il log conserva solo le ultime righe.
