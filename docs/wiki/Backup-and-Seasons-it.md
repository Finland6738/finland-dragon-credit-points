# Backup e season

> **Costruito, non ancora visto in gioco.** Tutto quello che c'è in questa pagina funziona nei test offline con un client simulato; l'aspetto della sotto-scheda, l'incolla di una stringa lunga e la dimensione dei dati salvati dopo una season lunga sono ancora da confermare nel gioco vero. [English](Backup-and-Seasons)

Il registro della gilda vive nei dati salvati del gioco di ogni officer. Questa pagina spiega come tenerne una copia fuori dal gioco, come condividere le regole della gilda con un'altra gilda e come rimpicciolire i dati salvati alla fine di una season.

## Dove si trova

**Storico › Backup** (la scheda Storico, quinta sotto-scheda). Ha tre modi, **Impostazioni**, **Backup** e **Archivio**, sopra un'unica casella di testo. **Genera** mette una stringa nella casella; **Seleziona tutto** la seleziona così **Ctrl+C** la copia (un addon non può scrivere negli appunti). Per importare o ripristinare, prima incolla una stringa nella casella con **Ctrl+V**.

Ogni stringa comincia con `!FDCP:` e dice cosa contiene: `!FDCP:CFG:` (impostazioni), `!FDCP:BAK:` (backup), `!FDCP:ARC:` (archivio). Spazi e a capo si ignorano, quindi una stringa spezzata da una finestra di chat o da Discord funziona lo stesso. Una stringa di una versione più nuova dell'addon viene rifiutata con un messaggio.

## Impostazioni: condividere le regole

- **Chiunque** può generare la stringa delle impostazioni: le regole sono già visibili a ogni membro in sola lettura.
- La stringa porta tutta la configurazione (costi, priorità, sessione, council, leggendari, panchina, avvisi, suggerimenti di upgrade) **tranne ciò che è solo della tua gilda**: l'elenco dei nomi del council e il nome della fazione sul sito della community. Quando un'altra gilda la importa, quei due restano quelli di quella gilda.
- **Solo il Guild Master** importa. Incolla la stringa e premi **Importa…**: una finestra dice quante impostazioni cambiano e quali; niente viene scritto finché non premi **Conferma**. L'importazione è una modifica delle regole, scritta nell'audit con il tuo nome (Storico › Audit, *Impostazioni*). Se non cambierebbe niente, la scheda lo dice.

## Backup: una copia di tutto il registro

- Gli **officer** (`view.attendance`) generano la stringa di backup: ogni evento del registro, presenze comprese, quindi tienila riservata. Salvala in un file di testo fuori dal gioco ogni tanto, e prima di qualunque operazione rischiosa (reinstallare il gioco, pulire la cartella `WTF`).
- **Ripristina** (`season.manage`, il Guild Master di base): incolla la stringa e premi **Ripristina…**. La finestra dice quanti eventi contiene il backup e quanti mancano qui. Un ripristino **aggiunge solo ciò che manca**: non toglie mai un evento e non ne sovrascrive nessuno. Ripristinare due volte lo stesso backup, o un backup più vecchio, non cambia niente. Ogni evento passa comunque dal controllo dei permessi della gilda, come nella sincronizzazione fra officer.
- Ogni ripristino è scritto nell'audit (*ha ripristinato un backup*), con il tuo nome e quanti eventi ha aggiunto.
- Ripristinato in un registro vuoto (un computer nuovo, dati salvati persi), un backup restituisce esattamente lo stesso registro. Gli altri officer lo ricevono poi con la sincronizzazione, come sempre.

## Archivio e compattazione: la fine di una season

Una season lunga riempie i dati salvati soprattutto di **cambi di formazione** (chi era in raid o in panchina in ogni momento). Quando una season è **chiusa** (vedi [[Season|Seasons-it]]), il Guild Master può compattarla:

1. In **Archivio**, scegli la season chiusa. L'elenco dice quanti eventi verrebbero tolti.
2. Premi **Genera**: la casella riceve la stringa di **archivio** della season, con **tutti** i suoi eventi. Salvala fuori dal gioco: è l'unica copia completa di ciò che la compattazione toglie.
3. Premi **Compatta…**. Funziona solo dopo che l'archivio è stato generato in questa sessione di gioco. La prima finestra dice quanti cambi di formazione verranno tolti e cosa resta; **Continua** porta a una seconda conferma, separata, **Compatta**. Annullare a uno qualsiasi dei due passi non cambia niente.

Cosa conserva la compattazione, verificato offline su una season intera:

- ogni **totale dei crediti** (anche con bonus o malus di panchina), ogni assegnazione, annullamento e correzione, le serate, le uccisioni e l'**audit**;
- le **presenze** di ogni membro a ogni serata (chi ha giocato, chi era in panchina, boss presenti e possibili), quindi le viste dello Storico, la regola dei nuovi arrivati e la rotazione della panchina danno gli stessi numeri. Sparisce solo la formazione minuto per minuto dentro una serata (il dettaglio della serata mostra chi ha giocato e chi era in panchina).

La compattazione è un evento del registro (*ha compattato la season*, nell'audit di quella season). Arriva agli altri officer con la sincronizzazione e anche i loro giochi compattano, quindi i dati di ogni officer si rimpiccioliscono. Un officer che era assente riceve gli eventi rimasti e una nota per ognuno di quelli tolti, e resta allineato. Un evento compattato non torna mai, nemmeno da un backup più vecchio. Nel gioco non si può annullare: la stringa di archivio è la strada per tornare ai dettagli.

## Dimensione dei dati salvati

`/fdcp debug` ha due righe sul registro: quanti eventi contiene, quanti kilobyte occupano più o meno nei dati salvati, quanti sono stati compattati (e di quali season) e i quattro tipi di evento che occupano più spazio.

## Buono a sapersi

- Chi può fare cosa: stringa delle impostazioni tutti, importazione delle impostazioni il Guild Master; backup e archivio gli officer; ripristino e compattazione `season.manage` (il Guild Master di base).
- La tabella dei crediti in sola lettura dei membri (vedi [[Tabella crediti|Credits-it]]) non cambia con una compattazione.
