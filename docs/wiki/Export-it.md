# Esporta: la tabella crediti per Discord, CSV e JSON

> **Costruito, non ancora visto in gioco.** L'esportazione funziona nei test offline con un client simulato; come si comporta la casella di copia nel gioco vero è ancora da confermare. [English](Export)

La sotto-scheda **Storico › Esporta** trasforma la **tabella crediti** della season in testo da incollare: in un canale Discord, in un foglio di calcolo o in qualsiasi strumento che legga JSON. Il testo si calcola dal registro ogni volta che apri la scheda, quindi coincide sempre con la scheda Crediti. Per i file del sito della community (roster, loot, progress) usa la forma **Sito** della stessa scheda: vedi [[Esportazione per il sito|Site-Export-it]].

## Chi può esportare

Il permesso `export.public`: di base gli **officer** (il Guild Master può abbassarlo o alzarlo, come gli altri permessi). Chiunque altro vede una riga che dice che il suo grado di gilda non può esportare, e nessun testo.

## Come copiare

1. Apri **Storico › Esporta** (la season mostrata è quella scelta nella scheda Serate).
2. Scegli **Discord**, **CSV** o **JSON** (la quarta voce, **Sito**, è per i file del sito della community: [[Esportazione per il sito|Site-Export-it]]).
3. Premi **Seleziona tutto**, poi **Ctrl+C**. Il gioco non lascia che un addon scriva negli appunti, quindi il testo viene selezionato per te. La casella non si modifica: una modifica a mano viene rimessa a posto.
4. Incolla dove ti serve.

## Le tre forme

| Forma | Cosa ottieni |
|---|---|
| **Discord** | Un titolo in grassetto con la season e la data dell'ultima serata, poi una tabella a larghezza fissa in un blocco di codice: posto in fila, membro, classe, ruolo, crediti. Discord rifiuta i messaggi sopra i 2000 caratteri, quindi una gilda grande si divide in **parti** (un pulsante *Parte successiva* le scorre; ogni parte ripete la riga delle colonne e finisce con `(parte 1/3)`). Incolla una parte per messaggio. |
| **CSV** | Una riga per membro: posto, membro, classe, ruolo, crediti, poi una colonna per serata con quanto il membro ha speso quella sera. In inglese il separatore è la virgola; in una lingua che scrive la virgola decimale (l'italiano) è il **punto e virgola**, così un foglio di calcolo di quella lingua lo apre bene. |
| **JSON** | Gli stessi dati per i programmi: date `AAAA-MM-GG`, numeri col punto decimale, chiavi sempre nello stesso ordine, ruoli e classi come codici (`WARRIOR`, `TANK`). Non cambia con la lingua. |

## Lingua

Discord e CSV usano la **lingua della gilda**: nomi di classi e ruoli, titolo, formato della data (`21/10/2026` in italiano, `10/21/2026` in inglese) e virgola decimale (`1,5` o `1.5`). Il JSON è la forma per le macchine e non cambia mai.

## Cosa c'è dentro, e cosa mai

La tabella è quella della scheda Crediti: i **main in gioco della tua fazione**, in ordine di fila (prima chi ha meno crediti), con i crediti spesi in ogni serata. Un'assegnazione annullata non conta, una correzione sì. I nomi sono scritti senza il reame.

**Le presenze non si esportano mai.** Chi era nel raid, chi in panchina e quante volte ha giocato qualcuno è solo per gli occhi degli officer nell'addon; nessuna esportazione lo porta.

Lo stesso registro dà sempre esattamente lo stesso testo.
