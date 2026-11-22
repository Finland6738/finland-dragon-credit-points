# Esportazione per il sito

> **Costruita, non ancora vista in gioco.** L'esportazione e lo script funzionano offline, provati con un client simulato e con copie dei file del sito; come si comporta la finestra di copia nel gioco vero e come il sito mostra il risultato di una serata reale è ancora da confermare. [English](Site-Export)

La pagina WoW Forever del sito della community legge tre file. FDCP li scrive tutti e tre nel formato attuale del sito, quindi si mettono nella cartella `content/games/wow-forever/` del sito **senza ritocchi**:

| File | Scheda del sito | Che cosa scrive FDCP |
|---|---|---|
| `roster.json` | Roster | I main della season della tua gilda. Per ognuno: nome, classe, spec principale, ruolo, fazione, Raider o Trial. |
| `loot.json` | Loot | Una voce per season, la più recente in cima, e una colonna per serata. Ogni serata elenca i pezzi assegnati, con costo 0, 1 o 2. I crediti li somma il sito. |
| `progress.json` | Progress | La data della prima uccisione di ogni boss da parte della tua gilda. |

## Due gilde, due fazioni

Nebulah (Orda) e Nebulaa (Alleanza) sono due gilde diverse nel gioco, quindi ognuna ha i propri dati nell'addon. Ogni gilda esporta solo la propria fazione e lascia com'è la parte dell'altra. Il GM può cambiare il nome della fazione usato dal sito in Impostazioni › Sito.

## Come si registrano le prime uccisioni

La scheda Progress e `progress.json` mostrano la data della prima uccisione di ogni boss. L'addon le registra; la scheda Progress le mostra.

- **In una serata ufficiale** l'addon del master looter registra ogni boss ucciso.
- **Fuori da una serata** l'addon di un officer che può guidare le serate registra la prima uccisione di un boss quando per il gioco il gruppo è un gruppo di gilda e si trova in un raid del pacchetto della season (Molten Core, Onyxia's Lair). Un'uccisione successiva dello stesso boss non aggiunge nulla. Serve una season aperta.
- **A mano.** Un officer con il permesso `progress.edit` può inserire una prima uccisione precedente all'addon, o la data dell'altra gilda come appare sul sito. Una data sbagliata inserita a mano si può correggere o togliere. Una data registrata dall'addon si può sostituire solo con una più vecchia.

La data non si sposta mai in avanti: la prima uccisione è sempre la data più vecchia. Ogni modifica è un evento del registro, quindi compare nell'audit. Il nome della fazione sul sito è Nebulah per una gilda dell'Orda e Nebulaa per una dell'Alleanza, a meno che il GM non scriva un altro nome nelle regole.

## Come esporta un officer

Serve il permesso `export.public` (gli officer, nel preset). Ci sono due modi; il secondo è quello consigliato.

### Lo script (consigliato)

1. **Dopo la serata** chiudi il gioco o scrivi `/reload`. A ogni chiusura di serata l'addon ha già salvato i tre file nei suoi dati salvati. Per salvarli senza chiudere una serata apri **Storico › Esporta › Sito** e premi **Salva per lo script**.
2. Sul computer lancia lo script dal repository dell'addon su una copia del sito:

   ```bash
   python -X utf8 tools/site_export.py --wow "<WoW folder>" --site <cartella del sito>
   ```

   Aggiungi `--dry-run` per vedere che cosa cambierebbe senza scrivere nulla. Serve solo Python 3.
3. Guarda i file cambiati nella cartella del sito e fai il commit come sempre.

Lo script **unisce**, non sovrascrive. Conserva i giocatori e le date dell'altra fazione, le season precedenti, le copertine, le istanze ancora da venire e ogni chiave che non conosce. Non sposta mai in avanti la data di una prima uccisione. Se i file del sito sono ancora quelli d'esempio vengono sostituiti e il badge "dati d'esempio" sparisce.

Prima di scrivere qualsiasi cosa lo script controlla le stesse regole che il sito controlla quando pubblica (classi, ruoli, il giocatore di ogni assegnazione nel roster della season, costi 0, 1 o 2, date, i nomi delle fazioni del `game.json` del sito). Se una regola non è rispettata dice quale e **non scrive nulla**: un'esportazione non può rompere il sito pubblicato.

Altre opzioni: `--account NOME` se la cartella di WoW ha più account, `--guild "<reame>/<gilda>"` se i dati salvati hanno più gilde con un'esportazione, `--only roster,loot,progress` per alcuni file soltanto, `--saved FILE` per indicare direttamente il file dei dati salvati e `--csv-dir CARTELLA` per scrivere anche `roster.csv` e `awards.csv`, i due fogli del percorso Google Sheets del sito.

### La finestra di copia

Apri **Storico › Esporta › Sito**, scegli il file (**roster.json**, **loot.json**, **progress.json**) e la forma, poi premi **Seleziona tutto** e **Ctrl+C**. Il gioco non lascia a un addon scrivere file né usare internet, quindi è testo da incollare.

| Forma | Che cosa ottieni | Quando usarla |
|---|---|---|
| **File completo** | Il file intero, con i soli dati di FDCP | Il sito non ha altro da conservare (la prima volta, una sola fazione, nessuna season precedente all'addon). **Sostituisce l'altra fazione e le season precedenti**, e la finestra lo dice. |
| **Frammento** | `roster.json`: l'elenco dei tuoi giocatori. `loot.json`: la season corrente, da mettere in cima a `seasons`. `progress.json`: le righe dei boss con la chiave della tua fazione. | Modifichi a mano il file del sito su GitHub o con un editor di contenuti. |

Sopra il testo la finestra elenca ciò che il sito non può mostrare (vedi sotto), se c'è qualcosa.

## Che cosa c'è nei file

- **roster.json**: i main attivi (Raider) e in prova (Trial) della tua fazione, con il nome inglese della spec principale e la parola del sito per il ruolo. Non ci sono inattivi, alt né l'altra fazione.
- **loot.json**: ogni season del tuo registro, la più recente in cima. Una season elenca ogni main che era nel suo pool, anche uno uscito dopo. Ogni serata **chiusa** è una colonna (una serata ancora aperta si aggiunge quando si chiude), con giorno e mese, il nome inglese dell'istanza e i boss `uccisi/totale`. Le righe sono le assegnazioni valide oggi: una annullata non c'è, una corretta ha il costo corretto, una off-spec ha costo 0 e la scritta "(off-spec)" dopo l'oggetto.
- **Crediti iniziali.** Il sito non ha un campo per i crediti con cui un membro parte (la media di chi arriva a season iniziata). Si scrivono come righe "Crediti iniziali (media del roster)" nella prima serata del membro, da 2 e da 1, così il totale del sito coincide con quello dell'addon. Il testo è nella lingua della gilda.
- **progress.json**: per ogni boss dei raid del pacchetto della season, la data della prima uccisione della tua fazione, oppure `null`. Si scrive solo la chiave della tua fazione.

## Che cosa il sito non può mostrare

Il sito accetta solo costi 0, 1 e 2 e solo giocatori del roster della season. Quindi l'esportazione lascia fuori, e la finestra e lo script dicono quanti sono:

- le assegnazioni alla banca di gilda, al disincanto o al master looter (non hanno un giocatore);
- le assegnazioni a chi non è un main del pool della tua fazione;
- le correzioni manuali dei crediti (il sito non può mostrare una riga negativa o frazionaria);
- le assegnazioni di una serata ancora aperta;
- i membri senza una specializzazione dichiarata (il sito ne ha bisogno).

Un costo che non è intero viene arrotondato a 0, 1 o 2 e un costo oltre 2 viene diviso in righe da 2 e da 1. Con le regole del preset non succede mai.

## Che cosa non esce mai dall'addon

Le esportazioni non contengono mai:

- presenze e panchine;
- note;
- motivazioni del council;
- chi non ha l'addon;
- alt;
- reami.

Correzioni e assegnazioni annullate sono già applicate, quindi i totali del sito coincidono con quelli dell'addon.

## Un'opzione per più avanti

Il GM non ha ancora deciso se il formato del sito possa avere due campi facoltativi, `start` (crediti iniziali) e `kind` (assegnazione o correzione), vedi l'[issue #3](https://github.com/Finland6738/finland-dragon-credit-points/issues/3). Finché non decide sono **spenti**: i file usano solo il formato attuale. L'interruttore esiste nelle regole (`site.extended`) ma non è in nessuna finestra.

## Dettagli

I contenuti esatti dei file e la corrispondenza dei campi sono nella specifica [`docs/specs/site-export.md`](https://github.com/Finland6738/finland-dragon-credit-points/blob/main/docs/specs/site-export.md) (in italiano).

Vedi anche: [[Esporta|Export-it]] · [[Giro dell'interfaccia|Interface-Tour-it]]
