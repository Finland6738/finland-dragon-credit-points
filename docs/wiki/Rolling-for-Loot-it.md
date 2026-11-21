# Rollare per il loot

> **Costruito, non ancora visto in gioco.** Il popup funziona nei test offline con un raid simulato; come appare in un raid vero, il tooltip del pezzo con il confronto e il roll dal pulsante sono ancora da confermare in gioco. [English](Rolling-for-Loot)

Questa pagina è per **ogni raider**. Quando il master looter apre il roll di un pezzo, l'addon ti mostra una finestra piccola, il **popup del pezzo**. Rispondi lì, rolli da lì, e sparisce quando il round si chiude. Non devi mai scrivere `/roll` a mano.

Ti serve l'addon attivo: solo i raider con l'addon possono rispondere e rollare, e un `/roll` scritto da chi non ce l'ha viene messo da parte (vedi [[Controllo dell'addon|Addon-Check-it]]).

## Il popup

![Popup del pezzo](../specs/mockups/fdcp-roll-popup.webp)

Dall'alto in basso:

- **La riga del titolo.** *ROLL APERTO · nome del boss* (o *REROLL*, o *ROLL LIBERO*, vedi sotto) e a destra il **timer** in minuti e secondi. Diventa ambra negli ultimi cinque secondi e dice *In pausa* quando il master looter mette in pausa. La crocetta nasconde la card per questo round.
- **Il pezzo.** L'icona e il nome nel colore della qualità e sotto lo slot, il tipo (stoffa, piastre, spada a una mano...) e il livello dell'oggetto. **Passa il mouse sull'icona o sul nome** per vedere il tooltip del gioco per il pezzo, con il confronto con quello che indossi.
- **Il chip del costo**, per esempio *ARMA · 2 CREDITI*: la categoria che la tabella della gilda ha dato al pezzo e quanto paghi se lo vinci con la risposta che hai scelto (prima di rispondere, il costo pieno). *COUNCIL* vuol dire che il costo lo decide il council. Accanto, quando il tuo client conosce la tabella dei crediti della gilda, **i tuoi crediti e il tuo posto stimato in fila**: *I tuoi crediti 2 · fila ~3ª*. Il posto è "1 + i membri del raid con meno crediti"; è una stima, perché una parità la decide il roll.
- **La tua risposta:** **Main-spec**, **Off-spec** o **Passo**. Clicca e parte subito. Puoi cambiare idea finché non rolli.
- **Un'etichetta, facoltativa**, per una risposta main-spec: **BiS**, **Upgrade grande**, **Upgrade piccolo** o **Situazionale**. Cliccala per metterla, cliccala di nuovo per toglierla. Informa solo il master looter e il council; non cambia mai chi vince. Se clicchi un'etichetta prima di rispondere, risponde main-spec al posto tuo. Off-spec e Passo non hanno etichetta.
- **Una nota, facoltativa.** Al massimo 80 caratteri (qualche parola in meno se usi le lettere accentate). Parte quando esci dalla casella, premi Invio o premi **Tira**.
- **La barra del timer**, che si svuota con il passare del tempo.
- **La riga di aiuto** e il pulsante **Tira**.

Il popup è una finestra a sé: **trascinalo da una qualunque card** per spostarlo e trascina la maniglia sottile sul bordo destro per allargarlo. Posizione e larghezza si ricordano per ogni personaggio.

## Come va un roll

1. **Rispondi.** Scegli Main-spec, Off-spec o Passo (e un'etichetta o una nota se vuoi).
2. **Tira.** Premi **Tira**: l'addon chiede al gioco `/roll 1-100`, esattamente come se lo avessi scritto tu. Il roll è del gioco e nessuno può sceglierlo. Il pulsante dice poi *Tirato* e la tua risposta si blocca: dopo aver rollato non puoi più cambiarla. Rolli **una volta** per round; un secondo roll non conta.
3. **Aspetta.** Il round si chiude da solo allo scadere del timer, o quando tutti hanno risposto e rollato. Il popup si chiude con lui e la finestra del master looter mostra la proposta.

**Passo** non richiede un roll. Se non rispondi affatto, per le regole è come un passo.

### Chi rolla e quando

- Le risposte **main-spec** rollano nel primo round. Se nessuno risponde main-spec, il **round off-spec** si apre da solo: se hai risposto Off-spec compare un nuovo popup con il solo **Tira**; se hai risposto Main-spec o Passo non vedi nulla.
- Se due giocatori sono **pari** per crediti e roll, si apre un **reroll** solo fra loro: il popup dice *REROLL* e lo vedono solo i pari.
- Se nessuno voleva il pezzo e la gilda usa un **roll libero**, il popup dice *ROLL LIBERO* e può rollare chiunque.

La riga di aiuto sotto la barra ti dice cosa fare adesso: *Scegli la risposta, poi tira*; *Il roll parte dal gioco: /roll 1-100*; *Tiri solo se nessuno chiede il pezzo prima di te* (hai risposto un tier più basso); *Siete pari: tira ancora*; *Tirato. Il master looter ha il tuo roll*.

## Se qualcosa va storto

- *Non è stato possibile inviare la tua risposta.* L'addon non è riuscito a consegnare la risposta al canale del raid; clicca di nuovo la risposta.
- *Il gioco non ha lasciato tirare all'addon: scrivi /roll 1-100.* Il client ha rifiutato il roll dal pulsante; scrivi tu il comando, conta uguale.
- **Hai ricaricato l'interfaccia o sei entrato durante un roll.** L'addon del master looter ti rimanda il popup con la tua risposta, l'etichetta e la nota com'erano.
- **Sei entrato nel raid dopo l'apertura del roll.** Vedi il popup, ma il raid di un pezzo si fissa quando si apre il suo roll: la tua risposta non conta per quel pezzo, solo dal successivo.

## Cosa vede il master looter

La tua risposta, l'etichetta e la nota, accanto ai tuoi crediti, nella tabella dei candidati della [[Guida del master looter|Master-Looter-Guide-it]]. Viaggiano sul canale addon del raid come ogni messaggio della sessione di loot; gli addon degli altri giocatori non li mostrano. Nessuno può rispondere a nome tuo: l'addon del master looter prende il giocatore dal mittente del messaggio, mai da quello che il messaggio dice.

Il popup non dice ancora se il pezzo è un upgrade per te: quell'indizio arriva con una versione successiva.
