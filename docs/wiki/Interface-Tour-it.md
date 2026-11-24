# Giro dell'interfaccia

> **Mockup, non screenshot.** Le immagini di questa pagina sono disegnate da `tools/make_mockups.py` dal layout e dai testi dell'addon, con nomi inventati, nello stile della pagina WoW Forever del sito della community. Nulla è ancora stato verificato in gioco, quindi la finestra vera può differire in piccoli dettagli. Qui le immagini sono in italiano; la pagina inglese ha quelle in inglese. [English](Interface-Tour)

## Cosa esiste ora

La finestra è costruita: la aprono `/fdcp`, il pulsante della minimappa (il logo della gilda) o la voce nell'AddOn Compartment. Ha la barra del titolo, le sei schede qui sotto, i **temi** (Nebula, Aurora, Drago: `/fdcp theme`) e le schede si riempiono con le versioni: Roster, Crediti, Progress e **Loot › Sessione** (la finestra del master looter, vedi la [[Guida del master looter|Master-Looter-Guide-it]]) e **Loot › Council** (vedi [[Council|Council-it]]) funzionano già, e anche **Storico › Serate** (vedi [[Storico|History-it]]); **Impostazioni** (vedi [[Impostazioni|Settings-it]]) ha le tue preferenze, le regole e i permessi della gilda (in sola lettura se non sei il Guild Master), la chiave del sito e la **Season** (vedi [[Season|Seasons-it]]). Si trascina dalla barra del titolo, si ridimensiona dall'angolo in basso a destra (non sotto 900 × 560) e ricorda dove stava per ogni personaggio; **Esc** la chiude. I font sono Outfit, JetBrains Mono e Orbitron, inclusi nell'addon (font liberi, SIL Open Font License); se uno non si carica si usa il font del gioco. Le immagini qui sotto sono ancora anteprime di progetto: la finestra vera non è stata ancora vista in gioco.

## Una finestra, sei schede

`/fdcp` (o il pulsante della minimappa) apre una sola finestra. La barra del titolo mostra il logo della gilda, la season, la tua fazione e se c'è una serata aperta. Sotto ci sono le schede, come sul sito della community. Vedi solo le schede che il tuo rango di gilda può usare.

| Scheda | Che cosa trovi |
|---|---|
| **Roster** | Il roster dei raid della fazione della tua gilda come sul sito: una colonna per tank, healer e DPS, con i posti liberi e chi è in prova. I giocatori ci entrano da qui (**Entra nel roster**); gli officer approvano le richieste, aggiungono giocatori direttamente o tutto il gruppo raid, e vedono la lineup della serata, la panchina e chi nel raid ha l'addon. |
| **Crediti** | La tabella dei crediti della season come sul sito: una colonna per serata, il tuo totale e il tuo posto nella fila del loot. Meno crediti vuol dire più precedenza. |
| **Progress** | Ogni boss di ogni raid, con la data della prima uccisione della tua gilda e dell'altra, come sul sito. |
| **Loot** | La sessione di loot del master looter: i pezzi, chi ha risposto, i roll e il vincitore proposto. Gli altri la vedono in sola lettura. Sotto-schede: **Sessione**, **Da consegnare** e **Council** (le segnalazioni, il voto, l'annullamento di un'assegnazione, la correzione dei crediti, l'audit e i progetti leggendari: [[Council|Council-it]]). |
| **Storico** | Le serate passate per settimana con chi ha preso cosa, lo storico di un membro e di un oggetto ([[Storico|History-it]]), il log del loot, l'audit delle correzioni e le esportazioni (Discord, CSV, JSON e i file del sito della community). |
| **Impostazioni** | Le tue preferenze (tema, effetti, font, lingua), le regole della gilda (in sola lettura se non sei il GM) e le impostazioni del sito. |

Quando c'è un pezzo a cui rispondere compare un **popup** a parte, con una card per ogni pezzo: vedi [[Rollare per il loot|Rolling-for-Loot-it]].

## La scheda Progress

Una card per raid, come sul sito: la copertina (l'immagine del raid dal Diario delle avventure del gioco quando il client ce l'ha, una generata altrimenti), la dimensione e il nome e, per ogni gilda, una barra con `uccisioni/totale`. Sotto, i boss su due colonne: il numero, il nome e, per ogni gilda, un teschio con la data della prima uccisione oppure un cerchio tratteggiato se il boss non è ancora caduto. La prima gilda è la tua. La colonna dell'altra gilda mostra solo le date che un officer ha inserito per lei: le due gilde non si scambiano mai dati. Con la rotellina del mouse si scorre quando le card non stanno nella finestra.

Le tue prime uccisioni si registrano da sole: durante una serata ufficiale o, fuori da una serata, in un gruppo di gilda. Gli officer (i ranghi con il permesso `progress.edit`, di norma il Guild Master e gli officer) possono anche **inserire o correggere una data**: clicca la riga del boss, scegli la gilda, scrivi la data come `AAAA-MM-GG` (non nel futuro) e premi **Salva**. **Rimuovi la data inserita** toglie un valore messo a mano; un'uccisione registrata dall'addon non si toglie così. Per gli altri la scheda è di sola lettura. Ogni modifica è una riga dell'audit.

## Mockup

Dieci delle finestre, come sono progettate. Ognuna è spiegata nella sua pagina di questo manuale.

### Il popup del roll

![Il popup del roll: tre pulsanti e il badge di upgrade](../specs/mockups/fdcp-roll-popup-it.webp)

*Mockup, non uno screenshot del gioco.*

### La sessione del master looter

![Loot › Sessione, la finestra del master looter](../specs/mockups/fdcp-loot-session-it.webp)

*Mockup, non uno screenshot del gioco.*

### Il council

![Loot › Council: segnali, prove di imbroglio, voto, assegnazioni](../specs/mockups/fdcp-council-it.webp)

*Mockup, non uno screenshot del gioco.*

### Crediti

![La scheda Crediti](../specs/mockups/fdcp-credits-it.webp)

*Mockup, non uno screenshot del gioco.*

### Roster

![Roster › Pool](../specs/mockups/fdcp-roster-it.webp)

*Mockup, non uno screenshot del gioco.*

### Una serata

![Roster › Serata, con le penalità di assenza](../specs/mockups/fdcp-night-it.webp)

*Mockup, non uno screenshot del gioco.*

### Progress

![La scheda Progress](../specs/mockups/fdcp-progress-it.webp)

*Mockup, non uno screenshot del gioco.*

### Permessi

![Impostazioni › Permessi](../specs/mockups/fdcp-permissions-it.webp)

*Mockup, non uno screenshot del gioco.*

### Season

![Impostazioni › Season, con la fascia di item level](../specs/mockups/fdcp-season-it.webp)

*Mockup, non uno screenshot del gioco.*

### Info

![Impostazioni › Info](../specs/mockups/fdcp-about-it.webp)

*Mockup, non uno screenshot del gioco.*

## Temi

Il tema predefinito è **Nebula**, l'aspetto scuro del sito della community. Lo cambi nelle Impostazioni, senza `/reload`:

- **Aurora** è il tema chiaro del sito.
- **Drago** usa i colori del logo della gilda.

I colori delle classi e della qualità degli oggetti sono sempre quelli del gioco. Nel tema chiaro Aurora il nome di un giocatore è scritto nel colore normale del testo e solo il quadratino accanto porta il colore della classe, così un sacerdote bianco resta leggibile.

## Effetti e animazioni

Due preferenze cambiano l'aspetto della finestra, entrambe attive di default e applicate subito, senza `/reload`:

- **Effetti neon** (`/fdcp effects on|off`): i bagliori morbidi (quello ambra dietro il pulsante principale, quello magenta sull'unico popup evidenziato, quello sotto il titolo e il logo) e le ombre sotto finestre e card. Spenti, la finestra è piatta.
- **Animazioni** (`/fdcp animations on|off`): le transizioni brevi (120 ms per un pulsante premuto o sotto il mouse, 200 ms per le schede, 320 ms per l'entrata di una card o di un dialog e per la freccia della season che ruota). Spente, tutto cambia di colpo, come per chi preferisce meno movimento.

Gli stessi due interruttori sono in **Impostazioni › Personali** (vedi [[Impostazioni|Settings-it]]).

![Impostazioni: preferenze personali, con i tre temi](../specs/mockups/fdcp-settings-it.webp)

*Mockup, non uno screenshot del gioco.*

## Che cosa sarà diverso dal sito

Il gioco non ha gli stili del web, quindi alcune cose sono approssimate:

- niente vetro sfocato dietro i dialog;
- i bagliori sono immagini sfumate sommate all'immagine;
- i gradienti hanno due colori;
- le animazioni sono semplici e finiscono sempre allo stesso modo (niente curve a molla);
- nei titoli non c'è spaziatura fra le lettere.

Il carattere del logo del sito non si può ridistribuire, quindi i titoli usano un carattere libero dalla forma simile. I caratteri del testo e dei numeri sono gli stessi del sito.

Vedi anche: [[Esportazione per il sito|Site-Export-it]] · [[Comandi|Commands-it]]
