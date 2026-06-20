# Exploration: boot une app Flutter web, active la semantique, dump + capture.
# Usage: python qa_e2e\_pw_snap.py <url> <label> [wait_s]
import sys, time
from pathlib import Path
from playwright.sync_api import sync_playwright

URL = sys.argv[1]
LABEL = sys.argv[2]
WAIT = int(sys.argv[3]) if len(sys.argv) > 3 else 8
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

with sync_playwright() as p:
    browser = p.chromium.launch(headless=False)
    ctx = browser.new_context(viewport={"width": 420, "height": 900}, service_workers="block")
    page = ctx.new_page()
    page.on("pageerror", lambda e: None)
    page.goto(URL, wait_until="domcontentloaded", timeout=60000)
    time.sleep(3)
    ph = page.locator("flt-semantics-placeholder")
    if ph.count() > 0:
        ph.first.dispatch_event("click")
    time.sleep(WAIT)
    page.screenshot(path=str(OUT / f"{LABEL}_snap.png"))
    items = page.evaluate(DUMP)
    print(f"[{LABEL}] {len(items)} visible elements | inputs={page.locator('input,textarea').count()}")
    for x in items[:90]:
        print(f"  <{x['tag']}> aria={x['aria']!r} role={x['role']!r} type={x['type']!r} text={x['text']!r} @({x['x']},{x['y']} {x['w']}x{x['h']})")
    browser.close()
print("DONE")
