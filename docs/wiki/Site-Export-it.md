# Esportazione per il sito

> **In programma, non ancora costruita.** Questa pagina descrive come gli officer aggiorneranno il sito della community dall'addon. La funzione arriva con la milestone dello storico e delle esportazioni. [English](Site-Export)

La pagina WoW Forever del sito della community legge tre file. FDCP li scrive tutti e tre nel formato attuale del sito, quindi si mettono nella cartella `content/games/wow-forever/` del sito **senza ritocchi**:

| File | Scheda del sito | Che cosa scrive FDCP |
|---|---|---|
| `roster.json` | Roster | I main della season della tua gilda. Per ognuno: nome, classe, spec principale, ruolo, fazione, Raider o Trial. |
| `loot.json` | Loot | Una voce per season, la più recente in cima, e una colonna per serata. Ogni serata elenca i pezzi assegnati, con costo 0, 1 o 2. I crediti li somma il sito. |
| `progress.json` | Progress | La data della prima uccisione di ogni boss da parte della tua gilda. |

## Due gilde, due fazioni

Nebulah (Orda) e Nebulaa (Alleanza) sono due gilde diverse nel gioco, quindi ognuna ha i propri dati nell'addon. Ogni gilda esporta solo la propria fazione e lascia com'è la parte dell'altra. Il GM può cambiare il nome della fazione usato dal sito in Impostazioni › Sito.

## Come esporta un officer

- **Finestra di copia (in gioco).** Apri Storico › Esporta e scegli il file. Il testo è già selezionato: premi Ctrl+C e incollalo nel sito. "File completo" sostituisce tutto il file. "Frammento" ti dà solo la tua parte, da incollare a mano.
- **Script (consigliato).** Dopo la serata chiudi il gioco o fai `/reload`, poi lancia il comando qui sotto sul computer. Unisce i dati della tua gilda ai file del sito e conserva tutto il resto (l'altra fazione, le season precedenti, le immagini di copertina). Poi fai il commit dei tre file nel sito come sempre.

  ```bash
  python -X utf8 tools/site_export.py --wow "<WoW folder>" --site <cartella del sito>
  ```

## Che cosa non esce mai dall'addon

Le esportazioni non contengono mai:

- presenze e panchine;
- note;
- motivazioni del council;
- chi non ha l'addon;
- alt;
- reami.

Correzioni e annullamenti sono già applicati, quindi i totali del sito coincidono con quelli dell'addon.

## Dettagli

Il contenuto esatto dei file e la corrispondenza dei campi sono nella specifica [`docs/specs/site-export.md`](https://github.com/Finland6738/finland-dragon-credit-points/blob/main/docs/specs/site-export.md).

Vedi anche: [[Giro dell'interfaccia|Interface-Tour-it]]
