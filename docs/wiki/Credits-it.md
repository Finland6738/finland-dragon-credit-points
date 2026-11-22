# Leggere la tabella dei crediti

> **Costruita, non ancora vista in gioco.** La scheda funziona nei test offline con un client simulato; come appare nel gioco vero è ancora da confermare. [English](Credits)

La scheda **Crediti** è la tabella dei crediti del loot della gilda, come sul sito della community. I crediti non si salvano mai: si ricalcolano ogni volta dal registro, quindi ogni client che ha gli stessi eventi mostra gli stessi numeri, e i membri vedono i numeri del registro degli officer (sotto). **Meno crediti vuol dire più precedenza.**

## Officer e membri

Solo il gioco degli officer tiene il registro (lo tengono sincronizzato fra loro). Il gioco di ogni altro membro riceve invece la **tabella** dal gioco di un officer: dopo ogni cambiamento del registro il gioco di un officer la manda a tutta la gilda, e quando fai login o /reload il tuo gioco la chiede e l'officer con il registro più nuovo te la manda in sussurro. Il tuo gioco la conserva, quindi c'è anche quando nessun officer è online.

- La scheda della season dice **sola lettura · inviata da** e il nome dell'officer.
- Vedi la season in corso (o l'ultima) con le sue ultime 8 serate; le season precedenti sono solo nelle tabelle degli officer.
- Gli stessi numeri danno i tuoi crediti e il tuo posto in fila nel popup del loot.
- Si usa solo una tabella mandata da chi ha un rango di gilda che può scrivere eventi del registro; il resto si ignora. Una tabella più vecchia non sostituisce mai una più nuova, quindi un officer rimasto assente non riporta numeri vecchi.

## Una fisarmonica per season

Ogni season è una scheda con il nome, il numero di serate, se è in corso o chiusa, la data dell'ultima serata e quanti giocatori ci sono nel roster. La season più recente è aperta; clicca l'intestazione di un'altra per aprirla (quella aperta si chiude).

## La tabella

| Colonna | Cosa mostra |
|---|---|
| **Prec.** | Il tuo posto nella fila del loot: prima chi ha meno crediti, poi per nome. |
| **Giocatore** | Il nome con il colore della classe (e un quadratino). |
| **Classe · Spec** | La classe e la spec principale dichiarata. |
| Una colonna per serata | La data e l'istanza della serata, e `+N` per quanto il giocatore ha pagato per gli oggetti vinti quella sera; un punto se niente. Chi vince due oggetti nella stessa serata vede la somma. Si vedono le ultime 8 serate; le più vecchie restano nel totale. |
| **Totale** | Il totale del registro in una pastiglia: i crediti iniziali della season (chi arriva dopo parte dai crediti più bassi del roster), più ogni assegnazione e correzione degli officer, meno le assegnazioni annullate. |

Per i crediti iniziali e le correzioni, il totale può essere più della somma delle colonne delle serate. Un'assegnazione appartiene alla serata che era aperta quando è stata registrata.

## Filtri, ordinamento, la tua riga

- **Tutti / Tank / Healer / DPS** e il pulsante **Classe** (cliccalo per scorrere le classi e tornare a tutte) filtrano le righe. Il posto in fila non cambia: è sempre il posto nella fila intera.
- L'interruttore **Orda / Alleanza** sceglie la fila della fazione; parte dalla tua.
- Clicca un'intestazione per ordinare, di nuovo per invertire.
- La tua riga (o quella del tuo main, se giochi un alt) è evidenziata con una barra ambra.

Scorri una tabella lunga con la rotella del mouse.
