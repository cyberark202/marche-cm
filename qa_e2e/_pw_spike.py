# Spike Playwright v2 : boot-aware + SwiftShader WebGL + activation semantique.
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:5000"
LABEL = sys.argv[2] if len(sys.argv) > 2 else "clients"
OUT = Path(__file__).parent / "artifacts" / "pw"
OUT.mkdir(parents=True, exist_ok=True)

CHROME_ARGS = []  # rendu GPU headless par defaut (swiftshader cassait CanvasKit)

DUMP_JS = r"""
() => {
  const out = [];
  const sel = 'input, textarea, [role], [aria-label], flt-semantics-placeholder';
  document.querySelectorAll(sel).forEach((el) => {
    const r = el.getBoundingClientRect();
    out.push({
      tag: el.tagName.toLowerCase(),
      role: el.getAttribute('role') || '',
      aria: el.getAttribute('aria-label') || '',
      type: el.getAttribute('type') || '',
      text: (el.textContent || '').trim().slice(0, 50),
      x: Math.round(r.x), y: Math.round(r.y),
      w: Math.round(r.width), h: Math.round(r.height),
    });
  });
  return out;
}
"""


def wait_for(page, js_cond, timeout=30, every=1.0, label=""):
    end = time.time() + timeout
    while time.time() < end:
        if page.evaluate(js_cond):
            return True
        time.sleep(every)
    print(f"  [wait timeout] {label}")
    return False


with sync_playwright() as p:
    browser = p.chromium.launch(headless=False, args=CHROME_ARGS)
    ctx = browser.new_context(viewport={"width": 420, "height": 900}, device_scale_factor=1)
    page = ctx.new_page()
    page.on("console", lambda m: print(f"[console.{m.type}] {m.text[:160]}") if m.type in ("error", "warning") else None)
    page.on("pageerror", lambda e: print(f"[pageerror] {str(e)[:200]}"))

    print(f"=== GOTO {URL} ===")
    page.goto(URL, wait_until="domcontentloaded", timeout=60000)

    # 1) Attendre le boot Dart : le placeholder a11y apparait quand le 1er frame est pose
    ok = wait_for(page, "() => !!document.querySelector('flt-semantics-placeholder')",
                  timeout=45, label="flt-semantics-placeholder present")
    print("placeholder present:", ok)
    time.sleep(2)
    page.screenshot(path=str(OUT / f"{LABEL}_01_loaded.png"))

    # 2) Activer la semantique
    clicked = page.evaluate("""() => {
      const ph = document.querySelector('flt-semantics-placeholder');
      if (ph) { ph.click(); return true; } return false;
    }""")
    print("semantics enable clicked:", clicked)

    # 3) Attendre que l'arbre semantique se peuple (plus d'1 noeud avec role/aria)
    wait_for(page, "() => document.querySelectorAll('[role],[aria-label],input,textarea').length > 3",
             timeout=15, label="semantics tree populated")
    time.sleep(1.5)
    page.screenshot(path=str(OUT / f"{LABEL}_02_semantics.png"))

    items = page.evaluate(DUMP_JS)
    vis = [x for x in items if x["w"] > 0 and x["h"] > 0]
    print(f"=== INTERACTABLES: {len(items)} total, {len(vis)} visible (w/h>0) ===")
    for x in items[:80]:
        flag = "" if (x["w"] > 0 and x["h"] > 0) else " [hidden]"
        print(f"  <{x['tag']}> role={x['role']!r} aria={x['aria']!r} type={x['type']!r} "
              f"text={x['text']!r} @({x['x']},{x['y']} {x['w']}x{x['h']}){flag}")

    browser.close()
print("=== SPIKE DONE ===")
