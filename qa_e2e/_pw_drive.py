"""Pilote a actions pour apps Flutter web (build release statique).

Usage: python qa_e2e\_pw_drive.py <url> <label> <actions_file> [keep_open_s]

Le fichier d'actions contient une action par ligne :
  wait:<s>
  shot:<name>
  dump
  tap_text:<texte>            (clic element dont le texte == texte, sinon contient)
  tap_label:<aria>           (clic element par aria-label)
  fill_label:<aria>=<valeur> (remplir input par aria-label)
  fill_input:<idx>=<valeur>  (remplir le Nieme input)
  tap_input:<idx>            (focus le Nieme input)
  type:<valeur>              (taper au clavier dans l'element focus)
  upload:<idx>=<chemin>      (set_input_files sur le Nieme input file)
  press:<Key>                (ex: Enter, Tab)
Les lignes vides et celles commençant par # sont ignorees.
"""
import sys, time
from pathlib import Path
from playwright.sync_api import sync_playwright

URL, LABEL, ACTIONS = sys.argv[1], sys.argv[2], sys.argv[3]
KEEP = int(sys.argv[4]) if len(sys.argv) > 4 else 0
OUT = Path(__file__).parent / "artifacts" / "pw"; OUT.mkdir(parents=True, exist_ok=True)

DUMP = r"""
() => {
  const out=[];
  function leafText(el){let t='';el.childNodes.forEach(n=>{if(n.nodeType===3)t+=n.textContent;});return t.trim();}
  function w(root){
    root.querySelectorAll('*').forEach(el=>{
      const tag=el.tagName.toLowerCase();
      const aria=el.getAttribute&&el.getAttribute('aria-label')||'';
      const role=el.getAttribute&&el.getAttribute('role')||'';
      const lt=leafText(el);
      if(tag==='input'||tag==='textarea'||aria||role||((lt&&lt.length<=70)&&['span','p','a','button','flt-semantics','h1','h2','li'].includes(tag))){
        const r=el.getBoundingClientRect();
        if(r.width>0&&r.height>0)
          out.push({tag,aria,role,type:(el.getAttribute&&el.getAttribute('type'))||'',text:lt.slice(0,70),x:Math.round(r.x),y:Math.round(r.y),w:Math.round(r.width),h:Math.round(r.height)});
      }
      if(el.shadowRoot) w(el.shadowRoot);
    });
  }
  w(document); return out;
}
"""

def do_dump(page, tag=""):
    items = page.evaluate(DUMP)
    print(f"  -- DUMP {tag}: {len(items)} elems | inputs={page.locator('input,textarea').count()}")
    for x in items[:90]:
        print(f"     <{x['tag']}> aria={x['aria']!r} role={x['role']!r} type={x['type']!r} text={x['text']!r} @({x['x']},{x['y']} {x['w']}x{x['h']})")

def enable_sem(page):
    ph = page.locator("flt-semantics-placeholder")
    if ph.count() > 0:
        ph.first.dispatch_event("click")

with sync_playwright() as p:
    browser = p.chromium.launch(headless=False)
    ctx = browser.new_context(viewport={"width": 420, "height": 900}, service_workers="block")
    page = ctx.new_page()
    page.on("pageerror", lambda e: print(f"  [pageerror] {str(e)[:120]}"))
    page.on("dialog", lambda d: d.accept())

    def boot_ready():
        deadline = time.time() + 35
        while time.time() < deadline:
            enable_sem(page)
            time.sleep(1.5)
            if page.locator("flt-semantics, input, textarea, [role=button], [role=group]").count() >= 2:
                return True
        return False

    print(f"=== BOOT {LABEL} {URL} ===")
    page.goto(URL, wait_until="domcontentloaded", timeout=60000)
    time.sleep(2)
    ok = boot_ready()
    if not ok:
        print("  [boot] page blanche -> reload de secours")
        page.reload(wait_until="domcontentloaded", timeout=60000)
        time.sleep(2)
        ok = boot_ready()
    print(f"  [boot] ready={ok}")
    time.sleep(3)

    for raw in Path(ACTIONS).read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        try:
            cmd, _, arg = line.partition(":")
            if cmd == "wait":
                time.sleep(float(arg))
            elif cmd == "shot":
                page.screenshot(path=str(OUT / f"{LABEL}_{arg}.png")); print(f"  shot {arg}")
            elif cmd == "dump":
                do_dump(page, arg)
            elif cmd == "tap_text":
                try:
                    page.get_by_text(arg, exact=True).first.click(timeout=6000, force=True)
                except Exception:
                    page.get_by_text(arg).first.click(timeout=6000, force=True)
                print(f"  tap_text {arg!r}")
            elif cmd == "tap_label":
                page.get_by_label(arg).first.click(timeout=6000, force=True); print(f"  tap_label {arg!r}")
            elif cmd == "fill_label":
                k, _, v = arg.partition("=")
                loc = page.get_by_label(k).first
                loc.click(force=True, timeout=6000); loc.fill(v, timeout=6000); print(f"  fill_label {k!r}<-{v!r}")
            elif cmd == "fill_input":
                k, _, v = arg.partition("=")
                inp = page.locator("input,textarea").nth(int(k))
                inp.click(force=True); inp.fill(v); print(f"  fill_input#{k}<-{v!r}")
            elif cmd == "tap_input":
                page.locator("input,textarea").nth(int(arg)).click(force=True); print(f"  tap_input#{arg}")
            elif cmd == "type":
                page.keyboard.type(arg); print(f"  type {arg!r}")
            elif cmd == "press":
                page.keyboard.press(arg); print(f"  press {arg}")
            elif cmd == "tap_xy":
                xs, _, ys = arg.partition(",")
                page.mouse.click(float(xs), float(ys)); print(f"  tap_xy {xs},{ys}")
            elif cmd == "scroll":
                dx, _, dy = arg.partition(",")
                page.mouse.move(210, 450)
                page.mouse.wheel(float(dx or 0), float(dy or 0)); print(f"  scroll {dx},{dy}")
            elif cmd == "hover":
                xs, _, ys = arg.partition(",")
                page.mouse.move(float(xs), float(ys)); print(f"  hover {xs},{ys}")
            elif cmd == "resize":
                w, _, h = arg.partition(",")
                page.set_viewport_size({"width": int(w), "height": int(h)}); print(f"  resize {w}x{h}")
            elif cmd == "upload":
                k, _, v = arg.partition("=")
                page.locator("input[type=file]").nth(int(k)).set_input_files(v); print(f"  upload#{k}<-{v}")
            elif cmd == "pick":
                k, _, v = arg.partition("=")
                with page.expect_file_chooser(timeout=12000) as fc:
                    try:
                        page.get_by_text(k, exact=True).first.click(timeout=6000, force=True)
                    except Exception:
                        page.get_by_text(k).first.click(timeout=6000, force=True)
                fc.value.set_files(v)
                print(f"  pick {k!r} <- {v}")
            else:
                print(f"  ?? unknown action {line!r}")
        except Exception as e:
            print(f"  !! action FAILED {line!r}: {str(e)[:160]}")
            do_dump(page, "on-fail")
    if KEEP:
        time.sleep(KEEP)
    browser.close()
print("=== DRIVE DONE ===")
