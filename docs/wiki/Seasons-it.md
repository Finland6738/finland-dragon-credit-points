# Season

> **Costruita, non ancora vista in gioco.** La finestra funziona nei test offline con un client simulato; come appare nel gioco vero è ancora da confermare. [English](Seasons)

Una **season** è l'unità dei crediti della gilda: un gruppo di raid (le istanze uscite con un aggiornamento), una tabella di crediti e un inizio. Una sessione di loot può girare solo dentro una **season aperta**. Ce n'è una sola aperta alla volta.

## Dove si trova

**Impostazioni › Season** (la scheda Impostazioni). **Ogni membro** vede la season corrente, in sola lettura: nome, se è aperta, i raid con la loro dimensione, la regola per chi entra in ritardo, i crediti iniziali e la **fascia di item level**. Se nessuna season è aperta lo dice.

## Aprire una season (Guild Master)

Il modulo lo vede solo chi ha il permesso `season.manage` (di default il **Guild Master**); per tutti gli altri non ci sono pulsanti, e una chiamata forzata viene rifiutata.

1. Scrivi un **nome** facoltativo (altrimenti la season si chiama S1, S2…).
2. Scrivi i **crediti iniziali** (da cui parte chi c'è dall'inizio; viene proposto quello delle regole della gilda, 0 nel preset *Patto*).
3. Scegli i **raid** del gruppo (clic su un raid per sceglierlo) e la **dimensione** di ciascuno (10, 20 o 40 giocatori).
4. Se vuoi, scrivi la **fascia di item level** (min – max): gli item level dei pezzi epici di questa season. Il badge di upgrade del popup conta un epico indossato **sotto** la fascia come un epico di una season precedente (un gradino sotto, come un blu): vedi [[Suggerimenti di upgrade|Upgrade-Hints-it]]. Puoi impostarla anche dopo.
5. Scegli la **regola per chi entra in ritardo**: con cosa parte un membro che entra dopo la prima serata (meno crediti del gruppo, il preset della gilda; media del gruppo, mediana, zero o un valore fisso). Se la cambi, la nuova regola viene scritta nelle regole della gilda come modifica verificabile, subito prima della season.
6. Premi **Apri la season**. Compare un riepilogo: non viene scritto nulla finché non premi **Conferma**; **Annulla** lascia tutto com'era.

La season è scritta nel registro della gilda come evento verificabile e **non si può cancellare**, solo chiudere. Non si può aprire una seconda season mentre una è aperta: la finestra lo dice e ti chiede di chiudere la prima.

## La fascia di item level (Guild Master)

Mentre una season è aperta, il Guild Master vede due caselle, **min** e **max**, e **Salva la fascia**. Scrivi due numeri interi (il minimo non sopra il massimo, da 1 a 2000) e conferma nella finestra: la fascia si scrive nel registro (`SEASON_BAND_SET`), e la sessione di loot successiva la manda al raid con i pezzi. Senza fascia, ogni epico conta come di questa season nel badge. Puoi reimpostarla quando vuoi; conta l'ultima.

## Chiudere una season (Guild Master)

Premi **Chiudi la season**. La chiusura chiede **due conferme separate**: la prima (**Continua**) mostra cosa sta per succedere, la seconda (**Chiudi per sempre**) avvisa che una season chiusa non si riapre. Annullare a uno dei due passi non cambia nulla. La storia della season resta: non si cancella nulla. Una season con una serata ancora aperta non si può chiudere: chiudi prima la serata (vedi [[Roster e Serate|Roster-and-Nights-it]]).

## Da sapere

- Ogni azione è un evento del registro (`SEASON_OPENED`, `SEASON_BAND_SET`, `SEASON_CLOSED`) con autore e data, quindi gli officer possono verificarli; le finestre degli altri officer si aggiornano quando l'evento arriva.
- I raid sono quelli della tabella dell'addon (per ora Molten Core e Onyxia's Lair).
- Una season chiusa si può archiviare e compattare per tenere piccoli i dati salvati: vedi [[Backup e season|Backup-and-Seasons-it]].
