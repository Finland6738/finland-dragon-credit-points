# Giro dell'interfaccia

> **Anteprime di progetto, non screenshot.** La finestra non è ancora costruita. Queste immagini mostrano come è progettata, nello stile della pagina WoW Forever del sito della community. Sono disegnate dalla specifica con nomi inventati e nulla è stato provato in gioco. [English](Interface-Tour)

## Una finestra, sei schede

`/fdcp` (o il pulsante della minimappa) apre una sola finestra. La barra del titolo mostra il logo della gilda, la season, la tua fazione e se c'è una serata aperta. Sotto ci sono le schede, come sul sito della community. Vedi solo le schede che il tuo rango di gilda può usare.

| Scheda | Che cosa trovi |
|---|---|
| **Roster** | Il roster dei raid come sul sito: una colonna per tank, healer e DPS, con i posti liberi e chi è in prova. Gli officer vedono anche la lineup della serata, la panchina e chi nel raid ha l'addon. |
| **Crediti** | La tabella dei crediti della season come sul sito: una colonna per serata, il tuo totale e il tuo posto nella fila del loot. Meno crediti vuol dire più precedenza. |
| **Progress** | Ogni boss di ogni raid, con la data della prima uccisione della tua gilda e dell'altra, come sul sito. |
| **Loot** | La sessione di loot del master looter: i pezzi, chi ha risposto, i roll e il vincitore proposto. Gli altri la vedono in sola lettura. |
| **Storico** | Le serate passate, il log del loot, l'audit delle correzioni e le esportazioni (Discord, CSV, JSON e i file del sito della community). |
| **Impostazioni** | Le tue preferenze (tema, effetti, font, lingua), le regole della gilda (in sola lettura se non sei il GM) e le impostazioni del sito. |

Quando c'è un pezzo a cui rispondere compare un **popup** a parte, con una card per ogni pezzo.

## Anteprime

![Scheda Roster](../specs/mockups/fdcp-roster.webp)

![Scheda Crediti](../specs/mockups/fdcp-credits.webp)

![Scheda Progress](../specs/mockups/fdcp-progress.webp)

![Scheda Loot, master looter](../specs/mockups/fdcp-loot-session.webp)

![Popup del pezzo](../specs/mockups/fdcp-roll-popup.webp)

## Temi

Il tema predefinito è **Nebula**, l'aspetto scuro del sito della community. Lo cambi nelle Impostazioni, senza `/reload`:

- **Aurora** è il tema chiaro del sito.
- **Drago** usa i colori del logo della gilda.

I colori delle classi e della qualità degli oggetti sono sempre quelli del gioco.

![Impostazioni: tema](../specs/mockups/fdcp-settings-theme.webp)

## Che cosa sarà diverso dal sito

Il gioco non ha gli stili del web, quindi alcune cose sono approssimate:

- niente vetro sfocato dietro i dialog;
- i bagliori sono immagini sfumate;
- i gradienti hanno due colori;
- le animazioni sono semplici;
- nei titoli non c'è spaziatura fra le lettere.

Il carattere del logo del sito non si può ridistribuire, quindi i titoli usano un carattere libero dalla forma simile. I caratteri del testo e dei numeri sono gli stessi del sito.

Vedi anche: [[Esportazione per il sito|Site-Export-it]] · [[Comandi|Commands-it]]
