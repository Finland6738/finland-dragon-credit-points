# Season

> **Costruita, non ancora vista in gioco.** La finestra funziona nei test offline con un client simulato; come appare nel gioco vero è ancora da confermare. [English](Seasons)

Una **season** è l'unità dei crediti della gilda: un gruppo di raid (le istanze uscite con un aggiornamento), una tabella di crediti e un inizio. Una sessione di loot può girare solo dentro una **season aperta**. Ce n'è una sola aperta alla volta.

## Dove si trova

**Impostazioni › Season** (la scheda Impostazioni). **Ogni membro** vede la season corrente, in sola lettura: nome, se è aperta, i raid con la loro dimensione, la regola per chi entra in ritardo e i crediti iniziali. Se nessuna season è aperta lo dice.

## Aprire una season (Guild Master)

Il modulo lo vede solo chi ha il permesso `season.manage` (di default il **Guild Master**); per tutti gli altri non ci sono pulsanti, e una chiamata forzata viene rifiutata.

1. Scrivi un **nome** facoltativo (altrimenti la season si chiama S1, S2…).
2. Scrivi i **crediti iniziali** (da cui parte chi c'è dall'inizio; viene proposto quello delle regole della gilda, 0 nel preset *Patto*).
3. Scegli i **raid** del gruppo (clic su un raid per sceglierlo) e la **dimensione** di ciascuno (10, 20 o 40 giocatori).
4. Scegli la **regola per chi entra in ritardo**: con cosa parte un membro che entra dopo la prima serata (media del gruppo, mediana, il più basso, zero o un valore fisso). Se la cambi, la nuova regola viene scritta nelle regole della gilda come modifica verificabile, subito prima della season.
5. Premi **Apri la season**. Compare un riepilogo: non viene scritto nulla finché non premi **Conferma**; **Annulla** lascia tutto com'era.

La season è scritta nel registro della gilda come evento verificabile e **non si può cancellare**, solo chiudere. Non si può aprire una seconda season mentre una è aperta: la finestra lo dice e ti chiede di chiudere la prima.

## Chiudere una season (Guild Master)

Premi **Chiudi la season**. La chiusura chiede **due conferme separate**: la prima (**Continua**) mostra cosa sta per succedere, la seconda (**Chiudi per sempre**) avvisa che una season chiusa non si riapre. Annullare a uno dei due passi non cambia nulla. La storia della season resta: non si cancella nulla. Una season con una serata ancora aperta non si può chiudere: chiudi prima la serata (vedi [[Roster e Serate|Roster-and-Nights-it]]).

## Da sapere

- Entrambe le azioni sono eventi del registro (`SEASON_OPENED`, `SEASON_CLOSED`) con autore e data, quindi gli officer possono verificarli; le finestre degli altri officer si aggiornano quando l'evento arriva.
- I raid sono quelli della tabella dell'addon (per ora Molten Core e Onyxia's Lair).
