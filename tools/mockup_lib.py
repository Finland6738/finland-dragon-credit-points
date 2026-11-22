"""Building blocks for tools/make_mockups.py: the design previews of docs/specs/ui-style.md.

Pure string helpers (no browser, no network). The look follows the guild community site's WoW Forever page as studied
in step M1-6b: the tokens below are the ones of docs/specs/ui-style.md §2 (the single source the addon's UI/Theme.lua
copies in M1-7). Each preview draws what the addon can build in game, not what a browser can do: no backdrop blur, glow
only where an additive texture can put it, fonts approximated with the system fonts of the machine that renders.

Original art only: shapes are CSS and inline SVG, the only picture is the guild logo of assets/; invented names.
"""

# ---- themes: same token names, three palettes (ui-style.md §2.1) ------------------------------------------------------
THEMES = {
    # "Nebula": the site's dark theme (src/styles/tokens/colors.css, data-theme="dark"); the addon's default
    "nebula": {
        "bg": "#0B0612", "surface-1": "#110A1A", "surface-2": "#170F22", "surface-3": "#1E142C", "raised": "#2A1D3B",
        "border-subtle": "rgba(243,238,247,.08)", "border": "rgba(243,238,247,.14)", "border-strong": "rgba(243,238,247,.26)",
        "text-1": "#F3EEF7", "text-2": "#C3B8D1", "text-3": "#9A8FAB", "on-accent": "#1A0710",
        "accent": "#FC7E46", "accent-hover": "#FDA877", "accent-text": "#FC8C46", "accent-2": "#EE4662",
        "neon": "#C45BC4", "neon-core": "#9A2A9A", "ok": "#46C28F", "warn": "#F2B33D", "err": "#FF6369",
        "grad": "#FC8C46, #EE4662 38%, #9A2A9A 72%, #702AA8", "glow": "rgba(154,42,154,.55)", "glow-accent": "rgba(252,126,70,.35)",
        "highlight": "rgba(255,255,255,.05)", "cover": "rgba(11,6,18,.9), rgba(11,6,18,.25)",
    },
    # "Aurora": the site's light theme (data-theme="light")
    "aurora": {
        "bg": "#F5F8FA", "surface-1": "#FFFFFF", "surface-2": "#EAF0F4", "surface-3": "#E1E9EF", "raised": "#FFFFFF",
        "border-subtle": "rgba(11,27,43,.07)", "border": "rgba(11,27,43,.13)", "border-strong": "rgba(11,27,43,.24)",
        "text-1": "#0B1B2B", "text-2": "#3C4E60", "text-3": "#526476", "on-accent": "#FFFFFF",
        "accent": "#0054B6", "accent-hover": "#003F8A", "accent-text": "#0054B6", "accent-2": "#00766C",
        "neon": "#008F84", "neon-core": "#009A9A", "ok": "#1B7A50", "warn": "#8F5B00", "err": "#C0262D",
        "grad": "#0054B6, #007EA8 35%, #00A89A 65%, #70C446", "glow": "rgba(0,168,154,.25)", "glow-accent": "rgba(0,84,182,.18)",
        "highlight": "rgba(255,255,255,0)", "cover": "rgba(11,27,43,.85), rgba(11,27,43,.2)",
    },
    # "Drago": the guild logo palette of ANALISI §9.1 mapped on the same tokens
    "drago": {
        "bg": "#071715", "surface-1": "#0E2422", "surface-2": "#16332F", "surface-3": "#1B3D38", "raised": "#22443F",
        "border-subtle": "rgba(230,239,233,.08)", "border": "rgba(230,239,233,.14)", "border-strong": "rgba(230,239,233,.26)",
        "text-1": "#E6EFE9", "text-2": "#C2D3CD", "text-3": "#9FB5AE", "on-accent": "#2A1E00",
        "accent": "#E9B949", "accent-hover": "#F2CD6E", "accent-text": "#E9B949", "accent-2": "#3E9E5F",
        "neon": "#B8E86A", "neon-core": "#6FA83A", "ok": "#5BC17F", "warn": "#F2B33D", "err": "#FF6B5E",
        "grad": "#E9B949, #B8E86A 45%, #3E9E5F 75%, #1F6F5A", "glow": "rgba(111,168,58,.45)", "glow-accent": "rgba(233,185,73,.35)",
        "highlight": "rgba(255,255,255,.05)", "cover": "rgba(7,23,21,.9), rgba(7,23,21,.25)",
    },
}

# The game's class colours, as on the site (Wow.jsx); the Italian names are the site's labels.
CLASSES = {
    "warrior": ("#C69B6D", "Guerriero"), "paladin": ("#F48CBA", "Paladino"), "hunter": ("#AAD372", "Cacciatore"),
    "rogue": ("#FFF468", "Ladro"), "priest": ("#FFFFFF", "Sacerdote"), "shaman": ("#0070DD", "Sciamano"),
    "mage": ("#3FC7EB", "Mago"), "warlock": ("#8788EE", "Stregone"), "druid": ("#FF7C0A", "Druido"),
}
QUALITY = {"epic": "#A335EE", "rare": "#0070DD", "legendary": "#FF8000", "uncommon": "#1EFF00"}

# Fonts: the addon ships Orbitron / Outfit / JetBrains Mono (OFL 1.1, ui-style.md §4); the preview uses the closest
# fonts a Windows machine has, so nothing is downloaded.
FONT_DISPLAY = "'Orbitron', 'Bahnschrift', 'Segoe UI', sans-serif"
FONT_BODY = "'Outfit', 'Segoe UI', system-ui, sans-serif"
FONT_MONO = "'JetBrains Mono', 'Cascadia Mono', 'Consolas', monospace"


def esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def css(theme):
    t = THEMES[theme]
    light = theme == "aurora"
    tokens = "\n".join(f"  --{k}: {v};" for k, v in t.items() if k not in ("grad", "cover"))
    return f""":root {{
{tokens}
  --grad: linear-gradient(120deg, {t['grad']});
  --cover: linear-gradient(0deg, {t['cover']});
  --display: {FONT_DISPLAY}; --body: {FONT_BODY}; --mono: {FONT_MONO};
}}
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{ background: {'#C9D3DB' if light else '#05030A'}; font: 400 14px/1.4 var(--body); color: var(--text-1); }}
.stage {{ position: relative; width: 1200px; height: 720px; overflow: hidden; display: flex; align-items: center;
  justify-content: center; background: {'radial-gradient(circle at 30% 20%, #DCE6EE, #B9C6D1)' if light else
  'radial-gradient(circle at 25% 15%, #1A1030, #05030A 70%)'}; }}
.dp {{ height: 34px; display: flex; align-items: center; gap: 14px; padding: 0 16px; background: #000; color: #bbb;
  font: 12px/1 'Segoe UI', sans-serif; }}
.dp b {{ color: #fff; letter-spacing: .12em; }} .dp .r {{ margin-left: auto; color: #888; }}
/* window */
.win {{ position: relative; width: 1040px; height: 640px; background: var(--bg); border: 1px solid var(--border);
  border-radius: 12px; box-shadow: inset 0 1px 0 var(--highlight), 0 24px 60px -20px rgba(0,0,0,.75); overflow: hidden;
  display: flex; flex-direction: column; }}
.win.small {{ width: 560px; height: auto; }}
.bar {{ height: 52px; display: flex; align-items: center; gap: 12px; padding: 0 16px 0 14px; background: var(--surface-1);
  border-bottom: 1px solid var(--border-subtle); }}
.bar img {{ width: 30px; height: 30px; border-radius: 50%; box-shadow: 0 0 12px var(--glow-accent); }}
.bar .ttl {{ font: 600 15px/1 var(--display); letter-spacing: .14em; text-transform: uppercase; }}
.bar .sub {{ font: 12px/1 var(--mono); color: var(--text-3); }}
.bar .sp {{ flex: 1; }}
.x {{ width: 28px; height: 28px; border-radius: 8px; display: grid; place-items: center; color: var(--text-3); }}
.x:hover, .x.h {{ background: var(--surface-3); color: var(--text-1); }}
.tabs {{ display: flex; gap: 24px; padding: 0 20px; height: 44px; align-items: stretch; background: var(--surface-1);
  border-bottom: 1px solid var(--border); }}
.tab {{ display: flex; align-items: center; gap: 8px; font: 500 14px/1 var(--body); color: var(--text-2); padding: 0 2px; }}
.tab.on {{ color: var(--text-1); box-shadow: inset 0 -2px 0 var(--accent); }}
.tab .n {{ font: 11px/1 var(--mono); color: var(--text-3); }}
.body {{ flex: 1; padding: 20px; display: flex; flex-direction: column; gap: 14px; overflow: hidden; }}
.row {{ display: flex; align-items: center; gap: 10px; }}
.sp {{ flex: 1; }}
h2 {{ font: 600 22px/1.1 var(--body); }} h3 {{ font: 600 16px/1.2 var(--body); }}
.lead {{ color: var(--text-2); font-size: 13px; }}
.eyebrow {{ font: 500 11px/1 var(--body); letter-spacing: .22em; text-transform: uppercase; color: var(--accent-text); }}
.mono {{ font-family: var(--mono); }} .dim {{ color: var(--text-3); }}
/* badges, chips, buttons */
.badge {{ display: inline-flex; align-items: center; gap: 6px; height: 22px; padding: 0 9px; border-radius: 999px;
  font: 600 10px/1 var(--body); letter-spacing: .12em; text-transform: uppercase; background: var(--surface-3);
  color: var(--text-2); border: 1px solid var(--border-subtle); white-space: nowrap; }}
.badge.accent {{ color: var(--accent-text); border-color: color-mix(in srgb, var(--accent) 35%, transparent);
  background: color-mix(in srgb, var(--accent) 16%, transparent); }}
.badge.ok {{ color: var(--ok); border-color: color-mix(in srgb, var(--ok) 40%, transparent);
  background: color-mix(in srgb, var(--ok) 12%, transparent); }}
.badge.warn {{ color: var(--warn); border-color: color-mix(in srgb, var(--warn) 40%, transparent);
  background: color-mix(in srgb, var(--warn) 12%, transparent); }}
.badge.err {{ color: var(--err); border-color: color-mix(in srgb, var(--err) 40%, transparent);
  background: color-mix(in srgb, var(--err) 12%, transparent); }}
.badge i {{ width: 6px; height: 6px; border-radius: 50%; background: currentColor; box-shadow: 0 0 8px currentColor; }}
.btn {{ display: inline-flex; align-items: center; justify-content: center; gap: 8px; height: 36px; padding: 0 16px;
  border-radius: 8px; font: 600 13px/1 var(--body); white-space: nowrap; background: var(--surface-3);
  border: 1px solid var(--border); color: var(--text-1); }}
.btn.primary {{ background: {'var(--accent)' if light else 'linear-gradient(120deg, var(--accent-text), var(--accent-2))'};
  color: var(--on-accent); border: 0; box-shadow: 0 0 24px var(--glow-accent); }}
.btn.ghost {{ background: transparent; border-color: transparent; color: var(--text-2); }}
.btn.neon {{ background: transparent; border: 1px solid var(--neon); color: var(--text-1);
  box-shadow: 0 0 0 1px color-mix(in srgb, var(--neon) 55%, transparent), 0 0 18px var(--glow); }}
.btn.sm {{ height: 28px; padding: 0 10px; font-size: 12px; border-radius: 6px; }}
.seg {{ display: inline-flex; padding: 3px; gap: 3px; border-radius: 10px; background: var(--surface-2);
  border: 1px solid var(--border-subtle); }}
.seg span {{ height: 30px; padding: 0 14px; display: grid; place-items: center; border-radius: 7px; font: 500 13px/1 var(--body);
  color: var(--text-2); }}
.seg span.on {{ background: var(--raised); color: var(--text-1); box-shadow: inset 0 1px 0 var(--highlight), 0 1px 2px rgba(0,0,0,.4); }}
.seg span.on.acc {{ background: color-mix(in srgb, var(--accent) 22%, var(--raised)); color: var(--accent-text); }}
.chip {{ display: inline-flex; align-items: center; height: 28px; padding: 0 12px; border-radius: 999px; font: 500 12px/1 var(--body);
  border: 1px solid var(--border); color: var(--text-2); }}
.chip.on {{ background: var(--accent); color: var(--on-accent); border-color: var(--accent); }}
/* class tag */
.cls {{ display: inline-flex; align-items: center; gap: 9px; font-weight: 600; color: var(--c); }}
.cls i {{ width: 10px; height: 10px; border-radius: 2px; background: var(--c); box-shadow: {'0 0 0 1px rgba(11,27,43,.25)' if light
  else '0 0 8px color-mix(in srgb, var(--c) 60%, transparent)'}; }}
{'.cls { color: var(--text-1); }' if light else ''}
/* cards */
.card {{ background: var(--surface-1); border: 1px solid var(--border-subtle); border-radius: 18px;
  box-shadow: inset 0 1px 0 var(--highlight), 0 8px 24px -8px rgba(0,0,0,{'.15' if light else '.6'}); }}
.acc {{ border: 1px solid var(--border-subtle); border-radius: 12px; background: var(--surface-1); overflow: hidden; }}
.acc.open {{ border-color: var(--border-strong); }}
.acc-h {{ display: grid; grid-template-columns: 40px 1fr auto 20px; gap: 14px; align-items: center; min-height: 58px; padding: 8px 16px; }}
.acc-h .sig {{ font: 22px/1 var(--display); color: var(--accent-text); text-align: center; }}
.acc-h small {{ display: block; margin-top: 3px; font: 12px/1 var(--mono); color: var(--text-3); }}
.acc-h .meta {{ font: 500 12px/1 var(--body); color: var(--text-2); }}
.chev {{ color: var(--text-3); }}
/* table */
table {{ width: 100%; border-collapse: collapse; font: 400 13px/1.3 var(--body); }}
th {{ font: 600 10px/1.2 var(--body); letter-spacing: .14em; text-transform: uppercase; color: var(--text-3);
  background: var(--surface-2); padding: 10px 14px; text-align: left; white-space: nowrap; }}
th.sorted {{ color: var(--accent-text); }} th.r, td.r {{ text-align: right; }} th.c, td.c {{ text-align: center; }}
th .d {{ display: block; font: 11px/1 var(--mono); letter-spacing: 0; }}
td {{ padding: 8px 14px; border-top: 1px solid var(--border-subtle); white-space: nowrap; }}
tr.me td {{ background: color-mix(in srgb, var(--accent) 8%, transparent); }}
tr.me td:first-child {{ box-shadow: inset 2px 0 0 var(--accent); }}
tr.hov td {{ background: var(--surface-2); }}
td.stick {{ background: var(--surface-1); }}
.run {{ font: 500 13px/1 var(--mono); color: var(--accent-text); }}
.tot {{ display: inline-grid; place-items: center; min-width: 32px; height: 26px; border-radius: 8px; background: var(--surface-3);
  font: 500 14px/1 var(--mono); }}
/* bars */
.bar4 {{ height: 4px; border-radius: 2px; background: var(--border-subtle); overflow: hidden; }}
.bar4 i {{ display: block; height: 100%; background: var(--grad); }}
.timer {{ height: 6px; border-radius: 3px; background: var(--border-subtle); overflow: hidden; }}
.timer i {{ display: block; height: 100%; background: var(--grad); box-shadow: 0 0 10px var(--glow-accent); }}
/* roster */
.rcol {{ padding: 16px; display: flex; flex-direction: column; gap: 10px; }}
.rcol h3 {{ display: flex; align-items: center; gap: 8px; }} .rcol h3 .sp {{ flex: 1; }}
.cnt b {{ font: 500 17px/1 var(--mono); }} .cnt {{ font: 13px/1 var(--mono); color: var(--text-3); }}
.rl {{ display: flex; align-items: center; gap: 10px; padding: 8px 0; border-top: 1px solid var(--border-subtle); font-size: 13px; }}
.rl .spec {{ color: var(--text-3); margin-right: auto; }}
.free {{ color: var(--text-3); font-style: italic; }}
/* progress */
.prog {{ display: grid; grid-template-columns: 250px 1fr; border-radius: 18px; overflow: hidden; background: var(--surface-1);
  border: 1px solid var(--border-subtle); }}
.cov {{ position: relative; min-height: 170px; padding: 16px; display: flex; flex-direction: column; justify-content: flex-end; gap: 6px;
  background: var(--bgimg); }}
.cov::before {{ content: ""; position: absolute; inset: 0; background: var(--cover); }}
.cov > * {{ position: relative; }}
.cov .eyebrow {{ color: #FDA877; }}
.cov .nm {{ font: 600 22px/1.05 var(--display); letter-spacing: .06em; text-transform: uppercase; color: #F3EEF7; }}
.cov.locked {{ filter: grayscale(1) brightness(.7); }}
.pb {{ padding: 16px 18px; display: flex; flex-direction: column; gap: 12px; }}
.psum {{ display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }}
.psum .row b {{ font-weight: 600; font-size: 13px; }}
.bl {{ display: grid; grid-template-columns: 1fr 1fr; column-gap: 22px; }}
.bo {{ display: grid; grid-template-columns: 24px 1fr auto auto; gap: 8px; align-items: center; padding: 6px 0;
  border-top: 1px solid var(--border-subtle); font-size: 13px; }}
.bo .ix {{ font: 12px/1 var(--mono); color: var(--text-3); }}
.bo .kd {{ display: block; font: 11px/1.2 var(--mono); color: var(--text-3); }}
.k {{ display: inline-flex; align-items: center; gap: 3px; font: 10px/1 var(--mono); color: var(--text-3); }}
.k.dead {{ color: var(--accent-text); }}
.k svg {{ width: 14px; height: 14px; }}
/* items */
.item {{ display: flex; align-items: center; gap: 10px; }}
.ico {{ width: 34px; height: 34px; border-radius: 6px; border: 1px solid var(--q); background: radial-gradient(circle at 35% 30%,
  color-mix(in srgb, var(--q) 70%, #fff 0%), #120a18 75%); box-shadow: 0 0 8px color-mix(in srgb, var(--q) 50%, transparent); flex: none; }}
.ico.lg {{ width: 44px; height: 44px; }}
.iname {{ font-weight: 600; color: var(--q); }}
.list {{ display: flex; flex-direction: column; gap: 6px; }}
.li {{ display: flex; align-items: center; gap: 10px; padding: 8px 10px; border-radius: 10px; border: 1px solid var(--border-subtle);
  background: var(--surface-1); }}
.li.on {{ border-color: color-mix(in srgb, var(--accent) 45%, transparent); background: color-mix(in srgb, var(--accent) 7%, var(--surface-1)); }}
.note {{ display: flex; gap: 10px; padding: 12px 14px; border-radius: 12px; background: var(--surface-2); font-size: 12.5px; color: var(--text-2); }}
.note b {{ color: var(--accent-text); }}
.code {{ font: 11.5px/1.45 var(--mono); background: var(--surface-2); border: 1px solid var(--border); border-radius: 10px;
  padding: 12px 14px; white-space: pre; color: var(--text-2); overflow: hidden; }}
.code .sel {{ background: color-mix(in srgb, var(--accent) 28%, transparent); color: var(--text-1); }}
.sw {{ width: 38px; height: 22px; border-radius: 11px; background: var(--surface-3); border: 1px solid var(--border); position: relative; }}
.sw::after {{ content: ""; position: absolute; top: 3px; left: 3px; width: 14px; height: 14px; border-radius: 50%; background: var(--text-3); }}
.sw.on {{ background: var(--accent); border-color: var(--accent); }} .sw.on::after {{ left: 19px; background: var(--on-accent); }}
.neon-t {{ font: 600 26px/1 var(--display); letter-spacing: .08em; text-transform: uppercase; color: {'#0054B6' if light else '#E9A6E9'};
  text-shadow: {'none' if light else '0 0 12px rgba(196,91,196,.8), 0 0 36px rgba(154,42,154,.55)'}; }}
.grad-t {{ font: 600 34px/1 var(--display); background: var(--grad); -webkit-background-clip: text; background-clip: text; color: transparent; }}
.tip {{ position: absolute; background: var(--text-1); color: var(--bg); font: 500 12px/1.3 var(--body); padding: 7px 10px; border-radius: 4px;
  max-width: 260px; box-shadow: 0 8px 24px -8px rgba(0,0,0,.6); }}
.scrim {{ position: absolute; inset: 0; background: rgba(5,3,10,.6); display: grid; place-items: center; }}
.dlg {{ width: 440px; padding: 24px; display: flex; flex-direction: column; gap: 14px; border-radius: 28px; background: var(--surface-1);
  border: 1px solid var(--border); box-shadow: 0 24px 60px -20px rgba(0,0,0,.75); }}
.toast {{ position: absolute; right: 20px; bottom: 20px; width: 330px; padding: 12px 14px; border-radius: 12px; background: var(--raised);
  border: 1px solid var(--border); display: flex; gap: 10px; font-size: 12.5px; box-shadow: 0 24px 60px -20px rgba(0,0,0,.75); }}
.sw-grid {{ display: grid; grid-template-columns: repeat(6, 1fr); gap: 8px; }}
.swatch {{ border-radius: 10px; border: 1px solid var(--border-subtle); overflow: hidden; font: 10.5px/1.25 var(--mono); }}
.swatch div {{ height: 34px; }} .swatch p {{ padding: 5px 7px; color: var(--text-2); background: var(--surface-1); }}
"""


# ---- small pieces -------------------------------------------------------------------------------------------------------
def cls(name, c):
    return f'<span class="cls" style="--c:{CLASSES[c][0]}"><i></i>{esc(name)}</span>'


def badge(text, tone="", dot=False):
    return f'<span class="badge {tone}">{"<i></i>" if dot else ""}{esc(text)}</span>'


def btn(text, kind="", small=False):
    return f'<span class="btn {kind}{" sm" if small else ""}">{esc(text)}</span>'


def seg(options, on, accent=False):
    return '<span class="seg">' + "".join(
        f'<span class="{"on" + (" acc" if accent else "") if o == on else ""}">{esc(o)}</span>' for o in options) + "</span>"


def item(name, q="epic", big=False, sub=""):
    s = f'<div class="dim" style="font-size:12px">{esc(sub)}</div>' if sub else ""
    return (f'<div class="item" style="--q:{QUALITY[q]}"><span class="ico{" lg" if big else ""}"></span>'
            f'<div><div class="iname">{esc(name)}</div>{s}</div></div>')


SKULL = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="9" cy="12" r="1"/>'
         '<circle cx="15" cy="12" r="1"/><path d="M8 20v2h8v-2"/><path d="M12.5 17l-.5-1-.5 1h1z"/>'
         '<path d="M16 20a2 2 0 0 0 1.56-3.25 8 8 0 1 0-11.12 0A2 2 0 0 0 8 20"/></svg>')
TODO = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-dasharray="3 3">'
        '<circle cx="12" cy="12" r="9"/></svg>')
ICONS = {
    "tank": '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
    "healer": '<path d="M19 14c1.5-1.5 3-3.2 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.8 0-3 .5-4.5 2-1.5-1.5-2.7-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4 3 5.5l7 7z"/><path d="M3.2 12h4.3l1.5-3 3 6 1.5-3h7.3"/>',
    "dps": '<path d="M14.5 17.5 3 6V3h3l11.5 11.5"/><path d="m13 19 6-6"/><path d="m16 16 4 4"/><path d="m19 21 2-2"/><path d="M9.5 6.5 21 18v3h-3"/>',
    "sum": '<path d="M18 7V4H6l6 8-6 8h12v-3"/>',
    "chev": '<path d="m6 9 6 6 6-6"/>',
    "x": '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
    "info": '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>',
    "copy": '<rect x="8" y="8" width="14" height="14" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>',
    "dice": '<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8.5" cy="8.5" r="1"/><circle cx="15.5" cy="15.5" r="1"/><circle cx="12" cy="12" r="1"/>',
    "check": '<path d="M20 6 9 17l-5-5"/>',
}


def icon(name, size=18, color="currentColor"):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{color}" stroke-width="2" '
            f'stroke-linecap="round" stroke-linejoin="round" style="flex:none">{ICONS[name]}</svg>')


def kill(letter, dead):
    return f'<span class="k{" dead" if dead else ""}">{SKULL if dead else TODO}{letter}</span>'
