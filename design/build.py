#!/usr/bin/env python3
"""Generates the Claude Design artboards (*.dc.html) for the Care Net
AI Tasks Management portal. Run: python3 design/build.py
Working files are written next to this script."""
import os, json

OUT = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- brand tokens
RED = "#ED1B24"; RED_D = "#B71219"; RED_L = "#FFEEEF"
INK = "#1F1F1F"; INK2 = "#4A4A4A"; MUTE = "#7A7A7A"; LINE = "#E6E6E4"; LINE2 = "#DCDCDA"
GROUND = "#F5F5F3"; PANEL = "#FFFFFF"
GREEN = "#007703"; BLUE = "#001489"; YELLOW = "#FFB81C"; PURPLE = "#5C367D"; TEAL = "#009688"; ORANGE = "#D16621"

PEOPLE = {
    "CB": ("Celeste Bulpitt", "#33578C"),
    "BK": ("Barteldt Kruger", "#171717"),
    "AW": ("Annemarie Wiese", PURPLE),
    "AN": ("Asandiswa Ntsali", GREEN),
    "AM": ("Asekhona Magwashu", ORANGE),
    "AS": ("Asivhanga More", TEAL),
    "GB": ("Grok bot", RED),
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
    "list": '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
    "layers": '<path d="m12 2 10 5-10 5L2 7z"/><path d="m2 12 10 5 10-5"/><path d="m2 17 10 5 10-5"/>',
    "x": '<path d="M18 6 6 18M6 6l12 12"/>',
    "pause": '<path d="M8 5v14M16 5v14"/>',
    "monitor": '<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8M12 17v4"/>',
    "phone": '<path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8.1 9.7a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.8 2z"/>',
}

def ic(name, size=18, color="currentColor", sw=1.75, extra=""):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{color}" '
            f'stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" {extra}>{ICONS[name]}</svg>')

def av(code, size=28):
    name, col = PEOPLE[code]
    fs = 11 if size >= 28 else 9
    return (f'<span title="{name}" style="width:{size}px;height:{size}px;border-radius:50%;background:{col};color:#fff;'
            f'display:inline-flex;align-items:center;justify-content:center;font-family:Montserrat,Arial,sans-serif;'
            f'font-weight:600;font-size:{fs}px;flex-shrink:0">{code if code!="GB" else ic("bot",14,"#fff",2)}</span>')

PILL = {
    "new":  ("#FFF2D6", "#7A5200", "New"),
    "prog": ("#E3E7F5", BLUE, "In progress"),
    "done": ("#DDF1DD", "#0B5A0E", "Completed"),
    "over": ("#FFE5E6", RED_D, "Overdue"),
    "wait": ("#EFE8F5", PURPLE, "Awaiting approval"),
    "hold": ("#EEEEEC", "#4A4A4A", "On hold"),
}
def pill(kind, text=None):
    bg, fg, label = PILL[kind]
    return (f'<span style="display:inline-flex;align-items:center;height:22px;padding:0 9px;border-radius:999px;'
            f'background:{bg};color:{fg};font-size:11.5px;font-weight:600;white-space:nowrap">{text or label}</span>')

SRC = {
    "mco": ("MCO", BLUE, "#C9D0EA", "#F3F5FB"),
    "bot": ("Grok", RED_D, "#F3C4C6", "#FFF5F5"),
    "man": ("Manual", "#5A5A5A", "#DCDCDA", "#FAFAF9"),
    "ghl": ("CRM", "#7A5200", "#F1DDA8", "#FFF8E6"),
}
def src(kind):
    label, fg, bd, bg = SRC[kind]
    return (f'<span style="display:inline-flex;align-items:center;height:20px;padding:0 7px;border-radius:5px;'
            f'border:1px solid {bd};background:{bg};color:{fg};font-size:10.5px;font-weight:700;letter-spacing:.02em">{label}</span>')

def stage(text, on=False, done=False):
    if on:
        st = f"background:{RED};color:#fff;border:1px solid {RED}"
    elif done:
        st = f"background:#F0F0EE;color:{INK2};border:1px solid #E1E1DF"
    else:
        st = f"background:#fff;color:{MUTE};border:1px dashed #D3D3D0"
    return (f'<span style="display:inline-flex;align-items:center;height:22px;padding:0 9px;border-radius:6px;'
            f'font-size:11px;font-weight:600;white-space:nowrap;{st}">{text}</span>')

def btn(text, kind="sec", icon=None, h=36):
    styles = {
        "pri": f"background:{RED};color:#fff;border:1px solid {RED}",
        "sec": f"background:#fff;color:{INK};border:1px solid {LINE2}",
        "ghost": f"background:transparent;color:{RED_D};border:1px solid transparent;padding:0 6px",
        "dark": f"background:{INK};color:#fff;border:1px solid {INK}",
    }[kind]
    i = ic(icon, 16, "currentColor", 2) if icon else ""
    return (f'<button style="height:{h}px;padding:0 14px;border-radius:8px;font-family:\'Open Sans\',Arial,sans-serif;'
            f'font-weight:600;font-size:13px;display:inline-flex;align-items:center;gap:8px;cursor:pointer;{styles}">{i}{text}</button>')

def field(label, value, w=200, icon="chevdown", placeholder=False):
    col = MUTE if placeholder else INK
    return (f'<div style="position:relative;width:{w}px;height:40px;border:1px solid {LINE2};border-radius:8px;background:#fff;'
            f'display:flex;align-items:center;justify-content:space-between;padding:0 12px;box-sizing:border-box">'
            f'<span style="position:absolute;top:-8px;left:10px;background:#fff;padding:0 4px;font-size:10.5px;color:{MUTE}">{label}</span>'
            f'<span style="font-size:13px;color:{col};white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{value}</span>{ic(icon,16,MUTE,2)}</div>')

def kpi(label, value, sub, tone=INK):
    return (f'<div style="flex:1;background:#fff;border:1px solid {LINE};border-radius:12px;padding:14px 16px;display:flex;flex-direction:column;gap:4px">'
            f'<div style="font-size:11.5px;color:{MUTE};font-weight:600;text-transform:uppercase;letter-spacing:.04em">{label}</div>'
            f'<div style="font-family:Montserrat,Arial,sans-serif;font-weight:700;font-size:26px;color:{tone};line-height:1.1">{value}</div>'
            f'<div style="font-size:12px;color:{INK2}">{sub}</div></div>')

# ---------------------------------------------------------------- base css
BASE_CSS = """
@import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@500;600;700&family=Open+Sans:wght@400;500;600;700&display=swap');
body{margin:0;font-family:'Open Sans','Segoe UI',Arial,sans-serif;color:#1F1F1F;background:#F5F5F3;font-size:13px;line-height:1.45;-webkit-font-smoothing:antialiased}
h1,h2,h3,h4{font-family:Montserrat,'Segoe UI',Arial,sans-serif;margin:0;color:#1F1F1F}
a{color:#B71219;text-decoration:none}a:hover{color:#ED1B24}
button{font-family:inherit}
table{border-collapse:collapse}
"""

def logo():
    return ('<div style="display:flex;align-items:center;gap:10px;padding:18px 16px 14px 16px">'
            '<svg width="30" height="30" viewBox="0 0 30 30" fill="none"><rect width="30" height="30" rx="7" fill="#ED1B24"/>'
            '<polyline points="5,16 10,16 13,9 16,22 19,12 21,16 25,16" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/></svg>'
            '<div><div style="font-family:Montserrat,Arial,sans-serif;font-weight:700;font-size:13px;color:#fff;letter-spacing:.01em">Care Net Portal</div>'
            '<div style="font-size:10.5px;color:#9A9A9A">Sales dashboard</div></div></div>')

NAV = [("home","My Work"),("inbox","Inbox"),("board","Team Board"),("building","Clients"),("bot","Automations"),("chart","Reports"),("shield","Permissions")]

def sidebar(active, badge_inbox=12):
    items = []
    for key, label in NAV:
        on = label == active
        bg = "background:#2A2A2A;color:#fff" if on else "color:#C9C9C9"
        icol = RED if on else "#9A9A9A"
        badge = (f'<span style="margin-left:auto;background:{RED};color:#fff;font-size:10px;font-weight:700;height:18px;min-width:18px;'
                 f'padding:0 5px;border-radius:9px;display:inline-flex;align-items:center;justify-content:center">{badge_inbox}</span>') if label=="Inbox" else ""
        items.append(f'<div style="display:flex;align-items:center;gap:10px;height:40px;padding:0 12px;border-radius:8px;font-weight:600;font-size:13px;{bg}">{ic(key,18,icol)}{label}{badge}</div>')
    nav = '<div style="display:flex;flex-direction:column;gap:2px;padding:0 10px">' + "".join(items) + "</div>"
    dept = ('<div style="padding:18px 16px 8px 16px;font-size:10.5px;font-weight:700;color:#7A7A7A;letter-spacing:.08em;text-transform:uppercase">Departments</div>'
            '<div style="display:flex;flex-direction:column;gap:2px;padding:0 10px">'
            f'<div style="display:flex;align-items:center;gap:10px;height:34px;padding:0 12px;border-radius:8px;font-size:12.5px;color:#fff"><span style="width:8px;height:8px;border-radius:50%;background:{RED}"></span>Sales<span style="margin-left:auto;font-size:10.5px;color:#9A9A9A">live</span></div>'
            '<div style="display:flex;align-items:center;gap:10px;height:34px;padding:0 12px;border-radius:8px;font-size:12.5px;color:#8A8A8A"><span style="width:8px;height:8px;border-radius:50%;border:1px solid #6A6A6A"></span>Clinic operations<span style="margin-left:auto;font-size:10.5px;color:#6A6A6A">next</span></div>'
            '<div style="display:flex;align-items:center;gap:10px;height:34px;padding:0 12px;border-radius:8px;font-size:12.5px;color:#8A8A8A"><span style="width:8px;height:8px;border-radius:50%;border:1px solid #6A6A6A"></span>Finance<span style="margin-left:auto;font-size:10.5px;color:#6A6A6A">next</span></div>'
            '<div style="display:flex;align-items:center;gap:10px;height:34px;padding:0 12px;border-radius:8px;font-size:12.5px;color:#8A8A8A"><span style="width:8px;height:8px;border-radius:50%;border:1px solid #6A6A6A"></span>HR &amp; compliance<span style="margin-left:auto;font-size:10.5px;color:#6A6A6A">next</span></div>'
            '</div>')
    foot = ('<div style="margin-top:auto;padding:14px 16px;border-top:1px solid #2A2A2A;display:flex;align-items:center;gap:10px">'
            f'{av("BK")}<div style="min-width:0"><div style="font-size:12.5px;font-weight:600;color:#fff">Barteldt Kruger</div><div style="font-size:11px;color:#9A9A9A">Director · full access</div></div>'
            f'<span style="margin-left:auto">{ic("settings",16,"#9A9A9A")}</span></div>')
    return f'<aside style="width:232px;flex-shrink:0;background:#171717;display:flex;flex-direction:column">{logo()}{nav}{dept}{foot}</aside>'

def topbar(crumbs, right_extra=""):
    crumb_html = ""
    for i, c in enumerate(crumbs):
        last = i == len(crumbs) - 1
        col = INK if last else MUTE
        wt = 600 if last else 500
        crumb_html += f'<span style="font-size:13px;color:{col};font-weight:{wt}">{c}</span>'
        if not last:
            crumb_html += ic("chevright", 14, "#B5B5B5", 2)
    return (f'<header style="height:60px;flex-shrink:0;background:#fff;border-bottom:1px solid {LINE};display:flex;align-items:center;padding:0 24px;gap:16px">'
            f'<div style="display:flex;align-items:center;gap:6px">{crumb_html}</div>'
            f'<div style="margin-left:auto;display:flex;align-items:center;gap:12px">'
            f'<div style="width:280px;height:36px;border:1px solid {LINE2};border-radius:8px;display:flex;align-items:center;gap:8px;padding:0 12px;color:{MUTE};font-size:12.5px;box-sizing:border-box">{ic("search",16,MUTE,2)}Search tasks, clients, people<span style="margin-left:auto;font-size:10.5px;border:1px solid {LINE2};border-radius:4px;padding:0 5px">⌘K</span></div>'
            f'{right_extra}'
            f'<span style="position:relative;display:inline-flex">{ic("bell",18,INK2)}<span style="position:absolute;top:-2px;right:-3px;width:8px;height:8px;border-radius:50%;background:{RED};border:2px solid #fff"></span></span>'
            f'{av("BK",32)}</div></header>')

def shell(active, crumbs, body, right_extra="", h=900):
    return (f'<div style="display:flex;width:1440px;height:{h}px;overflow:hidden;background:{GROUND}">{sidebar(active)}'
            f'<div style="flex:1;display:flex;flex-direction:column;min-width:0">{topbar(crumbs, right_extra)}{body}</div></div>')

def doc(title, body, extra_css=""):
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
  <style>{BASE_CSS}{extra_css}</style>
</helmet>
{body}
</x-dc>
</body>
</html>
"""

def write(name, html):
    p = os.path.join(OUT, name)
    with open(p, "w", encoding="utf-8") as f:
        f.write(html)
    print("wrote", name, len(html), "bytes")

# =============================================================== 1. MY WORK
def task_row(title, kind, due, who, source, stage_txt, sub=None, indent=False, ai=False, cols=None):
    pad = 56 if indent else 16
    connector = (f'<span style="width:14px;height:14px;border-left:1px solid #D3D3D0;border-bottom:1px solid #D3D3D0;'
                 f'border-radius:0 0 0 4px;margin-right:6px;margin-top:-8px;flex-shrink:0"></span>') if indent else ""
    cb = (f'<span style="width:16px;height:16px;border-radius:5px;border:1.5px solid #C4C4C1;background:#fff;flex-shrink:0;'
          f'display:inline-flex;align-items:center;justify-content:center">{"" if kind!="done" else ic("check",12,GREEN,3)}</span>')
    aichip = (f'<span style="display:inline-flex;align-items:center;gap:4px;font-size:10.5px;font-weight:700;color:{RED_D}">{ic("sparkle",12,RED_D,2)}drafted</span>') if ai else ""
    subline = f'<div style="font-size:11.5px;color:{MUTE};margin-top:1px">{sub}</div>' if sub else ""
    fs = "13px" if indent else "13.5px"
    fw = 500 if indent else 600
    return (f'<div style="display:grid;grid-template-columns:minmax(0,1fr) 120px 150px 96px 72px 60px;align-items:center;'
            f'height:{"44px" if indent else "50px"};padding:0 16px 0 {pad}px;border-top:1px solid #F0F0EE;background:#fff">'
            f'<div style="display:flex;align-items:center;gap:10px;min-width:0">{connector}{cb}<div style="min-width:0"><div style="display:flex;align-items:center;gap:8px;min-width:0"><span style="font-size:{fs};font-weight:{fw};color:{INK};white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{title}</span>{aichip}</div>{subline}</div></div>'
            f'<div>{pill(kind)}</div>'
            f'<div>{stage(stage_txt, on=True) if not indent else stage(stage_txt, done=True)}</div>'
            f'<div style="font-size:12.5px;color:{RED_D if kind=="over" else INK2};display:flex;align-items:center;gap:6px">{ic("calendar",14,MUTE if kind!="over" else RED_D)}{due}</div>'
            f'<div>{av(who,26)}</div>'
            f'<div style="display:flex;justify-content:flex-end">{src(source)}</div></div>')

def group_header(client, meta, count, expanded=True):
    return (f'<div style="display:flex;align-items:center;gap:12px;height:46px;padding:0 16px;background:#FAFAF9;border-top:1px solid {LINE}">'
            f'{ic("chevdown" if expanded else "chevright",16,INK2,2)}{ic("building",16,INK2)}'
            f'<span style="font-family:Montserrat,Arial,sans-serif;font-weight:600;font-size:13.5px">{client}</span>'
            f'<span style="font-size:12px;color:{MUTE}">{meta}</span>'
            f'<span style="margin-left:auto;font-size:11.5px;color:{MUTE};font-weight:600">{count}</span>{ic("more",16,MUTE)}</div>')

def my_work():
    filters = ('<div style="display:flex;gap:14px;flex-wrap:wrap;align-items:center">'
               + field("Source", "All sources", 150) + field("Task type", "All", 170) + field("Status", "New, In progress", 170)
               + field("Journey stage", "All stages", 160) + field("Client", "All clients", 180)
               + field("Date type", "Task due date", 150) + field("Date from", "01/09/2026", 130, "calendar") + field("Date to", "30/11/2026", 130, "calendar")
               + f'<span style="display:flex;align-items:center;gap:6px;color:{RED_D};font-weight:600;font-size:12.5px">{ic("filter",14,RED_D,2)}Save view</span></div>')
    head = (f'<div style="display:flex;align-items:flex-end;gap:16px">'
            f'<div><h1 style="font-size:22px;font-weight:700">My Work</h1><div style="font-size:12.5px;color:{MUTE};margin-top:2px">Wednesday, 3 September 2026 · Celeste Bulpitt · Sales consultant</div></div>'
            f'<div style="margin-left:auto;display:flex;gap:8px">{btn("Add a task","sec","plus")}{btn("Excel report","sec","file")}{btn("Ask the assistant","pri","sparkle")}</div></div>')
    tabs_items = [("List", True), ("Board", False), ("Calendar", False), ("Timeline", False), ("Client journey", False)]
    tabs = '<div style="display:flex;gap:4px;border-bottom:1px solid #E6E6E4">' + "".join(
        f'<div style="padding:8px 12px;font-size:13px;font-weight:600;color:{INK if on else MUTE};border-bottom:2px solid {RED if on else "transparent"};margin-bottom:-1px">{t}</div>' for t, on in tabs_items) + '</div>'
    kpis = ('<div style="display:flex;gap:12px">'
            + kpi("Due today", "6", "2 from MCO sync this morning")
            + kpi("Overdue", "2", "Tolcon Group · CGI Industries", RED_D)
            + kpi("Awaiting my action", "3", "Bot drafts to review and send", PURPLE)
            + kpi("Automated this week", "41", "Sub-tasks created by Grok, 0 errors", GREEN) + "</div>")
    cols = (f'<div style="display:grid;grid-template-columns:minmax(0,1fr) 120px 150px 96px 72px 60px;padding:0 16px;height:36px;align-items:center;'
            f'font-size:11px;font-weight:700;color:{MUTE};text-transform:uppercase;letter-spacing:.05em;background:#fff">'
            '<div>Task</div><div>Status</div><div>Journey stage</div><div>Due</div><div>Owner</div><div style="text-align:right">Source</div></div>')
    rows = [
        group_header("Pt Operational Services (Pty) Ltd", "Account owner Celeste · Renewal window Oct 2026", "1 parent · 5 sub-tasks"),
        task_row("97× Medical(s) expiring between 01/10/2026 and 31/10/2026", "prog", "16/09/2026", "CB", "mco", "Renewal",
                 sub="MCO Medicals Due · created 01/09 09:30 · Grok grouped 5 sub-tasks · 2 of 5 done"),
        task_row("Confirm employee list and sites with HR contact", "done", "03/09/2026", "CB", "bot", "Renewal", indent=True),
        task_row("Send booking proposal for 6 to 10 October", "wait", "04/09/2026", "CB", "bot", "Schedule", indent=True, ai=True),
        task_row("Reserve mobile clinic slots at Secunda and Sasolburg", "new", "08/09/2026", "AN", "bot", "Schedule", indent=True),
        task_row("Collect outstanding ID copies (12 pending)", "new", "10/09/2026", "CB", "mco", "Certificates", indent=True),
        task_row("Raise pro-forma invoice for 97 medicals", "new", "12/09/2026", "AW", "bot", "Invoice", indent=True),
        group_header("Afrirent Auto (Pty) Ltd", "Account owner Celeste · 26 medicals due Oct 2026", "1 parent · 4 sub-tasks", expanded=False),
        task_row("26× Medical(s) expiring between 01/10/2026 and 31/10/2026", "new", "16/09/2026", "CB", "mco", "Renewal",
                 sub="Grok proposed 4 sub-tasks · awaiting your approval"),
        group_header("Tolcon Group (Pty) Ltd.", "Account owner Celeste · 24 medicals due, 3 non-arrivals last clinic day", "2 parents · 6 sub-tasks", expanded=False),
        task_row("Non arrival: 3 employees missed clinic day 28/08", "over", "01/09/2026", "CB", "mco", "Clinic day",
                 sub="Rebooking required · client contact Lindiwe M."),
        task_row("24× Medical(s) expiring between 01/10/2026 and 31/10/2026", "new", "16/09/2026", "CB", "mco", "Renewal"),
        group_header("CGI Industries", "Account owner Celeste · single-site client", "1 parent · 2 sub-tasks", expanded=False),
        task_row("Medicals: ID pending for T. Henderson", "over", "02/09/2026", "CB", "mco", "Certificates"),
    ]
    table = f'<div style="background:#fff;border:1px solid {LINE};border-radius:12px;overflow:hidden">{cols}{"".join(rows)}</div>'

    rail = (f'<aside style="width:300px;flex-shrink:0;display:flex;flex-direction:column;gap:12px">'
            # assistant card
            f'<div style="background:#fff;border:1px solid {LINE};border-radius:12px;padding:16px;display:flex;flex-direction:column;gap:12px">'
            f'<div style="display:flex;align-items:center;gap:8px"><span style="width:28px;height:28px;border-radius:8px;background:{RED_L};display:inline-flex;align-items:center;justify-content:center">{ic("sparkle",16,RED,2)}</span><h3 style="font-size:14px;font-weight:700">Assistant</h3><span style="margin-left:auto;font-size:11px;color:{MUTE}">Grok · 09:31</span></div>'
            f'<p style="margin:0;font-size:12.5px;color:{INK2};line-height:1.5">I pulled <strong>10 Medicals Due</strong> tasks from MyClinicOnline for your clients. I grouped them by client and drafted sub-tasks along the renewal journey. Two items need you:</p>'
            f'<div style="display:flex;flex-direction:column;gap:8px">'
            f'<div style="border:1px solid {LINE};border-radius:10px;padding:10px 12px;display:flex;flex-direction:column;gap:6px"><div style="font-size:12.5px;font-weight:600">Approve booking proposal email</div><div style="font-size:11.5px;color:{MUTE}">Pt Operational Services · 97 medicals · 6 to 10 Oct</div><div style="display:flex;gap:6px">{btn("Approve and send","pri",None,30)}{btn("Edit","sec",None,30)}</div></div>'
            f'<div style="border:1px solid {LINE};border-radius:10px;padding:10px 12px;display:flex;flex-direction:column;gap:6px"><div style="font-size:12.5px;font-weight:600">Accept 4 proposed sub-tasks</div><div style="font-size:11.5px;color:{MUTE}">Afrirent Auto · 26 medicals · assigned to you</div><div style="display:flex;gap:6px">{btn("Accept all","dark",None,30)}{btn("Review","sec",None,30)}</div></div>'
            f'</div>'
            f'<div style="height:36px;border:1px solid {LINE2};border-radius:8px;display:flex;align-items:center;padding:0 12px;color:{MUTE};font-size:12.5px;gap:8px">Ask about a client or task…<span style="margin-left:auto">{ic("arrow",14,MUTE,2)}</span></div>'
            f'</div>'
            # journey card
            f'<div style="background:#fff;border:1px solid {LINE};border-radius:12px;padding:16px;display:flex;flex-direction:column;gap:10px">'
            f'<h3 style="font-size:13px;font-weight:700">My clients on the journey</h3>'
            + "".join(
                f'<div style="display:flex;align-items:center;gap:10px"><span style="width:96px;font-size:12px;color:{INK2};white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{n}</span>'
                f'<div style="flex:1;display:flex;gap:3px">' + "".join(f'<span style="flex:1;height:6px;border-radius:3px;background:{RED if i==cur else ("#DEDEDC" if i<cur else "#F0F0EE")}"></span>' for i in range(8)) + f'</div><span style="font-size:11px;color:{MUTE};width:64px;text-align:right">{s}</span></div>'
                for n, cur, s in [("Pt Operational", 7, "Renewal"), ("Afrirent Auto", 7, "Renewal"), ("Tolcon Group", 4, "Clinic day"), ("Nuvest Chemicals", 3, "Schedule"), ("Univac Cooling", 2, "Onboard"), ("CGI Industries", 5, "Certificates")])
            + f'<div style="font-size:11px;color:{MUTE};display:flex;justify-content:space-between"><span>Prospect</span><span>Renewal</span></div>'
            f'</div>'
            # today
            f'<div style="background:#fff;border:1px solid {LINE};border-radius:12px;padding:16px;display:flex;flex-direction:column;gap:8px">'
            f'<h3 style="font-size:13px;font-weight:700">Today</h3>'
            + "".join(f'<div style="display:flex;gap:10px;align-items:flex-start"><span style="font-size:11.5px;color:{MUTE};width:40px;flex-shrink:0;padding-top:1px">{t}</span><span style="font-size:12.5px;color:{INK2}">{d}</span></div>'
                      for t, d in [("10:00", "Call Lindiwe M. (Tolcon) about 3 non-arrivals"), ("11:30", "Weekly pipeline review with Barteldt"), ("14:00", "Nuvest Chemicals: confirm clinic date")])
            + '</div></aside>')

    body = (f'<div style="flex:1;overflow:hidden;padding:20px 24px;display:flex;gap:20px">'
            f'<div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:16px">{head}{tabs}{kpis}{filters}{table}</div>{rail}</div>')
    return doc("My Work", shell("My Work", ["Sales", "My Work"], body, h=1200))

# =============================================================== 2. TEAM BOARD
def card(client, title, who, due, n, kind, source="mco", ai=False):
    aichip = f'<span style="display:inline-flex;align-items:center;gap:4px;font-size:10.5px;font-weight:700;color:{RED_D}">{ic("sparkle",11,RED_D,2)}bot</span>' if ai else ""
    return (f'<div style="background:#fff;border:1px solid {LINE};border-radius:10px;padding:12px;display:flex;flex-direction:column;gap:8px;box-shadow:0 1px 2px rgba(0,0,0,.04)">'
            f'<div style="display:flex;align-items:center;gap:6px;font-size:11px;color:{MUTE};font-weight:600">{ic("building",12,MUTE)}<span style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{client}</span><span style="margin-left:auto">{src(source)}</span></div>'
            f'<div style="font-size:12.5px;font-weight:600;line-height:1.4">{title}</div>'
            f'<div style="display:flex;align-items:center;gap:8px">{pill(kind)}{aichip}<span style="margin-left:auto;font-size:11px;color:{MUTE};white-space:nowrap">{n}</span></div>'
            f'<div style="display:flex;align-items:center;gap:6px;font-size:11.5px;color:{RED_D if kind=="over" else INK2}">{ic("calendar",13,RED_D if kind=="over" else MUTE)}{due}<span style="margin-left:auto">{av(who,24)}</span></div></div>')

def column(name, count, cards, tone=None):
    dot = f'<span style="width:8px;height:8px;border-radius:50%;background:{tone or "#C4C4C1"}"></span>'
    return (f'<div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:10px">'
            f'<div style="display:flex;align-items:center;gap:8px;height:32px;padding:0 4px">{dot}<span style="font-family:Montserrat,Arial,sans-serif;font-weight:600;font-size:12.5px">{name}</span><span style="font-size:11.5px;color:{MUTE};font-weight:600">{count}</span><span style="margin-left:auto">{ic("plus",14,MUTE,2)}</span></div>'
            f'<div style="display:flex;flex-direction:column;gap:8px;background:#EFEFED;border-radius:12px;padding:8px;min-height:380px">{"".join(cards)}</div></div>')

def team_board():
    head = (f'<div style="display:flex;align-items:flex-end;gap:16px">'
            f'<div><h1 style="font-size:22px;font-weight:700">Team Board</h1><div style="font-size:12.5px;color:{MUTE};margin-top:2px">Sales team · every open parent task placed on the client journey · manager view</div></div>'
            f'<div style="margin-left:auto;display:flex;gap:8px">{field("Group by","Journey stage",170)}{field("Team","Sales · all consultants",200)}{btn("Reassign","sec","users")}{btn("Allocate queue (4)","pri","sparkle")}</div></div>')
    # workload strip
    def load(code, n, cap, over_n):
        name, col = PEOPLE[code]
        pct = min(100, int(n / cap * 100))
        bar_col = RED if n > cap else INK
        return (f'<div style="flex:1;min-width:0;background:#fff;border:1px solid {LINE};border-radius:12px;padding:12px 14px;display:flex;flex-direction:column;gap:8px">'
                f'<div style="display:flex;align-items:center;gap:8px">{av(code,26)}<div style="min-width:0"><div style="font-size:12.5px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{name}</div><div style="font-size:11px;color:{MUTE}">{n} open · {over_n} overdue</div></div>'
                f'<span style="margin-left:auto;font-family:Montserrat,Arial,sans-serif;font-weight:700;font-size:13px;color:{bar_col}">{pct}%</span></div>'
                f'<div style="height:6px;border-radius:3px;background:#EEEEEC;overflow:hidden"><span style="display:block;height:100%;width:{pct}%;background:{bar_col};border-radius:3px"></span></div></div>')
    loads = ('<div style="display:flex;gap:10px;align-items:flex-start">' + load("CB", 14, 12, 2) + load("AN", 11, 12, 0) + load("AW", 9, 12, 1) + load("AS", 8, 12, 0) + load("AM", 6, 12, 0)
             + f'<div style="width:270px;flex-shrink:0;background:{INK};color:#fff;border-radius:12px;padding:12px 14px;display:flex;flex-direction:column;gap:6px;box-sizing:border-box">'
             f'<div style="display:flex;align-items:center;gap:8px">{ic("sparkle",16,RED,2)}<span style="font-size:12.5px;font-weight:600">Allocation queue</span><span style="margin-left:auto;font-family:Montserrat,Arial,sans-serif;font-weight:700;font-size:18px">4</span></div>'
             f'<div style="font-size:11.5px;color:#C9C9C9">Grok suggests Asekhona for 3 tasks (lowest load). One task exceeds the 20-medical threshold and needs your sign-off.</div></div></div>')
    cols = (f'<div style="display:flex;gap:12px">'
            + column("Onboard", 3, [
                card("Univac Cooling Services", "Onboarding pack and site risk questionnaire", "AS", "05/09", "3 sub-tasks", "prog", "ghl"),
                card("Mega Bus & Coach", "3× medicals due · first renewal cycle", "AM", "16/09", "0 of 4", "wait", "mco", ai=True),
                card("ISE Group (Pty) Ltd", "Confirm medical protocol per job category", "AS", "09/09", "1 of 3", "prog", "man"),
            ], "#9A9A9A")
            + column("Schedule", 4, [
                card("Nuvest Chemicals", "4× medicals due · book Sasolburg clinic day", "AM", "16/09", "1 of 4", "prog", "mco"),
                card("Gritsol (Pty) Ltd", "4× medicals due · confirm October dates", "AN", "16/09", "0 of 4", "new", "mco", ai=True),
                card("Pt Operational Services", "Reserve clinic slots Secunda and Sasolburg", "AN", "08/09", "sub-task", "new", "bot", ai=True),
                card("Afrirent Auto (Pty) Ltd", "Send booking proposal for 26 medicals", "CB", "09/09", "sub-task", "wait", "bot", ai=True),
            ], YELLOW)
            + column("Clinic day", 2, [
                card("Tolcon Group (Pty) Ltd.", "Non arrival: 3 employees missed 28/08", "CB", "01/09", "rebook", "over", "mco"),
                card("Nuvest Chemicals", "Mobile clinic · Sasolburg · 18 Sept", "AN", "18/09", "day plan", "prog", "man"),
            ], ORANGE)
            + column("Certificates", 3, [
                card("CGI Industries", "Medicals: ID pending for T. Henderson", "CB", "02/09", "1 doc", "over", "mco"),
                card("Pt Operational Services", "Collect outstanding ID copies (12 pending)", "CB", "10/09", "sub-task", "new", "mco"),
                card("Tolcon Group (Pty) Ltd.", "Medicals: error resolution · 2 certificates", "AW", "05/09", "2 items", "prog", "mco"),
            ], BLUE)
            + column("Invoice", 2, [
                card("Pt Operational Services", "Raise pro-forma invoice for 97 medicals", "AW", "12/09", "sub-task", "new", "bot", ai=True),
                card("ISE Group (Pty) Ltd", "Medicals: admin · PO number outstanding", "AW", "04/09", "1 of 1", "prog", "mco"),
            ], GREEN)
            + column("Renewal", 5, [
                card("Pt Operational Services", "97× medicals expiring Oct 2026", "CB", "16/09", "2 of 5", "prog", "mco"),
                card("Afrirent Auto (Pty) Ltd", "26× medicals expiring Oct 2026", "CB", "16/09", "0 of 4", "wait", "mco", ai=True),
                card("Tolcon Group (Pty) Ltd.", "24× medicals expiring Oct 2026", "CB", "16/09", "0 of 4", "new", "mco"),
                card("All clients", "Christmas message · draft and schedule", "GB", "01/12", "campaign", "hold", "bot", ai=True),
            ], RED)
            + "</div>")
    body = f'<div style="flex:1;overflow:hidden;padding:20px 24px;display:flex;flex-direction:column;gap:16px">{head}{loads}{cols}</div>'
    return doc("Team Board", shell("Team Board", ["Sales", "Team Board"], body, h=1120))

# =============================================================== 3. CLIENT 360
def client360():
    stages = ["Prospect", "Quote", "Onboard", "Schedule", "Clinic day", "Certificates", "Invoice", "Renewal"]
    cur = 7
    stepper = '<div style="display:flex;align-items:center;gap:0">'
    for i, s in enumerate(stages):
        done = i < cur; on = i == cur
        circ_bg = RED if on else (INK if done else "#fff")
        circ_bd = RED if on else (INK if done else "#C4C4C1")
        inner = ic("check", 12, "#fff", 3) if done else (f'<span style="width:8px;height:8px;border-radius:50%;background:#fff"></span>' if on else "")
        stepper += (f'<div style="display:flex;flex-direction:column;align-items:center;gap:6px;width:110px">'
                    f'<span style="width:24px;height:24px;border-radius:50%;background:{circ_bg};border:2px solid {circ_bd};display:inline-flex;align-items:center;justify-content:center;box-sizing:border-box">{inner}</span>'
                    f'<span style="font-size:11.5px;font-weight:{700 if on else 600};color:{RED_D if on else (INK2 if done else MUTE)};white-space:nowrap">{s}</span></div>')
        if i < len(stages) - 1:
            stepper += f'<span style="flex:1;height:2px;background:{INK if i < cur-1 else (RED if i == cur-1 else "#DEDEDC")};margin:0 -30px;margin-bottom:22px"></span>'
    stepper += "</div>"

    header = (f'<div style="background:#fff;border:1px solid {LINE};border-radius:12px;padding:20px 24px;display:flex;flex-direction:column;gap:18px">'
              f'<div style="display:flex;align-items:flex-start;gap:16px">'
              f'<span style="width:48px;height:48px;border-radius:12px;background:{INK};color:#fff;display:inline-flex;align-items:center;justify-content:center;font-family:Montserrat,Arial,sans-serif;font-weight:700;font-size:16px">PT</span>'
              f'<div><h1 style="font-size:20px;font-weight:700">Pt Operational Services (Pty) Ltd</h1><div style="font-size:12.5px;color:{MUTE};margin-top:2px">Mining services · Secunda and Sasolburg · 214 employees on medical surveillance · MCO client since 2019</div>'
              f'<div style="display:flex;gap:8px;margin-top:8px;align-items:center">{pill("done","Active")}{stage("Renewal", on=True)}<span style="font-size:12px;color:{INK2}">Account owner</span>{av("CB",22)}<span style="font-size:12px;color:{INK2}">Celeste Bulpitt</span><span style="font-size:12px;color:{INK2};margin-left:6px">Oversight</span>{av("BK",22)}</div></div>'
              f'<div style="margin-left:auto;display:flex;gap:8px">{btn("Log activity","sec","message")}{btn("Open in MCO","sec","external")}{btn("New task","pri","plus")}</div></div>'
              f'{stepper}</div>')

    def stat(l, v, s):
        return (f'<div style="flex:1;background:#fff;border:1px solid {LINE};border-radius:12px;padding:12px 16px"><div style="font-size:11px;color:{MUTE};font-weight:700;text-transform:uppercase;letter-spacing:.04em">{l}</div>'
                f'<div style="font-family:Montserrat,Arial,sans-serif;font-weight:700;font-size:20px;margin-top:2px">{v}</div><div style="font-size:11.5px;color:{INK2}">{s}</div></div>')
    stats = '<div style="display:flex;gap:12px">' + stat("Medicals due Oct", "97", "16 Sept internal deadline") + stat("Open tasks", "6", "1 parent · 5 sub-tasks") + stat("Certificates outstanding", "12", "ID copies pending") + stat("Last clinic day", "14 Apr 2026", "0 non-arrivals") + stat("Contract renewal", "31 Mar 2027", "SLA · annual") + "</div>"

    # timeline
    events = [
        ("03/09 09:31", "GB", "Grouped 5 sub-tasks under the Medicals Due parent and drafted the booking proposal email for Celeste to approve.", "bot"),
        ("01/09 09:30", "GB", "Ingested MCO task <strong>97× Medical(s) expiring 01/10 to 31/10/2026</strong> via Supabase sync and allocated it to the account owner.", "mco"),
        ("28/08 15:10", "CB", "Called Thabo N. (HR) to pre-warn about the October renewal wave. Sites confirmed as Secunda and Sasolburg.", "man"),
        ("14/04 17:00", "AN", "Clinic day closed. 88 employees seen, 0 non-arrivals, 3 referrals for audiometry follow-up.", "man"),
        ("02/04 08:00", "GB", "Invoice INV-2026-0412 raised from the confirmed attendance list and sent to accounts@ptops.co.za.", "bot"),
    ]
    tl = f'<div style="background:#fff;border:1px solid {LINE};border-radius:12px;padding:16px 20px;display:flex;flex-direction:column;gap:0;flex:1;min-width:0">'
    tl += f'<div style="display:flex;align-items:center;gap:8px;margin-bottom:12px"><h3 style="font-size:14px;font-weight:700">Journey timeline</h3><span style="font-size:11.5px;color:{MUTE}">every touchpoint from MCO, the bots and the team</span><span style="margin-left:auto;display:flex;gap:6px">{src("mco")}{src("bot")}{src("man")}</span></div>'
    for i, (t, who, txt, s) in enumerate(events):
        last = i == len(events) - 1
        tl += (f'<div style="display:flex;gap:12px"><div style="display:flex;flex-direction:column;align-items:center;width:28px;flex-shrink:0">{av(who,26)}<span style="flex:1;width:1px;background:{"transparent" if last else "#E1E1DF"};margin:4px 0"></span></div>'
               f'<div style="padding-bottom:{"0" if last else "16px"};min-width:0"><div style="display:flex;align-items:center;gap:8px;font-size:11.5px;color:{MUTE}"><span style="font-weight:600;color:{INK2}">{PEOPLE[who][0]}</span>·<span>{t}</span>{src(s)}</div>'
               f'<div style="font-size:12.5px;color:{INK};margin-top:3px;line-height:1.5">{txt}</div></div></div>')
    tl += "</div>"

    # open tasks + contacts
    tasks_card = (f'<div style="background:#fff;border:1px solid {LINE};border-radius:12px;padding:16px 20px;display:flex;flex-direction:column;gap:10px">'
                  f'<div style="display:flex;align-items:center;gap:8px"><h3 style="font-size:14px;font-weight:700">Open tasks</h3><span style="margin-left:auto;font-size:12px;color:{RED_D};font-weight:600">View all 6</span></div>'
                  + "".join(f'<div style="display:flex;align-items:center;gap:10px;padding:8px 0;border-top:1px solid #F0F0EE"><span style="width:16px;height:16px;border-radius:5px;border:1.5px solid #C4C4C1;flex-shrink:0"></span><span style="flex:1;font-size:12.5px;font-weight:{600 if p else 500};min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{t}</span>{pill(k)}<span style="font-size:11.5px;color:{MUTE};width:44px;text-align:right">{d}</span>{av(w,22)}</div>'
                            for t, k, d, w, p in [("97× medicals expiring Oct 2026", "prog", "16/09", "CB", True), ("Send booking proposal 6 to 10 Oct", "wait", "04/09", "CB", False), ("Reserve clinic slots Secunda, Sasolburg", "new", "08/09", "AN", False), ("Collect outstanding ID copies (12)", "new", "10/09", "CB", False), ("Raise pro-forma invoice", "new", "12/09", "AW", False)])
                  + "</div>")
    contacts = (f'<div style="background:#fff;border:1px solid {LINE};border-radius:12px;padding:16px 20px;display:flex;flex-direction:column;gap:10px">'
                f'<h3 style="font-size:14px;font-weight:700">Client contacts</h3>'
                + "".join(f'<div style="display:flex;align-items:center;gap:10px;padding:6px 0;border-top:1px solid #F0F0EE"><span style="width:30px;height:30px;border-radius:50%;background:#EEEEEC;color:{INK2};display:inline-flex;align-items:center;justify-content:center;font-family:Montserrat,Arial,sans-serif;font-weight:600;font-size:11px">{i}</span><div style="flex:1"><div style="font-size:12.5px;font-weight:600">{n}</div><div style="font-size:11.5px;color:{MUTE}">{r}</div></div>{ic("mail",16,MUTE)}{ic("phone",16,MUTE)}</div>'
                          for i, n, r in [("TN", "Thabo N.", "HR manager · primary"), ("RV", "Riaan v.d. B.", "SHEQ officer · site access"), ("AP", "Accounts payable", "accounts@ · invoices and POs")])
                + "</div>")
    nba = (f'<div style="background:{INK};color:#fff;border-radius:12px;padding:16px 20px;display:flex;flex-direction:column;gap:8px">'
           f'<div style="display:flex;align-items:center;gap:8px">{ic("sparkle",16,RED,2)}<h3 style="font-size:13px;font-weight:700;color:#fff">Next best action</h3></div>'
           f'<div style="font-size:12.5px;color:#DEDEDC;line-height:1.5">Approve the booking proposal today. Historically this client confirms within 3 working days, which keeps the 6 to 10 October clinic window realistic and avoids a second Medicals Overdue wave in November.</div>'
           f'<div style="display:flex;gap:6px">{btn("Open proposal","pri",None,30)}</div></div>')
    right = f'<div style="width:380px;flex-shrink:0;display:flex;flex-direction:column;gap:12px">{nba}{tasks_card}{contacts}</div>'
    body = f'<div style="flex:1;overflow:hidden;padding:20px 24px;display:flex;flex-direction:column;gap:12px">{header}{stats}<div style="display:flex;gap:12px;flex:1;min-height:0">{tl}{right}</div></div>'
    return doc("Client 360", shell("Clients", ["Sales", "Clients", "Pt Operational Services"], body, h=1100))

# =============================================================== 4. TASK DETAIL
def task_detail():
    def prop(label, value_html):
        return (f'<div style="display:flex;align-items:center;gap:12px;min-height:36px"><span style="width:110px;font-size:12px;color:{MUTE};font-weight:600;flex-shrink:0">{label}</span><div style="display:flex;align-items:center;gap:8px;font-size:13px;min-width:0">{value_html}</div></div>')
    props = (f'<div style="width:320px;flex-shrink:0;background:#fff;border:1px solid {LINE};border-radius:12px;padding:16px 18px;display:flex;flex-direction:column;gap:2px">'
             + prop("Status", pill("prog"))
             + prop("Priority", f'<span style="display:inline-flex;align-items:center;gap:6px;font-weight:600;color:{RED_D}">{ic("alert",14,RED_D,2)}High</span>')
             + prop("Assigned to", f'{av("CB",24)}Celeste Bulpitt')
             + prop("Reviewer", f'{av("BK",24)}Barteldt Kruger')
             + prop("Due date", f'<span style="display:inline-flex;align-items:center;gap:6px">{ic("calendar",14,MUTE)}16/09/2026</span>')
             + prop("Client", f'<span style="display:inline-flex;align-items:center;gap:6px">{ic("building",14,MUTE)}Pt Operational Services</span>')
             + prop("Journey stage", stage("Renewal", on=True))
             + prop("Task type", '<span>Medicals Due</span>')
             + prop("Source", f'{src("mco")}<span style="font-size:12px;color:{MUTE}">MCO #48213 · synced 01/09 09:30</span>')
             + prop("Department", "Sales")
             + prop("Bot run", f'<a href="#">run_2026-09-03_0931</a>')
             + prop("Watchers", f'<span style="display:inline-flex">{av("AN",24)}</span><span style="display:inline-flex;margin-left:-6px">{av("AW",24)}</span>')
             + f'<div style="border-top:1px solid #F0F0EE;margin:10px 0"></div>'
             f'<div style="font-size:12px;color:{MUTE};font-weight:600;margin-bottom:6px">Permissions on this task</div>'
             f'<div style="display:flex;flex-direction:column;gap:6px;font-size:12px;color:{INK2}">'
             f'<div style="display:flex;gap:8px;align-items:center">{ic("check",13,GREEN,3)}Celeste can edit sub-tasks and log activity</div>'
             f'<div style="display:flex;gap:8px;align-items:center">{ic("check",13,GREEN,3)}Barteldt can reassign, approve and close</div>'
             f'<div style="display:flex;gap:8px;align-items:center">{ic("lock",13,MUTE,2)}Grok can propose, never send without approval</div></div></div>')

    subs = [
        ("Confirm employee list and sites with HR contact", "done", "CB", "03/09", "Thabo N. confirmed 97 names · Secunda 61, Sasolburg 36"),
        ("Send booking proposal for 6 to 10 October", "wait", "CB", "04/09", "Email drafted by Grok · needs your approval before sending"),
        ("Reserve mobile clinic slots at Secunda and Sasolburg", "new", "AN", "08/09", "Depends on proposal acceptance"),
        ("Collect outstanding ID copies (12 pending)", "new", "CB", "10/09", "MCO Medicals: ID Pending will auto-close when documents arrive"),
        ("Raise pro-forma invoice for 97 medicals", "new", "AW", "12/09", "Grok will pre-fill from the confirmed list"),
    ]
    sub_html = ""
    for t, k, w, d, note in subs:
        chk = f'<span style="width:18px;height:18px;border-radius:5px;border:1.5px solid {"transparent" if k=="done" else "#C4C4C1"};background:{GREEN if k=="done" else "#fff"};display:inline-flex;align-items:center;justify-content:center;flex-shrink:0">{ic("check",12,"#fff",3) if k=="done" else ""}</span>'
        sub_html += (f'<div style="display:flex;align-items:flex-start;gap:12px;padding:10px 0;border-top:1px solid #F0F0EE">{chk}'
                     f'<div style="flex:1;min-width:0"><div style="font-size:13px;font-weight:600;{"text-decoration:line-through;color:#8A8A8A" if k=="done" else ""}">{t}</div><div style="font-size:11.5px;color:{MUTE};margin-top:2px">{note}</div></div>'
                     f'{pill(k)}<span style="font-size:12px;color:{INK2};width:44px;text-align:right">{d}</span>{av(w,24)}{ic("more",16,MUTE)}</div>')
    subs_card = (f'<div style="background:#fff;border:1px solid {LINE};border-radius:12px;padding:16px 20px">'
                 f'<div style="display:flex;align-items:center;gap:10px;margin-bottom:8px"><h3 style="font-size:14px;font-weight:700">Sub-tasks</h3><span style="font-size:12px;color:{MUTE}">2 of 5 complete</span>'
                 f'<div style="flex:1;max-width:200px;height:6px;border-radius:3px;background:#EEEEEC;overflow:hidden"><span style="display:block;width:40%;height:100%;background:{GREEN}"></span></div>'
                 f'<span style="margin-left:auto;display:flex;align-items:center;gap:6px;color:{RED_D};font-weight:600;font-size:12.5px">{ic("plus",14,RED_D,2)}Add sub-task</span></div>{sub_html}</div>')

    desc = (f'<div style="background:#fff;border:1px solid {LINE};border-radius:12px;padding:16px 20px;display:flex;flex-direction:column;gap:8px">'
            f'<div style="display:flex;align-items:center;gap:8px"><h3 style="font-size:14px;font-weight:700">Description</h3><span style="display:inline-flex;align-items:center;gap:4px;font-size:11px;font-weight:700;color:{RED_D}">{ic("sparkle",12,RED_D,2)}summarised by Grok from MCO</span></div>'
            f'<p style="margin:0;font-size:13px;line-height:1.6;color:{INK2}">MyClinicOnline reports 97 periodic medicals expiring between 1 and 31 October 2026 for Pt Operational Services. 61 employees are based at Secunda and 36 at Sasolburg. Last year the client used two mobile clinic days per site. Recommended plan: propose 6 to 10 October, secure slots once accepted, chase 12 outstanding ID copies in parallel and raise the pro-forma before the clinic days so certificates release without delay.</p>'
            f'<div style="display:flex;gap:8px;margin-top:4px">' + "".join(f'<span style="display:inline-flex;align-items:center;gap:6px;height:28px;padding:0 10px;border:1px solid {LINE2};border-radius:6px;font-size:12px;color:{INK2}">{ic("file",13,MUTE)}{n}</span>' for n in ["MCO_medicals_due_oct2026.xlsx", "Booking_proposal_draft.docx"]) + '</div></div>')

    acts = [
        ("GB", "03/09 09:31", "Drafted <strong>Booking proposal · 6 to 10 October</strong> and attached it to sub-task 2. Waiting for Celeste's approval.", "bot"),
        ("BK", "02/09 16:40", "Approved the bot allocation. Note: keep Annemarie on invoicing so the PO chase starts early.", "man"),
        ("CB", "02/09 11:05", "Marked <em>Confirm employee list</em> complete. Thabo confirmed 97 names, split 61 / 36.", "man"),
        ("GB", "01/09 09:30", "Created this task from MCO Medicals Due #48213 and allocated to the account owner under rule R-02.", "mco"),
    ]
    act_html = "".join(f'<div style="display:flex;gap:12px;padding:10px 0;border-top:1px solid #F0F0EE">{av(w,26)}<div style="min-width:0"><div style="display:flex;align-items:center;gap:8px;font-size:11.5px;color:{MUTE}"><span style="font-weight:600;color:{INK2}">{PEOPLE[w][0]}</span>·<span>{t}</span>{src(s)}</div><div style="font-size:12.5px;line-height:1.5;margin-top:2px">{x}</div></div></div>' for w, t, x, s in acts)
    activity = (f'<div style="background:#fff;border:1px solid {LINE};border-radius:12px;padding:16px 20px">'
                f'<div style="display:flex;gap:4px;border-bottom:1px solid {LINE};margin-bottom:4px">' + "".join(f'<div style="padding:6px 10px;font-size:12.5px;font-weight:600;color:{INK if on else MUTE};border-bottom:2px solid {RED if on else "transparent"};margin-bottom:-1px">{t}</div>' for t, on in [("Activity", True), ("Comments 3", False), ("Bot log", False), ("Emails 1", False)]) + '</div>'
                f'{act_html}'
                f'<div style="display:flex;gap:10px;margin-top:12px">{av("BK",28)}<div style="flex:1;height:40px;border:1px solid {LINE2};border-radius:8px;display:flex;align-items:center;padding:0 12px;color:{MUTE};font-size:12.5px">Write a comment or @mention a colleague…</div></div></div>')

    approval = (f'<div style="background:#FFF8F8;border:1px solid #F3C4C6;border-radius:12px;padding:12px 16px;display:flex;align-items:center;gap:12px">'
                f'<span style="width:32px;height:32px;border-radius:8px;background:{RED};display:inline-flex;align-items:center;justify-content:center">{ic("sparkle",16,"#fff",2)}</span>'
                f'<div style="flex:1"><div style="font-size:13px;font-weight:600">Grok is asking for approval: send the booking proposal to Thabo N.</div><div style="font-size:12px;color:{INK2}">Sub-task 2 · email preview attached · sending is blocked until a human approves</div></div>'
                f'{btn("Preview email","sec")}{btn("Request changes","sec")}{btn("Approve and send","pri","check")}</div>')

    titlebar = (f'<div style="display:flex;align-items:flex-start;gap:16px">'
                f'<div style="min-width:0"><div style="display:flex;align-items:center;gap:8px;font-size:12px;color:{MUTE}"><span>Parent task</span>·<span>TSK-2026-1187</span>·{src("mco")}</div>'
                f'<h1 style="font-size:21px;font-weight:700;margin-top:4px;line-height:1.3">97× Medical(s) expiring for Pt Operational Services between 01/10/2026 and 31/10/2026</h1></div>'
                f'<div style="margin-left:auto;display:flex;gap:8px;flex-shrink:0">{btn("Mark complete","sec","check")}{btn("Reassign","sec","users")}{btn("Open in MCO","sec","external")}{ic("more",18,MUTE)}</div></div>')

    left = f'<div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:12px">{titlebar}{approval}{subs_card}{desc}{activity}</div>'
    body = f'<div style="flex:1;overflow:hidden;padding:20px 24px;display:flex;gap:16px">{left}{props}</div>'
    return doc("Task Detail", shell("My Work", ["Sales", "My Work", "Pt Operational Services", "TSK-2026-1187"], body, h=1290))

# =============================================================== 5. AUTOMATIONS
def automations():
    head = (f'<div style="display:flex;align-items:flex-end;gap:16px">'
            f'<div><h1 style="font-size:22px;font-weight:700">Automations</h1><div style="font-size:12.5px;color:{MUTE};margin-top:2px">Grok bots read MyClinicOnline through Supabase, create and allocate portal tasks, and hand anything sensitive to a person</div></div>'
            f'<div style="margin-left:auto;display:flex;gap:8px">{btn("Pause all bots","sec","pause")}{btn("Run sync now","sec","refresh")}{btn("New rule","pri","plus")}</div></div>')

    # pipeline strip
    def node(icon, title, sub, dark=False):
        bg = INK if dark else "#fff"; fg = "#fff" if dark else INK; sc = "#C9C9C9" if dark else MUTE
        return (f'<div style="flex:1;background:{bg};border:1px solid {INK if dark else LINE};border-radius:12px;padding:14px 16px;display:flex;gap:12px;align-items:center">'
                f'<span style="width:36px;height:36px;border-radius:10px;background:{"#2A2A2A" if dark else RED_L};display:inline-flex;align-items:center;justify-content:center;flex-shrink:0">{ic(icon,18,RED,2)}</span>'
                f'<div><div style="font-family:Montserrat,Arial,sans-serif;font-weight:600;font-size:13px;color:{fg}">{title}</div><div style="font-size:11.5px;color:{sc}">{sub}</div></div></div>')
    arrow = f'<span style="display:inline-flex;align-items:center;flex-shrink:0">{ic("arrow",18,"#B5B5B5",2)}</span>'
    pipeline = (f'<div style="display:flex;align-items:center;gap:10px">'
                + node("monitor", "MyClinicOnline", "Task types: Medicals Due, Overdue, Admin, Documents, Error resolution, ID pending, Non arrival, General, Other") + arrow
                + node("db", "Supabase", "mco_tasks table · 15 min sync · 1,284 rows · last 09:30") + arrow
                + node("bot", "Grok bots", "Classify · group by client · draft · propose allocation", dark=True) + arrow
                + node("layers", "Portal tasks", "Parent and sub-tasks on the client journey") + arrow
                + node("users", "People", "Consultant executes · manager approves · director oversees")
                + "</div>")

    # rules table
    def rule(rid, trigger, action, owner, runs, on=True, guard=""):
        tog = (f'<span style="width:34px;height:20px;border-radius:10px;background:{GREEN if on else "#C4C4C1"};position:relative;display:inline-block">'
               f'<span style="position:absolute;top:2px;{"right:2px" if on else "left:2px"};width:16px;height:16px;border-radius:50%;background:#fff"></span></span>')
        g = f'<div style="display:inline-flex;align-items:center;gap:5px;font-size:11px;color:{PURPLE};font-weight:600;margin-top:3px">{ic("shield",12,PURPLE,2)}{guard}</div>' if guard else ""
        return (f'<div style="display:grid;grid-template-columns:52px minmax(0,1fr) minmax(0,2.1fr) 120px 70px 44px;gap:12px;align-items:center;padding:12px 16px;border-top:1px solid #F0F0EE">'
                f'<span style="font-family:Montserrat,Arial,sans-serif;font-weight:600;font-size:12px;color:{INK2}">{rid}</span>'
                f'<div style="font-size:12.5px;font-weight:600">{trigger}</div>'
                f'<div><div style="font-size:12.5px;color:{INK2}">{action}</div>{g}</div>'
                f'<div style="display:flex;align-items:center;gap:6px;font-size:12px">{av(owner,22)}{PEOPLE[owner][0].split()[0]}</div>'
                f'<span style="font-size:12px;color:{MUTE}">{runs}</span><div style="display:flex;justify-content:flex-end">{tog}</div></div>')
    rules = (f'<div style="flex:1;min-width:0;background:#fff;border:1px solid {LINE};border-radius:12px;overflow:hidden">'
             f'<div style="display:flex;align-items:center;gap:8px;padding:14px 16px"><h3 style="font-size:14px;font-weight:700">Allocation and journey rules</h3><span style="font-size:12px;color:{MUTE}">7 active · every rule has a human owner</span></div>'
             f'<div style="display:grid;grid-template-columns:52px minmax(0,1fr) minmax(0,2.1fr) 120px 70px 44px;gap:12px;padding:0 16px 8px;font-size:11px;font-weight:700;color:{MUTE};text-transform:uppercase;letter-spacing:.05em"><span>Rule</span><span>When</span><span>Grok does</span><span>Owner</span><span>Runs 30d</span><span style="text-align:right">On</span></div>'
             + rule("R-01", "New MCO task of any type", "Create a portal parent task, link the MCO id, place it on the client journey stage by type", "BK", "312")
             + rule("R-02", "Medicals Due · new", "Allocate to the client's account owner, draft renewal sub-tasks (confirm list, propose dates, reserve slots, IDs, invoice)", "BK", "118", guard="Over 20 medicals: manager approval before allocation")
             + rule("R-03", "Medicals Overdue · new", "Escalate to account owner and manager, draft recovery call script, set priority High", "BK", "27", guard="Never emails the client directly")
             + rule("R-04", "Non arrival logged", "Create rebooking sub-task under the clinic-day parent, notify consultant same day", "AN", "14")
             + rule("R-05", "Medicals: ID pending or Documents", "Draft the document request, attach MCO list, auto-close when MCO shows received", "CB", "63")
             + rule("R-06", "Sub-task drafts an outbound email", "Hold in Awaiting approval until the assigned person or their manager approves", "BK", "41", guard="Hard stop · POPIA: no employee medical data in email body")
             + rule("R-07", "Consultant load above 12 open parents", "Suggest the least-loaded consultant with client history, ask manager to confirm", "BK", "9")
             + "</div>")

    # run history
    runs = [("09:30 today", "Sync + allocate", "10 ingested", "10 created", "8 allocated", "2 need review", "done"),
            ("06:01 today", "Sync", "1 ingested", "1 created", "1 allocated", "0", "done"),
            ("Yesterday 17:15", "Overdue sweep", "3 flagged", "3 escalated", "3 allocated", "0", "done"),
            ("Yesterday 09:30", "Sync + allocate", "6 ingested", "6 created", "6 allocated", "1 need review", "done"),
            ("01/09 09:30", "Sync + allocate", "10 ingested", "9 created", "9 allocated", "1 error", "over")]
    run_html = "".join(f'<div style="display:flex;flex-direction:column;gap:3px;padding:9px 0;border-top:1px solid #F0F0EE;font-size:12px"><div style="display:flex;align-items:center;gap:8px"><span style="font-weight:600">{k}</span><span style="color:{MUTE}">{t}</span><span style="margin-left:auto">{pill(s, "OK" if s=="done" else "1 error")}</span></div><div style="color:{MUTE}">{a} · {b} · {c} · {d}</div></div>' for t, k, a, b, c, d, s in runs)
    history = (f'<div style="width:400px;flex-shrink:0;display:flex;flex-direction:column;gap:12px">'
               f'<div style="background:#fff;border:1px solid {LINE};border-radius:12px;padding:16px">'
               f'<div style="display:flex;align-items:center;gap:8px;margin-bottom:6px"><h3 style="font-size:14px;font-weight:700">Bot runs</h3><span style="margin-left:auto;font-size:12px;color:{RED_D};font-weight:600">Full log</span></div>{run_html}</div>'
               f'<div style="background:#fff;border:1px solid {LINE};border-radius:12px;padding:16px;display:flex;flex-direction:column;gap:10px">'
               f'<h3 style="font-size:14px;font-weight:700">Guardrails</h3>'
               + "".join(f'<div style="display:flex;gap:10px;align-items:flex-start"><span style="width:22px;height:22px;border-radius:6px;background:{RED_L};display:inline-flex;align-items:center;justify-content:center;flex-shrink:0">{ic(i,13,RED,2)}</span><div style="font-size:12.5px;color:{INK2};line-height:1.45">{t}</div></div>'
                         for i, t in [("lock", "Bots propose; people approve. No client-facing message leaves without a named approver."),
                                      ("shield", "POPIA: employee names and medical outcomes stay inside the portal and MCO. Emails carry counts and dates only."),
                                      ("users", "Every allocation follows the parent-child structure: consultant owns, team lead sees, manager approves, director audits."),
                                      ("refresh", "Every bot action is reversible from the task's Bot log within 24 hours.")])
               + "</div></div>")
    body = f'<div style="flex:1;overflow:hidden;padding:20px 24px;display:flex;flex-direction:column;gap:14px">{head}{pipeline}<div style="display:flex;gap:12px;flex:1;min-height:0">{rules}{history}</div></div>'
    return doc("Automations", shell("Automations", ["Sales", "Automations"], body, h=1300))

# =============================================================== 6. PERMISSIONS
def permissions():
    head = (f'<div style="display:flex;align-items:flex-end;gap:16px">'
            f'<div><h1 style="font-size:22px;font-weight:700">Permissions and team structure</h1><div style="font-size:12.5px;color:{MUTE};margin-top:2px">Parent and child structure per employee · management oversight through role rights · bots are a role with the fewest rights</div></div>'
            f'<div style="margin-left:auto;display:flex;gap:8px">{btn("Audit log","sec","file")}{btn("Invite person","pri","plus")}</div></div>')

    def person(code, role, n, depth, kids=""):
        name, col = PEOPLE[code]
        conn = "" if depth == 0 else '<span style="width:14px;height:14px;border-left:1px solid #D3D3D0;border-bottom:1px solid #D3D3D0;border-radius:0 0 0 4px;margin:-10px 0 0 -22px;flex-shrink:0"></span>'
        return (f'<div style="display:flex;flex-direction:column;gap:6px;margin-left:{depth*28}px">'
                f'<div style="display:flex;align-items:center;gap:10px;background:#fff;border:1px solid {LINE};border-radius:10px;padding:8px 12px">'
                f'{conn}'
                f'{av(code,28)}<div style="min-width:0"><div style="font-size:12.5px;font-weight:600">{name}</div><div style="font-size:11px;color:{MUTE}">{role}</div></div>'
                f'<span style="margin-left:auto;font-size:11.5px;color:{INK2}">{n}</span>{ic("more",16,MUTE)}</div>{kids}</div>')
    tree = (f'<div style="width:420px;flex-shrink:0;background:#F5F5F3;display:flex;flex-direction:column;gap:12px">'
            f'<div style="background:#fff;border:1px solid {LINE};border-radius:12px;padding:16px;display:flex;flex-direction:column;gap:8px">'
            f'<div style="display:flex;align-items:center;gap:8px;margin-bottom:4px"><h3 style="font-size:14px;font-weight:700">Sales department</h3><span style="font-size:12px;color:{MUTE}">who oversees whom</span></div>'
            + person("BK", "Director · oversees all departments", "sees 6 people", 0,
                     person("AW", "Sales manager · approves bot allocations", "4 reports · 9 open", 1,
                            person("CB", "Senior consultant · Key accounts", "14 open · 6 clients", 2)
                            + person("AN", "Consultant · Mpumalanga and Free State", "11 open · 5 clients", 2)
                            + person("AS", "Consultant · Onboarding", "8 open · 4 clients", 2)
                            + person("AM", "Junior consultant · shadowing Celeste", "6 open · 3 clients", 2))
                     + person("GB", "Grok bot · service account", "7 rules · proposes only", 1))
            + f'</div>'
            f'<div style="background:#fff;border:1px solid {LINE};border-radius:12px;padding:16px;display:flex;flex-direction:column;gap:8px">'
            f'<h3 style="font-size:13px;font-weight:700">How rights flow</h3>'
            f'<div style="font-size:12.5px;color:{INK2};line-height:1.5">A person sees their own tasks plus everything owned by people below them in the tree. Approval rights sit one level above the doer. The director sees everything and can act anywhere, and every action is written to the audit log.</div></div></div>')

    roles = ["Director", "Manager", "Team lead", "Consultant", "Grok bot"]
    rights = [
        ("View own tasks", [1, 1, 1, 1, 1]),
        ("View team tasks", [1, 1, 1, 0, 1]),
        ("View all departments", [1, 0, 0, 0, 0]),
        ("Create and edit tasks", [1, 1, 1, 1, 2]),
        ("Reassign within team", [1, 1, 1, 0, 2]),
        ("Approve bot allocation", [1, 1, 0, 0, 0]),
        ("Approve outbound client email", [1, 1, 1, 1, 0]),
        ("Edit automation rules", [1, 1, 0, 0, 0]),
        ("Pause bots", [1, 1, 0, 0, 0]),
        ("View client financials and invoices", [1, 1, 0, 0, 0]),
        ("Export Excel reports", [1, 1, 1, 1, 0]),
        ("View employee medical outcomes (POPIA)", [1, 0, 0, 0, 0]),
        ("Access audit log", [1, 1, 0, 0, 0]),
    ]
    def cell(v):
        if v == 1: return f'<span style="width:24px;height:24px;border-radius:6px;background:#DDF1DD;display:inline-flex;align-items:center;justify-content:center">{ic("check",14,GREEN,3)}</span>'
        if v == 2: return f'<span style="display:inline-flex;align-items:center;height:22px;padding:0 8px;border-radius:6px;background:{RED_L};color:{RED_D};font-size:10.5px;font-weight:700">propose</span>'
        return f'<span style="width:24px;height:24px;border-radius:6px;background:#F0F0EE;display:inline-flex;align-items:center;justify-content:center">{ic("x",12,"#B5B5B5",2)}</span>'
    matrix = (f'<div style="flex:1;min-width:0;background:#fff;border:1px solid {LINE};border-radius:12px;overflow:hidden">'
              f'<div style="display:flex;align-items:center;gap:8px;padding:14px 16px"><h3 style="font-size:14px;font-weight:700">Role rights</h3><span style="font-size:12px;color:{MUTE}">a person inherits the role of their position in the tree; a director can grant exceptions per client</span><span style="margin-left:auto;font-size:12px;color:{RED_D};font-weight:600">Edit roles</span></div>'
              f'<div style="display:grid;grid-template-columns:minmax(0,1.6fr) repeat(5, minmax(0,1fr));gap:8px;padding:8px 16px;background:#FAFAF9;border-top:1px solid {LINE};border-bottom:1px solid {LINE};font-size:11px;font-weight:700;color:{MUTE};text-transform:uppercase;letter-spacing:.05em"><span>Right</span>' + "".join(f'<span style="text-align:center">{r}</span>' for r in roles) + '</div>'
              + "".join(f'<div style="display:grid;grid-template-columns:minmax(0,1.6fr) repeat(5, minmax(0,1fr));gap:8px;align-items:center;padding:8px 16px;border-top:1px solid #F0F0EE"><span style="font-size:12.5px;font-weight:{600 if i in (5,6,11) else 500}">{r}</span>' + "".join(f'<span style="display:flex;justify-content:center">{cell(v)}</span>' for v in vals) + '</div>' for i, (r, vals) in enumerate(rights))
              + f'<div style="padding:12px 16px;border-top:1px solid {LINE};display:flex;gap:16px;font-size:11.5px;color:{MUTE};align-items:center">{cell(1)} allowed {cell(2)} may propose, a person confirms {cell(0)} not allowed</div></div>')
    body = f'<div style="flex:1;overflow:hidden;padding:20px 24px;display:flex;flex-direction:column;gap:14px">{head}<div style="display:flex;gap:12px;flex:1;min-height:0">{tree}{matrix}</div></div>'
    return doc("Permissions", shell("Permissions", ["Sales", "Permissions"], body, h=1000))

# =============================================================== 7. INBOX
def inbox():
    head = (f'<div style="display:flex;align-items:flex-end;gap:16px">'
            f'<div><h1 style="font-size:22px;font-weight:700">Inbox</h1><div style="font-size:12.5px;color:{MUTE};margin-top:2px">Everything that needs a decision from you, in one place · bot proposals, approvals, mentions, MCO changes</div></div>'
            f'<div style="margin-left:auto;display:flex;gap:8px">{btn("Mark all read","sec")}{btn("Approve all safe items (5)","dark","check")}</div></div>')
    tabs = '<div style="display:flex;gap:4px;border-bottom:1px solid #E6E6E4">' + "".join(
        f'<div style="padding:8px 12px;font-size:13px;font-weight:600;color:{INK if on else MUTE};border-bottom:2px solid {RED if on else "transparent"};margin-bottom:-1px;display:flex;gap:6px;align-items:center">{t}<span style="font-size:11px;color:{MUTE};background:#F0F0EE;border-radius:9px;padding:0 6px">{n}</span></div>' for t, n, on in [("Needs approval", 4, True), ("Proposed by Grok", 5, False), ("Mentions", 2, False), ("MCO changes", 1, False), ("All", 12, False)]) + '</div>'
    def item(kind_icon, title, meta, who, when, actions, sel=False, s="bot"):
        return (f'<div style="display:flex;gap:12px;padding:14px 16px;border-top:1px solid #F0F0EE;background:{"#FFF8F8" if sel else "#fff"}">'
                f'<span style="width:32px;height:32px;border-radius:8px;background:{RED_L if s=="bot" else "#F0F0EE"};display:inline-flex;align-items:center;justify-content:center;flex-shrink:0">{ic(kind_icon,16,RED if s=="bot" else INK2,2)}</span>'
                f'<div style="flex:1;min-width:0"><div style="display:flex;align-items:center;gap:8px"><span style="font-size:13px;font-weight:600">{title}</span>{src(s)}<span style="margin-left:auto;font-size:11.5px;color:{MUTE}">{when}</span></div>'
                f'<div style="font-size:12px;color:{INK2};margin-top:2px">{meta}</div>'
                f'<div style="display:flex;gap:6px;margin-top:8px;align-items:center">{actions}<span style="margin-left:auto;display:inline-flex;align-items:center;gap:6px;font-size:11.5px;color:{MUTE}">{av(who,20)}{PEOPLE[who][0]}</span></div></div></div>')
    items = (item("sparkle", "Approve allocation: 26× medicals · Afrirent Auto", "Grok proposes Celeste (account owner, 14 open). Alternative: Asekhona (6 open, no history with this client).", "GB", "09:31",
                  btn("Approve Celeste", "pri", None, 30) + btn("Assign Asekhona", "sec", None, 30) + btn("Open task", "ghost", None, 30), sel=True)
             + item("mail", "Approve outbound email: booking proposal to Thabo N. (Pt Operational Services)", "Sub-task 2 of TSK-2026-1187 · counts and dates only, no employee names · rule R-06 hold.", "GB", "09:31",
                    btn("Preview", "sec", None, 30) + btn("Approve and send", "pri", None, 30) + btn("Request changes", "ghost", None, 30))
             + item("alert", "Threshold exceeded: 97 medicals · Pt Operational Services", "Above the 20-medical limit in rule R-02. Allocation to Celeste is on hold until a manager confirms.", "GB", "01/09 09:30",
                    btn("Confirm allocation", "pri", None, 30) + btn("Split across two consultants", "sec", None, 30))
             + item("users", "Reassignment request from Celeste", "“Can Asandiswa take the Secunda slot reservation? I’m at Tolcon that week.” Sub-task 3 of TSK-2026-1187.", "CB", "Yesterday 16:20",
                    btn("Approve", "pri", None, 30) + btn("Decline", "sec", None, 30), s="man")
             + item("message", "Annemarie mentioned you on ISE Group · PO number outstanding", "“@Barteldt the client wants the PO referenced on the pro-forma. Can we hold the invoice two days?”", "AW", "Yesterday 14:02",
                    btn("Reply", "sec", None, 30) + btn("Open task", "ghost", None, 30), s="man")
             + item("refresh", "MCO changed a task you follow", "Medicals: ID pending for T. Henderson (CGI Industries) moved to Completed in MyClinicOnline. Portal task will auto-close in 24h unless you keep it open.", "GB", "06:01",
                    btn("Close now", "sec", None, 30) + btn("Keep open", "ghost", None, 30), s="mco"))
    listc = f'<div style="flex:1;min-width:0;background:#fff;border:1px solid {LINE};border-radius:12px;overflow:hidden">{items}</div>'
    side = (f'<div style="width:320px;flex-shrink:0;display:flex;flex-direction:column;gap:12px">'
            f'<div style="background:#fff;border:1px solid {LINE};border-radius:12px;padding:16px;display:flex;flex-direction:column;gap:10px">'
            f'<h3 style="font-size:13px;font-weight:700">Why you are seeing these</h3>'
            f'<div style="font-size:12.5px;color:{INK2};line-height:1.5">You are the director. You receive approvals that exceed manager thresholds, anything Annemarie escalates, and a daily digest of bot activity. Consultants only see items for their own tasks.</div>'
            f'<div style="display:flex;align-items:center;gap:8px;font-size:12.5px;color:{RED_D};font-weight:600">{ic("settings",14,RED_D,2)}Notification rules</div></div>'
            f'<div style="background:#fff;border:1px solid {LINE};border-radius:12px;padding:16px;display:flex;flex-direction:column;gap:10px">'
            f'<h3 style="font-size:13px;font-weight:700">This morning\'s sync</h3>'
            + "".join(f'<div style="display:flex;justify-content:space-between;font-size:12.5px;padding:6px 0;border-top:1px solid #F0F0EE"><span style="color:{INK2}">{k}</span><span style="font-weight:600">{v}</span></div>' for k, v in [("MCO tasks read", "1,284"), ("New since yesterday", "11"), ("Parent tasks created", "11"), ("Sub-tasks drafted", "38"), ("Auto-allocated", "8"), ("Held for a person", "3"), ("Errors", "0")])
            + '</div></div>')
    body = f'<div style="flex:1;overflow:hidden;padding:20px 24px;display:flex;flex-direction:column;gap:14px">{head}{tabs}<div style="display:flex;gap:12px;flex:1;min-height:0">{listc}{side}</div></div>'
    return doc("Inbox", shell("Inbox", ["Sales", "Inbox"], body, h=960))

# =============================================================== files + canvas
write("Main.dc.html", my_work())
write("Inbox.dc.html", inbox())
write("TeamBoard.dc.html", team_board())
write("ClientJourney.dc.html", client360())
write("TaskDetail.dc.html", task_detail())
write("Automations.dc.html", automations())
write("Permissions.dc.html", permissions())

GAP_X = 1440 + 120
ROW2 = 1200 + 200
ROW3 = ROW2 + 1300 + 200
canvas = {
    "artboards": [
        {"file": "Main.dc.html", "title": "01 · My Work (consultant)", "x": 0, "y": 0, "w": 1440, "h": 1200},
        {"file": "Inbox.dc.html", "title": "02 · Inbox (director approvals)", "x": GAP_X, "y": 0, "w": 1440, "h": 960},
        {"file": "TeamBoard.dc.html", "title": "03 · Team Board (manager)", "x": GAP_X * 2, "y": 0, "w": 1440, "h": 1120},
        {"file": "ClientJourney.dc.html", "title": "04 · Client 360 · journey", "x": 0, "y": ROW2, "w": 1440, "h": 1100},
        {"file": "TaskDetail.dc.html", "title": "05 · Task detail · parent and sub-tasks", "x": GAP_X, "y": ROW2, "w": 1440, "h": 1290},
        {"file": "Automations.dc.html", "title": "06 · Automations · Grok rules", "x": GAP_X * 2, "y": ROW2, "w": 1440, "h": 1300},
        {"file": "Permissions.dc.html", "title": "07 · Permissions · parent-child tree", "x": 0, "y": ROW3, "w": 1440, "h": 1000},
    ],
    "annotations": [
        {"id": "brief", "x": 0, "y": -260, "w": 520,
         "text": "Care Net AI Tasks Management · Sales dashboard first\n\nMyClinicOnline tasks land in Supabase, Grok bots read them, create parent tasks per client, draft sub-tasks along the client journey and propose who does the work. People approve. Managers oversee through role rights.\n\nJourney stages used everywhere: Prospect · Quote · Onboard · Schedule · Clinic day · Certificates · Invoice · Renewal."},
        {"id": "principles", "x": 600, "y": -260, "w": 520,
         "text": "Design principles\n1. One task model: parent per MCO item, sub-tasks per journey step.\n2. Source is always visible (MCO · Grok · Manual · CRM).\n3. Bots propose, people approve. Client emails never leave without a named approver.\n4. Status vocabulary kept from MCO: New · In progress · Completed, plus Awaiting approval and Overdue.\n5. Same shell for every department: swap the Sales data for Clinic operations, Finance, HR later."},
        {"id": "next", "x": 1200, "y": -260, "w": 480,
         "text": "Open questions for the build\n· Confirm the 20-medical approval threshold and who signs off.\n· Which MCO task types map to which journey stage (draft mapping is in screen 06).\n· Should Grok be allowed to auto-close portal tasks when MCO marks them Completed, or always ask?\n· Team lead layer: needed now or only when the team grows?"},
    ],
    "launch": {"view": "canvas"},
}
with open(os.path.join(OUT, "canvas.json"), "w") as f:
    json.dump(canvas, f, indent=2)
print("wrote canvas.json")
