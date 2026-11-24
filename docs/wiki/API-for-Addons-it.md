# API per altri addon

*English: [[API for Other Addons|API-for-Addons]]*

FDCP condivide i suoi dati con altri addon attraverso una tabella **in sola lettura**, `FinlandDragonCreditPointsAPI`. Il nome della tabella non cambia mai. Azeroth Accord, l'hub di gilda dello stesso autore, la legge per mostrare il pool della season, la formazione e i crediti di un membro. Anche qualunque altro addon può leggerla.

Questa pagina è per **chi scrive addon**. I giocatori non devono fare niente: l'API non costa nulla finché un addon non la usa.

## Le regole

- **Sola lettura.** Ogni funzione restituisce una **copia nuova**, mai una delle tabelle di FDCP. Se cambi quello che ricevi, in FDCP non cambia niente. Le scritture sulla tabella dell'API vengono ignorate.
- **Mai un errore.** Se passi un argomento sbagliato, o se il dato non è su questo client, ricevi `nil`, oppure una lista vuota dove ci si aspetta una lista.
- **Con una versione.** `API_VERSION` è un numero intero, oggi `1`. Sale solo per un cambiamento che rompe chi legge: un campo o una funzione tolti, o un campo che cambia significato. Campi e funzioni nuovi non lo cambiano, quindi ignora quello che non conosci.
- **Solo quello che il giocatore vede già in FDCP.** Presenze e assenze **non** si condividono mai, perché sono solo per gli ufficiali. Lo stesso vale per la nota libera del giocatore nel roster, l'audit, il log e il council.

## Client degli ufficiali e client dei membri

Non tutti i client hanno gli stessi dati:

- il client di un **ufficiale** ha il registro della gilda;
- il client di un **membro** ha solo la tabella dei crediti che gli ha mandato un ufficiale.

`GetSource()` dice che cosa stai leggendo: `"LEDGER"` o `"SNAPSHOT"`, oppure `nil` se il client non ha ancora dati. Un campo `nil` vuol dire "non è su questo client", non "vuoto".

| Funzione | Client di un ufficiale (`LEDGER`) | Client di un membro (`SNAPSHOT`) |
|---|---|---|
| `IsReady()` | `true` dopo la lettura del roster di gilda | uguale |
| `GetVersion()` | la versione dell'addon, `API_VERSION` | uguale |
| `GetSeason()` | `id`, `name`, `state` (`"OPEN"` o `"CLOSED"`), `updated` (data dell'ultima serata) | uguale, più `asOf` (l'ora del server in cui l'ufficiale ha fatto la tabella) |
| `GetPool()` | ogni main della season (vedi sotto) | i main che giocano (attivi e trial), senza `ms2`, `os`, `twin` e `avail` |
| `GetMember(nome)` | una voce del pool; un alt dà il suo main, con `viaAlt = true` | uguale, dalla tabella |
| `GetCredits(nome)` | `name`, `credits`, `place`, `of`, `faction`, `viaAlt` | gli stessi numeri |
| `GetCreditList()` | crediti e posti di ogni main che gioca | uguale |
| `GetNight()` | la serata aperta: `date`, `instanceID`, `instance`, `size`, `difficulty`, `faction`, `raid` = nomi, `bench` = nomi | `nil`: i membri non hanno le serate |
| `GetRules()` | il riassunto delle regole della gilda, `source = "GUILD"` | i valori del preset Patto, `source = "DEFAULT"` |
| `GetEvents()` | i nomi degli eventi che puoi registrare | uguale |

Ogni voce del pool ha questi campi:

- `name`: `"Nome-Reame"`;
- `faction`, `class` e `role`;
- `ms1`, `ms2` e `os`: gli id delle spec del gioco. MS1 è la spec principale e MS2 l'off-spec per il loot. OS è la spec che il giocatore vorrebbe giocare;
- `status`: `"ACTIVE"`, `"TRIAL"` o `"INACTIVE"`;
- `alts`: una lista di nomi;
- `twin`: il main dello stesso giocatore nell'altra fazione;
- `avail`: i giorni in cui il giocatore può fare raid (`"MON"` … `"SUN"`).

`place` è il posto del giocatore nella coda del loot, come lo mostra la [[Tabella crediti|Credits-it]]: prima chi ha meno crediti, poi il nome. Si conta fra i main che giocano della fazione del giocatore, e `of` dice quanti sono. Un membro inattivo ha i crediti ma non ha un posto.

`GetRules()` dà:

- `preset` (per esempio `"PATTO"`), e `custom = true` se la gilda ha cambiato il preset;
- `metric`, `startCredits` e `awardMode`;
- `costs[categoria][qualità]`: un numero, oppure `"council"`. Le qualità sono `3` (blu), `4` (viola) e `5` (arancione);
- `responseMultiplier` (`MS`, `OS`, `TMOG`);
- `lateJoin`;
- `bench` (`effect`, `amount`);
- `penalties` (`absence`, `cheat`).

## Avvisi

```lua
local api = FinlandDragonCreditPointsAPI
if api and api.API_VERSION == 1 then
  api.RegisterCallback("CREDITS_CHANGED", function(event)
    local mine = api.GetCredits(UnitName("player"))
    -- mine è nil finché questo client non conosce i tuoi crediti
  end)
end
```

Gli eventi sono:

- `READY`: il roster di gilda è stato letto;
- `SEASON_CHANGED`;
- `POOL_CHANGED`;
- `CREDITS_CHANGED`;
- `NIGHT_CHANGED`;
- `RULES_CHANGED`.

La tua funzione riceve solo il nome dell'evento. I dati nuovi si leggono con le funzioni. Gira **protetta**: se va in errore, FDCP conta l'errore (`/fdcp debug`, riga `API`) e va avanti. Un evento parte una volta per ogni cambiamento, e solo se sono cambiati i suoi dati. FDCP controlla i cambiamenti una volta al secondo, e solo finché c'è almeno una callback registrata. Ogni evento accetta fino a 32 callback. Per smettere di ascoltare usa `UnregisterCallback(evento, fn)`.

Funzionano sia `api.GetSeason()` sia `api:GetSeason()`.

## Ordine di caricamento

Il tuo addon può caricarsi prima di FDCP. Cerca la tabella dopo `PLAYER_LOGIN`, oppure aggiungi `## OptionalDeps: FinlandDragonCreditPoints` al tuo TOC. Prima che il roster di gilda sia letto, `IsReady()` è `false` e le funzioni danno `nil` o liste vuote: registra `READY`.

## Non ancora verificato in gioco

L'API è provata offline (`Tests/test_public_api.lua`). Tre cose non sono ancora state provate nel client vero:

- un altro addon che la legge;
- l'ordine in cui si caricano i due addon;
- il costo del controllo dei cambiamenti durante un raid.

Vedi anche [[Privacy e dati|Privacy-and-Data-it]] e il documento della decisione [ADR 0009](https://github.com/Finland6738/finland-dragon-credit-points/blob/main/docs/adr/0009-public-read-only-api.md) (in inglese).
