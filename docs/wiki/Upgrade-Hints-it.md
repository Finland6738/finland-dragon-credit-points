# Suggerimenti di upgrade

> **Costruito, non ancora visto in gioco.** Tutto funziona nei test offline; se il gioco dà qualità e item level dei pezzi indossati come previsto, e l'istantanea dell'equipaggiamento all'inizio di uno scontro col boss, sono ancora da confermare. [English](Upgrade-Hints)

Il popup mostra un **badge di upgrade** per ogni pezzo in palio ([[Rollare per il loot|Rolling-for-Loot-it]], "È un upgrade?"). Lo calcola l'addon da solo, allo stesso modo per tutti: non c'è nulla da impostare, nessun peso delle statistiche da importare e nessuna lista da tenere. **Informa** te, il master looter e il council; **non cambia mai chi vince**.

## La regola

Il pezzo si confronta con quello che indossavi **in quello slot durante lo scontro col boss**:

| Indossavi | Un pezzo viola di questa season è |
|---|---|
| un **viola di questa season** | **Upgrade piccolo** |
| un **blu**, o un **viola di una season precedente** | **Upgrade medio** |
| un **verde o inferiore**, o **niente** | **Upgrade grande** |

- Il badge mostra sempre la **differenza di item level**: *Upgrade piccolo · ilvl +13*. Uno slot vuoto dice *Upgrade grande · slot vuoto*.
- Un pezzo **peggiore** del tuo (item level più basso, o stesso livello senza niente di meglio) è **Nessun upgrade**. Un pezzo che la tua classe non può usare è **Non usabile**, e Passo viene preselezionato per te.
- Un leggendario conta come un viola. Un pezzo blu si legge allo stesso modo, un gradino sotto: su un verde è un upgrade medio, su un blu piccolo.
- **Anelli e trinket** si confrontano col peggiore dei tuoi due (prima uno vuoto, poi il colore più basso, poi l'item level più basso). Un'**arma a due mani** si confronta con mano destra più mano sinistra (il colore più basso dei due, l'item level medio). Un'arma a una mano si confronta con la mano peggiore solo se usi due armi.

## Raid nuovi: la fascia di item level della season

Quando una nuova season porta raid nuovi, i viola della season scorsa non sono più quelli di prima. Ogni season ha una **fascia di item level**, gli item level dei suoi pezzi epici, che il Guild Master imposta in **Impostazioni › Season** ([[Season|Seasons-it]]). Un viola che indossi **sotto la fascia** conta come un viola di una season precedente, un gradino sotto, come un blu: un viola nuovo su di lui è un upgrade **medio**, non piccolo. Senza fascia ogni viola conta come di questa season.

## L'equipaggiamento dello scontro

L'addon fa un'istantanea del tuo equipaggiamento quando lo scontro col boss **inizia** (se hai ricaricato durante lo scontro, quando finisce) e confronta con quella il loot di quel boss, per al massimo un'ora. Togliersi un pezzo dopo il kill non fa sembrare un pezzo un upgrade più grande. Fuori da uno scontro (per esempio un roll di prova) confronta con quello che indossi ora; il tooltip del badge dice quale.

## Tolto

Le versioni precedenti avevano pesi delle statistiche personali con import tipo Pawn (`/fdcp weights`), una wishlist best in slot (`/fdcp wish`), e etichette e nota nel popup. Il Guild Master ha deciso di sostituirli con questo badge: non ci sono più, e i comandi non esistono più.

## Limiti

- Il badge legge **colore e item level**, non le statistiche: due viola di questa season con statistiche diverse per la tua spec sono entrambi un upgrade piccolo se il nuovo ha un item level più alto.
- Il pezzo in palio si legge dal suo id, quindi il suo item level è quello base; i pezzi che indossi si leggono dai loro link, con i loro aggiornamenti.
- Un token per un'altra classe risulta *non confrontabile*, non *non usabile*.
- Il badge viene dal tuo addon: un client modificato potrebbe mentire. Informa il council, che decide.
