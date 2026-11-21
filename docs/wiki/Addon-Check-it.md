# Controllo dell'addon

> **Costruito, non ancora visto in gioco.** Il pannello e l'avviso funzionano nei test offline; come il client vero consegna i messaggi è ancora da confermare in gioco. [English](Addon-Check)

Tutti i raider devono avere l'addon attivo. FDCP lo verifica da solo e aiuta il Guild Master, gli officer e il master looter a sollecitare chi manca.

## Chi ha l'addon

All'apertura della serata, quando qualcuno entra nel raid e ogni volta che chiedi di nuovo, l'addon interroga il raid e ogni addon risponde con la sua versione. Ogni membro ha poi uno di questi stati:

| Stato | Significato |
|---|---|
| **Attivo** | Ha risposto, versione aggiornata. |
| **Da aggiornare** | Ha risposto con una versione più vecchia: può ancora rollare, e gli si chiede di aggiornare. |
| **Versione incompatibile** | Ha risposto con un protocollo che questa versione non capisce: non può rollare dall'addon. |
| **Addon non attivo** | Nessuna risposta entro 15 secondi. "Non installato" e "disattivato" sono uguali, quindi l'addon dice "non attivo". |
| **In attesa** | Offline, non ancora interpellato o interpellato da poco: si ricontrolla da solo. |

Solo chi ha l'addon attivo o da aggiornare è candidato a un oggetto.

## Il pannello

**Roster › Addon** lo vede chi ha il permesso *vedere chi non ha l'addon e avvisarlo* (di preset gli officer) e il master looter della serata. Mostra una riga per membro del raid (nome, stato, versione), prima chi richiede attenzione, e il riepilogo, per esempio **37/40 con l'addon**. Lo stesso riepilogo compare come chip nella barra del titolo.

| Pulsante | Cosa fa |
|---|---|
| **Chiedi di nuovo** | Interroga ancora tutto il raid. |
| **Avvisa in /raid** | Scrive un messaggio in chat raid con i nomi di chi non ha l'addon attivo. |
| **Avvisa chi è da aggiornare** | Lo stesso per chi deve solo aggiornare. |

## L'avviso in /raid

Il messaggio è fatto così (nella tua lingua):

> [FDCP] Corin, Dara: vi manca l'addon del loot (Finland Dragon Credit Points). Scaricatelo da <link> prima del prossimo boss, serve per rollare.

- Se i nomi non stanno in un messaggio di chat (255 caratteri), vengono divisi su più righe.
- Il Guild Master può cambiare il testo dei due avvisi, il link di download, ogni quanto un avviso può partire, e scegliere il **sussurro** al posto di /raid (un sussurro a ognuno). Nel testo, `{names}`, `{link}` e `{addon}` diventano l'elenco, il link e il nome dell'addon.
- Al massimo **un avviso ogni 5 minuti** (il Guild Master può cambiarlo), contato per serata.
- Mai durante un boss: il pulsante risponde "un boss è in corso" e si riclicca dopo.
- Parte solo dal clic di chi ha il permesso: l'addon non lo scrive mai da solo.
- Ogni avviso finisce nel registro: chi, quando, a chi, quante righe.

## Quali roll contano

I roll sono i risultati del `/roll` del gioco: l'addon li legge dalla chat di sistema nella lingua del tuo client e non ne inventa mai uno. Un roll conta solo se è:

- un roll **1-100** (`/roll 50` o `/roll 1-1000` non conta, e non consuma il tuo turno);
- fatto **dopo che il master looter ha aperto il round** (un roll di prima è ignorato);
- il tuo **primo** roll valido del round (un secondo è ignorato);
- di un personaggio **nel raid** con l'**addon attivo**. Un `/roll` fatto a mano da chi non ha l'addon viene messo da parte e il master looter lo vede come "roll scartato: addon non attivo", così nessuno pensa che sia stato perso per errore.

Durante un boss il gioco può nascondere la chat agli addon: l'addon tiene da parte quei messaggi e li legge a fine combattimento, con l'ora in cui sono arrivati, così un roll conta comunque per il round in cui è stato fatto.
