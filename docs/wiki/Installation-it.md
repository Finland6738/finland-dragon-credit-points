# Installazione

> **Solo versioni di prova.** Finland Dragon Credit Points non si può ancora scaricare: l'addon è in costruzione e nulla è stato provato in gioco. Fino alla prima release si installa dal sorgente con lo script qui sotto. [English](Installation)

## Per i tester: installare dal sorgente

Servono [Python](https://www.python.org/) 3.9 o più recente e una copia del repository (`git clone` o lo zip del repository).

1. Copia `tools/local.example.ini` in `tools/local.ini` e imposta `folder` con la cartella che contiene `_forever_` (la tua `<cartella WoW>`). Il file resta sul tuo PC: non viene mai committato.
2. Scarica le librerie (Ace3 e le altre, fissate in `.pkgmeta`):

```
python -I -X utf8 tools/fetch_libs.py
```

3. Installa l'addon in `<cartella WoW>/_forever_/Interface/AddOns/FinlandDragonCreditPoints`:

```
python -I -X utf8 tools/install_addon.py
```

   Con `--link` la cartella viene collegata invece di copiata (le modifiche si vedono dopo `/reload`), con `--uninstall` viene rimossa.
4. In gioco attiva **Finland Dragon Credit Points** nella lista AddOn della schermata dei personaggi, entra e scrivi `/fdcp help`.

Ogni raider avrà bisogno dell'addon per rollare: chi non ce l'ha non può partecipare ai roll.

## Librerie e licenze

L'addon incorpora Ace3, LibDataBroker-1.1 e LibDBIcon-1.0 (la versione di ciascuna è fissata in `.pkgmeta`). Ogni libreria mantiene il proprio file di licenza dentro `FinlandDragonCreditPoints/Libs/`. L'addon è GPL-3.0.

Torna alla [[Home|Home-it]].
