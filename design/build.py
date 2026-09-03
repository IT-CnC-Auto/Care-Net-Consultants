#!/usr/bin/env python3
"""Generates the Claude Design artboards (*.dc.html) for the Care Net
Sales tasks module. Run: python3 design/build.py

Matches the CNC Sales platform design handoff (Client Portal shell:
216px sidebar, 64px top bar, StatCard, CNC tokens in design/tokens/).
Working files are written next to this script."""
import os, json

OUT = os.path.dirname(os.path.abspath(__file__))

# ------------------------------------------------- CNC tokens (design/tokens/colors.css)
RED = "#ED1B24"; RED_D = "#C1272D"; RED_DEEP = "#8B0000"; RED_T = "#FDE8E9"; RED_SOFT = "#FEEDED"   # primary-soft = 8% red on white
INK = "#1E1E1E"; MUTE = "#787878"; LINE = "#E2E2E2"; GREY_L = "#F0F0F0"; SURFACE = "#F2F2F2"; CARD = "#FFFFFF"
GREEN = "#007749"; GREEN_T = "#E6F1ED"; BLUE = "#001489"; BLUE_T = "#E6E8F3"; YELLOW = "#FFB81C"; YELLOW_T = "#FFF4DC"
WARN = "#7A5A12"  # warning = yellow mixed 55% with charcoal, readable on yellow tint
SHADOW = "0 1px 3px rgba(0,0,0,.08),0 4px 14px rgba(0,0,0,.06)"
R_SM, R_MD, R_LG = "6px", "10px", "14px"
HEAD = "Montserrat,'Segoe UI',Arial,sans-serif"
BODY = "'Open Sans','Segoe UI',Arial,sans-serif"

PEOPLE = {
    "CB": ("Celeste Bulpitt", "#33578C"),
    "BK": ("Barteldt Kruger", INK),
    "AW": ("Annemarie Wiese", "#5C367D"),
    "AN": ("Asandiswa Ntsali", GREEN),
    "AM": ("Asekhona Magwashu", "#B35A1E"),
    "AS": ("Asivhanga More", "#0F6E6A"),
    "GB": ("Grok agent", RED),
}

ICONS = {
    "home": '<path d="M3 11l9-8 9 8v9a1 1 0 0 1-1 1h-5v-6h-4v6H4a1 1 0 0 1-1-1z"/>',
    "inbox": '<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
    "board": '<path d="M3 4h5v16H3z"/><path d="M10 4h5v10h-5z"/><path d="M17 4h4v7h-4z"/>',
    "users": '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
    "building": '<path d="M3 21h18"/><path d="M5 21V5a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v16"/><path d="M15 9h3a1 1 0 0 1 1 1v11"/><path d="M8 8h2M8 12h2M8 16h2"/>',
    "bot": '<path d="M12 2v3"/><rect x="5" y="5" width="14" height="14" rx="3"/><path d="M9 12h.01M15 12h.01M9 16h6M2 11v4M22 11v4"/>',
    "chart": '<path d="M3 3v18h18"/><path d="M7 14l4-4 4 3 5-6"/>',
    "settings": '<circle cx="12" cy="12" r="3"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
    "search": '<circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/>',
    "bell": '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/>',
    "plus": '<path d="M12 5v14M5 12h14"/>',
    "check": '<path d="M20 6 9 17l-5-5"/>',
    "chevdown": '<path d="m6 9 6 6 6-6"/>',
    "chevright": '<path d="m9 6 6 6-6 6"/>',
    "filter": '<path d="M22 3H2l8 9.5V19l4 2v-8.5z"/>',
    "calendar": '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
    "clock": '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    "alert": '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>',
    "sparkle": '<path d="M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9z"/><path d="M19 17l.8 2.2L22 20l-2.2.8L19 23l-.8-2.2L16 20l2.2-.8z"/>',
    "more": '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
    "db": '<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14c0 1.7 4 3 9 3s9-1.3 9-3V5"/><path d="M3 12c0 1.7 4 3 9 3s9-1.3 9-3"/>',
    "arrow": '<path d="M5 12h14"/><path d="M12 5l7 7-7 7"/>',
    "external": '<path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><path d="M15 3h6v6"/><path d="M10 14 21 3"/>',
    "message": '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
    "file": '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>',
    "shield": '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
    "lock": '<rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>',
    "mail": '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m2 7 10 7 10-7"/>',
    "refresh": '<path d="M21 12a9 9 0 1 1-2.6-6.4"/><path d="M21 3v6h-6"/>',
    "layers": '<path d="m12 2 10 5-10 5L2 7z"/><path d="m2 12 10 5 10-5"/><path d="m2 17 10 5 10-5"/>',
    "x": '<path d="M18 6 6 18M6 6l12 12"/>',
    "pause": '<path d="M8 5v14M16 5v14"/>',
    "monitor": '<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8M12 17v4"/>',
    "desk": '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
    "zap": '<path d="M13 2 3 14h9l-1 8 10-12h-9z"/>',
}

def ic(name, size=18, color="currentColor", sw=1.75):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{color}" '
            f'stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">{ICONS[name]}</svg>')

def av(code, size=28):
    name, col = PEOPLE[code]
    fs = 11 if size >= 28 else 9
    inner = code if code != "GB" else ic("bot", max(12, size // 2), "#fff", 2)
    return (f'<span title="{name}" style="width:{size}px;height:{size}px;border-radius:999px;background:{col};color:#fff;'
            f'display:inline-flex;align-items:center;justify-content:center;font-family:{HEAD};'
            f'font-weight:600;font-size:{fs}px;flex-shrink:0">{inner}</span>')

# Status vocabulary kept from MyClinicOnline (New, In progress, Completed) plus two portal states.
PILL = {
    "new":  (YELLOW_T, WARN, "New", "transparent"),
    "prog": (BLUE_T, BLUE, "In progress", "transparent"),
    "done": (GREEN_T, GREEN, "Completed", "transparent"),
    "over": (RED_T, RED_D, "Overdue", "transparent"),
    "wait": ("#fff", INK, "Awaiting approval", INK),
    "hold": (GREY_L, MUTE, "On hold", "transparent"),
}
def pill(kind, text=None):
    bg, fg, label, bd = PILL[kind]
    return (f'<span style="display:inline-flex;align-items:center;height:22px;padding:0 9px;border-radius:999px;box-sizing:border-box;'
            f'background:{bg};color:{fg};border:1px solid {bd};font-size:11.5px;font-weight:600;white-space:nowrap">{text or label}</span>')

SRC = {
    "mco": ("MCO", BLUE, BLUE_T),
    "bot": ("Grok", RED_D, RED_T),
    "man": ("Manual", MUTE, GREY_L),
    "crm": ("AutoHive CRM", "#5C367D", "#EEE8F4"),
}
def src(kind):
    label, fg, bg = SRC[kind]
    return (f'<span style="display:inline-flex;align-items:center;height:20px;padding:0 7px;border-radius:{R_SM};'
            f'background:{bg};color:{fg};font-size:10.5px;font-weight:700;letter-spacing:.02em;white-space:nowrap">{label}</span>')

def stage(text, on=False, done=False):
    if on:
        st = f"background:{RED};color:#fff;border:1px solid {RED}"
    elif done:
        st = f"background:{GREY_L};color:{INK};border:1px solid {LINE}"
    else:
        st = f"background:#fff;color:{MUTE};border:1px dashed #CFCFCF"
    return (f'<span style="display:inline-flex;align-items:center;height:22px;padding:0 9px;border-radius:{R_SM};box-sizing:border-box;'
            f'font-size:11px;font-weight:600;white-space:nowrap;{st}">{text}</span>')

def btn(text, kind="sec", icon=None, h=36):
    styles = {
        "pri": f"background:{RED};color:#fff;border:1px solid {RED}",
        "sec": f"background:#fff;color:{INK};border:1px solid {LINE}",
        "ghost": f"background:transparent;color:{BLUE};border:1px solid transparent;padding:0 6px",
        "dark": f"background:{INK};color:#fff;border:1px solid {INK}",
    }[kind]
    i = ic(icon, 16, "currentColor", 2) if icon else ""
    return (f'<button style="height:{h}px;padding:0 14px;border-radius:{R_SM};font-family:{BODY};'
            f'font-weight:600;font-size:13px;display:inline-flex;align-items:center;gap:8px;cursor:pointer;{styles}">{i}{text}</button>')

def field(label, value, w=200, icon="chevdown", placeholder=False):
    col = MUTE if placeholder else INK
    return (f'<div style="position:relative;width:{w}px;height:40px;border:1px solid {LINE};border-radius:{R_SM};background:#fff;'
            f'display:flex;align-items:center;justify-content:space-between;padding:0 12px;box-sizing:border-box">'
            f'<span style="position:absolute;top:-8px;left:10px;background:#fff;padding:0 4px;font-size:10.5px;color:{MUTE}">{label}</span>'
            f'<span style="font-size:13px;color:{col};white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{value}</span>{ic(icon,16,MUTE,2)}</div>')

def statcard(label, value, detail, tone=None):
    """Reproduces AutoHivePeopleDesignSystem StatCard as used in the Client Portal (hint-size 100%,104px)."""
    vcol = {"warning": WARN, "success": GREEN, "danger": RED_D}.get(tone, INK)
    return (f'<div style="flex:1;min-width:0;height:104px;box-sizing:border-box;background:{CARD};border:1px solid {LINE};border-radius:{R_MD};'
            f'box-shadow:{SHADOW};padding:16px 18px;display:flex;flex-direction:column;justify-content:center;gap:2px">'
            f'<div style="font-size:12px;color:{MUTE};font-weight:600">{label}</div>'
            f'<div style="font-family:{HEAD};font-weight:600;font-size:26px;color:{vcol};line-height:1.15">{value}</div>'
            f'<div style="font-size:12px;color:{MUTE};white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{detail}</div></div>')

def card(inner, pad="16px 20px", extra=""):
    return f'<div style="background:{CARD};border:1px solid {LINE};border-radius:{R_MD};box-shadow:{SHADOW};padding:{pad};{extra}">{inner}</div>'

def h2(text, sub=None):
    s = f'<span style="font-size:12px;color:{MUTE};font-weight:400">{sub}</span>' if sub else ""
    return f'<h2 style="font-family:{HEAD};font-weight:600;font-size:15px;color:{RED};margin:0;display:flex;align-items:baseline;gap:10px">{text}{s}</h2>'

def confirm(text):
    return f'<span style="display:inline-flex;align-items:center;height:18px;padding:0 6px;border-radius:4px;background:{YELLOW_T};color:{WARN};font-size:10px;font-weight:700;letter-spacing:.04em;white-space:nowrap">{text}</span>'

# ---------------------------------------------------------------- base css
BASE_CSS = f"""
@import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700&family=Open+Sans:ital,wght@0,400;0,600;0,700;1,400&display=swap');
body{{margin:0;font-family:{BODY};color:{INK};background:{SURFACE};font-size:13px;line-height:1.55;-webkit-font-smoothing:antialiased}}
h1,h2,h3,h4{{font-family:{HEAD};margin:0;color:{INK}}}
a{{color:{BLUE};text-decoration:none}}a:hover{{color:#000C5E}}
button{{font-family:inherit}}
table{{border-collapse:collapse}}
"""

NAV = [("desk", "Desk"), ("home", "My work"), ("inbox", "Inbox"), ("board", "Team board"), ("building", "Clients"),
       ("zap", "Sales automations"), ("shield", "Roles and permissions")]

def sidebar(active, badge_inbox=12):
    logo = ('<div style="padding:18px 20px 14px 20px;display:flex;flex-direction:column;gap:10px">'
            '<img src="cnc-logo-trim.png" alt="Care Net Consultants" style="height:44px;width:auto;align-self:flex-start">'
            f'<div><div style="font-family:{HEAD};font-weight:600;font-size:16px;color:{RED}">Care Net Consultants</div>'
            f'<div style="font-size:12px;color:{MUTE};margin-top:2px">Sales Executive desk</div></div></div>')
    items = []
    for key, label in NAV:
        on = label == active
        st = f"background:{RED_SOFT};color:{RED_D}" if on else f"color:{INK}"
        icol = RED_D if on else MUTE
        badge = (f'<span style="margin-left:auto;background:{RED};color:#fff;font-size:10px;font-weight:700;height:18px;min-width:18px;'
                 f'padding:0 5px;border-radius:9px;display:inline-flex;align-items:center;justify-content:center">{badge_inbox}</span>') if label == "Inbox" else ""
        items.append(f'<div style="display:flex;align-items:center;gap:10px;height:40px;padding:0 12px;border-radius:{R_SM};font-weight:600;font-size:13px;{st}">{ic(key,18,icol)}{label}{badge}</div>')
    nav = '<nav style="display:flex;flex-direction:column;gap:2px;padding:0 12px">' + "".join(items) + "</nav>"
    mods = (f'<div style="padding:18px 20px 8px 20px;font-size:10.5px;font-weight:700;color:{MUTE};letter-spacing:.08em;text-transform:uppercase">Modules</div>'
            '<div style="display:flex;flex-direction:column;gap:2px;padding:0 12px">'
            f'<div style="display:flex;align-items:center;gap:10px;height:34px;padding:0 12px;border-radius:{R_SM};font-size:12.5px;color:{INK}"><span style="width:8px;height:8px;border-radius:50%;background:{RED}"></span>Sales<span style="margin-left:auto;font-size:10.5px;color:{GREEN};font-weight:600">live</span></div>'
            + "".join(f'<div style="display:flex;align-items:center;gap:10px;height:34px;padding:0 12px;border-radius:{R_SM};font-size:12.5px;color:{MUTE}"><span style="width:8px;height:8px;border-radius:50%;border:1px solid #BDBDBD"></span>{m}<span style="margin-left:auto;font-size:10.5px;color:{MUTE}">next</span></div>'
                      for m in ["Clinic operations", "Finance", "HR and compliance"])
            + '</div>')
    foot = (f'<div style="margin-top:auto;padding:14px 20px;border-top:1px solid {LINE};display:flex;align-items:center;gap:10px">'
            f'{av("BK")}<div style="min-width:0"><div style="font-size:12.5px;font-weight:600">Barteldt Kruger</div><div style="font-size:11px;color:{MUTE}">Franchise Director</div></div>'
            f'<span style="margin-left:auto">{ic("settings",16,MUTE)}</span></div>')
    return (f'<aside style="width:216px;flex:none;border-right:1px solid {LINE};background:{CARD};display:flex;flex-direction:column">'
            f'{logo}{nav}{mods}{foot}</aside>')

def topbar(crumbs):
    crumb_html = ""
    for i, c in enumerate(crumbs):
        last = i == len(crumbs) - 1
        crumb_html += f'<span style="font-size:13px;color:{INK if last else MUTE};font-weight:{600 if last else 400}">{c}</span>'
        if not last:
            crumb_html += ic("chevright", 14, "#BDBDBD", 2)
    quick = (f'<div style="width:360px;height:40px;border:1px solid {LINE};border-radius:{R_SM};display:flex;align-items:center;gap:8px;padding:0 12px;'
             f'color:{MUTE};font-size:12.5px;box-sizing:border-box;background:{CARD}">{ic("plus",16,RED_D,2)}Quick add a task, for example call Thabo Friday 9am</div>')
    return (f'<header style="height:64px;flex:none;border-bottom:1px solid {LINE};background:{CARD};display:flex;align-items:center;gap:12px;padding:0 24px">'
            f'<div style="display:flex;align-items:center;gap:6px">{crumb_html}</div>'
            f'{confirm("Demo data, mock fixtures")}'
            f'<div style="margin-left:auto;display:flex;align-items:center;gap:12px">{quick}'
            f'<span style="display:inline-flex;width:40px;height:40px;align-items:center;justify-content:center;border:1px solid {LINE};border-radius:{R_SM};background:{CARD}">{ic("search",18,INK)}</span>'
            f'<span style="position:relative;display:inline-flex;width:40px;height:40px;align-items:center;justify-content:center;border:1px solid {LINE};border-radius:{R_SM};background:{CARD}">{ic("bell",18,INK)}<span style="position:absolute;top:8px;right:9px;width:8px;height:8px;border-radius:50%;background:{RED};border:2px solid #fff"></span></span>'
            f'{av("BK",36)}</div></header>')

def footer():
    return (f'<footer style="flex:none;border-top:1px solid {LINE};background:{CARD};display:flex;align-items:center;justify-content:center;gap:10px;padding:10px 24px;font-size:11.5px;color:{MUTE}">'
            f'<span>Care Net Consultants (Pty) Ltd · Sales tasks module · data stays in the portal and MyClinicOnline</span>'
            f'<span style="display:inline-flex;align-items:center;gap:6px;border:1px solid {LINE};border-radius:999px;padding:2px 10px">A proudly AutoHive built application {confirm("CONFIRM attribution")}</span></footer>')

def shell(active, crumbs, body, h=900):
    return (f'<div style="display:flex;width:1440px;height:{h}px;overflow:hidden;background:{SURFACE}">{sidebar(active)}'
            f'<div style="flex:1;display:flex;flex-direction:column;min-width:0">{topbar(crumbs)}{body}{footer()}</div></div>')

def doc(title, body):
    return f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <title>{title}</title>
  <style>{BASE_CSS}</style>
</helmet>
{body}
</x-dc>
</body>
</html>
"""

def write(name, html):
    with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
        f.write(html)
    print("wrote", name, len(html), "bytes")

def page_head(title, sub, actions):
    return (f'<div style="display:flex;align-items:flex-end;gap:16px">'
            f'<div><h1 style="font-size:22px;font-weight:600">{title}</h1><div style="font-size:13px;color:{MUTE};margin-top:2px">{sub}</div></div>'
            f'<div style="margin-left:auto;display:flex;gap:8px">{actions}</div></div>')

# =============================================================== 01 MY WORK
GRID = "minmax(0,1fr) 130px 150px 100px 72px 90px"
def task_row(title, kind, due, who, source, stage_txt, sub=None, indent=False, ai=False):
    pad = 56 if indent else 16
    connector = (f'<span style="width:14px;height:14px;border-left:1px solid #CFCFCF;border-bottom:1px solid #CFCFCF;'
                 f'border-radius:0 0 0 4px;margin-right:6px;margin-top:-8px;flex-shrink:0"></span>') if indent else ""
    tick = (f'<span style="width:18px;height:18px;border-radius:5px;border:1.5px solid {"transparent" if kind=="done" else "#BDBDBD"};background:{GREEN if kind=="done" else "#fff"};flex-shrink:0;'
            f'display:inline-flex;align-items:center;justify-content:center">{ic("check",12,"#fff",3) if kind=="done" else ""}</span>')
    aichip = (f'<span style="display:inline-flex;align-items:center;gap:4px;font-size:10.5px;font-weight:700;color:{RED_D}">{ic("sparkle",12,RED_D,2)}drafted</span>') if ai else ""
    subline = f'<div style="font-size:11.5px;color:{MUTE};margin-top:1px">{sub}</div>' if sub else ""
    return (f'<div style="display:grid;grid-template-columns:{GRID};align-items:center;'
            f'height:{"44px" if indent else "52px"};padding:0 16px 0 {pad}px;border-top:1px solid {GREY_L};background:{CARD}">'
            f'<div style="display:flex;align-items:center;gap:10px;min-width:0">{connector}{tick}<div style="min-width:0"><div style="display:flex;align-items:center;gap:8px;min-width:0"><span style="font-size:13px;font-weight:{500 if indent else 600};color:{INK};white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{title}</span>{aichip}</div>{subline}</div></div>'
            f'<div>{pill(kind)}</div>'
            f'<div>{stage(stage_txt, on=not indent, done=indent)}</div>'
            f'<div style="font-size:12.5px;color:{RED_D if kind=="over" else INK};display:flex;align-items:center;gap:6px">{ic("calendar",14,RED_D if kind=="over" else MUTE)}{due}</div>'
            f'<div>{av(who,26)}</div>'
            f'<div style="display:flex;justify-content:flex-end">{src(source)}</div></div>')

def group_header(client, meta, count, expanded=True):
    return (f'<div style="display:flex;align-items:center;gap:12px;height:46px;padding:0 16px;background:#FAFAFA;border-top:1px solid {LINE}">'
            f'{ic("chevdown" if expanded else "chevright",16,INK,2)}{ic("building",16,MUTE)}'
            f'<span style="font-family:{HEAD};font-weight:600;font-size:13.5px">{client}</span>'
            f'<span style="font-size:12px;color:{MUTE}">{meta}</span>'
            f'<span style="margin-left:auto;font-size:11.5px;color:{MUTE};font-weight:600">{count}</span>{ic("more",16,MUTE)}</div>')

def my_work():
    head = page_head("My work", "Wednesday 3 September 2026 · Celeste Bulpitt · Sales Consultant · ranked by due date, SLA risk and dependency",
                     btn("Add a task", "sec", "plus") + btn("Excel report", "sec", "file") + btn("Ask the assistant", "pri", "sparkle"))
    tabs = '<div style="display:flex;gap:4px;border-bottom:1px solid ' + LINE + '">' + "".join(
        f'<div style="padding:8px 12px;font-size:13px;font-weight:600;color:{INK if on else MUTE};border-bottom:2px solid {RED if on else "transparent"};margin-bottom:-1px">{t}</div>'
        for t, on in [("Today", True), ("List", False), ("Board", False), ("Calendar", False), ("Client journey", False)]) + '</div>'
    stats = ('<div style="display:flex;gap:12px">'
             + statcard("Due today", "6", "2 from the MCO sync this morning")
             + statcard("Overdue", "2", "Tolcon Group · CGI Industries", "danger")
             + statcard("Awaiting my signature", "3", "Grok drafts to review before they send", "warning")
             + statcard("Ticked this week", "41", "subtasks closed, 0 agent errors", "success") + "</div>")
    filters = ('<div style="display:flex;gap:14px;flex-wrap:wrap;align-items:center">'
               + field("Source", "All sources", 150) + field("Task type", "All", 170) + field("Status", "New, In progress", 170)
               + field("Journey stage", "All stages", 160) + field("Client", "All clients", 180)
               + field("Date type", "Task due date", 150) + field("Date from", "01/09/2026", 130, "calendar") + field("Date to", "30/11/2026", 130, "calendar")
               + f'<span style="display:flex;align-items:center;gap:6px;color:{BLUE};font-weight:600;font-size:12.5px">{ic("filter",14,BLUE,2)}Save view</span></div>')
    cols = (f'<div style="display:grid;grid-template-columns:{GRID};padding:0 16px;height:36px;align-items:center;'
            f'font-size:11px;font-weight:700;color:{MUTE};text-transform:uppercase;letter-spacing:.05em;background:{CARD}">'
            '<div>Task</div><div>Status</div><div>Journey stage</div><div>Due</div><div>Owner</div><div style="text-align:right">Source</div></div>')
    rows = [
        group_header("Pt Operational Services (Pty) Ltd", "Account owner Celeste · renewal window October 2026", "1 parent · 5 subtasks"),
        task_row("97 medicals expiring between 01/10/2026 and 31/10/2026", "prog", "16/09/2026", "CB", "mco", "Renewal",
                 sub="MCO Medicals Due · created 01/09 09:30 · Grok grouped 5 subtasks · 2 of 5 ticked"),
        task_row("Confirm employee list and sites with the HR contact", "done", "03/09/2026", "CB", "bot", "Renewal", indent=True),
        task_row("Send booking proposal for 6 to 10 October", "wait", "04/09/2026", "CB", "bot", "Schedule", indent=True, ai=True),
        task_row("Reserve mobile clinic slots at Secunda and Sasolburg", "new", "08/09/2026", "AN", "bot", "Schedule", indent=True),
        task_row("Collect outstanding ID copies (12 cases pending)", "new", "10/09/2026", "CB", "mco", "Certificates", indent=True),
        task_row("Raise pro forma invoice for 97 medicals", "new", "12/09/2026", "AW", "bot", "Invoice", indent=True),
        group_header("Afrirent Auto (Pty) Ltd", "Account owner Celeste · 26 medicals due October 2026", "1 parent · 4 subtasks", expanded=False),
        task_row("26 medicals expiring between 01/10/2026 and 31/10/2026", "new", "16/09/2026", "CB", "mco", "Renewal",
                 sub="Grok proposed 4 subtasks · awaiting your acceptance"),
        group_header("Tolcon Group (Pty) Ltd.", "Account owner Celeste · 24 medicals due, 3 non arrivals on the last clinic day", "2 parents · 6 subtasks", expanded=False),
        task_row("Non arrival: 3 cases missed clinic day 28/08", "over", "01/09/2026", "CB", "mco", "Clinic day",
                 sub="Rebooking required · client contact in AutoHive CRM"),
        task_row("24 medicals expiring between 01/10/2026 and 31/10/2026", "new", "16/09/2026", "CB", "mco", "Renewal"),
        group_header("CGI Industries", "Account owner Celeste · single site client", "1 parent · 2 subtasks", expanded=False),
        task_row("Medicals: ID pending, case 4471", "over", "02/09/2026", "CB", "mco", "Certificates"),
    ]
    table = f'<div style="background:{CARD};border:1px solid {LINE};border-radius:{R_MD};box-shadow:{SHADOW};overflow:hidden">{cols}{"".join(rows)}</div>'

    assistant = card(
        f'<div style="display:flex;align-items:center;gap:8px;margin-bottom:10px"><span style="width:28px;height:28px;border-radius:{R_SM};background:{RED_T};display:inline-flex;align-items:center;justify-content:center">{ic("sparkle",16,RED,2)}</span>{h2("Assistant")}<span style="margin-left:auto;font-size:11px;color:{MUTE}">Grok · 09:31</span></div>'
        f'<p style="margin:0 0 10px;font-size:13px;color:{INK};line-height:1.55">I pulled <strong>10 Medicals Due</strong> tasks from MyClinicOnline for your clients, grouped them by client and drafted subtasks along the renewal journey. Two items need your signature:</p>'
        f'<div style="display:flex;flex-direction:column;gap:8px">'
        f'<div style="border:1px solid {LINE};border-radius:{R_SM};padding:10px 12px;display:flex;flex-direction:column;gap:6px"><div style="font-size:12.5px;font-weight:600">Sign and send the booking proposal</div><div style="font-size:11.5px;color:{MUTE}">Pt Operational Services · 97 medicals · 6 to 10 October</div><div style="display:flex;gap:6px">{btn("Approve and send","pri",None,32)}{btn("Edit draft","sec",None,32)}</div></div>'
        f'<div style="border:1px solid {LINE};border-radius:{R_SM};padding:10px 12px;display:flex;flex-direction:column;gap:6px"><div style="font-size:12.5px;font-weight:600">Accept 4 proposed subtasks</div><div style="font-size:11.5px;color:{MUTE}">Afrirent Auto · 26 medicals · assigned to you</div><div style="display:flex;gap:6px">{btn("Accept all","dark",None,32)}{btn("Review","sec",None,32)}</div></div>'
        f'</div>'
        f'<div style="margin-top:10px;height:40px;border:1px solid {LINE};border-radius:{R_SM};display:flex;align-items:center;padding:0 12px;color:{MUTE};font-size:12.5px;gap:8px">Ask about a client or task<span style="margin-left:auto">{ic("arrow",14,MUTE,2)}</span></div>'
        f'<div style="margin-top:8px;font-size:11px;color:{MUTE}">AI drafts, a named human signs. Nothing sends without you.</div>', pad="16px")
    journey = card(
        h2("My clients on the journey") + '<div style="display:flex;flex-direction:column;gap:8px;margin-top:10px">'
        + "".join(
            f'<div style="display:flex;align-items:center;gap:10px"><span style="width:100px;font-size:12px;color:{INK};white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{n}</span>'
            f'<div style="flex:1;display:flex;gap:3px">' + "".join(f'<span style="flex:1;height:6px;border-radius:3px;background:{RED if i==cur else ("#D6D6D6" if i<cur else GREY_L)}"></span>' for i in range(8)) + f'</div><span style="font-size:11px;color:{MUTE};width:66px;text-align:right">{s}</span></div>'
            for n, cur, s in [("Pt Operational", 7, "Renewal"), ("Afrirent Auto", 7, "Renewal"), ("Tolcon Group", 4, "Clinic day"), ("Nuvest Chemicals", 3, "Schedule"), ("Univac Cooling", 2, "Onboard"), ("CGI Industries", 5, "Certificates")])
        + f'</div><div style="font-size:11px;color:{MUTE};display:flex;justify-content:space-between;margin-top:8px"><span>Prospect</span><span>Renewal</span></div>', pad="16px")
    today = card(
        h2("Today") + '<div style="display:flex;flex-direction:column;gap:8px;margin-top:10px">'
        + "".join(f'<div style="display:flex;gap:10px;align-items:flex-start"><span style="font-size:11.5px;color:{MUTE};width:40px;flex-shrink:0;padding-top:1px">{t}</span><span style="font-size:12.5px;color:{INK}">{d}</span></div>'
                  for t, d in [("10:00", "Call the Tolcon HR contact about 3 non arrivals"), ("11:30", "Weekly pipeline review with Barteldt"), ("14:00", "Nuvest Chemicals: confirm clinic date")])
        + "</div>", pad="16px")
    rail = f'<aside style="width:300px;flex-shrink:0;display:flex;flex-direction:column;gap:12px">{assistant}{journey}{today}</aside>'
    body = (f'<div style="flex:1;overflow:hidden;padding:20px 24px;display:flex;gap:20px">'
            f'<div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:16px">{head}{tabs}{stats}{filters}{table}</div>{rail}</div>')
    return doc("My work", shell("My work", ["Sales Executive desk", "My work"], body, h=1240))

# =============================================================== 02 INBOX
def inbox():
    head = page_head("Inbox", "Everything that needs a decision from you in one place: agent proposals, signatures, mentions, MCO changes",
                     btn("Mark all read", "sec") + btn("Approve all safe items (5)", "dark", "check"))
    tabs = '<div style="display:flex;gap:4px;border-bottom:1px solid ' + LINE + '">' + "".join(
        f'<div style="padding:8px 12px;font-size:13px;font-weight:600;color:{INK if on else MUTE};border-bottom:2px solid {RED if on else "transparent"};margin-bottom:-1px;display:flex;gap:6px;align-items:center">{t}<span style="font-size:11px;color:{MUTE};background:{GREY_L};border-radius:9px;padding:0 6px">{n}</span></div>'
        for t, n, on in [("Needs my signature", 4, True), ("Proposed by Grok", 5, False), ("Mentions", 2, False), ("MCO changes", 1, False), ("All", 12, False)]) + '</div>'
    def item(kind_icon, title, meta, who, when, actions, sel=False, s="bot"):
        return (f'<div style="display:flex;gap:12px;padding:14px 16px;border-top:1px solid {GREY_L};background:{RED_SOFT if sel else CARD}">'
                f'<span style="width:32px;height:32px;border-radius:{R_SM};background:{RED_T if s=="bot" else GREY_L};display:inline-flex;align-items:center;justify-content:center;flex-shrink:0">{ic(kind_icon,16,RED if s=="bot" else INK,2)}</span>'
                f'<div style="flex:1;min-width:0"><div style="display:flex;align-items:center;gap:8px"><span style="font-size:13px;font-weight:600">{title}</span>{src(s)}<span style="margin-left:auto;font-size:11.5px;color:{MUTE}">{when}</span></div>'
                f'<div style="font-size:12.5px;color:{INK};margin-top:2px">{meta}</div>'
                f'<div style="display:flex;gap:6px;margin-top:8px;align-items:center">{actions}<span style="margin-left:auto;display:inline-flex;align-items:center;gap:6px;font-size:11.5px;color:{MUTE}">{av(who,20)}{PEOPLE[who][0]}</span></div></div></div>')
    items = (item("sparkle", "Approve allocation: 26 medicals · Afrirent Auto", "Grok proposes Celeste (account owner, 14 open). Alternative: Asekhona (6 open, largest book gap, no history with this client).", "GB", "09:31",
                  btn("Approve Celeste", "pri", None, 32) + btn("Assign Asekhona", "sec", None, 32) + btn("Open task", "ghost", None, 32), sel=True)
             + item("mail", "Sign outbound email: booking proposal to the Pt Operational Services HR contact", "Subtask 2 of TSK-2026-1187 · counts and dates only, no employee names · rule R-06 hold.", "GB", "09:31",
                    btn("Preview", "sec", None, 32) + btn("Approve and send", "pri", None, 32) + btn("Request changes", "ghost", None, 32))
             + item("alert", "Threshold exceeded: 97 medicals · Pt Operational Services", f"Above the 20 medical limit in rule R-02 {confirm('CONFIRM threshold')}. Allocation to Celeste is on hold until a Sales Manager confirms.", "GB", "01/09 09:30",
                    btn("Confirm allocation", "pri", None, 32) + btn("Split across two consultants", "sec", None, 32))
             + item("users", "Reassignment request from Celeste", "Can Asandiswa take the Secunda slot reservation? I am at Tolcon that week. Subtask 3 of TSK-2026-1187.", "CB", "Yesterday 16:20",
                    btn("Approve", "pri", None, 32) + btn("Decline", "sec", None, 32), s="man")
             + item("message", "Annemarie mentioned you on ISE Group · PO number outstanding", "@Barteldt the client wants the PO referenced on the pro forma. Can we hold the invoice two days?", "AW", "Yesterday 14:02",
                    btn("Reply", "sec", None, 32) + btn("Open task", "ghost", None, 32), s="man")
             + item("refresh", "MCO changed a task you follow", "Medicals: ID pending, case 4471 (CGI Industries) moved to Completed in MyClinicOnline. The portal task closes in 24 hours unless you keep it open.", "GB", "06:01",
                    btn("Close now", "sec", None, 32) + btn("Keep open", "ghost", None, 32), s="mco"))
    listc = f'<div style="flex:1;min-width:0;background:{CARD};border:1px solid {LINE};border-radius:{R_MD};box-shadow:{SHADOW};overflow:hidden">{items}</div>'
    side = (f'<div style="width:320px;flex-shrink:0;display:flex;flex-direction:column;gap:12px">'
            + card(h2("Why you are seeing these") + f'<div style="font-size:12.5px;color:{INK};line-height:1.55;margin-top:8px">You are the Franchise Director. You receive signatures that exceed Sales Manager thresholds, anything Annemarie escalates, and one daily digest of agent activity. Consultants only see items for their own tasks.</div>'
                   f'<div style="display:flex;align-items:center;gap:8px;font-size:12.5px;color:{BLUE};font-weight:600;margin-top:10px">{ic("settings",14,BLUE,2)}Notification rules</div>', pad="16px")
            + card(h2("This morning's sync") + '<div style="margin-top:6px">'
                   + "".join(f'<div style="display:flex;justify-content:space-between;font-size:12.5px;padding:6px 0;border-top:1px solid {GREY_L}"><span style="color:{INK}">{k}</span><span style="font-weight:600">{v}</span></div>' for k, v in [("MCO tasks read", "1,284"), ("New since yesterday", "11"), ("Parent tasks created", "11"), ("Subtasks drafted", "38"), ("Allocated by rule", "8"), ("Held for a person", "3"), ("Errors", "0")])
                   + "</div>", pad="16px")
            + '</div>')
    body = f'<div style="flex:1;overflow:hidden;padding:20px 24px;display:flex;flex-direction:column;gap:14px">{head}{tabs}<div style="display:flex;gap:12px;flex:1;min-height:0">{listc}{side}</div></div>'
    return doc("Inbox", shell("Inbox", ["Sales Executive desk", "Inbox"], body, h=1000))

# =============================================================== 03 TEAM BOARD
def kcard(client, title, who, due, n, kind, source="mco", ai=False):
    aichip = f'<span style="display:inline-flex;align-items:center;gap:4px;font-size:10.5px;font-weight:700;color:{RED_D}">{ic("sparkle",11,RED_D,2)}Grok</span>' if ai else ""
    return (f'<div style="background:{CARD};border:1px solid {LINE};border-radius:{R_SM};padding:12px;display:flex;flex-direction:column;gap:8px;box-shadow:{SHADOW}">'
            f'<div style="display:flex;align-items:center;gap:6px;font-size:11px;color:{MUTE};font-weight:600;min-width:0">{ic("building",12,MUTE)}<span style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{client}</span><span style="margin-left:auto">{src(source)}</span></div>'
            f'<div style="font-size:12.5px;font-weight:600;line-height:1.4">{title}</div>'
            f'<div style="display:flex;align-items:center;gap:8px">{pill(kind)}{aichip}<span style="margin-left:auto;font-size:11px;color:{MUTE};white-space:nowrap">{n}</span></div>'
            f'<div style="display:flex;align-items:center;gap:6px;font-size:11.5px;color:{RED_D if kind=="over" else INK}">{ic("calendar",13,RED_D if kind=="over" else MUTE)}{due}<span style="margin-left:auto">{av(who,24)}</span></div></div>')

def column(name, count, cards, tone):
    return (f'<div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:10px">'
            f'<div style="display:flex;align-items:center;gap:8px;height:32px;padding:0 4px"><span style="width:8px;height:8px;border-radius:50%;background:{tone}"></span><span style="font-family:{HEAD};font-weight:600;font-size:12.5px">{name}</span><span style="font-size:11.5px;color:{MUTE};font-weight:600">{count}</span><span style="margin-left:auto">{ic("plus",14,MUTE,2)}</span></div>'
            f'<div style="display:flex;flex-direction:column;gap:8px;background:{GREY_L};border-radius:{R_MD};padding:8px;min-height:380px">{"".join(cards)}</div></div>')

def team_board():
    head = page_head("Team board", "Sales team · every open parent task placed on the client journey · Sales Manager view",
                     field("Group by", "Journey stage", 170) + field("Team", "Sales · all consultants", 200) + btn("Reassign", "sec", "users") + btn("Allocate queue (4)", "pri", "sparkle"))
    def load(code, n, cap, over_n):
        name, col = PEOPLE[code]
        pct = min(100, int(n / cap * 100))
        bar = RED if n > cap else INK
        return (f'<div style="flex:1;min-width:0;background:{CARD};border:1px solid {LINE};border-radius:{R_MD};box-shadow:{SHADOW};padding:12px 14px;display:flex;flex-direction:column;gap:8px">'
                f'<div style="display:flex;align-items:center;gap:8px">{av(code,26)}<div style="min-width:0"><div style="font-size:12.5px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{name}</div><div style="font-size:11px;color:{MUTE}">{n} open · {over_n} overdue</div></div>'
                f'<span style="margin-left:auto;font-family:{HEAD};font-weight:600;font-size:13px;color:{bar}">{pct}%</span></div>'
                f'<div style="height:6px;border-radius:3px;background:{GREY_L};overflow:hidden"><span style="display:block;height:100%;width:{pct}%;background:{bar};border-radius:3px"></span></div></div>')
    loads = ('<div style="display:flex;gap:10px;align-items:flex-start">' + load("CB", 14, 12, 2) + load("AN", 11, 12, 0) + load("AW", 9, 12, 1) + load("AS", 8, 12, 0) + load("AM", 6, 12, 0)
             + f'<div style="width:270px;flex-shrink:0;box-sizing:border-box;background:{INK};color:#fff;border-radius:{R_MD};padding:12px 14px;display:flex;flex-direction:column;gap:6px">'
             f'<div style="display:flex;align-items:center;gap:8px">{ic("sparkle",16,RED,2)}<span style="font-size:12.5px;font-weight:600">Allocation queue</span><span style="margin-left:auto;font-family:{HEAD};font-weight:600;font-size:18px">4</span></div>'
             f'<div style="font-size:11.5px;color:#D6D6D6">Allocation rule: standard task to the consultant with the largest book gap, high profile client to a senior with room. One task exceeds the 20 medical threshold and needs your sign off.</div></div></div>')
    cols = (f'<div style="display:flex;gap:12px">'
            + column("Onboard", 3, [
                kcard("Univac Cooling Services", "Onboarding pack and site risk questionnaire", "AS", "05/09", "3 subtasks", "prog", "crm"),
                kcard("Mega Bus & Coach", "3 medicals due · first renewal cycle", "AM", "16/09", "0 of 4", "wait", "mco", ai=True),
                kcard("ISE Group (Pty) Ltd", "Confirm medical protocol per job category", "AS", "09/09", "1 of 3", "prog", "man"),
            ], "#BDBDBD")
            + column("Schedule", 4, [
                kcard("Nuvest Chemicals", "4 medicals due · book Sasolburg clinic day", "AM", "16/09", "1 of 4", "prog", "mco"),
                kcard("Gritsol (Pty) Ltd", "4 medicals due · confirm October dates", "AN", "16/09", "0 of 4", "new", "mco", ai=True),
                kcard("Pt Operational Services", "Reserve clinic slots Secunda and Sasolburg", "AN", "08/09", "subtask", "new", "bot", ai=True),
                kcard("Afrirent Auto (Pty) Ltd", "Send booking proposal for 26 medicals", "CB", "09/09", "subtask", "wait", "bot", ai=True),
            ], YELLOW)
            + column("Clinic day", 2, [
                kcard("Tolcon Group (Pty) Ltd.", "Non arrival: 3 cases missed 28/08", "CB", "01/09", "rebook", "over", "mco"),
                kcard("Nuvest Chemicals", "Mobile clinic · Sasolburg · 18 September", "AN", "18/09", "day plan", "prog", "man"),
            ], "#B35A1E")
            + column("Certificates", 3, [
                kcard("CGI Industries", "Medicals: ID pending, case 4471", "CB", "02/09", "1 document", "over", "mco"),
                kcard("Pt Operational Services", "Collect outstanding ID copies (12 cases)", "CB", "10/09", "subtask", "new", "mco"),
                kcard("Tolcon Group (Pty) Ltd.", "Medicals: error resolution · 2 certificates", "AW", "05/09", "2 items", "prog", "mco"),
            ], BLUE)
            + column("Invoice", 2, [
                kcard("Pt Operational Services", "Raise pro forma invoice for 97 medicals", "AW", "12/09", "subtask", "new", "bot", ai=True),
                kcard("ISE Group (Pty) Ltd", "Medicals: admin · PO number outstanding", "AW", "04/09", "1 of 1", "prog", "mco"),
            ], GREEN)
            + column("Renewal", 5, [
                kcard("Pt Operational Services", "97 medicals expiring October 2026", "CB", "16/09", "2 of 5", "prog", "mco"),
                kcard("Afrirent Auto (Pty) Ltd", "26 medicals expiring October 2026", "CB", "16/09", "0 of 4", "wait", "mco", ai=True),
                kcard("Tolcon Group (Pty) Ltd.", "24 medicals expiring October 2026", "CB", "16/09", "0 of 4", "new", "mco"),
                kcard("All clients", "Christmas message · draft and schedule", "GB", "01/12", "campaign", "hold", "bot", ai=True),
            ], RED)
            + "</div>")
    body = f'<div style="flex:1;overflow:hidden;padding:20px 24px;display:flex;flex-direction:column;gap:16px">{head}{loads}{cols}</div>'
    return doc("Team board", shell("Team board", ["Sales Executive desk", "Team board"], body, h=1160))

# =============================================================== 04 CLIENT 360
def client360():
    stages = ["Prospect", "Quote", "Onboard", "Schedule", "Clinic day", "Certificates", "Invoice", "Renewal"]
    cur = 7
    stepper = '<div style="display:flex;align-items:center">'
    for i, s in enumerate(stages):
        done = i < cur; on = i == cur
        circ_bg = RED if on else (INK if done else "#fff")
        circ_bd = RED if on else (INK if done else "#BDBDBD")
        inner = ic("check", 12, "#fff", 3) if done else ('<span style="width:8px;height:8px;border-radius:50%;background:#fff"></span>' if on else "")
        stepper += (f'<div style="display:flex;flex-direction:column;align-items:center;gap:6px;width:110px">'
                    f'<span style="width:24px;height:24px;border-radius:50%;background:{circ_bg};border:2px solid {circ_bd};display:inline-flex;align-items:center;justify-content:center;box-sizing:border-box">{inner}</span>'
                    f'<span style="font-size:11.5px;font-weight:{700 if on else 600};color:{RED_D if on else (INK if done else MUTE)};white-space:nowrap">{s}</span></div>')
        if i < len(stages) - 1:
            stepper += f'<span style="flex:1;height:2px;background:{INK if i < cur-1 else (RED if i == cur-1 else "#D6D6D6")};margin:0 -30px 22px -30px"></span>'
    stepper += "</div>"
    header = card(
        f'<div style="display:flex;align-items:flex-start;gap:16px;margin-bottom:18px">'
        f'<span style="width:48px;height:48px;border-radius:{R_MD};background:{INK};color:#fff;display:inline-flex;align-items:center;justify-content:center;font-family:{HEAD};font-weight:600;font-size:16px">PT</span>'
        f'<div><h1 style="font-size:20px;font-weight:600">Pt Operational Services (Pty) Ltd</h1><div style="font-size:12.5px;color:{MUTE};margin-top:2px">Mining services · Secunda and Sasolburg · 214 employees on medical surveillance · MCO client since 2019</div>'
        f'<div style="display:flex;gap:8px;margin-top:8px;align-items:center">{pill("done","Active")}{stage("Renewal", on=True)}<span style="font-size:12px;color:{INK}">Account owner</span>{av("CB",22)}<span style="font-size:12px;color:{INK}">Celeste Bulpitt</span><span style="font-size:12px;color:{INK};margin-left:6px">Oversight</span>{av("AW",22)}</div></div>'
        f'<div style="margin-left:auto;display:flex;gap:8px">{btn("Log activity","sec","message")}{btn("Open in MCO","sec","external")}{btn("Open in AutoHive CRM","sec","external")}{btn("New task","pri","plus")}</div></div>'
        f'{stepper}', pad="20px 24px")
    stats = ('<div style="display:flex;gap:12px">' + statcard("Medicals due October", "97", "16 September internal deadline")
             + statcard("Open tasks", "6", "1 parent · 5 subtasks") + statcard("Certificates outstanding", "12", "ID copies pending, by case number", "warning")
             + statcard("Last clinic day", "14/04/2026", "0 non arrivals", "success") + statcard("Contract renewal", "31/03/2027", "SLA · annual") + "</div>")
    events = [
        ("03/09 09:31", "GB", "Grouped 5 subtasks under the Medicals Due parent and drafted the booking proposal email for Celeste to sign.", "bot"),
        ("01/09 09:30", "GB", "Ingested MCO task <strong>97 medicals expiring 01/10 to 31/10/2026</strong> through the Supabase sync and allocated it to the account owner.", "mco"),
        ("28/08 15:10", "CB", "Called the HR manager to pre warn about the October renewal wave. Sites confirmed as Secunda and Sasolburg.", "man"),
        ("14/04 17:00", "AN", "Clinic day closed. 88 employees seen, 0 non arrivals, 3 referrals for audiometry follow up recorded in MCO by the OMP.", "man"),
        ("02/04 08:00", "GB", "Pro forma INV-2026-0412 prepared from the confirmed attendance list. Annemarie signed and sent it from AutoHive CRM.", "bot"),
    ]
    tl = f'<div style="display:flex;align-items:center;gap:8px;margin-bottom:12px">{h2("Journey timeline", "every touchpoint from MCO, the agents and the team")}<span style="margin-left:auto;display:flex;gap:6px">{src("mco")}{src("bot")}{src("man")}</span></div>'
    for i, (t, who, txt, s) in enumerate(events):
        last = i == len(events) - 1
        tl += (f'<div style="display:flex;gap:12px"><div style="display:flex;flex-direction:column;align-items:center;width:28px;flex-shrink:0">{av(who,26)}<span style="flex:1;width:1px;background:{"transparent" if last else LINE};margin:4px 0"></span></div>'
               f'<div style="padding-bottom:{"0" if last else "16px"};min-width:0"><div style="display:flex;align-items:center;gap:8px;font-size:11.5px;color:{MUTE}"><span style="font-weight:600;color:{INK}">{PEOPLE[who][0]}</span>·<span>{t}</span>{src(s)}</div>'
               f'<div style="font-size:12.5px;color:{INK};margin-top:3px;line-height:1.5">{txt}</div></div></div>')
    timeline = card(tl, extra="flex:1;min-width:0")
    tasks_card = card(
        f'<div style="display:flex;align-items:center;gap:8px">{h2("Open tasks")}<span style="margin-left:auto;font-size:12px;color:{BLUE};font-weight:600">View all 6</span></div>'
        + "".join(f'<div style="display:flex;align-items:center;gap:10px;padding:8px 0;border-top:1px solid {GREY_L}"><span style="width:16px;height:16px;border-radius:5px;border:1.5px solid #BDBDBD;flex-shrink:0"></span><span style="flex:1;font-size:12.5px;font-weight:{600 if p else 400};min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{t}</span>{pill(k)}<span style="font-size:11.5px;color:{MUTE};width:44px;text-align:right">{d}</span>{av(w,22)}</div>'
                  for t, k, d, w, p in [("97 medicals expiring October 2026", "prog", "16/09", "CB", True), ("Send booking proposal 6 to 10 October", "wait", "04/09", "CB", False), ("Reserve clinic slots Secunda, Sasolburg", "new", "08/09", "AN", False), ("Collect outstanding ID copies (12 cases)", "new", "10/09", "CB", False), ("Raise pro forma invoice", "new", "12/09", "AW", False)]))
    contacts = card(
        h2("Client contacts") + f'<div style="font-size:11.5px;color:{MUTE};margin-top:2px">Names and roles only. Email and phone live in AutoHive CRM (POPIA board rule).</div>'
        + "".join(f'<div style="display:flex;align-items:center;gap:10px;padding:8px 0;border-top:1px solid {GREY_L}"><span style="width:30px;height:30px;border-radius:50%;background:{GREY_L};color:{INK};display:inline-flex;align-items:center;justify-content:center;font-family:{HEAD};font-weight:600;font-size:11px">{i}</span><div style="flex:1"><div style="font-size:12.5px;font-weight:600">{n}</div><div style="font-size:11.5px;color:{MUTE}">{r}</div></div>{btn("Open in CRM","ghost",None,28)}</div>'
                  for i, n, r in [("TN", "Thabo N.", "HR manager · primary"), ("RV", "Riaan v.d. B.", "SHEQ officer · site access"), ("AP", "Accounts payable", "invoices and purchase orders")]))
    nba = (f'<div style="background:{INK};color:#fff;border-radius:{R_MD};padding:16px 20px;display:flex;flex-direction:column;gap:8px">'
           f'<div style="display:flex;align-items:center;gap:8px">{ic("sparkle",16,RED,2)}<h3 style="font-size:13px;font-weight:600;color:#fff">Next best action</h3></div>'
           f'<div style="font-size:12.5px;color:#D6D6D6;line-height:1.55">Sign the booking proposal today. This client has confirmed within 3 working days on the last two cycles, which keeps the 6 to 10 October clinic window realistic and avoids a Medicals Overdue wave in November.</div>'
           f'<div style="display:flex;gap:6px">{btn("Open proposal","pri",None,32)}</div></div>')
    right = f'<div style="width:380px;flex-shrink:0;display:flex;flex-direction:column;gap:12px">{nba}{tasks_card}{contacts}</div>'
    body = f'<div style="flex:1;overflow:hidden;padding:20px 24px;display:flex;flex-direction:column;gap:12px">{header}{stats}<div style="display:flex;gap:12px;flex:1;min-height:0">{timeline}{right}</div></div>'
    return doc("Client 360", shell("Clients", ["Sales Executive desk", "Clients", "Pt Operational Services"], body, h=1140))

# =============================================================== 05 TASK DETAIL
def task_detail():
    def prop(label, value_html):
        return (f'<div style="display:flex;align-items:center;gap:12px;min-height:36px"><span style="width:110px;font-size:12px;color:{MUTE};font-weight:600;flex-shrink:0">{label}</span><div style="display:flex;align-items:center;gap:8px;font-size:13px;min-width:0">{value_html}</div></div>')
    props = card(
        prop("Status", pill("prog"))
        + prop("Priority", f'<span style="display:inline-flex;align-items:center;gap:6px;font-weight:600;color:{RED_D}">{ic("alert",14,RED_D,2)}High</span>')
        + prop("Assigned to", f'{av("CB",24)}Celeste Bulpitt')
        + prop("Signs for", f'{av("AW",24)}Annemarie Wiese, Sales Manager')
        + prop("Due date", f'<span style="display:inline-flex;align-items:center;gap:6px">{ic("calendar",14,MUTE)}16/09/2026</span>')
        + prop("Client", f'<span style="display:inline-flex;align-items:center;gap:6px">{ic("building",14,MUTE)}Pt Operational Services</span>')
        + prop("Journey stage", stage("Renewal", on=True))
        + prop("Task type", "<span>Medicals Due</span>")
        + prop("Source", f'{src("mco")}<span style="font-size:12px;color:{MUTE}">MCO 48213 · synced 01/09 09:30</span>')
        + prop("Module", "Sales")
        + prop("Agent run", '<a href="#">run_2026-09-03_0931</a>')
        + prop("Watchers", f'<span style="display:inline-flex">{av("AN",24)}</span><span style="display:inline-flex;margin-left:-6px">{av("BK",24)}</span>')
        + f'<div style="border-top:1px solid {GREY_L};margin:10px 0"></div>'
        f'<div style="font-size:12px;color:{MUTE};font-weight:600;margin-bottom:6px">Rights on this task</div>'
        f'<div style="display:flex;flex-direction:column;gap:6px;font-size:12px;color:{INK}">'
        f'<div style="display:flex;gap:8px;align-items:center">{ic("check",13,GREEN,3)}Celeste edits subtasks and logs activity</div>'
        f'<div style="display:flex;gap:8px;align-items:center">{ic("check",13,GREEN,3)}Annemarie reassigns, signs and closes</div>'
        f'<div style="display:flex;gap:8px;align-items:center">{ic("lock",13,MUTE,2)}Grok proposes, never sends without a signature</div></div>',
        pad="16px 18px", extra="width:320px;flex-shrink:0;box-sizing:border-box")
    subs = [
        ("Confirm employee list and sites with the HR contact", "done", "CB", "03/09", "HR confirmed 97 cases · Secunda 61, Sasolburg 36"),
        ("Send booking proposal for 6 to 10 October", "wait", "CB", "04/09", "Email drafted by Grok · needs your signature before it sends"),
        ("Reserve mobile clinic slots at Secunda and Sasolburg", "new", "AN", "08/09", "Depends on proposal acceptance"),
        ("Collect outstanding ID copies (12 cases pending)", "new", "CB", "10/09", "MCO Medicals: ID Pending closes automatically when documents arrive"),
        ("Raise pro forma invoice for 97 medicals", "new", "AW", "12/09", "Grok prefills from the confirmed list, Annemarie signs"),
    ]
    sub_html = ""
    for t, k, w, d, note in subs:
        chk = f'<span style="width:18px;height:18px;border-radius:5px;border:1.5px solid {"transparent" if k=="done" else "#BDBDBD"};background:{GREEN if k=="done" else "#fff"};display:inline-flex;align-items:center;justify-content:center;flex-shrink:0">{ic("check",12,"#fff",3) if k=="done" else ""}</span>'
        sub_html += (f'<div style="display:flex;align-items:flex-start;gap:12px;padding:10px 0;border-top:1px solid {GREY_L}">{chk}'
                     f'<div style="flex:1;min-width:0"><div style="font-size:13px;font-weight:600;{"text-decoration:line-through;color:#8A8A8A" if k=="done" else ""}">{t}</div><div style="font-size:11.5px;color:{MUTE};margin-top:2px">{note}</div></div>'
                     f'{pill(k)}<span style="font-size:12px;color:{INK};width:44px;text-align:right">{d}</span>{av(w,24)}{ic("more",16,MUTE)}</div>')
    subs_card = card(
        f'<div style="display:flex;align-items:center;gap:10px;margin-bottom:8px">{h2("Subtasks", "2 of 5 ticked")}'
        f'<div style="flex:1;max-width:200px;height:6px;border-radius:3px;background:{GREY_L};overflow:hidden"><span style="display:block;width:40%;height:100%;background:{GREEN}"></span></div>'
        f'<span style="margin-left:auto;display:flex;align-items:center;gap:6px;color:{BLUE};font-weight:600;font-size:12.5px">{ic("plus",14,BLUE,2)}Add subtask</span></div>{sub_html}'
        f'<div style="font-size:11.5px;color:{MUTE};margin-top:8px">Tickbox principle: every leaf is a single tick. Grok proposed this breakdown, Celeste accepted it on 02/09.</div>')
    desc = card(
        f'<div style="display:flex;align-items:center;gap:8px">{h2("Description")}<span style="display:inline-flex;align-items:center;gap:4px;font-size:11px;font-weight:700;color:{RED_D}">{ic("sparkle",12,RED_D,2)}summarised by Grok from MCO</span></div>'
        f'<p style="margin:8px 0 0;font-size:13px;line-height:1.6;color:{INK}">MyClinicOnline reports 97 periodic medicals expiring between 1 and 31 October 2026 for Pt Operational Services. 61 cases are based at Secunda and 36 at Sasolburg. Last year the client used two mobile clinic days per site. Recommended plan: propose 6 to 10 October, secure slots once accepted, chase 12 outstanding ID copies in parallel and raise the pro forma before the clinic days so the OMP can release certificates without delay.</p>'
        f'<div style="display:flex;gap:8px;margin-top:10px">' + "".join(f'<span style="display:inline-flex;align-items:center;gap:6px;height:28px;padding:0 10px;border:1px solid {LINE};border-radius:{R_SM};font-size:12px;color:{INK}">{ic("file",13,MUTE)}{n}</span>' for n in ["MCO_medicals_due_oct2026.xlsx", "Booking_proposal_draft.docx"]) + '</div>')
    acts = [
        ("GB", "03/09 09:31", "Drafted <strong>Booking proposal · 6 to 10 October</strong> and attached it to subtask 2. Waiting for Celeste's signature.", "bot"),
        ("AW", "02/09 16:40", "Confirmed the agent allocation. Keep Annemarie on invoicing so the PO chase starts early.", "man"),
        ("CB", "02/09 11:05", "Ticked <em>Confirm employee list</em>. HR confirmed 97 cases, split 61 and 36.", "man"),
        ("GB", "01/09 09:30", "Created this task from MCO Medicals Due 48213 and allocated it to the account owner under rule R-02.", "mco"),
    ]
    act_html = "".join(f'<div style="display:flex;gap:12px;padding:10px 0;border-top:1px solid {GREY_L}">{av(w,26)}<div style="min-width:0"><div style="display:flex;align-items:center;gap:8px;font-size:11.5px;color:{MUTE}"><span style="font-weight:600;color:{INK}">{PEOPLE[w][0]}</span>·<span>{t}</span>{src(s)}</div><div style="font-size:12.5px;line-height:1.5;margin-top:2px">{x}</div></div></div>' for w, t, x, s in acts)
    activity = card(
        f'<div style="display:flex;gap:4px;border-bottom:1px solid {LINE};margin-bottom:4px">' + "".join(f'<div style="padding:6px 10px;font-size:12.5px;font-weight:600;color:{INK if on else MUTE};border-bottom:2px solid {RED if on else "transparent"};margin-bottom:-1px">{t}</div>' for t, on in [("Activity", True), ("Comments 3", False), ("Agent log", False), ("Emails 1", False)]) + '</div>'
        f'{act_html}'
        f'<div style="display:flex;gap:10px;margin-top:12px">{av("BK",28)}<div style="flex:1;height:40px;border:1px solid {LINE};border-radius:{R_SM};display:flex;align-items:center;padding:0 12px;color:{MUTE};font-size:12.5px">Write a comment or mention a colleague</div></div>')
    approval = (f'<div style="background:{RED_SOFT};border:1px solid #F3C4C6;border-radius:{R_MD};padding:12px 16px;display:flex;align-items:center;gap:12px">'
                f'<span style="width:32px;height:32px;border-radius:{R_SM};background:{RED};display:inline-flex;align-items:center;justify-content:center">{ic("sparkle",16,"#fff",2)}</span>'
                f'<div style="flex:1"><div style="font-size:13px;font-weight:600">Grok drafted the booking proposal. A named human signs: Celeste Bulpitt.</div><div style="font-size:12px;color:{INK}">Subtask 2 · email preview attached · counts and dates only · sending is blocked until signed</div></div>'
                f'{btn("Preview email","sec")}{btn("Request changes","sec")}{btn("Approve and send","pri","check")}</div>')
    titlebar = (f'<div style="display:flex;align-items:flex-start;gap:16px">'
                f'<div style="min-width:0"><div style="display:flex;align-items:center;gap:8px;font-size:12px;color:{MUTE}"><span>Parent task</span>·<span>TSK-2026-1187</span>·{src("mco")}</div>'
                f'<h1 style="font-size:21px;font-weight:600;margin-top:4px;line-height:1.3">97 medicals expiring for Pt Operational Services between 01/10/2026 and 31/10/2026</h1></div>'
                f'<div style="margin-left:auto;display:flex;gap:8px;flex-shrink:0">{btn("Mark complete","sec","check")}{btn("Reassign","sec","users")}{btn("Open in MCO","sec","external")}{ic("more",18,MUTE)}</div></div>')
    left = f'<div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:12px">{titlebar}{approval}{subs_card}{desc}{activity}</div>'
    body = f'<div style="flex:1;overflow:hidden;padding:20px 24px;display:flex;gap:16px">{left}{props}</div>'
    return doc("Task detail", shell("My work", ["Sales Executive desk", "My work", "Pt Operational Services", "TSK-2026-1187"], body, h=1330))

# =============================================================== 06 SALES AUTOMATIONS
def automations():
    head = page_head("Sales automations", "Grok agents read MyClinicOnline through Supabase, create and allocate portal tasks, and hand anything sensitive to a named person",
                     btn("Pause all agents", "sec", "pause") + btn("Run sync now", "sec", "refresh") + btn("New rule", "pri", "plus"))
    def node(icon, title, sub, dark=False):
        bg = INK if dark else CARD; fg = "#fff" if dark else INK; sc = "#D6D6D6" if dark else MUTE
        return (f'<div style="flex:1;min-width:0;background:{bg};border:1px solid {INK if dark else LINE};border-radius:{R_MD};box-shadow:{SHADOW};padding:14px 16px;display:flex;gap:12px;align-items:center">'
                f'<span style="width:36px;height:36px;border-radius:{R_SM};background:{"#333" if dark else RED_T};display:inline-flex;align-items:center;justify-content:center;flex-shrink:0">{ic(icon,18,RED,2)}</span>'
                f'<div style="min-width:0"><div style="font-family:{HEAD};font-weight:600;font-size:13px;color:{fg}">{title}</div><div style="font-size:11.5px;color:{sc};line-height:1.45">{sub}</div></div></div>')
    arrow = f'<span style="display:inline-flex;align-items:center;flex-shrink:0">{ic("arrow",18,"#BDBDBD",2)}</span>'
    pipeline = ('<div style="display:flex;align-items:stretch;gap:10px">'
                + node("monitor", "MyClinicOnline", "Task types: Medicals Due, Medicals Overdue, Admin, Documents, Error Resolution, ID Pending, Non Arrival, General, Other") + arrow
                + node("db", "Supabase", f"mco_tasks table · sync every 15 minutes {confirm('CONFIRM')} · 1,284 rows · last 09:30") + arrow
                + node("bot", "Grok agents", "Classify · group by client · draft subtasks · propose allocation", dark=True) + arrow
                + node("layers", "Portal tasks", "Parent and subtasks on the client journey, one Task table") + arrow
                + node("users", "People", "Consultant works it · Sales Manager signs · Director audits")
                + "</div>")
    RG = "52px minmax(0,1fr) minmax(0,2.1fr) 130px 70px 44px"
    def rule(rid, trigger, agent, action, owner, runs, on=True, guard=""):
        tog = (f'<span style="width:34px;height:20px;border-radius:10px;background:{GREEN if on else "#BDBDBD"};position:relative;display:inline-block">'
               f'<span style="position:absolute;top:2px;{"right:2px" if on else "left:2px"};width:16px;height:16px;border-radius:50%;background:#fff"></span></span>')
        g = f'<div style="display:inline-flex;align-items:center;gap:5px;font-size:11px;color:{BLUE};font-weight:600;margin-top:3px">{ic("shield",12,BLUE,2)}{guard}</div>' if guard else ""
        return (f'<div style="display:grid;grid-template-columns:{RG};gap:12px;align-items:center;padding:12px 16px;border-top:1px solid {GREY_L}">'
                f'<span style="font-family:{HEAD};font-weight:600;font-size:12px;color:{INK}">{rid}</span>'
                f'<div style="font-size:12.5px;font-weight:600">{trigger}</div>'
                f'<div><div style="font-size:12.5px;color:{INK}"><strong>{agent}:</strong> {action}</div>{g}</div>'
                f'<div style="display:flex;align-items:center;gap:6px;font-size:12px">{av(owner,22)}{PEOPLE[owner][0].split()[0]}</div>'
                f'<span style="font-size:12px;color:{MUTE}">{runs}</span><div style="display:flex;justify-content:flex-end">{tog}</div></div>')
    rules = (f'<div style="flex:1;min-width:0;background:{CARD};border:1px solid {LINE};border-radius:{R_MD};box-shadow:{SHADOW};overflow:hidden">'
             f'<div style="display:flex;align-items:center;gap:8px;padding:14px 16px">{h2("Allocation and journey rules", "7 active · every rule has a human owner, a last fired time and a kill switch")}</div>'
             f'<div style="display:grid;grid-template-columns:{RG};gap:12px;padding:0 16px 8px;font-size:11px;font-weight:700;color:{MUTE};text-transform:uppercase;letter-spacing:.05em"><span>Rule</span><span>When</span><span>Agent and action</span><span>Owner</span><span>Runs 30d</span><span style="text-align:right">On</span></div>'
             + rule("R-01", "New MCO task of any type", "Documentation agent", "Create a portal parent task, link the MCO id, place it on the journey stage mapped from the task type", "AW", "312")
             + rule("R-02", "Medicals Due · new", "Booking agent, 30 to 90 days", "Allocate to the client's account owner and draft renewal subtasks (confirm list, propose dates, reserve slots, ID copies, pro forma)", "AW", "118", guard=f"Over 20 medicals: Sales Manager signs before allocation {confirm('CONFIRM threshold')}")
             + rule("R-03", "Medicals Overdue · new", "Follow up agent", "Escalate to account owner and Sales Manager, draft the recovery call script, set priority High", "AW", "27", guard="Never contacts the client directly")
             + rule("R-04", "Non arrival logged", "Booking agent, 30 to 90 days", "Create the rebooking subtask under the clinic day parent and notify the consultant the same day", "AN", "14")
             + rule("R-05", "Medicals: ID Pending or Documents", "Documentation agent", "Draft the document request, attach the MCO case list, close when MCO shows received", "CB", "63")
             + rule("R-06", "Any subtask drafts an outbound email", "Follow up agent", "Hold in Awaiting approval until the assigned person or their Sales Manager signs", "AW", "41", guard="Hard stop · POPIA: no employee name or medical outcome in an email body")
             + rule("R-07", "Consultant load above 12 open parents", "Allocation rule", "Standard task to the consultant with the largest book gap, high profile client to a senior with room, Sales Manager confirms", "AW", "9")
             + "</div>")
    runs = [("09:30 today", "Sync and allocate", "10 ingested", "10 created", "8 allocated", "2 need a signature", "done"),
            ("06:01 today", "Sync", "1 ingested", "1 created", "1 allocated", "0", "done"),
            ("Yesterday 17:15", "Overdue sweep", "3 flagged", "3 escalated", "3 allocated", "0", "done"),
            ("Yesterday 09:30", "Sync and allocate", "6 ingested", "6 created", "6 allocated", "1 need a signature", "done"),
            ("01/09 09:30", "Sync and allocate", "10 ingested", "9 created", "9 allocated", "1 error", "over")]
    run_html = "".join(f'<div style="display:flex;flex-direction:column;gap:3px;padding:9px 0;border-top:1px solid {GREY_L};font-size:12px"><div style="display:flex;align-items:center;gap:8px"><span style="font-weight:600">{k}</span><span style="color:{MUTE}">{t}</span><span style="margin-left:auto">{pill(s, "OK" if s=="done" else "1 error")}</span></div><div style="color:{MUTE}">{a} · {b} · {c} · {d}</div></div>' for t, k, a, b, c, d, s in runs)
    history = (f'<div style="width:400px;flex-shrink:0;display:flex;flex-direction:column;gap:12px">'
               + card(f'<div style="display:flex;align-items:center;gap:8px;margin-bottom:6px">{h2("Agent runs")}<span style="margin-left:auto;font-size:12px;color:{BLUE};font-weight:600">Full log</span></div>{run_html}', pad="16px")
               + card(h2("Guardrails") + '<div style="display:flex;flex-direction:column;gap:10px;margin-top:10px">'
                      + "".join(f'<div style="display:flex;gap:10px;align-items:flex-start"><span style="width:22px;height:22px;border-radius:{R_SM};background:{RED_T};display:inline-flex;align-items:center;justify-content:center;flex-shrink:0">{ic(i,13,RED,2)}</span><div style="font-size:12.5px;color:{INK};line-height:1.45">{t}</div></div>'
                                for i, t in [("lock", "AI drafts, a named human signs. No agent sends, pays, files or advances a gated step."),
                                             ("shield", "POPIA: employee names and medical outcomes stay inside MCO and the Person record. Boards and emails carry counts, dates and case numbers only."),
                                             ("users", "Every allocation follows the parent and child structure: consultant owns, Sales Manager signs, Franchise Director audits."),
                                             ("refresh", "Every agent action is logged with input reference, output, model and the person who accepted or rejected it, and is reversible for 24 hours.")])
                      + "</div>", pad="16px")
               + "</div>")
    body = f'<div style="flex:1;overflow:hidden;padding:20px 24px;display:flex;flex-direction:column;gap:14px">{head}{pipeline}<div style="display:flex;gap:12px;flex:1;min-height:0">{rules}{history}</div></div>'
    return doc("Sales automations", shell("Sales automations", ["Sales Executive desk", "Sales automations"], body, h=1240))

# =============================================================== 07 ROLES AND PERMISSIONS
def permissions():
    head = page_head("Roles and permissions", "Parent and child structure per employee · management oversight through role rights · agents are a role with the fewest rights",
                     btn("Audit log", "sec", "file") + btn("Invite person", "pri", "plus"))
    def person(code, role, n, depth, kids=""):
        name, col = PEOPLE[code]
        conn = "" if depth == 0 else '<span style="width:14px;height:14px;border-left:1px solid #CFCFCF;border-bottom:1px solid #CFCFCF;border-radius:0 0 0 4px;margin:-10px 0 0 -22px;flex-shrink:0"></span>'
        return (f'<div style="display:flex;flex-direction:column;gap:6px;margin-left:{depth*28}px">'
                f'<div style="display:flex;align-items:center;gap:10px;background:{CARD};border:1px solid {LINE};border-radius:{R_SM};padding:8px 12px">{conn}'
                f'{av(code,28)}<div style="min-width:0"><div style="font-size:12.5px;font-weight:600">{name}</div><div style="font-size:11px;color:{MUTE}">{role}</div></div>'
                f'<span style="margin-left:auto;font-size:11.5px;color:{INK}">{n}</span>{ic("more",16,MUTE)}</div>{kids}</div>')
    tree = (f'<div style="width:420px;flex-shrink:0;display:flex;flex-direction:column;gap:12px">'
            + card(f'<div style="display:flex;align-items:center;gap:8px;margin-bottom:10px">{h2("Sales module", "who oversees whom")}</div>'
                   + person("BK", "Franchise Director · oversees all modules", "sees 6 people", 0,
                            person("AW", "Sales Manager · signs agent allocations", "4 reports · 9 open", 1,
                                   person("CB", "Senior Sales Consultant · key accounts", "14 open · 6 clients", 2)
                                   + person("AN", "Sales Consultant · Mpumalanga and Free State", "11 open · 5 clients", 2)
                                   + person("AS", "Sales Consultant · onboarding", "8 open · 4 clients", 2)
                                   + person("AM", "Junior Sales Consultant · shadowing Celeste", "6 open · 3 clients", 2))
                            + person("GB", "Grok agent · service account", "7 rules · proposes only", 1)), pad="16px")
            + card(h2("How rights flow") + f'<div style="font-size:12.5px;color:{INK};line-height:1.55;margin-top:8px">A person sees their own tasks plus everything owned by people below them in the tree. Signing rights sit one level above the doer. The Franchise Director sees everything, and every action is written to the audit log. The Information Officer sees the audit log and POPIA requests, not the sales book.</div>', pad="16px")
            + '</div>')
    roles = ["Franchise Director", "Sales Manager", "Sales Consultant", "Information Officer", "Grok agent"]
    rights = [
        ("View own tasks", [1, 1, 1, 0, 1]),
        ("View team tasks", [1, 1, 0, 0, 1]),
        ("View all modules", [1, 0, 0, 0, 0]),
        ("Create and edit tasks", [1, 1, 1, 0, 2]),
        ("Reassign within team", [1, 1, 0, 0, 2]),
        ("Sign agent allocation", [1, 1, 0, 0, 0]),
        ("Sign outbound client email", [1, 1, 1, 0, 0]),
        ("Edit automation rules and kill switch", [1, 1, 0, 0, 0]),
        ("View client financials and invoices", [1, 1, 0, 0, 0]),
        ("Export Excel reports (logged to audit)", [1, 1, 1, 0, 0]),
        ("View employee medical outcomes", [0, 0, 0, 0, 0]),
        ("POPIA data subject requests", [1, 0, 0, 1, 0]),
        ("Access audit log", [1, 1, 0, 1, 0]),
    ]
    def cell(v):
        if v == 1: return f'<span style="width:24px;height:24px;border-radius:{R_SM};background:{GREEN_T};display:inline-flex;align-items:center;justify-content:center">{ic("check",14,GREEN,3)}</span>'
        if v == 2: return f'<span style="display:inline-flex;align-items:center;height:22px;padding:0 8px;border-radius:{R_SM};background:{RED_T};color:{RED_D};font-size:10.5px;font-weight:700">propose</span>'
        return f'<span style="width:24px;height:24px;border-radius:{R_SM};background:{GREY_L};display:inline-flex;align-items:center;justify-content:center">{ic("x",12,"#BDBDBD",2)}</span>'
    MG = "minmax(0,1.6fr) repeat(5, minmax(0,1fr))"
    matrix = (f'<div style="flex:1;min-width:0;background:{CARD};border:1px solid {LINE};border-radius:{R_MD};box-shadow:{SHADOW};overflow:hidden">'
              f'<div style="display:flex;align-items:center;gap:8px;padding:14px 16px">{h2("Role rights", "a person inherits the role of their position in the tree, the Director can grant exceptions per client")}<span style="margin-left:auto;font-size:12px;color:{BLUE};font-weight:600">Edit roles</span></div>'
              f'<div style="display:grid;grid-template-columns:{MG};gap:8px;padding:8px 16px;background:#FAFAFA;border-top:1px solid {LINE};border-bottom:1px solid {LINE};font-size:11px;font-weight:700;color:{MUTE};text-transform:uppercase;letter-spacing:.05em"><span>Right</span>' + "".join(f'<span style="text-align:center">{r}</span>' for r in roles) + '</div>'
              + "".join(f'<div style="display:grid;grid-template-columns:{MG};gap:8px;align-items:center;padding:8px 16px;border-top:1px solid {GREY_L}"><span style="font-size:12.5px;font-weight:{600 if i in (5,6,10) else 400}">{r}</span>' + "".join(f'<span style="display:flex;justify-content:center">{cell(v)}</span>' for v in vals) + '</div>' for i, (r, vals) in enumerate(rights))
              + f'<div style="padding:10px 16px;border-top:1px solid {GREY_L};font-size:11.5px;color:{MUTE}">Medical outcomes never enter the sales app. Clinical records stay in MyClinicOnline and certificates are issued by the OMP only (HPCSA).</div>'
              + f'<div style="padding:12px 16px;border-top:1px solid {LINE};display:flex;gap:16px;font-size:11.5px;color:{MUTE};align-items:center">{cell(1)} allowed {cell(2)} may propose, a person confirms {cell(0)} not allowed</div></div>')
    body = f'<div style="flex:1;overflow:hidden;padding:20px 24px;display:flex;flex-direction:column;gap:14px">{head}<div style="display:flex;gap:12px;flex:1;min-height:0">{tree}{matrix}</div></div>'
    return doc("Roles and permissions", shell("Roles and permissions", ["Sales Executive desk", "Roles and permissions"], body, h=1060))

# =============================================================== 08 STATES
def states():
    """Empty, loading, error, forbidden and package off states required by the franchise SOP section 3.1."""
    def state_card(title, who, inner):
        return (f'<div style="display:flex;flex-direction:column;gap:8px"><div style="display:flex;align-items:baseline;gap:8px"><span style="font-family:{HEAD};font-weight:600;font-size:13px">{title}</span><span style="font-size:11.5px;color:{MUTE}">{who}</span></div>'
                f'<div style="background:{CARD};border:1px solid {LINE};border-radius:{R_MD};box-shadow:{SHADOW};height:300px;box-sizing:border-box;display:flex;align-items:center;justify-content:center;padding:24px">{inner}</div></div>')
    def centre(icon, title, text, action=None, tone=INK):
        a = f'<div style="margin-top:6px">{action}</div>' if action else ""
        return (f'<div style="display:flex;flex-direction:column;align-items:center;text-align:center;gap:8px;max-width:360px">'
                f'<span style="width:44px;height:44px;border-radius:{R_MD};background:{GREY_L};display:inline-flex;align-items:center;justify-content:center">{ic(icon,22,tone,1.75)}</span>'
                f'<div style="font-family:{HEAD};font-weight:600;font-size:15px;color:{INK}">{title}</div><div style="font-size:13px;color:{MUTE};line-height:1.55">{text}</div>{a}</div>')
    skeleton = ('<div style="width:100%;display:flex;flex-direction:column;gap:12px">' + "".join(
        f'<div style="display:flex;gap:12px;align-items:center"><span style="width:18px;height:18px;border-radius:5px;background:{GREY_L}"></span><span style="flex:1;height:12px;border-radius:6px;background:{GREY_L};max-width:{w}%"></span><span style="width:80px;height:22px;border-radius:999px;background:{GREY_L}"></span><span style="width:26px;height:26px;border-radius:50%;background:{GREY_L}"></span></div>'
        for w in [70, 55, 62, 48, 66]) + f'<div style="font-size:12px;color:{MUTE};text-align:center;margin-top:8px">Reading the 09:30 sync from Supabase</div></div>')
    error = (f'<div style="width:100%;display:flex;flex-direction:column;gap:12px">'
             f'<div style="background:{RED_T};border:1px solid #F3C4C6;border-radius:{R_SM};padding:12px 14px;display:flex;gap:10px;align-items:flex-start">{ic("alert",18,RED_D,2)}<div><div style="font-size:13px;font-weight:600;color:{RED_D}">MCO sync failed at 09:30</div><div style="font-size:12.5px;color:{INK};margin-top:2px">Supabase could not reach MyClinicOnline. Tasks shown are from 06:01. No agent ran and nothing was allocated. The Sales Manager has been notified.</div><div style="display:flex;gap:6px;margin-top:8px">{btn("Retry sync","pri",None,32)}{btn("View error log","sec",None,32)}</div></div></div>'
             f'<div style="font-size:12px;color:{MUTE}">Rule: red is used for accent, overdue and failure only.</div></div>')
    head = page_head("Screen states", "Every screen ships with empty, loading, error, forbidden and package off states (franchise SOP 3.1). Copy is the shipped copy.", "")
    grid = ('<div style="display:grid;grid-template-columns:repeat(3, minmax(0,1fr));gap:20px">'
            + state_card("Empty · My work", "consultant with nothing due",
                         centre("check", "Nothing due today", "There are no results for the selected filters. The next MCO sync runs at 09:45. Tasks from clients you do not own are not in this list, which is correct.", btn("Add a task", "sec", "plus", 36), GREEN))
            + state_card("Empty · Team board", "Sales Manager, CNC owned only",
                         centre("board", "No CNC owned leads this week", "Franchisees on Independent Sales are not in this board. That is correct.", btn("View allocation rules", "ghost", None, 36)))
            + state_card("Loading", "any list", skeleton)
            + state_card("Error", "sync failure banner", error)
            + state_card("Forbidden", "wrong tenant", centre("lock", "This book is not in your tenant", "You are signed in to Care Net Consultants head office. The task you opened belongs to a franchisee tenant. Ask the Franchise Director for a mentorship grant if you need to see it.", btn("Back to my work", "sec", None, 36)))
            + state_card("Package off", "franchisee without the module", centre("layers", "Sales automations are not on this pack", "Grok agents and the allocation queue are part of the Independent Sales and Full packages. Use Care Net Consultants Sales, or add a seat.", btn("Compare packages", "pri", None, 36)))
            + "</div>")
    body = f'<div style="flex:1;overflow:hidden;padding:20px 24px;display:flex;flex-direction:column;gap:16px">{head}{grid}</div>'
    return doc("Screen states", shell("My work", ["Sales Executive desk", "Screen states"], body, h=900))

# =============================================================== files + canvas
write("Main.dc.html", my_work())
write("Inbox.dc.html", inbox())
write("TeamBoard.dc.html", team_board())
write("ClientJourney.dc.html", client360())
write("TaskDetail.dc.html", task_detail())
write("Automations.dc.html", automations())
write("Permissions.dc.html", permissions())
write("States.dc.html", states())

GAP_X = 1440 + 120
ROW2 = 1240 + 200
ROW3 = ROW2 + 1330 + 200
canvas = {
    "artboards": [
        {"file": "Main.dc.html", "title": "01 · My work (Sales Consultant)", "x": 0, "y": 0, "w": 1440, "h": 1240},
        {"file": "Inbox.dc.html", "title": "02 · Inbox (Franchise Director signatures)", "x": GAP_X, "y": 0, "w": 1440, "h": 1000},
        {"file": "TeamBoard.dc.html", "title": "03 · Team board (Sales Manager)", "x": GAP_X * 2, "y": 0, "w": 1440, "h": 1160},
        {"file": "ClientJourney.dc.html", "title": "04 · Client 360 · journey", "x": 0, "y": ROW2, "w": 1440, "h": 1140},
        {"file": "TaskDetail.dc.html", "title": "05 · Task detail · parent and subtasks", "x": GAP_X, "y": ROW2, "w": 1440, "h": 1330},
        {"file": "Automations.dc.html", "title": "06 · Sales automations · Grok agents", "x": GAP_X * 2, "y": ROW2, "w": 1440, "h": 1240},
        {"file": "Permissions.dc.html", "title": "07 · Roles and permissions", "x": 0, "y": ROW3, "w": 1440, "h": 1060},
        {"file": "States.dc.html", "title": "08 · Screen states (empty, loading, error, forbidden, package off)", "x": GAP_X, "y": ROW3, "w": 1440, "h": 900},
    ],
    "annotations": [
        {"id": "brief", "x": 0, "y": -280, "w": 520,
         "text": "Care Net AI tasks module · Sales first\n\nMyClinicOnline tasks land in Supabase, Grok agents read them, create one parent task per client, draft subtasks along the client journey and propose who does the work. AI drafts, a named human signs. Managers oversee through role rights.\n\nJourney stages used everywhere: Prospect · Quote · Onboard · Schedule · Clinic day · Certificates · Invoice · Renewal."},
        {"id": "matched", "x": 600, "y": -280, "w": 520,
         "text": "Matched to the CNC Sales platform handoff\nShell: Client Portal AppShell (216px white sidebar, 64px top bar, StatCard 104px, attribution footer). Tokens: design/tokens (red #ED1B24, charcoal #1E1E1E, greys #787878 / #F0F0F0 / #E2E2E2, blue links, green success, yellow warning). Type: Montserrat 600 headings, Open Sans body. Radii 6 / 10 / 14.\nRules applied: British English, sentence case, no dash punctuation, AutoHive CRM only, [CONFIRM] on unconfirmed values, mock data labelled, no contact email or phone on boards, cases by number not worker name, medical outcomes never in the sales app."},
        {"id": "next", "x": 1200, "y": -280, "w": 480,
         "text": "Open questions for the build\n· 20 medical threshold for Sales Manager sign off [CONFIRM].\n· MCO task type to journey stage mapping (draft on screen 06).\n· Sync interval, default 15 minutes [CONFIRM].\n· May Grok close portal tasks when MCO marks them Completed, or always ask?\n· Attribution pill on CNC screens [CONFIRM per licence tier].\n· Team lead layer: needed now or when the team grows?"},
    ],
    "launch": {"view": "canvas"},
}
with open(os.path.join(OUT, "canvas.json"), "w") as f:
    json.dump(canvas, f, indent=2)
print("wrote canvas.json")
