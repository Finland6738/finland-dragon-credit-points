# Preparazione del raid

> **Costruito, non ancora visto in gioco.** La scheda, l'avviso e i sussurri funzionano nei test offline; come risponde il client vero (gli ID di oggetti e buff, i sussurri di un raid pieno) è ancora da confermare in gioco. [English](Raid-Readiness)

Prima di un pull il master looter vuole sapere chi non è pronto: un incantamento mancante, nessun flask, nessuna pozione, niente acqua per i healer, niente munizioni per i cacciatori. FDCP interroga l'addon di ogni raider e mostra le risposte in una sola tabella; un pulsante dice al raid cosa manca.

## Chi la vede

**Roster › Preparazione** c'è per il master looter della serata e per chi ha il permesso *vedere chi non ha l'addon e avvisarlo* (gli officer, di partenza): le stesse persone che usano il [[Controllo dell'addon|Addon-Check-it]]. Per tutti gli altri la sotto-scheda non si vede. Fuori da un raid lo dice e i pulsanti sono spenti.

## Come funziona

- **Controlla il raid** interroga l'addon di ogni raider. Ognuno guarda **il proprio** personaggio (quali slot hanno un incantamento, quali buff di cibo, flask ed elisir sono attivi, quanti consumabili ci sono nelle borse) e ti sussurra una piccola risposta. Nient'altro delle borse si legge né si manda. Il controllo non si fa mai in combattimento né durante un boss: una risposta aspetta la fine dello scontro.
- Puoi chiedere una volta ogni 30 secondi; il pulsante mostra i secondi che mancano.
- Un raider senza addon, offline o con una versione vecchia è **Ignoto**, e la riga dice perché.
- Non si salva nulla. Un nuovo controllo, l'uscita dal raid o `/reload` svuotano la tabella. Non entra mai nel registro, nei crediti, negli export né nell'API per altri addon.

## La tabella

Una riga per membro del raid, per primi quelli che richiedono attenzione:

| Colonna | Significato |
|---|---|
| **Nome** | Nel colore della classe. |
| **Stato** | **OK**, **Scarso** (ce n'è, ma meno del richiesto), **Manca**, o **Ignoto** (nessuna risposta, o un valore che il gioco non mostra). |
| **Incantamenti mancanti** | Gli slot senza incantamento, per nome (polsi, mani, schiena...). Una riga senza risposta dice perché: non ancora richiesto, in attesa di risposta, senza addon, offline, nessuna risposta. |
| Cibo con buff, Cibo, Ampolla, Pozioni, Acqua, Munizioni, Cibo pet | **OK**, *ha/serve* (arancio se scarso, rosso se manca del tutto), **?** se non si è potuto leggere, **-** se a quel raider non è richiesto (l'acqua è per le classi con mana, munizioni e cibo del pet per i cacciatori). |

Il riassunto sopra la tabella dice, per esempio, **31 ok · 5 scarsi · 3 mancanti · 1 ignoto** e **36/40 risposte**. La tabella si ridisegna man mano che arrivano le risposte.

Un flask o un elisir vale se ne è **attivo** uno, anche senza averne nelle borse; lo stesso per il cibo con buff. Un valore che l'addon non riesce a leggere si mostra come ignoto e non si indovina mai.

## Avvisa il raid

**Avvisa il raid** chiede conferma (*Scrivere N righe in /raid e sussurrare a M giocatori?*) e poi scrive:

1. Un riassunto breve in `/raid`, per esempio `[FDCP] Preparazione: 2 con mancanze, 1 con scorte basse. Controllate i sussurri.`, seguito dai nomi raggruppati per cosa manca (`[FDCP] pozioni: Aurel, Corin`). Gli elenchi lunghi si dividono su più righe di al massimo 255 caratteri, senza tagliare un nome.
2. **Un sussurro a ogni raider** con stato Manca o Scarso, che dice esattamente cosa e dove: `[FDCP] Ti manca: incantamento polsi, mani; pozioni 0/2; ampolla 0/1`. Chi è Ignoto non riceve sussurri. Le righe sono nella **tua** lingua.

Le regole del pulsante:

- Parte **solo dal tuo clic**, mai da solo.
- Mai durante un boss o mentre il gioco blocca la chat: l'avviso **aspetta** e parte alla fine dello scontro (dopo 10 minuti si butta, perché la tabella sarebbe vecchia).
- I messaggi partono uno alla volta, a meno di un secondo l'uno dall'altro.
- Al massimo **un avviso ogni 5 minuti** (il Guild Master lo cambia in Impostazioni › Regole › Messaggi in /raid, *Minuti tra due avvisi*); il pulsante mostra i secondi che mancano.
- Ogni avviso finisce nel registro del tuo personaggio (quando, quante righe e sussurri, se ha dovuto aspettare).

## I requisiti

Cosa è richiesto lo decide il Guild Master, in **Impostazioni › Regole › Preparazione del raid**:

- l'interruttore dell'intero controllo;
- un interruttore per ogni slot che richiede un incantamento (testa, spalle, petto, gambe, piedi, polsi, mani, schiena, mano principale, mano secondaria, a distanza: lo slot a distanza si chiede solo ai cacciatori);
- il **minimo** di ogni consumabile (0 = non richiesto): cibo con buff, cibo, ampolla o elisir, pozioni, acqua, munizioni, cibo pet;
- se l'acqua si chiede solo alle classi con mana, e munizioni e cibo del pet solo ai cacciatori;
- il testo della riga `/raid` e del sussurro (vuoto = quello predefinito della lingua; segnaposto `{missing} {low} {unknown} {total}` nella riga `/raid`, `{list} {name}` nel sussurro).

I valori di partenza: incantati petto, piedi, polsi, mani, schiena e gli slot delle armi; 1 cibo con buff, 5 cibo, 2 pozioni e 1 flask o elisir per tutti; 10 acqua per le classi con mana; 1000 munizioni e 10 cibo pet per i cacciatori. Testa, spalle e gambe sono spenti.

> **Per il Guild Master:** cambiare questi requisiti scrive una nuova versione delle regole che un addon più vecchio di questo non sa leggere. Chiedi prima a tutti gli officer di aggiornare. Finché i requisiti sono quelli di partenza per loro non cambia nulla.

Vedi anche [[Impostazioni|Settings-it]], [[Controllo dell'addon|Addon-Check-it]] e [[Privacy e dati|Privacy-and-Data-it]].
