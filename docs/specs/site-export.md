# Esportazione per il sito della community

> Specifica del passo **M1-6b**. Vale per M3 (che cosa registrare: roster, serate, prime uccisioni) e per M6-4
> (l'esportazione). Fonte: il repository del sito `../nebula-community/nebula-community`, letto e mai modificato:
> `content/games/wow-forever/{roster,loot,progress}.json`, `game.json`, `src/kit/Wow.jsx`, `src/lib/content.mjs`,
> `scripts/validate.mjs`. I numeri di riga citati sono di quel repository al momento dello studio (novembre 2026).
> Stile dell'interfaccia: [ui-style.md](ui-style.md).

## 1. Obiettivo e principi

FDCP produce i **tre file** della pagina WoW Forever del sito (`roster.json`, `loot.json`, `progress.json`) in una
forma che si mette in `content/games/wow-forever/` **senza ritocchi**: passa il controllo del sito
(`npm run validate`, che ferma la pubblicazione se fallisce) e la pagina li mostra come i file scritti a mano.

1. **Solo il formato attuale.** Nessun campo nuovo è necessario per avere i file giusti; le estensioni
   (`start`, `kind`) restano dietro un'opzione spenta finché il GM non decide ([issue #3](https://github.com/Finland6738/finland-dragon-credit-points/issues/3)).
2. **I totali li calcola il sito.** Come nell'addon, i crediti non si scrivono mai: si esportano le assegnazioni e il
   sito somma i `cost`.
3. **FDCP esporta solo ciò che conosce.** Una gilda conosce la propria fazione e le season che ha registrato; tutto il
   resto del file del sito (l'altra fazione, le season precedenti all'addon, le copertine, le istanze "in arrivo") si
   **conserva**. Per questo il percorso consigliato è lo script che unisce (§6.2).
4. **Una sola fonte.** I tre oggetti li costruisce `Domain/SiteExport.lua` (Lua puro, testato offline); la finestra di
   copia e lo script in Python usano lo stesso risultato, mai una seconda implementazione.

## 2. Come il sito legge i file

| File | Chi lo legge | Che cosa calcola il sito | Campi obbligatori (se mancano la pagina si rompe) | Controlli di `validate.mjs` |
|---|---|---|---|---|
| `roster.json` | `content.mjs:55` al build → scheda Roster (`Wow.jsx:315-339`) | ordina per classe e nome; filtra per fazione; conta i posti per ruolo con `recruitment.json` | `players` | `class` fra le nove, `role` fra `tank`/`healer`/`dps` |
| `loot.json` | `Wow.jsx:16-125`, letto dal browser | per ogni giocatore della season: somma dei `cost` per run e totale; precedenza = totale più basso, poi nome | `seasons[].roster`, `seasons[].raids`, `raids[].awards` | `class`, ogni `player` presente nel `roster` della stessa season, `cost` solo 0, 1 o 2 |
| `progress.json` | `content.mjs:55-56` al build → scheda Progress (`Wow.jsx:341-362`) | conteggi `uccisi/totale` per fazione; mostra solo le fazioni con `active: true` in `game.json` | `instances`, `instances[].bosses` | solo la sintassi JSON e le immagini mancanti (avviso) |

Chiavi sconosciute: il sito le **ignora** (nessun controllo le rifiuta; `_readme` ed `example` esistono già). Ordine:
`seasons` dalla più recente (il sito non riordina), `raids` in ordine cronologico (ordine delle colonne), `instances` e
`bosses` nell'ordine voluto (il sito li numera così); i `players` li riordina il sito.

## 3. I tre file che FDCP produce

Esempi completi con nomi inventati. Le date sono quelle di una season di prova.

### 3.1 `roster.json`

```json
{
  "updated": "2026-10-28",
  "players": [
    { "name": "Aurel", "class": "warrior", "spec": "Protection", "role": "tank", "faction": "Nebulah", "rank": "Raider" },
    { "name": "Mordo", "class": "warrior", "spec": "Protection", "role": "tank", "faction": "Nebulah", "rank": "Trial" },
    { "name": "Bryn", "class": "priest", "spec": "Holy", "role": "healer", "faction": "Nebulah", "rank": "Raider" },
    { "name": "Corin", "class": "mage", "spec": "Frost", "role": "dps", "faction": "Nebulah", "rank": "Raider" }
  ]
}
```

| Campo | Valore | Da dove in FDCP |
|---|---|---|
| `updated` | data dell'esportazione `AAAA-MM-GG` | orologio del client |
| `players[]` | un elemento per **main** attivo o in prova del pool della season (niente alt, niente inattivi) | `Domain/Roster.lua` (M3-2) |
| `name` | nome del personaggio **senza reame** | roster di gilda; il reame si toglie sempre allo stesso modo |
| `class` | `warrior` `paladin` `hunter` `rogue` `priest` `shaman` `mage` `warlock` `druid` | `classFile` del roster di gilda in minuscolo; una classe fuori da queste nove non si esporta e lo si segnala |
| `spec` | nome inglese della specializzazione MS1 (`Protection`, `Holy`, `Restoration`…) | spec dichiarata (M3-2), salvata come ID; il nome inglese viene da una tabella fissa `specID → nome` in `Data/`, perché un client italiano restituisce nomi italiani |
| `role` | `tank`, `healer`, `dps` | dal ruolo della spec MS1 (tabella fissa) |
| `faction` | `Nebulah` (Orda) o `Nebulaa` (Alleanza) | impostazione "nome della fazione sul sito" (§5) |
| `rank` | `Raider` o `Trial` | stato del pool: `trial` → `Trial`, `active` → `Raider` |

### 3.2 `loot.json`

```json
{
  "seasons": [
    {
      "season": "2",
      "updated": "2026-10-28",
      "closed": false,
      "roster": [
        { "name": "Aurel", "class": "warrior", "spec": "Protection", "faction": "Nebulah" },
        { "name": "Bryn", "class": "priest", "spec": "Holy", "faction": "Nebulah" },
        { "name": "Corin", "class": "mage", "spec": "Frost", "faction": "Nebulah" }
      ],
      "raids": [
        {
          "id": "s2-r1", "instance": "Molten Core", "date": "14/10", "bosses": "4/10",
          "awards": [
            { "player": "Bryn", "item": "Sash of Whispered Secrets", "cost": 1 },
            { "player": "Corin", "item": "Staff of Dominance", "cost": 2 },
            { "player": "Aurel", "item": "Cloak of the Shrouded Mists (off-spec)", "cost": 0 }
          ]
        },
        {
          "id": "s2-r2", "instance": "Onyxia's Lair", "date": "21/10", "bosses": "1/1",
          "awards": []
        }
      ]
    }
  ]
}
```

| Campo | Valore | Da dove in FDCP |
|---|---|---|
| `seasons[]` | le season del registro, dalla più recente | eventi `SEASON_OPENED` / `SEASON_CLOSED` (M2-4) |
| `season` | etichetta della season scritta dal GM all'apertura (`"2"`) | `SEASON_OPENED.label` |
| `updated` | data dell'ultima serata della season, `AAAA-MM-GG` | `NIGHT_CLOSED` più recente |
| `closed` | `true` dopo `SEASON_CLOSED`, altrimenti `false` | registro |
| `roster[]` | **ogni** main che ha fatto parte del pool della season, anche se poi è uscito, più chiunque abbia ricevuto un'assegnazione nella season | `Domain/Roster.lua` + registro; garantisce il controllo "player nel roster" del sito |
| `roster[].name/class/spec/faction` | come in `roster.json` | — |
| `raids[]` | una voce per **serata ufficiale chiusa** della season, in ordine di data; per due istanze nella stessa sera, una voce per istanza | `NIGHT_OPENED` / `NIGHT_CLOSED` (M3-3) |
| `id` | `s<season>-r<n>` (n = posizione cronologica nella season) | calcolato; stabile finché non si annulla una serata |
| `instance` | nome **inglese** dell'istanza come nel `progress.json` del sito (`Molten Core`) | `Data/Instances.lua`: `instanceID → { id del sito, nome inglese, dimensione, boss in ordine }` |
| `date` | `GG/MM` della serata (il sito non mostra l'anno) | data di `NIGHT_OPENED` |
| `bosses` | `"uccisi/totale"` della serata in quell'istanza (il sito oggi non lo mostra, ma il formato lo prevede) | `ENCOUNTER_KILLED` della serata + numero di boss della tabella fissa |
| `awards[]` | ogni `ITEM_AWARDED` **valido** della serata, in ordine di assegnazione | registro dopo annullamenti e correzioni (§4) |
| `player` | nome senza reame del vincitore (il main, anche se ha vinto con un alt) | `ITEM_AWARDED.player` risolto al main |
| `item` | nome dell'oggetto; suffisso ` (off-spec)` per il tier off-spec | `C_Item.GetItemInfo(itemID)` al momento dell'esportazione, nella lingua del client (il sito non lo mostra) |
| `cost` | `0`, `1` o `2` | costo dell'assegnazione dopo le correzioni |

### 3.3 `progress.json`

```json
{
  "instances": [
    {
      "id": "mc", "name": "Molten Core", "size": 40, "cover": "media/art/concept-nebula-inn.webp",
      "bosses": [
        { "name": "Lucifron", "Nebulaa": "2026-10-16", "Nebulah": "2026-10-14" },
        { "name": "Magmadar", "Nebulaa": null, "Nebulah": "2026-10-14" },
        { "name": "Gehennas", "Nebulaa": null, "Nebulah": null }
      ]
    },
    {
      "id": "ony", "name": "Onyxia's Lair", "size": 40,
      "bosses": [ { "name": "Onyxia", "Nebulaa": null, "Nebulah": "2026-10-28" } ]
    },
    { "id": "next", "name": "[[PROSSIMA ISTANZA]]", "size": null, "locked": true, "bosses": [] }
  ]
}
```

| Campo | Valore | Da dove in FDCP |
|---|---|---|
| `instances[]` | le istanze del pacchetto di raid della tabella fissa, nel suo ordine | `Data/Instances.lua` |
| `id`, `name`, `size` | slug del sito (`mc`, `ony`), nome inglese, giocatori | tabella fissa; se il sito ha già l'istanza, restano i suoi valori |
| `cover`, `locked`, istanze "in arrivo" | decisi dal sito | **mai scritti da FDCP**: lo script li conserva; la finestra di copia li omette |
| `bosses[]` | i boss nell'ordine della tabella fissa | tabella fissa (`encounterID → nome inglese`) |
| `name` | nome inglese del boss | tabella fissa: un client italiano restituisce nomi italiani |
| `Nebulah` / `Nebulaa` | data `AAAA-MM-GG` della **prima uccisione** di quella fazione, o `null` | la più vecchia fra `ENCOUNTER_KILLED` e `PROGRESS_SET` per quel boss (M3-3b); FDCP scrive solo la chiave della **propria** fazione |

## 4. Che cosa FDCP deve registrare

| Dato del sito | Evento del registro (codici e numeri, mai frasi) | Passo |
|---|---|---|
| Etichetta e chiusura della season | `SEASON_OPENED{label}`, `SEASON_CLOSED` | M2-4 |
| Pool: main, classe, spec, stato | `MEMBER_JOINED{member, faction, class (classFile), role, ms1 (specID), ms2, os, status, avail, note, twin, …}`, `ROSTER_CHANGED{member, set, clear}` (stato `ACTIVE` / `TRIAL` / `INACTIVE`, correzioni dell'officer) | M3-2 |
| Serate | `NIGHT_OPENED{date, instanceID, size, difficulty}`, `NIGHT_CLOSED` | M3-3 |
| Boss uccisi nella serata | `ENCOUNTER_KILLED{encounterID, difficulty, time, date, night, instanceID, size}` da `ENCOUNTER_END` con successo (`Nights.KillsByEncounter` le dà per boss, dentro e fuori da una serata) | M3-3 |
| Formazione e presenze della serata (**mai esportate**: solo per gli officer) | `LINEUP_CHANGED{night, boss, raid, bench, absent}` | M3-3 |
| **Prima uccisione per boss e per fazione** | `ENCOUNTER_KILLED` scritto anche **fuori da una serata ufficiale** quando il client di un editor del registro è in un raid della gilda (`InGuildParty`) dentro un'istanza della tabella; `PROGRESS_SET{encounterID, faction, date}` per inserire a mano una prima uccisione precedente all'addon o correggerla (permesso `progress.edit`, finisce nell'audit) | M3-3b |
| Assegnazioni | `ITEM_AWARDED{itemID, player, cost, tier, nightID, encounterID}` | M4-4 |
| Annullamenti e correzioni | `AWARD_VOIDED{ref}`, `AWARD_CORRECTED{ref, cost}` | M2-3, M5-5 |
| Crediti iniziali dei nuovi arrivati | `LATE_JOIN{player, start}` (media del roster) | M2-4 |

La prima uccisione **non** si salva come numero a parte: si ricava dal registro (la data più vecchia), come i
crediti. Le date si salvano come tempo del server; l'esportazione le scrive nel giorno locale del raid.

**Correzioni e annullamenti nel formato attuale.** Il controllo del sito accetta solo `cost` 0, 1 o 2 e la tabella
mostrerebbe un costo negativo come "+-1": quindi **niente righe con costo negativo** (l'analisi lo prevedeva, ma il
sito lo rifiuta). L'esportazione è lo **stato attuale** del registro: un'assegnazione annullata non compare, una
corretta compare con il costo corretto. Il totale del sito torna sempre uguale a quello dell'addon.

**Crediti iniziali.** Il formato attuale non ha un campo per i crediti di partenza di chi arriva a season iniziata.
Default reversibile: nella prima serata del nuovo arrivato si aggiungono righe sintetiche
`{ "player": "Hadri", "item": "Crediti iniziali (media del roster)", "cost": 2 }` (più righe da 2 e 1 fino alla
media), testo nella lingua della gilda; così il totale del sito coincide con quello dell'addon. Con l'opzione `start`
accesa (issue #3), al loro posto si scrive `"start": N` nella riga del roster della season e il sito, una volta
aggiornato, lo somma.

**Oggetti alla banca di gilda** e assegnazioni a chi non è nel pool: non si esportano (il sito rifiuterebbe un
`player` assente dal roster).

## 5. Le due fazioni

Le due gilde della community (Nebulah in Orda, Nebulaa in Alleanza) sono **due gilde diverse** nel gioco: ogni
gilda ha il proprio registro FDCP (chiave `<reame>/<gilda>`, M1-4) e i messaggi dell'addon non attraversano le
fazioni. Quindi:

- l'impostazione **"Nome della fazione sul sito"** (scheda Impostazioni › Sito, solo GM) vale per default `Nebulah`
  se la gilda è dell'Orda e `Nebulaa` se è dell'Alleanza (`UnitFactionGroup("player")`); un'altra gilda che usa
  l'addon scrive il nome che usa il proprio sito;
- `roster.json`: FDCP scrive solo i giocatori della propria fazione; lo script conserva quelli dell'altra;
- `loot.json`: ogni gilda ha le proprie season; se le due gilde condividono una season sul sito, lo script unisce i
  `roster` e le `raids` della stessa `season` per fazione (le `id` hanno già il numero della season);
- `progress.json`: FDCP scrive solo la chiave della propria fazione e **mai** una data più recente di quella già
  presente (una prima uccisione non può spostarsi in avanti); l'altra chiave resta com'è, o `null` se il boss è nuovo;
- il sito mostra solo le fazioni con `active: true` in `game.json` (oggi solo Nebulah): non è un dato di FDCP.

## 6. Come esporta un officer

### 6.1 Finestra di copia (nel gioco)

Storico › Esporta (permesso `export.public`): si sceglie il file e la finestra mostra il JSON già selezionato
(Ctrl+C). Un addon non può scrivere file né usare la rete, quindi è testo da incollare. Per ogni file due forme:

| Forma | Cosa contiene | Quando usarla |
|---|---|---|
| **File completo** | il file intero con i soli dati di FDCP | quando il file del sito non ha nulla da conservare (la prima volta, una sola fazione attiva, nessuna season precedente all'addon) |
| **Frammento** | `loot.json`: l'oggetto della season corrente, da mettere in cima a `seasons`; `roster.json`: l'elenco `players` della propria fazione; `progress.json`: le righe dei boss con la propria chiave | quando si modifica il file a mano su GitHub o con Pages CMS |

La finestra avvisa che il file completo sostituisce l'altra fazione e le season precedenti, e consiglia lo script.

### 6.2 SavedVariables e lo script `tools/site_export.py` (consigliato)

A ogni chiusura di serata, e a richiesta, FDCP salva nelle SavedVariables
(`FinlandDragonCreditPointsDB.global.guilds["<reame>/<gilda>"].siteExport`) i tre oggetti già costruiti e la data
dell'esportazione. Dopo il `/reload` o l'uscita dal gioco:

```bash
python -X utf8 tools/site_export.py --wow "<WoW folder>" --site ../nebula-community/nebula-community
```

Lo script legge `<WoW folder>/_forever_/WTF/Account/<account>/SavedVariables/FinlandDragonCreditPoints.lua` (con
`--account` se ce n'è più di uno), sceglie la gilda (`--guild` se ce n'è più di una), **unisce** i tre oggetti ai file
in `content/games/wow-forever/` secondo il §5, conserva tutte le chiavi che FDCP non conosce (`_readme`, `example`,
`cover`, `locked`, istanze "in arrivo", season vecchie, l'altra fazione), scrive JSON con rientro di 2 spazi e a capo
LF, e fa gli stessi controlli di `validate.mjs` (classi, ruoli, `player` nel roster, `cost` 0-2, date `AAAA-MM-GG`,
fazioni note). Con `--dry-run` mostra le differenze senza scrivere. Il commit sul sito lo fa l'officer: lo script
non usa git e non tocca altro che quei tre file. Non ci sono dipendenze oltre a Python 3.

### 6.3 Che cosa non si esporta mai

Presenze e panchine (sono dati da officer), note, interventi del council e motivazioni, chi non ha l'addon, alt,
GUID, reami. L'esportazione pubblica contiene solo ciò che il sito già pubblica oggi.

## 7. Tabelle fisse in `Data/`

| Tabella | Contenuto | Perché è fissa |
|---|---|---|
| `Data/Instances.lua` | per ogni raid del pacchetto: `instanceID`, slug del sito, nome inglese, dimensione, boss in ordine con `encounterID` e nome inglese | il client dà nomi nella sua lingua e non conosce gli slug e l'ordine del sito |
| `Data/Specs.lua` | `specID → classe, nome inglese, ruolo` | la spec dichiarata va esportata in inglese con il ruolo del sito |

Sono dati, non testo dell'interfaccia: nella finestra i nomi si mostrano nella lingua del client quando il gioco li
fornisce (`EJ_GetEncounterInfo`, `GetSpecializationInfoByID` tramite Compat), altrimenti si usano quelli della tabella.

## 8. Estensioni: issue #3

Lo studio del sito ha cambiato due cose rispetto all'analisi, scritte anche nell'issue
[#3](https://github.com/Finland6738/finland-dragon-credit-points/issues/3) (nessuna decisione presa da questo passo):

1. il costo negativo per le correzioni oggi **ferma la pubblicazione** del sito (`validate.mjs` accetta solo 0, 1, 2):
   FDCP non lo usa ed esporta lo stato corretto (§4);
2. `start` e `kind` oggi il sito li **ignora** senza errori: si possono aggiungere senza rompere nulla, ma contano
   solo dopo una modifica di `Wow.jsx` nel repository del sito. Finché il GM non decide, FDCP usa le righe sintetiche
   dei crediti iniziali (§4) e tiene `start` / `kind` dietro un'opzione spenta.
