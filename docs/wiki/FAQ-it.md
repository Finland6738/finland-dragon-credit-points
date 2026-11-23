# FAQ

> **Costruita, non ancora vista in gioco.** Le risposte seguono il codice dell'addon e i suoi test offline. [English](FAQ)

## Installare e avviare

**Dove va l'addon?** In `<cartella di WoW>/_forever_/Interface/AddOns/FinlandDragonCreditPoints`. Vedi [[Installazione|Installation-it]].

**Scrivo `/fdcp` e non si apre nulla.** Controlla che l'addon sia attivo nell'elenco degli AddOn e che il gioco sia WoW: Forever (fuori da Forever l'addon avvisa una volta). Poi `/reload`. Se non basta, fai un [[rapporto sul bug|Reporting-Bugs-it]].

**Posso cambiare lingua?** Sì: `/fdcp language itIT` o `enUS` (`auto` segue il gioco), poi `/reload`. Gli annunci della gilda in `/raid` usano sempre la lingua della gilda, qualunque sia la tua.

## Rollare

**Perché non posso rollare?** Rolla solo chi ha l'addon attivo e compatibile. Un ufficiale vede chi manca, chi deve aggiornare e chi ha una versione incompatibile in [[Controllo dell'addon|Addon-Check-it]].

**Ho scritto `/roll` e non è contato.** Un roll conta solo se parte dal pulsante di tiro del popup, una volta per oggetto (il Guild Master può togliere questa regola). Vedi [[Rollare per il loot|Rolling-for-Loot-it]].

**Ho chiuso il popup per sbaglio.** Riapri la riga dell'oggetto in **Loot** o fai `/reload`: la sessione torna da sola, anche dopo un `/reload`.

**Cosa significano i colori dell'upgrade?** Il badge confronta l'oggetto con l'equipaggiamento che indossavi durante il combattimento col boss: [[Suggerimenti di upgrade|Upgrade-Hints-it]].

**Cos'è la penalità +2?** Barare sul roll (cambiare equipaggiamento dopo il combattimento, passare su un grosso upgrade e simili) costa +2 crediti quando il master looter o il council lo confermano. [[Regole del loot|Loot-Rules-it]], «Imbrogli sul roll».

## Crediti

**Perché meno crediti vuol dire più priorità?** I crediti sono quelli già spesi: vince il roll prima chi ne ha meno; i pari si risolvono con il roll più alto. [[Regole del loot|Loot-Rules-it]].

**I miei crediti sono diversi da quelli di un ufficiale.** I membri ricevono la tabella dall'addon di un ufficiale (a ogni modifica e al login). Aspetta un momento o fai `/reload`; la tabella di chi non è ufficiale viene ignorata. [[Tabella crediti|Credits-it]].

**Chi può cambiare i crediti?** Solo il council, con un motivo, e ogni correzione resta nell'audit della season ([[Council|Council-it]], [[Storico|History-it]]).

**Sono entrato in ritardo: da quanti crediti parto?** Dal minimo del roster. Una serata persa può costare +1 credito, che un ufficiale conferma ([[Regole del loot|Loot-Rules-it]], «Assenze»).

## Ufficiali

**Due ufficiali hanno gestito serate diverse.** Gli addon degli ufficiali sincronizzano un solo registro sul canale ufficiali; dai qualche minuto. `/fdcp debug` ha una riga **Sync**.

**Come faccio il backup?** **Storico › Backup** copia tutto il registro come stringa e lo ripristina senza togliere eventi: [[Backup e season|Backup-and-Seasons-it]].

**Come aggiorno il sito della community?** [[Esportazione per il sito|Site-Export-it]].

## Altro

**L'addon fa richieste web?** No: non può, e non manda mai nulla fuori dal gioco. Vedi [[Privacy e dati|Privacy-and-Data-it]].

**Dove segnalo un problema?** [[Segnalare un bug|Reporting-Bugs-it]].
