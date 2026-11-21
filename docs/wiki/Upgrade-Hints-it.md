# Suggerimenti di upgrade

> **Costruito, non ancora visto in gioco.** Tutto funziona nei test offline; come appare e come si usa in un raid vero è ancora da confermare. [English](Upgrade-Hints)

Il popup ti dice se un pezzo è un upgrade ([[Rollare per il loot|Rolling-for-Loot-it]], "È un upgrade?"). Due impostazioni **personali e facoltative** regolano quel suggerimento per te. Appartengono solo al tuo personaggio: non vanno mai alla gilda, non si scrivono mai nel registro e non cambiano mai chi vince un pezzo.

## I tuoi pesi delle statistiche

Il suggerimento pesa ogni statistica del pezzo per la tua specializzazione. L'addon ha pesi predefiniti per ogni spec; se preferisci i tuoi, importali.

**Import.** `/fdcp weights import <spec> <stringa>`

- `<spec>` è l'id di una specializzazione (per esempio `72`), oppure `ms` / `os` per la tua main-spec e off-spec dichiarate.
- `<stringa>` è un elenco di coppie `Statistica=peso`, anche dentro l'intestazione tipo Pawn: `( Pawn: v1: "La mia Fury": Strength=1, CritRating=0.85, HasteRating=0.6 )`. Va bene anche la forma nuda `Strength=1, CritRating=0.85`, con maiuscole o minuscole, e vanno bene i codici brevi dell'addon (`STR=1, CRIT=0.85`). Il separatore decimale è il punto.
- Le statistiche che l'addon sa pesare sono: Strength, Agility, Stamina, Intellect, Spirit, Ap, Rap, SpellDamage, Healing, CritRating, HitRating, HasteRating, ExpertiseRating, ArmorPenetration, MasteryRating, Versatility, Mp5, Dps, Armor, DefenseRating, DodgeRating, ParryRating, BlockRating, BlockValue. Gli altri nomi della stringa (castoni, gemme) si elencano come ignorati; l'import si rifiuta solo se nessuno è noto.
- Un import **sostituisce l'intera riga** di quella spec e **accende i pesi personali**.

**Una stringa non valida viene rifiutata con un messaggio e non cambia nulla.** L'addon indica il pezzo sbagliato: una stringa vuota, troppo lunga (oltre 2000 caratteri), un pezzo che non è `Statistica=numero`, un numero che non è un decimale semplice (niente `0x10`, `1e3`, `inf`) o oltre ±1000, oppure nessuna statistica che l'addon conosce.

| Comando | Cosa fa |
|---|---|
| `/fdcp weights` | Dice se i pesi personali sono accesi, per quali spec li hai impostati e come si usa. |
| `/fdcp weights show <spec>` | Stampa i pesi di quella spec come stringa: i tuoi se li hai impostati, altrimenti quelli predefiniti. Puoi condividerla. |
| `/fdcp weights off` / `on` | Torna ai pesi predefiniti / usa di nuovo i tuoi. Non si perde nulla. |
| `/fdcp weights reset <spec>` oppure `reset all` | Toglie i tuoi pesi per quella spec, o per tutte. |

Quando si usano i tuoi pesi, il tooltip della riga del verdetto lo dice, e il verdetto che la tua risposta porta al master looter è quello calcolato con loro. I pesi predefiniti restano la regola finché non importi qualcosa. Non è stato chiesto al Guild Master di approvare i pesi personali; il suggerimento informa soltanto, e decide il council.

## La tua lista best-in-slot

Segna i pezzi che consideri best in slot e il popup te lo ricorda quando uno è in palio.

| Comando | Cosa fa |
|---|---|
| `/fdcp wish add <oggetto> ...` | Aggiunge uno o più pezzi: clic con Maiusc su un link nella riga, oppure scrivi l'id. |
| `/fdcp wish remove <oggetto> ...` | Li toglie. |
| `/fdcp wish` oppure `/fdcp wish list` | Elenca i tuoi pezzi. |
| `/fdcp wish clear` | Svuota la lista. |

Un pezzo della tua lista mostra il badge **Nella tua lista BiS** sopra le righe del verdetto (passandoci sopra, ricorda che lo vedi solo tu). La lista è salvata per personaggio, sopravvive a `/reload`, contiene fino a 300 pezzi ed è solo un promemoria: non manda nulla e non cambia nulla per gli altri. Per dire al council che una risposta è per un pezzo best in slot, usa l'etichetta **BiS** del popup ([[Rollare per il loot|Rolling-for-Loot-it]]).

## Cosa non c'è

- **Nessuna BiS list di gilda** e nessun peso condiviso: se la gilda le vuole è ancora una domanda aperta con il Guild Master.
- Il suggerimento resta un'approssimazione (proc, effetti d'uso, bonus di set e limiti non entrano nel punteggio), qualunque siano i pesi.
