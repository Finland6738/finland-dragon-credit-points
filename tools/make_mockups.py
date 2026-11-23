"""Generates the UI mockups of docs/specs/ui-style.md into docs/specs/mockups/ (one WebP image per scene and language).

Adapted from Azeroth Accord's tools/make_mockups.py (same owner, GPL-3.0): an HTML page per scene, built from the tokens
and pieces of tools/mockup_lib.py, rendered by headless Chrome or Edge and saved as WebP with Pillow. The scenes follow the
CURRENT windows of the addon (docs/wiki/Interface-Tour.md and the UI/Windows/*.lua files): the three-button roll popup
with the upgrade badge, the master looter's session, the council with its flags, the night with absences, the settings
with permissions, the season window and the Info page. Each scene is drawn twice, in English and in Italian, with the
addon's own texts (Locale/enUS.lua and itIT.lua). Nothing has run in the WoW client yet, so every image carries a strip
that says "mockup, not an in-game screenshot". Invented characters; original shapes and icons; the only picture is the
guild logo and the NEBULA community logo of assets/. Never Blizzard art.

The files are docs/specs/mockups/fdcp-<scene>-en.webp and fdcp-<scene>-it.webp (unique names, because the wiki
publishes every image in one flat folder).

Usage:
    python -X utf8 tools/make_mockups.py              all images
    python -X utf8 tools/make_mockups.py popup        only the scenes whose name contains the text
    python -X utf8 tools/make_mockups.py --lang en    only one language (en or it)
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
LANGS = ("en", "it")

import mockup_lib as M  # noqa: E402
from mockup_lib import badge, btn, esc, icon, item, kill, seg  # noqa: E402

LANG = "en"   # the language being drawn; set by build()


def t(en, it):
    """The text in the language being drawn."""
    return it if LANG == "it" else en


def cls(name, c):
    return M.cls(name, c)


def cname(c):
    en = {"warrior": "Warrior", "paladin": "Paladin", "hunter": "Hunter", "rogue": "Rogue", "priest": "Priest",
          "shaman": "Shaman", "mage": "Mage", "warlock": "Warlock", "druid": "Druid"}
    return M.CLASSES[c][1] if LANG == "it" else en[c]


EXTRA_CSS = """
/* popup */
.game { position: absolute; inset: 0; background: radial-gradient(circle at 72% 78%, #3a1a10, #0b0612 62%); }
.game .frame { position: absolute; left: 36px; bottom: 36px; width: 190px; height: 210px; border-radius: 8px;
  background: rgba(0,0,0,.38); border: 1px solid rgba(255,255,255,.06); }
.game .frame i { display: block; height: 14px; margin: 10px; border-radius: 3px; background: rgba(255,255,255,.08); }
.game .chat { position: absolute; left: 36px; top: 40px; width: 360px; height: 120px; border-radius: 6px;
  background: rgba(0,0,0,.3); }
.pop { width: 480px; padding: 16px 18px; display: flex; flex-direction: column; gap: 12px; }
.pop.hl { box-shadow: 0 0 0 1px rgba(196,91,196,.4), 0 0 28px var(--glow), 0 24px 60px -20px rgba(0,0,0,.75); }
.help { font-size: 12px; color: var(--text-2); min-height: 16px; }
.threebtn { display: grid; grid-template-columns: 1fr 1.25fr 1.25fr; gap: 8px; }
.threebtn .btn { height: 38px; }
.btn.pre { border-color: var(--accent); box-shadow: 0 0 0 1px var(--accent) inset; }
/* flags and notes */
.flag { display: flex; gap: 8px; align-items: flex-start; font-size: 12.5px; color: var(--warn); line-height: 1.35; }
.flag svg { margin-top: 1px; }
.flag.cheat { color: var(--err); }
.flag.ok { color: var(--ok); }
.strip { padding: 12px 14px; border-radius: 12px; background: color-mix(in srgb, var(--accent) 8%, var(--surface-2));
  border: 1px solid color-mix(in srgb, var(--accent) 28%, transparent); display: flex; flex-direction: column; gap: 6px; font-size: 13px; }
.strip.warn { background: color-mix(in srgb, var(--warn) 9%, var(--surface-2)); border-color: color-mix(in srgb, var(--warn) 35%, transparent); }
.sel-box { display: inline-flex; align-items: center; gap: 10px; height: 30px; padding: 0 10px 0 12px; border-radius: 6px;
  background: var(--surface-2); border: 1px solid var(--border); font: 500 12.5px/1 var(--body); min-width: 150px; justify-content: space-between; }
.sel-box.lock { color: var(--text-3); }
.inp { display: inline-flex; align-items: center; height: 30px; padding: 0 12px; border-radius: 6px; background: var(--surface-2);
  border: 1px solid var(--border); font: 13px/1 var(--mono); width: 78px; }
.lbox { display: flex; flex-direction: column; gap: 5px; }
.lbox .u { font: 11.5px/1.3 var(--mono); color: var(--text-1); padding: 9px 12px; border-radius: 6px; background: var(--surface-2);
  border: 1px solid var(--border); }
.lbox .l { font-size: 12px; color: var(--text-3); }
.col3 .rl { padding: 4px 0; }
.col3 { display: grid; grid-template-columns: repeat(3, 1fr); gap: 14px; align-items: start; }
.perm { display: grid; grid-template-columns: 1fr auto; gap: 14px; align-items: center; padding: 7px 0; border-top: 1px solid var(--border-subtle); font-size: 13px; }
.perm.chg .sel-box { border-color: var(--warn); }
.perm.chg b { color: var(--warn); font-weight: 600; }
.dp b { white-space: nowrap; }
.dp span { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
table.cp td, table.cp th { padding-left: 9px; padding-right: 9px; }
.sub7 { flex-wrap: nowrap; }
.sub7 span { padding: 0 11px; font-size: 12.5px; }
"""


# ---- shared pieces ------------------------------------------------------------------------------------------------------
def tabs_list():
    return [("roster", t("Roster", "Roster")), ("credits", t("Credits", "Crediti")), ("progress", t("Progress", "Progress")),
            ("loot", t("Loot", "Loot")), ("history", t("History", "Storico")), ("settings", t("Settings", "Impostazioni"))]


ROSTER = [  # name, class, spec, role, trial
    ("Aurel", "warrior", "Protection", "tank", ""), ("Mordo", "warrior", "Protection", "tank", "Trial"),
    ("Hadri", "druid", "Restoration", "healer", "Trial"), ("Bryn", "priest", "Holy", "healer", ""),
    ("Lyra", "priest", "Holy", "healer", ""), ("Elwin", "shaman", "Restoration", "healer", ""),
    ("Fenn", "hunter", "Marksmanship", "dps", ""), ("Corin", "mage", "Frost", "dps", ""),
    ("Dessa", "rogue", "Combat", "dps", ""), ("Ivo", "shaman", "Enhancement", "dps", ""),
    ("Gilda", "warlock", "Destruction", "dps", ""), ("Kael", "warlock", "Affliction", "dps", ""),
]
SPEC = {n: (c, s) for n, c, s, _, _ in ROSTER}


def window(active, body, sub=None, state="open"):
    tabs = "".join(f'<span class="tab{" on" if k == active else ""}">{lab}</span>' for k, lab in tabs_list())
    logo = "file:///" + LOGO.replace("\\", "/")
    sub = sub or t("Season 2 · Horde", "Season 2 · Orda")
    tone, label = {"open": ("ok", t("Night open", "Serata aperta")),
                   "closed": ("", t("Night closed", "Serata chiusa")),
                   "none": ("", t("No night open", "Nessuna serata"))}[state]
    return (f'<div class="win"><div class="bar"><img src="{logo}" alt=""><span class="ttl">Dragon Credit Points</span>'
            f'<span class="sub">{esc(sub)}</span><span class="sp"></span>{badge(label, tone, state == "open")}'
            f'<span class="x">{icon("x", 16)}</span></div><div class="tabs">{tabs}</div><div class="body">{body}</div></div>')


def subtabs(options, on):
    return seg(options, on)


def head(eyebrow, title, right="", lead=""):
    ld = f'<div class="lead" style="margin-top:6px">{lead}</div>' if lead else ""
    return (f'<div class="row"><div><div class="eyebrow">{eyebrow}</div><h2 style="margin-top:6px">{title}</h2>{ld}</div>'
            f'<span class="sp"></span>{right}</div>')


def warn_icon():
    return icon("info", 15)


# ---- Credits ------------------------------------------------------------------------------------------------------------
RUNS = [("10-14", "Molten Core"), ("10-21", "Molten Core"), ("10-28", "Onyxia's Lair")]
CREDITS = [("Fenn", [0, 0, 0]), ("Elwin", [0, 1, 0]), ("Bryn", [1, 0, 1]), ("Corin", [2, 0, 0])]


def credits_scene():
    rows = ""
    for i, (n, runs) in enumerate(CREDITS, 1):
        c, s = SPEC[n]
        cells = "".join(f'<td class="r">{f"<span class=run>+{v}</span>" if v else "<span class=dim>·</span>"}</td>' for v in runs)
        cl = ' class="me"' if n == "Corin" else (' class="hov"' if n == "Bryn" else "")
        rows += (f'<tr{cl}><td class="dim mono">{i}</td><td class="stick">{cls(n, c)}</td>'
                 f'<td class="dim">{cname(c)} · {s}</td>{cells}<td class="r stick"><span class="tot">{sum(runs)}</span></td></tr>')
    heads = "".join(f'<th class="r"><span class="d">{d}</span>{esc(i)}</th>' for d, i in RUNS)
    return window("credits", head(t("Season 2 · in progress", "Season 2 · in corso"), t("Credits", "Crediti"),
                                  f'{badge(t("Up to date", "Aggiornata"), "ok", True)} {badge(t("Horde", "Orda"), "accent")}')
                  + f"""
<div class="row">{seg([t("All", "Tutti"), "Tank", "Healer", "DPS"], t("All", "Tutti"))}<span class="chip">{t("Class", "Classe")} ▾</span><span class="sp"></span>
<span class="lead">{t("Fewer credits = more priority", "Meno crediti = più precedenza")}</span></div>
<div class="acc open"><div class="acc-h"><span class="sig">{icon("sum", 22)}</span><div><b>Season 2</b><small>{t("3 nights · in progress · last night 10-28", "3 serate · in corso · ultima serata 10-28")}</small></div>
<span class="meta">{t("9 in the roster", "9 nel roster")}</span><span class="chev">{icon("chev", 18)}</span></div>
<table><tr><th class="sorted">{t("Queue", "Fila")} ↑</th><th>{t("Player", "Giocatore")}</th><th>{t("Class · Spec", "Classe · Spec")}</th>{heads}<th class="r sorted">{t("Total", "Totale")} ↑</th></tr>{rows}</table></div>
<div class="acc"><div class="acc-h"><span class="sig">{icon("sum", 22)}</span><div><b>Season 1</b><small>{t("6 nights · closed · last night 09-30", "6 serate · chiusa · ultima serata 09-30")}</small></div>
<span class="meta">{t("11 in the roster", "11 nel roster")}</span><span class="chev">{icon("chev", 18)}</span></div></div>""")


# ---- Roster (Pool) ------------------------------------------------------------------------------------------------------
def roster_scene():
    cols = ""
    for role, title, target in (("tank", "Tank", 3), ("healer", "Healer", 5), ("dps", "DPS", 12)):
        people = [p for p in ROSTER if p[3] == role]
        lines = "".join(f'<div class="rl">{cls(n, c)}<span class="spec">{s}</span>{badge("Trial", "warn") if r else ""}</div>'
                        for n, c, s, _, r in people)
        free = target - len(people)
        lines += f'<div class="rl free">+ {free} {t("free slot" if free == 1 else "free slots", "posto libero" if free == 1 else "posti liberi")}</div>'
        pct = round(100 * len(people) / target)
        cols += (f'<div class="card rcol"><h3>{icon(role, 18)} {title}<span class="sp"></span><span class="cnt"><b>{len(people)}</b>/{target}</span></h3>'
                 f'<div class="bar4"><i style="width:{pct}%"></i></div>{lines}</div>')
    return window("roster", head(t("Season pool", "Pool della season"), t("The raid roster", "Il roster dei raid"),
                                 subtabs([t("Pool", "Pool"), t("Night", "Serata"), "Addon"], t("Pool", "Pool")),
                                 t("Who is declared as a main for the season. Socials and alts are not listed here.",
                                   "Chi è dichiarato main per la season. Social e alt non compaiono qui."))
                  + f"""
<div class="row">{seg([t("Horde", "Orda"), t("Alliance", "Alleanza")], t("Horde", "Orda"))}<span class="sp"></span>
{badge(t("12 players · 2 on trial · 0 without spec", "12 giocatori · 2 in prova · 0 senza spec"), "")}</div>
<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:14px;align-items:start">{cols}</div>""")


# ---- Progress -----------------------------------------------------------------------------------------------------------
BOSSES_MC = ["Lucifron", "Magmadar", "Gehennas", "Garr", "Shazzrah", "Baron Geddon", "Golemagg", "Sulfuron Harbinger",
             "Majordomo Executus", "Ragnaros"]
KILLS_H = {0: "2026-10-14", 1: "2026-10-14", 2: "2026-10-21", 3: "2026-10-21"}
KILLS_A = {0: "2026-10-16"}


def progress_scene():
    def boss(i, n, kh, ka):
        dates = " · ".join(x for x in (f"H {kh}" if kh else "", f"A {ka}" if ka else "") if x)
        d = f'<span class="kd">{dates}</span>' if dates else ""
        return (f'<div class="bo"><span class="ix">{i + 1:02d}</span><span>{esc(n)}{d}</span>'
                f'{kill("H", bool(kh))}{kill("A", bool(ka))}</div>')
    ony = boss(0, "Onyxia", "2026-10-28", None)

    def summary(k_h, k_a, tot):
        return (f'<div class="psum"><div><div class="row"><b>{t("Horde", "Orda")}</b><span class="sp"></span><span class="mono">{k_h}/{tot}</span></div>'
                f'<div class="bar4" style="margin-top:6px"><i style="width:{100 * k_h // tot}%"></i></div></div>'
                f'<div><div class="row"><b>{t("Alliance", "Alleanza")}</b><span class="sp"></span><span class="mono">{k_a}/{tot}</span></div>'
                f'<div class="bar4" style="margin-top:6px"><i style="width:{100 * k_a // tot}%"></i></div></div></div>')
    cover1 = "--bgimg: radial-gradient(circle at 70% 30%, #ff7a2f 0, #a3271f 25%, #3b0d18 55%, #12060c 80%)"
    cover2 = "--bgimg: radial-gradient(circle at 40% 40%, #7b4bd6 0, #3c1f6e 30%, #160b28 70%)"
    p = t("40 players", "40 giocatori")
    return window("progress", head(t("First kills by guild", "Prime uccisioni per gilda"), t("The guild's progress", "Il progress di gilda"),
                                   f'{badge(t("Horde 5/11", "Orda 5/11"), "accent")} {badge(t("Alliance 1/11", "Alleanza 1/11"), "")}')
                  + f"""
<div class="prog"><div class="cov" style="{cover1}"><span class="eyebrow">{p}</span><span class="nm">Molten Core</span></div>
<div class="pb">{summary(4, 1, 10)}<div class="bl"><div>{"".join(boss(i, n, KILLS_H.get(i), KILLS_A.get(i)) for i, n in enumerate(BOSSES_MC[:5]))}</div>
<div>{"".join(boss(i + 5, n, None, None) for i, n in enumerate(BOSSES_MC[5:]))}</div></div></div></div>
<div class="prog"><div class="cov" style="{cover2};min-height:96px"><span class="eyebrow">{p}</span><span class="nm">Onyxia's Lair</span></div>
<div class="pb">{summary(1, 0, 1)}<div class="bl"><div>{ony}</div></div></div></div>
<div class="lead" style="font-size:12px">{t("H = Horde (yours) · A = Alliance, entered by an officer. Skull: boss down, with the date of the first kill; dashed circle: not down yet.",
                                            "H = Orda (la tua) · A = Alleanza, inserita da un officer. Teschio: boss abbattuto, con la data della prima uccisione; cerchio tratteggiato: non ancora.")}</div>""")


# ---- Loot session (master looter) ---------------------------------------------------------------------------------------
def verdict(kind, extra="", short=False):
    names = {"minor": (t("Minor upgrade", "Upgrade piccolo"), ""), "medium": (t("Medium upgrade", "Upgrade medio"), ""),
             "major": (t("Major upgrade", "Upgrade grande"), "ok"), "none": (t("No upgrade", "Nessun upgrade"), ""),
             "unusable": (t("Not usable", "Non utilizzabile"), "warn")}
    n, tone = names[kind]
    if short:
        n = {"minor": t("Minor", "Piccolo"), "medium": t("Medium", "Medio"), "major": t("Major", "Grande")}.get(kind, n)
    return badge(n + (f" · {extra}" if extra else ""), tone)


def loot_scene():
    items = [("Sash of Whispered Secrets", "epic", t("Waist · 1 credit", "Vita · 1 credito"), t("Roll closed", "Roll chiuso"), "accent"),
             ("Choker of Enlightenment", "epic", t("Neck · 1 credit", "Collo · 1 credito"), t("Waiting", "In attesa"), ""),
             ("Medallion of Steadfast Might", "epic", t("Neck · 1 credit", "Collo · 1 credito"), t("Waiting", "In attesa"), ""),
             ("Ancient Petrified Leaf", "legendary", t("Quest · council sets the cost", "Quest · costo del council"), t("Waiting", "In attesa"), "warn")]
    left = "".join(f'<div class="li{" on" if i == 0 else ""}">{item(n, q, sub=s)}<span class="sp"></span>{badge(st, tone)}</div>'
                   for i, (n, q, s, st, tone) in enumerate(items))
    cands = [("Bryn", 1, "ms", 87, verdict("minor", "+3", True), t("Proposed", "Proposto"), "best"),
             ("Corin", 2, "ms", 91, verdict("major", t("empty slot", "slot vuoto"), True), t("Possible waste", "Possibile spreco"), ""),
             ("Gilda", 1, "pass", None, verdict("major", "+26", True), t("Upgrade ignored", "Upgrade ignorato"), ""),
             ("Kael", 3, "os", None, verdict("minor", "+2", True), t("Rolls later", "Tira dopo"), "")]
    resp = {"ms": badge("Main-spec", "accent"), "os": badge("Off-spec", ""), "pass": badge(t("Pass", "Passo"), "")}
    rows = ""
    for n, cr, r, roll, upg, note, flag in cands:
        c, _ = SPEC[n]
        rr = f'<span class="mono">{roll}</span>' if roll is not None else '<span class="dim">—</span>'
        tone = ' style="color:var(--warn)"' if (note and not flag and r != "os") else ' style="color:var(--text-3)"'
        rows += (f'<tr{" class=me" if flag else ""}><td>{cls(n, c)}</td><td class="r"><span class="tot">{cr}</span></td>'
                 f'<td>{resp[r]}</td><td class="r">{rr}</td><td>{upg}</td>'
                 f'<td{tone if note else ""}>{badge(note, "ok", True) if flag else esc(note)}</td></tr>')
    return window("loot", f"""
<div class="row">{subtabs([t("Session", "Sessione"), t("To deliver", "Da consegnare"), "Council"], t("Session", "Sessione"))}<span class="sp"></span>
{badge(t("37/40 can roll", "37/40 possono tirare"), "warn")} {btn(t("Notify in /raid", "Avvisa in /raid"), "ghost", True)} {btn(t("End session", "Termina la sessione"), "", True)}</div>
<div style="display:grid;grid-template-columns:290px 1fr;gap:16px;flex:1;min-height:0">
<div class="list">{left}</div>
<div class="card" style="padding:14px;display:flex;flex-direction:column;gap:10px">
<div class="row">{item("Sash of Whispered Secrets", "epic", True, t("Waist · Cloth · Item level 66", "Cintura · Stoffa · Livello 66"))}<span class="sp"></span>{badge(t("Waist · 1 credit", "Vita · 1 credito"), "accent")}</div>
<table class="cp"><tr><th>{t("Candidate", "Candidato")}</th><th class="r">{t("Credits", "Crediti")}</th><th>{t("Response", "Risposta")}</th><th class="r">Roll</th><th>Upgrade</th><th>{t("Notes", "Note")}</th></tr>{rows}</table>
<div class="strip"><div><b style="color:var(--accent-text)">{t("Proposal:", "Proposta:")}</b> {t("Bryn, 1 credit. Fewest credits among the main-spec answers.", "Bryn, 1 credito. Meno crediti fra chi ha risposto main-spec.")}</div>
<div class="flag">{warn_icon()}<span>{t("Possible waste: Bryn is first in line (Minor upgrade · ilvl +3), Corin has more to gain (Major upgrade · empty slot).",
                                         "Possibile spreco: Bryn è primo in fila (Upgrade piccolo · ilvl +3), Corin ci guadagna di più (Upgrade grande · slot vuoto).")}</span></div>
<div class="flag">{warn_icon()}<span>{t("Upgrade ignored: Gilda passed on it (Major upgrade · ilvl +26).", "Upgrade ignorato: Gilda passa (Upgrade grande · ilvl +26).")}</span></div></div>
<div class="row"><span class="sp"></span>{btn(t("Reject", "Rifiuta"), "")} {btn(t("Modify", "Modifica"), "")} {btn(t("Confirm and assign", "Conferma e assegna"), "primary")}</div>
</div></div>""")


# ---- Roll popup (three buttons + upgrade badge) -------------------------------------------------------------------------
def popup_card(item_name, quality, sub, chip, credits_line, badge_html, help_text, active, highlight, pre_pass=False, timer=62):
    b_pass = btn(t("Pass", "Passo"), "pre" if pre_pass else "")
    return f"""<div class="card pop{" hl" if highlight else ""}">
<div class="row"><span class="eyebrow">{active}</span><span class="sp"></span><span class="mono dim">0:18</span><span class="x" style="width:22px;height:22px">{icon("x", 14)}</span></div>
{item(item_name, quality, True, sub)}
<div class="row" style="gap:8px">{badge(chip, "accent")}{badge_html}</div><div>{credits_line}</div>
<div class="timer"><i style="width:{timer}%"></i></div><div class="help">{help_text}</div>
<div class="threebtn">{b_pass}{btn(t("Roll Main-spec", "Tira Main-spec"), "primary")}{btn(t("Roll Off-spec", "Tira Off-spec"), "")}</div></div>"""


def popup_scene():
    mine = (f'<span class="dim" style="font-size:12px">{t("Your credits", "I tuoi crediti")} <b class="mono" style="color:var(--text-1)">2</b>'
            f' · {t("queue ~3", "fila ~3ª")}</span>')
    c1 = popup_card("Sash of Whispered Secrets", "epic", t("Waist · Cloth · Item level 66", "Cintura · Stoffa · Livello 66"),
                    t("WAIST · 1 CREDIT", "VITA · 1 CREDITO"), mine, verdict("medium", "ilvl +13"),
                    t("Pass, or roll for main-spec or off-spec: one click answers and rolls.",
                      "Passa, oppure tira per main-spec o off-spec: un clic risponde e tira."),
                    t("ROLL OPEN · LUCIFRON", "ROLL APERTO · LUCIFRON"), True)
    c2 = popup_card("Gauntlets of the Iron Vow", "epic", t("Hands · Plate · Item level 66", "Mani · Piastre · Livello 66"),
                    t("HANDS · 1 CREDIT", "MANI · 1 CREDITO"), mine, verdict("unusable"),
                    t("Your class cannot use it: Pass is preselected. Nothing is sent by itself.",
                      "La tua classe non può usarlo: Passo è preselezionato. Non viene inviato nulla da solo."),
                    t("ROLL OPEN · LUCIFRON", "ROLL APERTO · LUCIFRON"), False, pre_pass=True, timer=62)
    c2 = c2.replace(btn(t("Roll Main-spec", "Tira Main-spec"), "primary"), btn(t("Roll Main-spec", "Tira Main-spec")))
    bg = ('<div class="game"><div class="chat"></div><div class="frame"><i></i><i></i><i></i><i></i><i></i></div></div>')
    return bg + f'<div style="position:relative;display:flex;gap:20px;align-items:flex-start;margin-top:-10px">{c1}{c2}</div>'


# ---- Night with absences ------------------------------------------------------------------------------------------------
def night_scene():
    def plist(rows, button):
        return "".join(f'<div class="rl">{cls(n, SPEC[n][0])}<span class="spec">{note}</span>{btn(button, "", True) if button else ""}</div>'
                       for n, note in rows)
    raid = [("Aurel", ""), ("Hadri", ""), ("Bryn", ""), ("Elwin", ""), ("Fenn", ""), ("Corin", "")]
    bench = [("Kael", t("officers' choice", "scelta degli officer")), ("Dessa", t("self-bench · +1", "da solo · +1"))]
    absent = [("Ivo", t("signed up", "iscritto")), ("Gilda", t("not signed up", "non iscritta"))]
    col = lambda title, n, rows, b: (f'<div class="card rcol"><h3>{title}<span class="sp"></span><span class="cnt"><b>{n}</b></span></h3>'
                                     f'{plist(rows, b)}</div>')
    return window("roster", head(t("Official night · Molten Core", "Serata ufficiale · Molten Core"), t("Night of 2026-10-28", "Serata del 2026-10-28"),
                                 subtabs([t("Pool", "Pool"), t("Night", "Serata"), "Addon"], t("Night", "Serata")))
                  + f"""
<div class="row">{btn(t("Open the night", "Apri la serata"), "", True)} {btn(t("Close the night", "Chiudi la serata"), "", True)} {btn(t("Propose the bench", "Proponi la panchina"), "", True)}
{btn(t("Bench myself", "Mettimi in panchina"), "ghost", True)}<span class="sp"></span><span class="lead" style="font-size:12px">{t("A self-bench costs +1 credit; a bench decided by the officers never does.", "Una panchina chiesta da te costa +1 credito; quella decisa dagli officer mai.")}</span></div>
<div class="col3">{col(t("In the raid", "Nel raid"), 6, raid, t("→ Bench", "→ Panchina"))}{col(t("Bench", "Panchina"), 2, bench, t("→ Raid", "→ Raid"))}{col(t("Absent", "Assenti"), 2, absent, t("→ Raid", "→ Raid"))}</div>
<div class="strip warn"><div class="row"><div class="flag" style="flex:1">{warn_icon()}<span>{t("Absence penalties proposed (2, +1 each): Ivo (signed up, did not come), Gilda (not signed up)",
                                                                                                     "Penalità di assenza proposte (2, +1 ciascuna): Ivo (iscritto, non presente), Gilda (non iscritta)")}</span></div>
{btn(t("Confirm the penalties", "Conferma le penalità"), "primary", True)}</div></div>
""",
                  state="closed")


# ---- Council with flags and cheat evidence ------------------------------------------------------------------------------
def council_scene():
    flags = f"""
<div class="flag cheat">{warn_icon()}<span><b>{t("Cheating?", "Imbroglio?")}</b> {t("Possible cheating, gear swapped: Corin wore Gloves of Smoldering Focus (ilvl 66) in the fight and Plain Cloth Gloves (ilvl 52) at the roll.",
                                                                                      "Possibile imbroglio, equipaggiamento cambiato: Corin aveva Gloves of Smoldering Focus (ilvl 66) nello scontro e Plain Cloth Gloves (ilvl 52) al tiro.")}</span></div>
<div class="flag cheat">{warn_icon()}<span>{t("Inspection: the gear worn now does NOT match what their addon reported.", "Ispezione: l'equipaggiamento indossato ora NON corrisponde a quello dichiarato dal suo addon.")}</span></div>
<div class="flag">{warn_icon()}<span>{t("Upgrade ignored: Gilda passed on it (Major upgrade · ilvl +26).", "Upgrade ignorato: Gilda passa (Upgrade grande · ilvl +26).")}</span></div>"""
    left = f"""<div class="card" style="padding:16px;display:flex;flex-direction:column;gap:11px;flex:1.15">
<div class="eyebrow">{t("On the table", "Sul tavolo")}</div>
<div class="row">{item("Gloves of Smoldering Focus", "epic", False, t("Hands · Cloth · Item level 66", "Mani · Stoffa · Livello 66"))}</div>
<div><b>{t("Proposal:", "Proposta:")}</b> <span class="dim">{t("Corin, 1 credit. Fewest credits among the main-spec answers.", "Corin, 1 credito. Meno crediti fra chi ha risposto main-spec.")}</span></div>
{flags}
<div class="row">{btn(t("Penalize +2", "Penalizza +2"), "neon", True)}<span class="dim" style="font-size:12px">{t("Click again within 5 s to confirm. Nothing is written on the first click.", "Un secondo clic entro 5 s conferma. Al primo clic non si scrive nulla.")}</span></div>
<div class="dim" style="font-size:12.5px">{t("Council votes (open): Bryn 2, Corin 1.", "Voti del council (aperti): Bryn 2, Corin 1.")}</div>
<div class="row"><span class="dim" style="font-size:12.5px">{t("Your vote", "Il tuo voto")}</span><span class="sel-box">Corin · {t("proposed", "proposto")} <span>▾</span></span>{btn(t("Vote", "Vota"), "", True)}</div></div>"""
    awards = [("Sash of Whispered Secrets", "Bryn", 1), ("Choker of Enlightenment", "Elwin", 1), ("Mantle of the Dawnbreaker", "Lyra", 2), ("Ring of Quiet Fury", "Aurel", 1)]
    arows = "".join(f'<tr{" class=hov" if i == 2 else ""}><td>{item(n, "epic")}</td><td>{cls(w, SPEC[w][0])}</td><td class="r"><span class="tot">{c}</span></td></tr>'
                    for i, (n, w, c) in enumerate(awards))
    right = f"""<div class="card" style="padding:16px;display:flex;flex-direction:column;gap:10px;flex:1">
<div class="row">{seg([t("Awards", "Assegnazioni"), "Audit", t("Legendary", "Leggendari")], t("Awards", "Assegnazioni"))}<span class="sp"></span></div>
<div class="lead" style="font-size:12px">{t("Select an award to cancel it. The credits come back; the award stays in the log, marked cancelled.", "Scegli un'assegnazione per annullarla. I crediti tornano; l'assegnazione resta nel registro, segnata come annullata.")}</div>
<table><tr><th>{t("Item", "Oggetto")}</th><th>{t("Winner", "Vincitore")}</th><th class="r">{t("Credits", "Crediti")}</th></tr>{arows}</table>
<div class="row"><span class="sp"></span>{btn(t("Cancel award...", "Annulla assegnazione..."), "", True)} {btn(t("Adjust credits...", "Correggi crediti..."), "", True)}</div></div>"""
    return window("loot", f"""
<div class="row">{subtabs([t("Session", "Sessione"), t("To deliver", "Da consegnare"), "Council"], "Council")}<span class="sp"></span>
{badge(t("You are on the council", "Fai parte del council"), "ok", True)}</div>
<div class="lead">{t("The council is set by guild rank (and presence in the raid). Awards: the master looter confirms each proposal.",
                     "Il council lo decide il rango di gilda (e la presenza nel raid). Assegnazioni: il master looter conferma ogni proposta.")}</div>
<div style="display:flex;gap:16px;flex:1;min-height:0">{left}{right}</div>""")


# ---- Settings: personal, permissions ------------------------------------------------------------------------------------
def settings_tabs(on):
    names = [("Personal", t("Personal", "Personali")), ("Profiles", t("Profiles", "Profili")), ("Rules", t("Rules", "Regole")),
             ("Permissions", t("Permissions", "Permessi")), ("Site", t("Site", "Sito")), ("Season", "Season"), ("Info", "Info")]
    return '<span class="seg sub7">' + "".join(f'<span class="{"on" if k == on else ""}">{lab}</span>' for k, lab in names) + "</span>"


def settings_scene():
    def opt(title, sub, control):
        return (f'<div class="row" style="padding:10px 0;border-top:1px solid var(--border-subtle)"><div><div style="font-weight:600">{title}</div>'
                f'<div class="dim" style="font-size:12px">{sub}</div></div><span class="sp"></span>{control}</div>')
    themes = ""
    for key, name in (("nebula", "Nebula"), ("aurora", "Aurora"), ("drago", "Drago")):
        th = M.THEMES[key]
        on = key == "nebula"
        themes += (f'<div class="card" style="padding:10px;width:150px;{"border-color:var(--accent);box-shadow:0 0 18px var(--glow-accent)" if on else ""}">'
                   f'<div style="height:50px;border-radius:10px;background:{th["bg"]};border:1px solid {th["border"]};padding:8px;display:flex;flex-direction:column;gap:6px">'
                   f'<div style="height:8px;width:60%;border-radius:4px;background:{th["text-1"]};opacity:.8"></div>'
                   f'<div style="height:4px;border-radius:2px;background:linear-gradient(120deg,{th["grad"]})"></div>'
                   f'<div style="height:12px;width:40%;border-radius:4px;background:{th["accent"]}"></div></div>'
                   f'<div class="row" style="margin-top:8px"><b>{name}</b><span class="sp"></span>{badge(t("Active", "Attivo"), "accent") if on else ""}</div></div>')
    return window("settings", head(t("Personal preferences", "Preferenze personali"), t("Settings", "Impostazioni"), settings_tabs("Personal"))
                  + f"""
<div class="card" style="padding:2px 18px 6px">
{opt(t("Theme", "Tema"), t("Nebula and Aurora are the site's dark and light themes; Drago uses the logo's colours", "Nebula e Aurora sono i temi scuro e chiaro del sito; Drago usa i colori del logo"), "")}
<div class="row" style="gap:12px;padding-bottom:10px">{themes}</div>
{opt(t("Neon effects", "Effetti neon"), t("Glow behind the main button and the open roll popup", "Bagliore sul pulsante principale e sul popup del roll aperto"), '<span class="sw on"></span>')}
{opt(t("Animations", "Animazioni"), t("120-320 ms transitions; off, everything changes at once", "Transizioni di 120-320 ms; spente, tutto cambia subito"), '<span class="sw on"></span>')}
{opt(t("Sounds", "Suoni"), t("A short chime when a loot popup appears", "Un breve suono quando compare un popup del loot"), '<span class="sw"></span>')}
{opt(t("Language", "Lingua"), t("The addon's language (needs /reload)", "Lingua dell'addon (serve /reload)"), seg(["Auto", "Italiano", "English"], "Auto"))}
</div>""")


def permissions_scene():
    perms = [("Change the rules", "Cambiare le regole", "gm", True), ("Change the permissions", "Cambiare i permessi", "gm", True),
             ("Open and close seasons", "Aprire e chiudere le season", "gm", False), ("Run a night", "Condurre una serata", "officer", False),
             ("Confirm awards", "Confermare le assegnazioni", "officer", False), ("Sit on the council", "Far parte del council", "officer", False),
             ("Correct credits and void awards", "Correggere i crediti e annullare assegnazioni", "officer", False),
             ("Check who has the addon", "Controllare chi ha l'addon", "veteran", True)]
    ranks = {"gm": "Guild Master", "officer": "Officer", "veteran": "Veteran"}
    rows = ""
    for en, it, rk, changed in perms:
        lock = en.startswith("Change")
        ctl = (f'<span class="sel-box lock">{ranks[rk]} <span>{t("fixed", "fisso")}</span></span>' if lock
               else f'<span class="sel-box">{ranks[rk]} <span>▾</span></span>')
        rows += f'<div class="perm{" chg" if changed and not lock else ""}"><div><b>{t(en, it)}</b></div>{ctl}</div>'
    return window("settings", head(t("The guild's rules", "Le regole della gilda"), t("Settings", "Impostazioni"), settings_tabs("Permissions"))
                  + f"""
<div class="lead">{t("For each permission, the lowest guild rank that holds it (that rank and every higher one have it). Only the Guild Master edits the table.",
                     "Per ogni permesso, il grado di gilda più basso che lo ha (quel grado e tutti i superiori). Solo il Guild Master modifica la tabella.")}</div>
<div class="card" style="padding:4px 18px 8px;flex:1;min-height:0">{rows}</div>
<div class="row">{badge(t("1 change not saved yet", "1 modifica non ancora salvata"), "warn")}<span class="sp"></span>{btn(t("Discard changes", "Annulla le modifiche"), "ghost")} {btn(t("Save", "Salva"), "primary")}</div>""")


# ---- Season window ------------------------------------------------------------------------------------------------------
def season_scene():
    left = f"""<div class="card" style="padding:18px;display:flex;flex-direction:column;gap:12px;flex:1">
<div class="row"><h3>Season 2</h3><span class="sp"></span>{badge(t("Open", "Aperta"), "ok", True)}</div>
<div class="row" style="gap:8px">{badge("Molten Core · 40", "accent")}{badge("Onyxia's Lair · 40", "accent")}</div>
<div class="dim" style="font-size:13px">{t("Late joiners start with: Fewest credits of the pool", "Chi entra in ritardo parte con: Meno crediti del pool")}</div>
<div class="dim" style="font-size:13px">{t("Start credits: 0", "Crediti iniziali: 0")}</div>
<div class="dim" style="font-size:13px">{t("Item-level band: 58–66", "Fascia di item level: 58–66")}</div>
<span class="sp"></span>
<div class="row">{btn(t("Close the season", "Chiudi la season"), "")}<span class="dim" style="font-size:12px">{t("Two confirmations; a closed season cannot be reopened.", "Due conferme; una season chiusa non si riapre.")}</span></div></div>"""
    right = f"""<div class="card" style="padding:18px;display:flex;flex-direction:column;gap:12px;flex:1">
<h3>{t("Item-level band (min – max)", "Fascia di item level (min – max)")}</h3>
<div class="row" style="gap:10px"><span class="inp">58</span><span class="dim">–</span><span class="inp">66</span>{btn(t("Save the band", "Salva la fascia"), "primary", True)}</div>
<div class="lead" style="font-size:12.5px">{t("The item levels of this season's epics. An epic worn below it counts as an older season's in the upgrade badge.",
                                              "Gli item level degli epici di questa season. Un epico indossato sotto la fascia conta come di una season precedente nel badge di upgrade.")}</div>
<div class="strip"><div class="row" style="gap:10px"><span class="chip">{t("worn", "indossato")} ilvl 52</span><span class="dim">→</span>{badge(t("older-season epic: one step down", "epico di una season precedente: un gradino in meno"), "")}</div>
<div class="row" style="gap:10px"><span class="chip">{t("worn", "indossato")} ilvl 62</span><span class="dim">→</span>{badge(t("this season's epic", "epico di questa season"), "ok")}</div></div>
<div class="note">{icon("info", 16)}<span>{t("Written in the guild's ledger (SEASON_BAND_SET) after your confirmation; you can set it again later.", "Scritta nel registro della gilda (SEASON_BAND_SET) dopo la tua conferma; si può reimpostare dopo.")}</span></div></div>"""
    return window("settings", head(t("Settings", "Impostazioni"), "Season", settings_tabs("Season"))
                  + f'<div style="display:flex;gap:16px;flex:1;min-height:0">{left}{right}</div>')


# ---- About / credits ----------------------------------------------------------------------------------------------------
def about_scene():
    logo = "file:///" + LOGO.replace("\\", "/")
    nebula = "file:///" + os.path.join(ROOT, "assets", "nebula-logo-dark.png").replace("\\", "/")   # the dark art: this scene is the Nebula theme
    links = [(t("Source code and downloads (GitHub)", "Codice e download (GitHub)"), "https://github.com/Finland6738/finland-dragon-credit-points"),
             (t("Report a bug or suggest something", "Segnala un errore o proponi qualcosa"), "https://github.com/Finland6738/finland-dragon-credit-points/issues"),
             (t("The NEBULA community site", "Il sito della community NEBULA"), "https://nebula-community.github.io/giochi/wow-forever/"),
             (t("Support the project (Ko-fi)", "Sostieni il progetto (Ko-fi)"), "https://ko-fi.com/finland6738")]
    lb = "".join(f'<div class="lbox"><span class="l">{a}</span><span class="u">{b}</span></div>' for a, b in links)
    left = f"""<div class="card" style="padding:20px;display:flex;flex-direction:column;gap:12px;flex:1.1">
<div class="row" style="gap:14px"><img src="{logo}" alt="" style="width:56px;height:56px;border-radius:50%;box-shadow:0 0 18px var(--glow-accent)">
<div><div style="font:600 18px/1.1 var(--display);letter-spacing:.1em;text-transform:uppercase">Finland Dragon Credit Points</div><div class="mono dim" style="margin-top:6px">{t("Version 1.0.0", "Versione 1.0.0")}</div></div><img src="{nebula}" alt="NEBULA" style="margin-left:auto;width:104px;height:104px;object-fit:contain"></div>
<div>{t("Conceived and made by <b>Finland</b> for the Italian guild <b>NEBULA</b>.", "Ideato e realizzato da <b>Finland</b> per la gilda italiana <b>NEBULA</b>.")}</div>
<div class="dim" style="font-size:13px">{t("It runs the guild's loot by credits: every raid night, every drop and every award is written in a ledger the whole guild can check, and the credits are always computed from it.",
                                         "Gestisce il loot della gilda a crediti: ogni serata di raid, ogni drop e ogni assegnazione finiscono in un registro che tutta la gilda può controllare, e i crediti si calcolano sempre da lì.")}</div>
<div class="dim" style="font-size:13px">{t("Free and open source. A coffee on Ko-fi is always welcome; a bug report or an idea on GitHub helps just as much.",
                                         "Libero e open source. Un caffè su Ko-fi è sempre gradito; anche una segnalazione o un'idea su GitHub aiutano molto.")}</div>
<div class="dim" style="font-size:12.5px">{t("Licence: GPL-3.0. Includes the fonts Outfit, JetBrains Mono and Orbitron and the libraries Ace3, LibDataBroker-1.1 and LibDBIcon-1.0, each under its own free licence.",
                                           "Licenza: GPL-3.0. Include i font Outfit, JetBrains Mono e Orbitron e le librerie Ace3, LibDataBroker-1.1 e LibDBIcon-1.0, ciascuno con la propria licenza libera.")}</div>
<span class="sp"></span><div class="dim" style="font-size:12px">{t("A fan-made addon, not affiliated with or endorsed by Blizzard Entertainment.", "Addon creato da fan, non affiliato né approvato da Blizzard Entertainment.")}</div></div>"""
    right = f"""<div class="card" style="padding:20px;display:flex;flex-direction:column;gap:12px;flex:1">
<div class="eyebrow">{t("Links", "Link")}</div><div class="lead" style="font-size:12.5px">{t("The game cannot open a web page: click a box and press Ctrl+C to copy the link.", "Il gioco non apre pagine web: clicca su una casella e premi Ctrl+C per copiare il link.")}</div>{lb}</div>"""
    return window("settings", head(t("Settings", "Impostazioni"), "Info", settings_tabs("Info"))
                  + f'<div style="display:flex;gap:16px;flex:1;min-height:0">{left}{right}</div>')


# ---- History > Export ---------------------------------------------------------------------------------------------------
EXPORT = """{
  "seasons": [
    {
      "season": "2",
      "updated": "2026-10-28",
      "closed": false,
      "roster": [
        { "name": "Aurel", "class": "warrior", "spec": "Protection", "faction": "Horde" },
        { "name": "Bryn", "class": "priest", "spec": "Holy", "faction": "Horde" },
        …
      ],
      "raids": [
        { "id": "s2-r1", "instance": "Molten Core", "date": "10-14", "bosses": "4/10",
          "awards": [ { "player": "Bryn", "item": "Sash of Whispered Secrets", "cost": 1 } ] },
        …"""


def export_scene():
    files = [("loot.json", t("Season 2 · 3 nights · 14 awards", "Season 2 · 3 serate · 14 assegnazioni"), True),
             ("roster.json", t("12 mains · Horde", "12 main · Orda"), False), ("progress.json", t("the Horde column only", "solo la colonna Orda"), False)]
    left = "".join(f'<div class="li{" on" if on else ""}"><div><div class="mono" style="font-weight:600">{f}</div>'
                   f'<div class="dim" style="font-size:12px">{s}</div></div></div>' for f, s, on in files)
    sel = '<span class="sel">' + esc(EXPORT) + "</span>"
    return window("history", f"""
<div class="row">{subtabs([t("Nights", "Serate"), "Log", "Audit", t("Export", "Esporta")], t("Export", "Esporta"))}<span class="sp"></span></div>
<div style="display:grid;grid-template-columns:260px 1fr;gap:16px;flex:1;min-height:0">
<div class="list">{left}<div class="note" style="margin-top:6px">{icon("info", 16)}<span>{t("Paste into", "Incolla in")} <b>content/games/wow-forever/</b> {t("of the site, or run", "del sito, oppure usa")}
<span class="mono">tools/site_export.py</span> {t("on the SavedVariables.", "sulle SavedVariables.")}</span></div></div>
<div style="display:flex;flex-direction:column;gap:10px;min-height:0"><div class="row">{badge(t("Current site format", "Formato attuale del sito"), "ok", True)}
<span class="sp"></span><span class="dim" style="font-size:12px">{t("Ctrl+C to copy", "Ctrl+C per copiare")}</span>{btn(t("Select all", "Seleziona tutto"), "", True)}</div>
<div class="code" style="flex:1">{sel}</div></div></div>
<div class="toast">{icon("check", 18, "var(--ok)")}<span>{t("Text selected: press <b>Ctrl+C</b> and paste it into the site's file.", "Testo selezionato: premi <b>Ctrl+C</b> e incollalo nel file del sito.")}</span></div>""")


# ---- Design system ------------------------------------------------------------------------------------------------------
def design_system_scene():
    th = M.THEMES["nebula"]
    keys = ["bg", "surface-1", "surface-2", "surface-3", "raised", "text-1", "text-2", "text-3", "accent", "accent-2", "neon",
            "neon-core", "ok", "warn", "err", "border"]
    sw = "".join(f'<div class="swatch"><div style="background:{th[k]}"></div><p>{k}<br>{th[k][:22]}</p></div>' for k in keys)
    return window("", f"""
<div class="row"><div><div class="eyebrow">Design system</div><h2 style="margin-top:6px">{t("Tokens and components · Nebula theme", "Token e componenti · tema Nebula")}</h2></div><span class="sp"></span>
<span class="neon-t">FDCP</span></div>
<div class="sw-grid" style="grid-template-columns:repeat(8,1fr)">{sw}</div>
<div class="bar4" style="height:6px"><i style="width:100%"></i></div>
<div class="row" style="gap:12px;flex-wrap:wrap">{btn(t("Confirm and assign", "Conferma e assegna"), "primary")}{btn(t("Secondary", "Secondario"))}{btn("Ghost", "ghost")}{btn("Council", "neon")}
{btn(t("Pass", "Passo"))}{btn(t("Roll Main-spec", "Tira Main-spec"), "primary")}{btn(t("Roll Off-spec", "Tira Off-spec"))}<span class="sw on"></span></div>
<div class="row" style="gap:8px;flex-wrap:wrap">{badge(t("Up to date", "Aggiornata"), "ok", True)}{badge("Trial", "warn")}{badge(t("Cancelled", "Annullato"), "err")}{badge(t("Horde", "Orda"), "accent")}
{badge("37/40", "")}{verdict("minor", "ilvl +3")}{verdict("medium", "ilvl +13")}{verdict("major", "ilvl +26")}{cls("Corin", "mage")}{cls("Hadri", "druid")}{cls("Aurel", "warrior")}<span class="tot">2</span><span class="run">+1</span>
{kill("H", True)}{kill("A", False)}</div>
<div class="row" style="gap:28px;align-items:flex-end"><div><div class="eyebrow">Display · Orbitron</div><div style="font:600 24px/1.1 var(--display);letter-spacing:.08em;text-transform:uppercase;margin-top:6px">Molten Core</div></div>
<div><div class="eyebrow">{t("Text", "Testo")} · Outfit</div><div style="font:600 18px/1.2 var(--body);margin-top:6px">{t("Credits of the season", "Crediti della season")}</div></div>
<div><div class="eyebrow">{t("Numbers", "Numeri")} · JetBrains Mono</div><div class="mono" style="font-size:18px;margin-top:6px">4/10 · 10-14 · +2</div></div>
<div><span class="grad-t">12</span></div></div>
<div class="row" style="gap:12px">{item("Sash of Whispered Secrets", "epic", sub=t("epic", "epico"))}{item("Ancient Petrified Leaf", "legendary", sub=t("legendary", "leggendario"))}{item("Robe of Volatile Power", "rare", sub=t("rare", "raro"))}</div>""",
                  sub=t("Token preview", "Anteprima dei token"))


# name, caption (en, it), function, theme
SCENES = [
    ("roll-popup", ("Roll popup: three buttons, the upgrade badge, your credits and place in the queue", "Popup del roll: tre pulsanti, badge di upgrade, i tuoi crediti e la tua fila"), popup_scene, "nebula"),
    ("loot-session", ("Loot › Session (master looter): candidates, rolls, upgrade column, proposal and council flags", "Loot › Sessione (master looter): candidati, tiri, colonna upgrade, proposta e segnali del council"), loot_scene, "nebula"),
    ("credits", ("Credits tab: one accordion per season, one column per night, total and place in the queue", "Scheda Crediti: una fisarmonica per season, una colonna per serata, totale e fila"), credits_scene, "nebula"),
    ("roster", ("Roster › Pool: columns by role, free slots, members on trial", "Roster › Pool: colonne per ruolo, posti liberi, membri in prova"), roster_scene, "nebula"),
    ("progress", ("Progress tab: first kills by boss and by guild, as on the community site", "Scheda Progress: prime uccisioni per boss e per gilda, come sul sito"), progress_scene, "nebula"),
    ("night", ("Roster › Night: the lineup, self-bench and the proposed absence penalties", "Roster › Serata: la formazione, panchina da soli e penalità di assenza proposte"), night_scene, "nebula"),
    ("council", ("Loot › Council: flags, roll-cheating evidence with Penalize +2, vote, awards", "Loot › Council: segnali, prove di imbroglio sul tiro con Penalizza +2, voto, assegnazioni"), council_scene, "nebula"),
    ("settings", ("Settings › Personal: theme, effects, sounds, fonts, language", "Impostazioni › Personali: tema, effetti, suoni, font, lingua"), settings_scene, "nebula"),
    ("permissions", ("Settings › Permissions: the lowest guild rank for each permission", "Impostazioni › Permessi: il grado di gilda più basso per ogni permesso"), permissions_scene, "nebula"),
    ("season", ("Settings › Season: the open season and its item-level band", "Impostazioni › Season: la season aperta e la sua fascia di item level"), season_scene, "nebula"),
    ("about", ("Settings › Info: who made it, the links to copy, licence and credits", "Impostazioni › Info: chi l'ha fatto, i link da copiare, licenza e crediti"), about_scene, "nebula"),
    ("site-export", ("History › Export: the three files for the community site, ready to copy", "Storico › Esporta: i tre file del sito pronti da copiare"), export_scene, "nebula"),
    ("credits-aurora", ("Credits tab in the light theme Aurora (the site's light theme)", "Scheda Crediti nel tema chiaro Aurora (il tema chiaro del sito)"), credits_scene, "aurora"),
    ("roster-drago", ("Roster tab in the Drago theme (the logo's palette)", "Scheda Roster nel tema Drago (la palette del logo)"), roster_scene, "drago"),
    ("design-system", ("Tokens, components and typography of the Nebula theme", "Token, componenti e tipografia del tema Nebula"), design_system_scene, "nebula"),
]


def filename(name, lang):
    return f"fdcp-{name}-{lang}.webp"


def build(name, caption, fn, theme, lang):
    """The HTML page of one scene in one language."""
    global LANG
    LANG = lang
    body = fn()
    cap = caption[0] if lang == "en" else caption[1]
    strip = ("MOCKUP · NOT A GAME SCREENSHOT", "Nothing verified in the game yet") if lang == "en" else \
            ("MOCKUP · NON È UNO SCREENSHOT", "Nulla ancora verificato in gioco")
    return f"""<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><title>{name}</title><style>{M.css(theme)}{EXTRA_CSS}</style></head>
<body><div class="stage">{body}</div><div class="dp"><b>{strip[0]}</b><span>{esc(cap)}</span>
<span class="r">{strip[1]}</span></div></body></html>"""


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
    """Called by tools/check_docs.py (no browser): every scene builds in both languages and has its images."""
    try:
        names = [s[0] for s in SCENES]
        if len(names) != len(set(names)):
            problems.append("tools/make_mockups.py: two scenes have the same name")
        for name, caption, fn, theme in SCENES:
            for lang in LANGS:
                if len(build(name, caption, fn, theme, lang)) < 2000:
                    problems.append(f"tools/make_mockups.py: the scene {name} ({lang}) is almost empty")
                if not os.path.isfile(os.path.join(OUT, filename(name, lang))):
                    problems.append(f"docs/specs/mockups/{filename(name, lang)} is missing: run python -X utf8 tools/make_mockups.py")
        known = {filename(s[0], lang) for s in SCENES for lang in LANGS}
        if os.path.isdir(OUT):
            for f in sorted(os.listdir(OUT)):
                if f.endswith(".webp") and f not in known:
                    problems.append(f"docs/specs/mockups/{f} is not made by tools/make_mockups.py (an obsolete image: delete it)")
    except Exception as e:  # noqa: BLE001 - a broken generator is a problem to report, not a crash
        problems.append(f"tools/make_mockups.py: the scenes do not build: {type(e).__name__}: {e}")


def main():
    argv = sys.argv[1:]
    langs = LANGS
    if "--lang" in argv:
        i = argv.index("--lang")
        langs = (argv[i + 1],)
        del argv[i:i + 2]
    args = [a for a in argv if not a.startswith("--")]
    only = args[0] if args else ""
    os.makedirs(OUT, exist_ok=True)
    chrome = None if "--html" in sys.argv else find_browser()
    tmp = tempfile.mkdtemp(prefix="fdcp-mockups-")
    try:
        for name, caption, fn, theme in SCENES:
            if only and only not in name:
                continue
            for lang in langs:
                html = build(name, caption, fn, theme, lang)
                base = filename(name, lang)[:-5]
                if chrome is None:
                    with open(os.path.join(OUT, base + ".html"), "w", encoding="utf-8", newline="\n") as f:
                        f.write(html)
                    print(base + ".html")
                    continue
                src = os.path.join(tmp, base + ".html")
                with open(src, "w", encoding="utf-8", newline="\n") as f:
                    f.write(html)
                png = os.path.join(tmp, base + ".png")
                subprocess.run([chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                                "--allow-file-access-from-files", f"--window-size={W},{H + STRIP}", "--virtual-time-budget=3000",
                                f"--screenshot={png}", "file:///" + src.replace("\\", "/")],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=120)
                from PIL import Image
                out = os.path.join(OUT, base + ".webp")
                Image.open(png).convert("RGB").save(out, "WEBP", quality=82, method=6)
                print(f"{base}.webp  {os.path.getsize(out) // 1024} KB")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
