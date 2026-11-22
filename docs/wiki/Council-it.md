# Council

> **Costruito, non ancora visto in gioco.** La pagina del council funziona nei test offline con un raid simulato; come appare e come si usa in un raid vero è ancora da confermare. [English](Council)

Questa pagina è per il **loot council**: gli officer (o i personaggi che la gilda elenca) che guardano le assegnazioni, votano quando la gilda lo chiede e correggono ciò che è andato storto. Tutto quello che fa il council ha la sua pagina nella finestra principale: **Loot › Council**, la terza sotto-scheda dopo *Sessione* e *Da consegnare*. I compiti del master looter (far girare il roll, confermare) sono nella [[Guida del master looter|Master-Looter-Guide-it]]; le regole che ci stanno dietro sono in [[Regole del loot|Loot-Rules-it]].

La pagina mostra quello che l'addon già sa e manda i tuoi clic alle stesse regole dei comandi in chat: non decide mai niente da sola. Ogni azione che cambia il registro chiede un **motivo**, e senza motivo non si scrive nulla.

## Chi è nel council

Di base, i ranghi di gilda con il permesso *membro del council* (gli officer) che sono **nel raid**. La gilda può scrivere nelle sue regole una **lista esplicita di personaggi**: allora la lista sostituisce il rango. La riga in alto nella pagina ti dice se **sei nel council**, se il council è deciso dal rango o dalla lista e come si decide un'assegnazione in questa gilda:

- **il master looter conferma ogni proposta** (il preset);
- **l'addon assegna da solo**, salvo che un segnale o un voto lo fermino;
- **decide il voto del council.**

Quando la gilda chiede il voto anche nelle altre modalità, la riga aggiunge *Il voto del council è un parere.*

## Il pezzo sul tavolo

La scheda a sinistra segue il pezzo che mostra la scheda Sessione (seleziona lì un altro pezzo per guardarlo qui). Contiene:

- il **pezzo** e la **proposta** scritta dall'addon (a chi, quanto, perché);
- le **segnalazioni** che nominano un giocatore: *upgrade ignorato* e *possibile spreco* ([[Guida del master looter|Master-Looter-Guide-it]], "Segnalazioni del council"). Sono in tempo reale mentre il round è aperto e non cambiano mai il vincitore da sole. *Nessun segnale su questo pezzo.* se non ce n'è;
- i **voti** espressi finora, per esempio *Voti del council (aperto): Corin 2, Bryn 1.*;
- **Il tuo voto:** una lista con il giocatore proposto per primo e poi i candidati, e il pulsante **Vota**. Un membro vota **un** giocatore e può cambiare voto finché il master looter non lo chiude. La riga accanto al titolo dice *hai votato Corin* quando è partito, oppure *nessun voto aperto su questo pezzo* (la modalità della gilda non prevede il voto, il pezzo non ha ancora una proposta o il voto è chiuso), oppure *votano solo i membri del council*;
- **Modifica** e **Correggi**, solo sul client del master looter: aprono le stesse finestre con il motivo della scheda Sessione (il vincitore o il costo con un motivo; la categoria o il costo prima che il roll si apra). La finestra di un altro officer è in sola lettura e non ha questi pulsanti.

Se non sei il master looter vedi la scheda da una **vista in sola lettura**: il pezzo, la proposta e, dove la gilda te lo permette (di base il council), i candidati, i badge di upgrade e le segnalazioni.

## Annullare un'assegnazione

**Assegnazioni** elenca le assegnazioni della season aperta, dalla più recente, con il pezzo, il vincitore e i crediti. Selezionane una e premi **Annulla assegnazione...**: una finestra chiede il **motivo** (*errore*, *assegnazione doppia*, *spreco palese*, *ha passato per fare il furbo*, *voto del council*, *leggendario*, *altro*). I crediti tornano; l'assegnazione resta nel registro, segnata come annullata, e l'audit mostra chi l'ha annullata e perché.

## Correggere i crediti

**Correggi crediti...** (in alto a destra) sposta a mano i crediti di un membro. Scegli il membro del pool della season, scrivi il numero (positivo aggiunge crediti, come un costo; negativo li toglie, con `-`; al massimo 1000 per parte) e scegli il motivo (*errore*, *penalità*, *bonus*, *voto del council*, *altro*). Un membro mancante, un numero che non è un numero, lo zero o un motivo mancante vengono rifiutati nella finestra e non si scrive nulla.

## L'audit

**Audit** elenca ogni intervento del council della season aperta, dal più recente: assegnazioni che si sono staccate dalla regola (con il vincitore della regola), correzioni di categoria o costo prima di un roll, voti che hanno deciso un'assegnazione, annullamenti e correzioni dei crediti, ognuno con il suo autore e il suo motivo. Un intervento che un annullamento successivo ha disfatto appare attenuato.

## Progetti leggendari

**Leggendari** mostra come le regole della gilda trattano un pezzo della catena (*vanno al costruttore scelto dal council, senza roll*; *il council vota*; *si rollano come un pezzo qualsiasi*; *vanno al primo della coda del progetto che è nel raid*) e il costo di un pezzo, poi i progetti della season: nome, costruttore, pezzi pagati sul totale e stato (*aperto*, *Completato*, *Abbandonato*).

- **Apri progetto...** chiede il **nome**, l'**oggetto finale**, i **pezzi della catena** e, se vuoi, il **costruttore** (la lista è il pool della season, oppure *Ancora nessuno*) e una **coda** di nomi. Gli oggetti sono id di oggetto, oppure link: clicca nel campo e fai **Maiusc+clic** sull'oggetto nelle borse o in chat. Un pezzo che un altro progetto aperto ha già, un oggetto mancante e un nome fuori dal pool vengono rifiutati nella finestra.
- **Segna come costruito** e **Abbandona** chiudono il progetto aperto selezionato. Un progetto chiuso resta nella lista.

Un pezzo della catena che cade viene riconosciuto dalla sessione e proposto come dicono le regole (nel preset, senza roll al costruttore); ogni pezzo pagato resta nel progetto.

## Chi può fare cosa

La pagina del council è aperta a chiunque veda la scheda Loot, ma ogni azione passa dallo stesso cancello dei permessi di tutto il resto: annullare un'assegnazione, correggere i crediti e aprire o chiudere un progetto richiedono il permesso della *serata* mentre una serata della season è aperta (il master looter scrive le correzioni del council) e il permesso di *correzione dei crediti* o da officer fuori dalla serata (il Guild Master nel preset). Se il tuo rango è troppo basso la finestra lo dice e non si scrive nulla. Gli addon degli altri giocatori controllano lo stesso permesso quando l'evento arriva.

## I comandi funzionano ancora

`/fdcp council` (stato, `vote`, `awards`, `void`, `adjust`, `audit`) e `/fdcp legendary` fanno le stesse cose dalla chat: vedi [[Comandi|Commands-it]].
