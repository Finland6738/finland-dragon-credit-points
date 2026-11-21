# Guida del master looter

> **Costruito, non ancora visto in gioco.** La finestra della sessione funziona nei test offline con un raid simulato; come appare e come si usa in un raid vero, e la consegna del pezzo, sono ancora da confermare in gioco. [English](Master-Looter-Guide)

Questa pagina è per il **master looter**: chi apre il corpo del boss e guida il roll. L'addon fa i conti e scrive la proposta; **tu confermi, rifiuti o modifichi**. Non calcoli mai i crediti a mano e non scrivi mai il motivo di un'assegnazione normale: lo fa l'addon. Scrivi un motivo solo quando ti discosti dalla regola.

## Prima del raid

- Imposta il metodo di bottino su **Master Looter** (l'addon lavora solo dal client del master looter) e la soglia sulla qualità per cui la gilda rolla.
- Tutti nel raid devono avere l'addon attivo: solo chi ce l'ha può rispondere e rollare. Vedi [[Controllo dell'addon|Addon-Check-it]]. La scheda Loot ti avvisa, per esempio **3 membri del raid non possono rollare**, con il pulsante **Avvisa in /raid** (per chi può usare il controllo dell'addon) che scrive l'avviso per te.
- Apri la serata ([[Roster e Serate|Roster-and-Nights-it]]) così uccisioni e assegnazioni appartengono a lei.

## Un boss, passo per passo

1. **Uccidi il boss.** Quando il boss muore l'addon apre una sessione sul tuo client. Durante il combattimento non si apre nulla: la sessione aspetta la fine del combattimento, di una restrizione dell'addon o del lockdown della chat.
2. **Apri il corpo.** Quando apri la finestra del bottino la finestra principale si apre su **Loot › Sessione**. I pezzi pari o sopra la soglia sono elencati a sinistra, ciascuno con categoria e costo (per esempio *Gioiello · 1 credito*), proposti dall'addon dalla tabella della gilda. Se i drop sono stati letti durante un lockdown, la finestra dice che sono in attesa e li legge appena finisce.
3. **Controlla la lista.** Seleziona un pezzo per vederlo a destra. Se una categoria o un costo è sbagliato, premi **Correggi** (vedi sotto). **Togli** toglie dalla lista un pezzo che non vuoi in sessione.
4. **Premi Avvia la sessione.** Categorie e costi vanno al raid. Con le impostazioni solite della gilda (avanzamento automatico) il primo roll si apre da solo; altrimenti premi **Apri il roll** sul pezzo che vuoi.
5. **Il roll.** Ogni raider con l'addon riceve un popup, risponde *Main-spec*, *Off-spec* o *Passo* (con un'etichetta e una nota facoltative) e rolla: vedi [[Rollare per il loot|Rolling-for-Loot-it]]. La parte destra della tua finestra si riempie man mano che arrivano risposte e roll: per ogni candidato i crediti, la risposta, il roll e una nota. Una barra sottile e un orologio contano il tempo del round. Il round si chiude da solo al timer o quando tutti hanno risposto e rollato; puoi chiuderlo prima con **Chiudi il round**. Se nessuno ha chiesto il pezzo in main-spec, il round off-spec si apre da solo; se due giocatori sono pari per crediti e roll, si apre un reroll fra loro.
6. **La proposta.** Quando il round si chiude l'addon scrive **a chi, quanto e perché**, per esempio *Proposta: Bryn, 1 credito. Stessi crediti degli altri, roll più alto.* Il giocatore proposto è segnato nella lista. Sotto la frase, in ambra, ciò che va guardato (roll scartati, un costo che deve fissare il council, una parità che le regole non sciolgono, una proposta dopo un rifiuto).
7. **Decidi tu:**
   - **Conferma e assegna** scrive l'assegnazione nel registro con il motivo dell'addon e addebita i crediti. Non c'è altro da scrivere.
   - **Rifiuta** non addebita nulla e rimette il pezzo in gioco (vedi sotto).
   - **Modifica** cambia il vincitore o il costo e vuole un motivo (vedi sotto).
8. **Il pezzo dopo.** Con l'avanzamento automatico il roll successivo si apre da solo dopo ogni assegnazione, quindi un boss con cinque pezzi sono cinque conferme. C'è sempre **un solo pezzo in corso**: il roll successivo si apre dopo l'assegnazione del precedente, così i crediti del suo vincitore sono già addebitati. Per questo non esiste il pulsante *Conferma tutto*: non c'è mai una seconda proposta in attesa.
9. **Chiudi la sessione** con **Chiudi sessione** quando l'ultimo pezzo è fatto (è disponibile finché nessun pezzo è in corso). I pezzi mai rollati restano elencati come in attesa. Anche la morte del boss successivo chiude la sessione precedente se nessun pezzo è in corso.

Se la finestra è chiusa, `/fdcp` la apre sulla scheda Loot mentre una sessione è in corso.

> **Consegna del pezzo.** **Conferma e assegna** consegna anche il pezzo, nello stesso clic: vedi [Consegna del pezzo](#consegna-del-pezzo) più sotto.

## Consegna del pezzo

**Conferma e assegna** fa due cose nello stesso clic: scrive l'assegnazione e addebita i crediti, e chiede al gioco di consegnare il pezzo al vincitore con il **master loot**. Il tuo clic è quello che il gioco può richiedere.

**Piano A: master loot.** L'addon cerca il pezzo nella finestra del bottino aperta (dal pezzo, non dalla posizione: la lista chiude i buchi man mano che i pezzi escono) e il vincitore nell'elenco del master loot, e lo consegna. Il pezzo aspetta poi in **Loot › Da consegnare** come *Consegnato: aspetto il messaggio del bottino* finché il messaggio di bottino del vincitore in chat (*Bryn riceve il bottino*) viene letto: allora è **Consegnato** ed esce dalla lista. Se il pezzo lo vinci tu, il tuo *Ricevi il bottino* è la ricevuta.

**Piano B: per scambio.** Quando il master loot non può farlo, l'assegnazione resta nel registro (i crediti sono addebitati comunque) e il pezzo va nell'elenco **Da consegnare** con il motivo:

| L'elenco dice | Cosa è successo |
|---|---|
| Qui il master loot non è in uso | Non sei il master looter, o il gruppo usa un altro metodo di loot: il caso tipico del piano B. |
| La finestra del bottino è chiusa | Hai chiuso il corpo prima di confermare. Riaprilo: l'addon riprova da solo. |
| Il pezzo non è più nella finestra del bottino | Qualcuno lo ha lootato, o era già stato consegnato. |
| Il vincitore non è nell'elenco del master loot | Troppo lontano, o non nel raid. Digli di avvicinarsi e premi **Consegna ora**, oppure scambia. |
| Il gioco ha rifiutato la consegna | Il gioco non ha accettato la chiamata. Premi **Consegna ora** (il tuo clic), oppure scambia. |

Consegna il pezzo con un **normale scambio**: l'addon non avvia, non riempie e non accetta mai uno scambio al posto tuo, guarda solo quelli che fai. Quando uno scambio che dà il pezzo al suo vincitore va a buon fine (o ricevi in uno scambio un pezzo che hai vinto tu), il pezzo è segnato **Consegnato**. Quando un messaggio di bottino mostra chi ha il pezzo, l'elenco lo dice (*Lo ha Corin*). Un pezzo che il vincitore aveva già lootato prima della tua conferma è consegnato subito.

**La scheda Da consegnare** elenca ogni pezzo assegnato che non è ancora arrivato al vincitore: il pezzo, il vincitore e a che punto è. Seleziona una riga e usa:

- **Consegna ora (master loot)**: riprova con il master loot, dal tuo clic. Usalo dopo aver riaperto il corpo o quando il gioco ha rifiutato. È nascosto mentre il pezzo aspetta il suo messaggio di bottino.
- **Segna come consegnato**: la tua parola che il pezzo è arrivato al vincitore (uno scambio che l'addon non ha potuto leggere, un messaggio di bottino nascosto dal gioco). Viene scritto come consegnato a mano.

L'intestazione della scheda Sessione conta i pezzi ancora da consegnare.

**Rollare tutto a fine serata.** Puoi rollare prima tutti i pezzi e consegnarli dopo: i pezzi restano nell'elenco, **Chiudi sessione** li tiene, e quando muore il boss successivo passano nell'elenco della sessione nuova, così non si perde nulla fra un boss e l'altro, nemmeno dopo un `/reload`. Quando riapri un corpo, i pezzi che lo aspettavano sono riprovati da soli (non quelli che il gioco ha rifiutato: aspettano il tuo clic).

> **Non ancora verificato in gioco:** che un addon possa chiamare `GiveMasterLoot` da un clic, che la finestra del bottino e l'elenco del master loot si leggano come descritto, cosa portano gli eventi dello scambio e se i messaggi di bottino sono leggibili dentro un'istanza. Se un passaggio non funziona, il pezzo aspetta nell'elenco e lo consegni con uno scambio.

## Leggere la tabella dei candidati

| Colonna | Significato |
|---|---|
| **Candidato** | Il nome, nel colore della classe. |
| **Crediti** | I crediti del giocatore all'apertura del roll di questo pezzo (congelati per il pezzo, così il risultato è quello contro cui il raid ha rollato). |
| **Risposta** | Main-spec, Off-spec o Passo, con l'etichetta dichiarata dal giocatore (*BiS*, *Upgrade grande*, *Upgrade piccolo*, *Situazionale*) se l'ha data; un punto se non ha ancora risposto. L'etichetta informa te e il council; non cambia mai la proposta. |
| **Roll** | Il primo roll 1-100 del round in corso (un reroll lo sostituisce per i pari). |
| **Note** | *Proposto* per il vincitore; *Non ha ancora risposto* a round aperto; la nota che il giocatore ha scritto nel suo popup (dopo gli altri testi); il motivo per cui un roll è stato scartato (un secondo roll, non 1-100, troppo presto, **l'addon non è attivo**). |

Ordina cliccando su un'intestazione. La lista è in ordine: prima main-spec, poi meno crediti, poi il roll più alto. In un reroll i giocatori non pari sono attenuati.

Un giocatore che rolla senza l'addon **non** conta: il roll compare con *L'addon non è attivo* così lo vedi, e lui non può rispondere.

## Modifica

Premi **Modifica** su una proposta. Si apre una scheda con:

- **Nuovo vincitore**: prima i candidati (con risposta e crediti), poi il resto del raid, poi **Alla banca di gilda** e **Da disincantare**. Un nuovo vincitore paga il costo della propria risposta, o il costo pieno se non ha risposto.
- **Costo in crediti**: cambialo se il vincitore deve pagare altro.
- **Motivo (obbligatorio)**: uno dell'elenco, mai testo libero:

| Motivo | Quando |
|---|---|
| Spreco palese | Dato a un altro candidato invece del primo in fila. |
| Passa per fare il furbo | Dato a chi non ha rollato, a costo pieno. |
| Il council ha stabilito il costo | Un costo deciso dal council. |
| La categoria o il costo era sbagliato | Una correzione a posteriori. |
| Un pezzo di una catena leggendaria | I pezzi leggendari. |
| Un errore del master looter o dell'addon | Uno sbaglio. |
| Un altro motivo | Qualunque altro (diccelo al raid). |

Mentre scegli, la scheda mostra la proposta che ne risulterebbe e **come si discosta dalla regola**: *Fuori fila: Bryn era primo, invece Corin.* e *Costo: 2 crediti invece di 1 credito come da regola.* **Salva** viene rifiutato, con il motivo a parole, finché non scegli un motivo o se non è cambiato nulla. Una proposta modificata resta una proposta: premi comunque **Conferma e assegna**. L'assegnazione è segnata nell'audit come intervento, con vincitore e costo della regola, il codice del tuo motivo e il tuo nome.

## Rifiuta

**Rifiuta** apre le scelte su cosa succede al pezzo. Nessuno viene addebitato:

| Scelta | Effetto |
|---|---|
| Rimetti il pezzo in gioco: riaprilo dopo | Torna in attesa, segnato *Sospeso*; apri il suo roll quando vuoi (selezionalo e premi **Apri il roll**). L'avanzamento automatico non lo riapre. |
| Riapri subito il roll | Si apre subito un roll nuovo. |
| Passa al tier successivo | I tier fino a quello della proposta vengono saltati (per esempio finito il main-spec, si va all'off-spec). |
| Mandalo alla banca di gilda / Disincantalo | Una nuova proposta per il personaggio banca o il disincantatore. |

La proposta successiva porta la nota *È una nuova proposta dopo un rifiuto.*

## Correggi (prima del roll)

**Correggi** è disponibile finché il pezzo non ha una proposta: scegli la **categoria** giusta, oppure scrivi il **costo base** (il moltiplicatore di ogni risposta si applica ancora), e dai un motivo. È bloccato dopo l'apertura del roll del pezzo quando le regole della gilda bloccano la categoria all'apertura.

## Pausa, timer e lockdown

- **Pausa** ferma i timer e i passi automatici e conserva il tempo rimasto; **Riprendi** continua. I tuoi pulsanti funzionano anche in pausa.
- La sessione non apre né chiude nulla durante un combattimento col boss o un lockdown della chat: aspetta e prosegue dopo. Un roll che il gioco ha nascosto durante il lockdown viene letto quando finisce, e il round non si chiude prima.
- Se fai `/reload` o ti disconnetti, la sessione torna come l'hai lasciata, anche a metà di un reroll.

## Gli altri officer

Gli officer che non sono il master looter vedono la stessa finestra **in sola lettura**: i pezzi, il round, la proposta e i suoi motivi, ma nessun pulsante e nessuna tabella dei candidati (le risposte vanno solo al master looter). Chi non ha il permesso vede invece il proprio popup.

## Se la gilda usa altre modalità

La gilda può impostare l'assegnazione **automatica** (l'addon conferma da solo una proposta pulita dopo una breve finestra, mai dopo un tuo intervento; la striscia dice *L'addon conferma da solo fra N s* e puoi ancora Rifiutare o Modificare in quel tempo) oppure **council** (il council vota; arriva in una versione successiva). Quale modalità vale è una regola della gilda: vedi [[Regole del loot|Loot-Rules-it]].
