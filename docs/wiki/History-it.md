# Storico: serate, membri e oggetti

> **Costruito, non ancora visto in gioco.** La scheda Storico funziona nei test offline con un client simulato; come appare nel gioco vero è ancora da confermare. [English](History)

La scheda **Storico** racconta cosa è successo nelle serate di raid della gilda. Come i crediti, tutto viene calcolato dal registro ogni volta: non si memorizza niente a parte, quindi ogni client con gli stessi eventi mostra lo stesso storico. La scheda ha quattro sotto-schede: **Serate**, **Registro**, **Audit** ed **Esporta**. Per ora è pronta solo **Serate**; le altre tre dicono che arrivano con una versione successiva (il registro del loot e l'audit con M6-2, le esportazioni con M6-3).

## Serate

Una tabella delle serate della season, **dalla più recente**, raggruppate per **settimana** (una settimana va da lunedì a domenica ed è indicata dal suo lunedì; la prima serata di una settimana la mostra nella prima colonna).

| Colonna | Cosa mostra |
|---|---|
| **Settimana** | Il lunedì della settimana, sulla prima serata della settimana. |
| **Data** | La data della serata (giorno/mese). |
| **Istanza** | Il raid. |
| **Boss** | I boss uccisi e il totale dell'istanza (per esempio `3/10`). |
| **Drop** | Ogni assegnazione della serata, anche una annullata e un oggetto per la banca di gilda. |
| **Crediti** | Quanto sono costate quella sera le assegnazioni valide ai membri. |

Il pulsante in alto a destra scorre le season. Clicca una serata per vederne il **dettaglio** a destra: la data, l'istanza, la dimensione e la difficoltà, i boss uccisi in ordine e ogni assegnazione con l'oggetto (nel colore della qualità), chi lo ha preso (oppure *Banca di gilda*, *Disincanto*, *Master looter*) e il costo. Un'assegnazione annullata resta nell'elenco, segnata *(annullato)*, e non costa nulla.

Gli **ufficiali** vedono anche chi era **nel raid** e chi **in panchina** a fine serata. I membri no: quei dati non sono nemmeno nella loro finestra.

## Lo storico di un membro

Clicca un drop e premi **Membro** per aprire la finestra del membro:

- I **crediti** adesso e a inizio season.
- Gli **oggetti vinti**, dal più recente, con la serata e il costo. Un'assegnazione annullata è attenuata. Clicca un oggetto per aprirne la finestra.
- I **crediti nel tempo**: l'inizio, poi ogni assegnazione e ogni correzione, fino al numero della tabella dei crediti.
- Gli **interventi del council**: ogni volta che il council ha modificato un'assegnazione, ne ha annullata una o ha corretto i crediti del membro, con il motivo.
- Le **presenze** (solo ufficiali): le serate giocate e in panchina, i boss a cui ha partecipato su quelli possibili e lo stato di ogni serata.

## Lo storico di un oggetto

Premi **Oggetto** (o clicca un oggetto nella finestra di un membro) per vedere quante volte l'oggetto è **caduto**, è stato **assegnato** e **visto**, **chi lo ha** (e quante volte) e **ogni drop** con la serata, chi lo ha preso e il costo, in tutte le season. Clicca un nome per aprire quel membro.

## Chi vede cosa

| | Tutti | Ufficiali (`view.attendance`) |
|---|---|---|
| Serate, drop, boss, crediti spesi | sì | sì |
| Oggetti, crediti e interventi del council di un membro | sì | sì |
| Drop e proprietari di un oggetto | sì | sì |
| Chi era nel raid o in panchina, presenze | no | sì |
