import sys, time
from pathlib import Path
from playwright.sync_api import sync_playwright

URL = "http://127.0.0.1:5000"
OUT = Path(__file__).parent / "artifacts" / "pw"; OUT.mkdir(parents=True, exist_ok=True)

# Dump shadow-piercant : capture aria/role/input + feuilles de texte (labels boutons).
DUMP = r"""
() => {
  const out=[];
  function leafText(el){
    let t='';
    el.childNodes.forEach(n=>{ if(n.nodeType===3) t+=n.textContent; });
    return t.trim();
  }
  function w(root){
    root.querySelectorAll('*').forEach(el=>{
      const tag=el.tagName.toLowerCase();
      const aria=el.getAttribute&&el.getAttribute('aria-label')||'';
      const role=el.getAttribute&&el.getAttribute('role')||'';
      const lt=leafText(el);
      if(tag==='input'||tag==='textarea'||aria||role||((lt&&lt.length<=60)&&['span','p','a','button','flt-semantics','h1','h2'].includes(tag))){
        const r=el.getBoundingClientRect();
        if(r.width>0&&r.height>0)
          out.push({tag,aria,role,type:(el.getAttribute&&el.getAttribute('type'))||'',text:lt.slice(0,60),x:Math.round(r.x),y:Math.round(r.y),w:Math.round(r.width),h:Math.round(r.height)});
      }
      if(el.shadowRoot) w(el.shadowRoot);
    });
  }
  w(document); return out;
}
"""

def dump(page, tag):
    items = page.evaluate(DUMP)
    print(f"--- DUMP [{tag}] {len(items)} visible elements ---")
    for x in items[:70]:
        print(f"   <{x['tag']}> aria={x['aria']!r} role={x['role']!r} type={x['type']!r} text={x['text']!r} @({x['x']},{x['y']} {x['w']}x{x['h']})")
    return items

def enable_sem(page):
    ph = page.locator("flt-semantics-placeholder")
    if ph.count() > 0:
        ph.first.dispatch_event("click")

with sync_playwright() as p:
    browser = p.chromium.launch(headless=False)
    ctx = browser.new_context(viewport={"width": 420, "height": 900}, service_workers="block")
    page = ctx.new_page()
    page.on("pageerror", lambda e: print(f"[pageerror] {str(e)[:200]}"))

    print("=== BOOT ===")
    page.goto(URL, wait_until="domcontentloaded", timeout=60000)
    time.sleep(3)
    enable_sem(page)
    time.sleep(7)  # laisser le splash s'auto-completer -> PublicHomePage
    page.screenshot(path=str(OUT / "clients_01_home.png"))
    dump(page, "HOME")

    print("=== TAP 'Se connecter' (home) ===")
    try:
        page.get_by_text("Se connecter", exact=True).first.click(timeout=8000, force=True)
    except Exception as e:
        print("tap login err:", e)
    time.sleep(6)  # splash + AuthPage
    enable_sem(page)
    time.sleep(1.5)
    page.screenshot(path=str(OUT / "clients_02_authpage.png"))
    items = dump(page, "AUTH")

    print("=== FILL credentials ===")
    inputs = page.locator("input, textarea")
    print("inputs found:", inputs.count())
    if inputs.count() >= 2:
        inputs.nth(0).click(force=True); inputs.nth(0).fill("buyer@marche-cm.local")
        inputs.nth(1).click(force=True); inputs.nth(1).fill("ChangeMe123!")
        time.sleep(1)
        page.screenshot(path=str(OUT / "clients_03_filled.png"))
        print("filled email+password")
    else:
        print("!! pas assez d'inputs, fallback coords requis")

    print("=== SUBMIT ===")
    try:
        page.get_by_text("Se connecter").last.click(timeout=8000, force=True)
    except Exception as e:
        print("submit err:", e)
    time.sleep(6)
    page.screenshot(path=str(OUT / "clients_04_after_login.png"))
    dump(page, "AFTER_LOGIN")

    browser.close()
print("=== DONE ===")
