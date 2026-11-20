"""Generates the design previews of docs/specs/ui-style.md into docs/specs/mockups/ (one WebP image per scene).

Adapted from Azeroth Accord's tools/make_mockups.py (same owner, GPL-3.0): an HTML page per scene, built from the tokens
and pieces of tools/mockup_lib.py, rendered by headless Chrome or Edge and saved as WebP with Pillow. The previews show
the window the addon will build in game in the style of the guild community site (step M1-6b); nothing has run in the
WoW client yet, so every image carries a "design preview" strip. Invented characters; original shapes and icons; the
only picture is the guild logo of assets/.

Usage:
    python -X utf8 tools/make_mockups.py              all images
    python -X utf8 tools/make_mockups.py progress     only the scenes whose name contains the text
    python -X utf8 tools/make_mockups.py --html       write the HTML pages next to the images instead (no browser)

Needs headless Chrome or Edge (the CHROME environment variable overrides the search) and Pillow.
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "docs", "specs", "mockups")
LOGO = os.path.join(ROOT, "assets", "logo-source.webp")
W, H, STRIP = 1200, 720, 34

import mockup_lib as M  # noqa: E402
from mockup_lib import badge, btn, cls, esc, icon, item, kill, seg  # noqa: E402

TABS = ["Roster", "Crediti", "Progress", "Loot", "Storico", "Impostazioni"]

ROSTER = [  # name, class, spec, role, rank
    ("Aurel", "warrior", "Protection", "tank", ""), ("Mordo", "warrior", "Protection", "tank", "Trial"),
    ("Hadri", "druid", "Restoration", "healer", "Trial"), ("Bryn", "priest", "Holy", "healer", ""),
    ("Lyra", "priest", "Holy", "healer", ""), ("Elwin", "shaman", "Restoration", "healer", ""),
    ("Fenn", "hunter", "Marksmanship", "dps", ""), ("Corin", "mage", "Frost", "dps", ""),
    ("Dessa", "rogue", "Combat", "dps", ""), ("Ivo", "shaman", "Enhancement", "dps", ""),
    ("Gilda", "warlock", "Destruction", "dps", ""), ("Kael", "warlock", "Affliction", "dps", ""),
]
SPEC = {n: (c, s) for n, c, s, _, _ in ROSTER}


def window(active, body, sub="Season 2 · Nebulah"):
    tabs = "".join(f'<span class="tab{" on" if t == active else ""}">{t}</span>' for t in TABS)
    logo = "file:///" + LOGO.replace("\\", "/")
    return (f'<div class="win"><div class="bar"><img src="{logo}" alt=""><span class="ttl">Dragon Credit Points</span>'
            f'<span class="sub">{esc(sub)}</span><span class="sp"></span>{badge("Serata aperta", "ok", True)}'
            f'<span class="x">{icon("x", 16)}</span></div><div class="tabs">{tabs}</div><div class="body">{body}</div></div>')


# ---- scenes -------------------------------------------------------------------------------------------------------------
RUNS = [("14/10", "Molten Core"), ("21/10", "Molten Core"), ("28/10", "Onyxia's Lair")]
CREDITS = [("Fenn", [0, 0, 0]), ("Elwin", [0, 1, 0]), ("Gilda", [0, 1, 0]), ("Bryn", [1, 0, 1]), ("Corin", [2, 0, 0]),
           ("Dessa", [0, 2, 0]), ("Hadri", [0, 2, 0]), ("Ivo", [0, 0, 2]), ("Aurel", [1, 0, 2])]


def credits_scene():
    rows = ""
    for i, (n, runs) in enumerate(CREDITS, 1):
        c, s = SPEC[n]
        cells = "".join(f'<td class="r">{f"<span class=run>+{v}</span>" if v else "<span class=dim>·</span>"}</td>' for v in runs)
        cl = ' class="me"' if n == "Corin" else (' class="hov"' if n == "Bryn" else "")
        rows += (f'<tr{cl}><td class="dim mono">{i}</td><td class="stick">{cls(n, c)}</td>'
                 f'<td class="dim">{M.CLASSES[c][1]} · {s}</td>{cells}<td class="r stick"><span class="tot">{sum(runs)}</span></td></tr>')
    heads = "".join(f'<th class="r"><span class="d">{d}</span>{esc(i)}</th>' for d, i in RUNS)
    return window("Crediti", f"""
<div class="row"><div><div class="eyebrow">Season 2 · in corso</div><h2 style="margin-top:6px">Crediti</h2></div><span class="sp"></span>
{badge("Aggiornata", "ok", True)} {badge("Nebulah · Orda", "accent")} {btn("Esporta", "", True)}</div>
<div class="row">{seg(["Tutti", "Tank", "Healer", "DPS"], "Tutti")}<span class="chip">Classe ▾</span><span class="sp"></span>
<span class="lead">Meno crediti = più precedenza</span></div>
<div class="acc open"><div class="acc-h"><span class="sig">{icon("sum", 22)}</span><div><b>Season 2</b><small>3 run · in corso · agg. 28/10</small></div>
<span class="meta">9 nel roster</span><span class="chev">{icon("chev", 18)}</span></div>
<table><tr><th class="sorted">Prec. ↑</th><th>Giocatore</th><th>Classe · Spec</th>{heads}<th class="r sorted">Totale ↑</th></tr>{rows}</table></div>
<div class="acc"><div class="acc-h"><span class="sig">{icon("sum", 22)}</span><div><b>Season 1</b><small>6 run · chiusa · agg. 30/09</small></div>
<span class="meta">11 nel roster</span><span class="chev">{icon("chev", 18)}</span></div></div>""")


def roster_scene(theme_note=""):
    cols = ""
    for role, title, target in (("tank", "Tank", 3), ("healer", "Healer", 5), ("dps", "DPS", 12)):
        people = [p for p in ROSTER if p[3] == role]
        lines = "".join(f'<div class="rl">{cls(n, c)}<span class="spec">{s}</span>{badge("Trial", "warn") if r else ""}</div>'
                        for n, c, s, _, r in people)
        free = target - len(people)
        lines += f'<div class="rl free">+ {free} {"posto libero" if free == 1 else "posti liberi"}</div>'
        pct = round(100 * len(people) / target)
        cols += (f'<div class="card rcol"><h3>{icon(role, 18)} {title}<span class="sp"></span><span class="cnt"><b>{len(people)}</b>/{target}</span></h3>'
                 f'<div class="bar4"><i style="width:{pct}%"></i></div>{lines}</div>')
    return window("Roster", f"""
<div class="row"><div><div class="eyebrow">Pool della season</div><h2 style="margin-top:6px">Roster dei raid</h2>
<div class="lead" style="margin-top:6px">Chi è segnato come main per la season. Social e alt non compaiono qui.</div></div><span class="sp"></span>
{seg(["Pool", "Serata", "Addon"], "Pool")}</div>
<div class="row">{seg(["Nebulah", "Nebulaa"], "Nebulah")}<span class="sp"></span>{badge("12 main · 3 alt", "")} {badge("Agg. 28/10", "")}</div>
<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:14px;align-items:start">{cols}</div>{theme_note}""")


BOSSES_MC = ["Lucifron", "Magmadar", "Gehennas", "Garr", "Shazzrah", "Baron Geddon", "Golemagg", "Sulfuron Harbinger",
             "Majordomo Executus", "Ragnaros"]
KILLS_H = {0: "14 ott 2026", 1: "14 ott 2026", 2: "21 ott 2026", 3: "21 ott 2026"}
KILLS_A = {0: "16 ott 2026"}


def progress_scene():
    def boss(i, n, kh, ka):
        dates = " · ".join(x for x in (f"O {kh}" if kh else "", f"A {ka}" if ka else "") if x)
        d = f'<span class="kd">{dates}</span>' if dates else ""
        return (f'<div class="bo"><span class="ix">{i + 1:02d}</span><span>{esc(n)}{d}</span>'
                f'{kill("O", bool(kh))}{kill("A", bool(ka))}</div>')
    ony = boss(0, "Onyxia", "28 ott 2026", None)

    def summary(k_h, k_a, tot):
        return (f'<div class="psum"><div><div class="row"><b>Nebulah</b><span class="sp"></span><span class="mono">{k_h}/{tot}</span></div>'
                f'<div class="bar4" style="margin-top:6px"><i style="width:{100 * k_h // tot}%"></i></div></div>'
                f'<div><div class="row"><b>Nebulaa</b><span class="sp"></span><span class="mono">{k_a}/{tot}</span></div>'
                f'<div class="bar4" style="margin-top:6px"><i style="width:{100 * k_a // tot}%"></i></div></div></div>')
    cover1 = "--bgimg: radial-gradient(circle at 70% 30%, #ff7a2f 0, #a3271f 25%, #3b0d18 55%, #12060c 80%)"
    cover2 = "--bgimg: radial-gradient(circle at 40% 40%, #7b4bd6 0, #3c1f6e 30%, #160b28 70%)"
    return window("Progress", f"""
<div class="row"><div><div class="eyebrow">Prime uccisioni per fazione</div><h2 style="margin-top:6px">Il progress di gilda</h2></div>
<span class="sp"></span>{badge("Nebulah 5/11", "accent")} {badge("Nebulaa 1/11", "")} {btn("Esporta progress.json", "", True)}</div>
<div class="prog"><div class="cov" style="{cover1}"><span class="eyebrow">40 giocatori</span><span class="nm">Molten Core</span></div>
<div class="pb">{summary(4, 1, 10)}<div class="bl"><div>{"".join(boss(i, n, KILLS_H.get(i), KILLS_A.get(i)) for i, n in enumerate(BOSSES_MC[:5]))}</div>
<div>{"".join(boss(i + 5, n, None, None) for i, n in enumerate(BOSSES_MC[5:]))}</div></div></div></div>
<div class="prog"><div class="cov" style="{cover2};min-height:96px"><span class="eyebrow">40 giocatori</span><span class="nm">Onyxia's Lair</span></div>
<div class="pb">{summary(1, 0, 1)}<div class="bl"><div>{ony}</div></div></div></div>
<div class="lead" style="font-size:12px">O = Nebulah (Orda) · A = Nebulaa (Alleanza). Teschio: boss abbattuto, con la data della prima uccisione.</div>""")


def loot_scene():
    items = [("Sash of Whispered Secrets", "epic", "Vita · 1 credito", "Roll aperto", "accent"),
             ("Choker of Enlightenment", "epic", "Collo · 1 credito", "In attesa", ""),
             ("Medallion of Steadfast Might", "epic", "Collo · 1 credito", "In attesa", ""),
             ("Ancient Petrified Leaf", "legendary", "Quest · 2 crediti", "Council", "warn")]
    left = "".join(f'<div class="li{" on" if i == 0 else ""}">{item(n, q, sub=s)}<span class="sp"></span>{badge(st, tone)}</div>'
                   for i, (n, q, s, st, tone) in enumerate(items))
    cands = [("Bryn", "MS", "BiS", 87, 2, ""), ("Lyra", "MS", "Grande upgrade", 54, 2, ""), ("Elwin", "MS", "", 12, 1, "best"),
             ("Hadri", "OS", "", 91, 2, ""), ("Gilda", "Passo", "", None, 1, "")]
    rows = ""
    for n, resp, lab, roll, cr, flag in cands:
        c, s = SPEC[n]
        r = f'<span class="mono">{roll}</span>' if roll is not None else '<span class="dim">—</span>'
        tone = "accent" if resp == "MS" else ("" if resp == "OS" else "")
        rows += (f'<tr{" class=me" if flag else ""}><td>{cls(n, c)}</td><td class="r"><span class="tot">{cr}</span></td>'
                 f'<td>{badge(resp, tone)} <span class="dim" style="font-size:12px">{esc(lab)}</span></td><td class="r">{r}</td>'
                 f'<td>{badge("Proposto", "ok", True) if flag else ""}</td></tr>')
    return window("Loot", f"""
<div class="row"><div><div class="eyebrow">Sessione · Lucifron</div><h2 style="margin-top:6px">Loot del boss</h2></div><span class="sp"></span>
{badge("37/40 con l'addon", "warn")} {btn("Avvisa in /raid", "ghost", True)} {btn("Pausa", "", True)}</div>
<div style="display:grid;grid-template-columns:340px 1fr;gap:16px;flex:1;min-height:0">
<div class="list">{left}</div>
<div class="card" style="padding:14px;display:flex;flex-direction:column;gap:12px">
<div class="row">{item("Sash of Whispered Secrets", "epic", True, "Cintura · Stoffa · Livello 66")}<span class="sp"></span>{badge("Vita · 1 credito", "accent")}</div>
<div class="timer"><i style="width:62%"></i></div>
<table><tr><th>Candidato</th><th class="r">Crediti</th><th>Risposta</th><th class="r">Roll</th><th></th></tr>{rows}</table>
<div class="note">{icon("info", 16)}<span><b>Proposta:</b> Elwin, 1 credito. Meno crediti fra chi ha risposto MS (1 contro 2); roll non necessario.</span></div>
<div class="row"><span class="sp"></span>{btn("Intervento del council", "neon")} {btn("Modifica", "")} {btn("Conferma e assegna", "primary")}</div>
</div></div>""")


def popup_scene():
    card = f"""<div class="card" style="width:430px;padding:18px;display:flex;flex-direction:column;gap:14px;box-shadow:0 0 0 1px rgba(196,91,196,.35), 0 24px 60px -20px rgba(0,0,0,.75)">
<div class="row"><span class="eyebrow">Roll aperto · Lucifron</span><span class="sp"></span><span class="mono dim">0:18</span></div>
<div class="row">{item("Sash of Whispered Secrets", "epic", True, "Cintura · Stoffa · Livello 66")}</div>
<div class="row">{badge("Vita · 1 credito", "accent")}{badge("Upgrade +9 ilvl", "ok")}<span class="sp"></span><span class="dim" style="font-size:12px">I tuoi crediti <b class="mono" style="color:var(--text-1)">2</b> · fila ~3ª</span></div>
{seg(["Main-spec", "Off-spec", "Passo"], "Main-spec", True)}
<div class="row" style="gap:6px"><span class="chip on">BiS</span><span class="chip">Grande upgrade</span><span class="chip">Piccolo upgrade</span><span class="chip">Situazionale</span></div>
<div class="timer"><i style="width:62%"></i></div>
<div class="row"><span class="lead" style="font-size:12px">Il roll parte dal gioco: /roll 1-100</span><span class="sp"></span>{btn("Tira", "primary")}</div></div>"""
    bg = ('<div style="position:absolute;inset:0;background:radial-gradient(circle at 70% 70%, #3a1a10, #0b0612 60%);"></div>'
          '<div style="position:absolute;left:40px;bottom:40px;width:420px;height:160px;border-radius:8px;background:rgba(0,0,0,.35)"></div>')
    return bg + f'<div style="position:relative">{card}</div>'


EXPORT = """{
  "seasons": [
    {
      "season": "2",
      "updated": "2026-10-28",
      "closed": false,
      "roster": [
        { "name": "Aurel", "class": "warrior", "spec": "Protection", "faction": "Nebulah" },
        { "name": "Bryn", "class": "priest", "spec": "Holy", "faction": "Nebulah" },
        …
      ],
      "raids": [
        { "id": "s2-r1", "instance": "Molten Core", "date": "14/10", "bosses": "4/10",
          "awards": [ { "player": "Bryn", "item": "Sash of Whispered Secrets", "cost": 1 } ] },
        …"""


def export_scene():
    files = [("loot.json", "Season 2 · 3 run · 14 assegnazioni", True), ("roster.json", "12 main · Nebulah", False),
             ("progress.json", "solo la colonna Nebulah", False)]
    left = "".join(f'<div class="li{" on" if on else ""}"><div><div class="mono" style="font-weight:600">{f}</div>'
                   f'<div class="dim" style="font-size:12px">{s}</div></div></div>' for f, s, on in files)
    sel = '<span class="sel">' + esc(EXPORT) + "</span>"
    return window("Storico", f"""
<div class="row"><div><div class="eyebrow">Storico</div><h2 style="margin-top:6px">Esporta per il sito</h2></div><span class="sp"></span>
{seg(["Serate", "Log", "Audit", "Esporta"], "Esporta")}</div>
<div style="display:grid;grid-template-columns:260px 1fr;gap:16px;flex:1;min-height:0">
<div class="list">{left}<div class="note" style="margin-top:6px">{icon("info", 16)}<span>Incolla in <b>content/games/wow-forever/</b> del sito, oppure usa
<span class="mono">tools/site_export.py</span> sulle SavedVariables.</span></div></div>
<div style="display:flex;flex-direction:column;gap:10px;min-height:0"><div class="row">{badge("Formato attuale del sito", "ok", True)}
{badge("start / kind: spenti", "")}<span class="sp"></span><span class="dim" style="font-size:12px">Ctrl+C per copiare</span>{btn("Seleziona tutto", "", True)}</div>
<div class="code" style="flex:1">{sel}</div></div></div>
<div class="toast">{icon("check", 18, "var(--ok)")}<span>Testo selezionato: premi <b>Ctrl+C</b> e incollalo nel file del sito.</span></div>""")


def settings_scene():
    def opt(title, sub, control):
        return (f'<div class="row" style="padding:12px 0;border-top:1px solid var(--border-subtle)"><div><div style="font-weight:600">{title}</div>'
                f'<div class="dim" style="font-size:12px">{sub}</div></div><span class="sp"></span>{control}</div>')
    themes = ""
    for key, name in (("nebula", "Nebula"), ("aurora", "Aurora"), ("drago", "Drago")):
        t = M.THEMES[key]
        on = key == "nebula"
        themes += (f'<div class="card" style="padding:10px;width:150px;{"border-color:var(--accent);box-shadow:0 0 18px var(--glow-accent)" if on else ""}">'
                   f'<div style="height:56px;border-radius:10px;background:{t["bg"]};border:1px solid {t["border"]};padding:8px;display:flex;flex-direction:column;gap:6px">'
                   f'<div style="height:8px;width:60%;border-radius:4px;background:{t["text-1"]};opacity:.8"></div>'
                   f'<div style="height:4px;border-radius:2px;background:linear-gradient(120deg,{t["grad"]})"></div>'
                   f'<div style="height:14px;width:40%;border-radius:4px;background:{t["accent"]}"></div></div>'
                   f'<div class="row" style="margin-top:8px"><b>{name}</b><span class="sp"></span>{badge("Attivo", "accent") if on else ""}</div></div>')
    return window("Impostazioni", f"""
<div class="row"><div><div class="eyebrow">Preferenze personali</div><h2 style="margin-top:6px">Impostazioni</h2></div><span class="sp"></span>
{seg(["Personali", "Regole", "Permessi", "Sito"], "Personali")}</div>
<div class="card" style="padding:4px 18px 8px">
{opt("Tema", "Nebula e Aurora sono i temi scuro e chiaro del sito; Drago usa i colori del logo", "")}
<div class="row" style="gap:12px;padding-bottom:12px">{themes}</div>
{opt("Effetti neon", "Bagliore sul pulsante principale e sulla card del roll aperto", '<span class="sw on"></span>')}
{opt("Animazioni", "Transizioni di 120-320 ms; spente, tutto cambia subito", '<span class="sw on"></span>')}
{opt("Font", "Outfit e JetBrains Mono inclusi nell'addon; in alternativa i font del gioco", seg(["Addon", "Gioco"], "Addon"))}
{opt("Lingua", "Lingua dell'addon (serve /reload)", seg(["Auto", "Italiano", "English"], "Auto"))}
</div>""")


def design_system_scene():
    t = M.THEMES["nebula"]
    keys = ["bg", "surface-1", "surface-2", "surface-3", "raised", "text-1", "text-2", "text-3", "accent", "accent-2", "neon",
            "neon-core", "ok", "warn", "err", "border"]
    sw = "".join(f'<div class="swatch"><div style="background:{t[k]}"></div><p>{k}<br>{t[k][:22]}</p></div>' for k in keys)
    return window("", f"""
<div class="row"><div><div class="eyebrow">Design system</div><h2 style="margin-top:6px">Token e componenti · tema Nebula</h2></div><span class="sp"></span>
<span class="neon-t">FDCP</span></div>
<div class="sw-grid" style="grid-template-columns:repeat(8,1fr)">{sw}</div>
<div class="bar4" style="height:6px"><i style="width:100%"></i></div>
<div class="row" style="gap:12px;flex-wrap:wrap">{btn("Conferma", "primary")}{btn("Secondario")}{btn("Ghost", "ghost")}{btn("Council", "neon")}
{seg(["Main-spec", "Off-spec", "Passo"], "Off-spec")}<span class="chip on">BiS</span><span class="chip">Situazionale</span><span class="sw on"></span></div>
<div class="row" style="gap:8px;flex-wrap:wrap">{badge("Aggiornata", "ok", True)}{badge("Trial", "warn")}{badge("Annullato", "err")}{badge("Nebulah · Orda", "accent")}
{badge("37/40", "")}{cls("Corin", "mage")}{cls("Hadri", "druid")}{cls("Aurel", "warrior")}<span class="tot">2</span><span class="run">+1</span>
{kill("O", True)}{kill("A", False)}</div>
<div class="row" style="gap:28px;align-items:flex-end"><div><div class="eyebrow">Display · Orbitron</div><div style="font:600 24px/1.1 var(--display);letter-spacing:.08em;text-transform:uppercase;margin-top:6px">Molten Core</div></div>
<div><div class="eyebrow">Testo · Outfit</div><div style="font:600 18px/1.2 var(--body);margin-top:6px">Crediti della season</div></div>
<div><div class="eyebrow">Numeri · JetBrains Mono</div><div class="mono" style="font-size:18px;margin-top:6px">4/10 · 14/10 · +2</div></div>
<div><span class="grad-t">12</span></div></div>
<div class="row" style="gap:12px">{item("Sash of Whispered Secrets", "epic", sub="epico")}{item("Ancient Petrified Leaf", "legendary", sub="leggendario")}{item("Robe of Volatile Power", "rare", sub="raro")}</div>""",
                  sub="Anteprima dei token")


# name, caption, function, theme
SCENES = [
    ("fdcp-roster", "Scheda Roster: colonne per ruolo, posti liberi, Trial (tema Nebula)", roster_scene, "nebula"),
    ("fdcp-credits", "Scheda Crediti: season a fisarmonica, una colonna per run, totale e precedenza", credits_scene, "nebula"),
    ("fdcp-progress", "Scheda Progress: prima uccisione per boss e per fazione, come sul sito", progress_scene, "nebula"),
    ("fdcp-loot-session", "Scheda Loot (master looter): pezzi, candidati, roll, proposta", loot_scene, "nebula"),
    ("fdcp-roll-popup", "Popup del pezzo per il giocatore: risposta, etichetta, timer, tiro", popup_scene, "nebula"),
    ("fdcp-site-export", "Storico > Esporta: i tre file del sito pronti da copiare", export_scene, "nebula"),
    ("fdcp-settings-theme", "Impostazioni: scelta del tema (Nebula, Aurora, Drago) ed effetti", settings_scene, "nebula"),
    ("fdcp-credits-aurora", "Scheda Crediti nel tema chiaro Aurora (il tema chiaro del sito)", credits_scene, "aurora"),
    ("fdcp-roster-drago", "Scheda Roster nel tema Drago (palette del logo, ANALISI §9.1)", roster_scene, "drago"),
    ("fdcp-design-system", "Token, componenti e tipografia del tema Nebula", design_system_scene, "nebula"),
]


def page(name, caption, theme, body):
    return f"""<!doctype html><html lang="it"><head><meta charset="utf-8"><title>{name}</title><style>{M.css(theme)}</style></head>
<body><div class="stage">{body}</div><div class="dp"><b>ANTEPRIMA DI PROGETTO</b><span>{esc(caption)}</span>
<span class="r">Non è uno screenshot: nulla è ancora stato provato in WoW Forever</span></div></body></html>"""


def find_browser():
    pf, pf86 = os.environ.get("ProgramFiles", ""), os.environ.get("ProgramFiles(x86)", "")
    for p in [os.environ.get("CHROME", ""), os.path.join(pf, "Google", "Chrome", "Application", "chrome.exe"),
              os.path.join(pf86, "Google", "Chrome", "Application", "chrome.exe"),
              os.path.join(pf86, "Microsoft", "Edge", "Application", "msedge.exe"),
              os.path.join(pf, "Microsoft", "Edge", "Application", "msedge.exe"), "/usr/bin/google-chrome", "/usr/bin/chromium",
              "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]:
        if p and os.path.exists(p):
            return p
    for n in ("google-chrome", "chromium", "chrome", "msedge"):
        if shutil.which(n):
            return shutil.which(n)
    sys.exit("No Chrome or Edge found: set the CHROME environment variable to its path.")


def check(problems):
    """Called by tools/check_docs.py (no browser): every scene builds and has its image."""
    try:
        names = [s[0] for s in SCENES]
        if len(names) != len(set(names)):
            problems.append("tools/make_mockups.py: two scenes have the same name")
        for name, caption, fn, theme in SCENES:
            if len(page(name, caption, theme, fn())) < 2000:
                problems.append(f"tools/make_mockups.py: the scene {name} is almost empty")
            if not os.path.isfile(os.path.join(OUT, name + ".webp")):
                problems.append(f"docs/specs/mockups/{name}.webp is missing: run python -X utf8 tools/make_mockups.py")
    except Exception as e:  # noqa: BLE001 - a broken generator is a problem to report, not a crash
        problems.append(f"tools/make_mockups.py: the scenes do not build: {type(e).__name__}: {e}")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    only = args[0] if args else ""
    os.makedirs(OUT, exist_ok=True)
    chrome = None if "--html" in sys.argv else find_browser()
    tmp = tempfile.mkdtemp(prefix="fdcp-mockups-")
    try:
        for name, caption, fn, theme in SCENES:
            if only and only not in name:
                continue
            html = page(name, caption, theme, fn())
            if chrome is None:
                with open(os.path.join(OUT, name + ".html"), "w", encoding="utf-8", newline="\n") as f:
                    f.write(html)
                print(f"{name}.html")
                continue
            src = os.path.join(tmp, name + ".html")
            with open(src, "w", encoding="utf-8", newline="\n") as f:
                f.write(html)
            png = os.path.join(tmp, name + ".png")
            subprocess.run([chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                            "--allow-file-access-from-files", f"--window-size={W},{H + STRIP}", "--virtual-time-budget=3000",
                            f"--screenshot={png}", "file:///" + src.replace("\\", "/")],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=120)
            from PIL import Image
            out = os.path.join(OUT, name + ".webp")
            Image.open(png).convert("RGB").save(out, "WEBP", quality=82, method=6)
            print(f"{name}.webp  {os.path.getsize(out) // 1024} KB")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
