import sys, time
from pathlib import Path
from playwright.sync_api import sync_playwright

URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:5000"
LABEL = sys.argv[2] if len(sys.argv) > 2 else "clients"
OUT = Path(__file__).parent / "artifacts" / "pw"; OUT.mkdir(parents=True, exist_ok=True)

PIERCE_JS = r"""
() => {
  const hits = [];
  let nodeCount = 0;
  const tags = {};
  function walk(root) {
    const els = root.querySelectorAll('*');
    els.forEach(el => {
      nodeCount++;
      const t = el.tagName.toLowerCase();
      tags[t] = (tags[t]||0)+1;
      const aria = el.getAttribute && el.getAttribute('aria-label');
      const role = el.getAttribute && el.getAttribute('role');
      if (t === 'input' || t === 'textarea' || t === 'flt-semantics-placeholder' ||
          aria || role || t === 'button') {
        const r = el.getBoundingClientRect();
        hits.push({tag:t, aria:aria||'', role:role||'',
                   type:(el.getAttribute&&el.getAttribute('type'))||'',
                   text:(el.textContent||'').trim().slice(0,40),
                   x:Math.round(r.x), y:Math.round(r.y), w:Math.round(r.width), h:Math.round(r.height)});
      }
      if (el.shadowRoot) walk(el.shadowRoot);
    });
  }
  walk(document);
  const topTags = Object.entries(tags).sort((a,b)=>b[1]-a[1]).slice(0,15);
  return {nodeCount, topTags, hits};
}
"""

logs = []
with sync_playwright() as p:
    browser = p.chromium.launch(headless=False)
    ctx = browser.new_context(viewport={"width": 420, "height": 900})
    page = ctx.new_page()
    page.on("console", lambda m: logs.append(f"[{m.type}] {m.text[:200]}"))
    page.on("pageerror", lambda e: logs.append(f"[PAGEERROR] {str(e)[:300]}"))
    page.on("requestfailed", lambda r: logs.append(f"[REQFAIL] {r.url[:120]} {r.failure}"))

    print(f"=== GOTO {URL} ===")
    page.goto(URL, wait_until="domcontentloaded", timeout=60000)
    time.sleep(20)
    page.screenshot(path=str(OUT / f"{LABEL}_diag.png"))

    res = page.evaluate(PIERCE_JS)
    print(f"DOM nodes (shadow-pierced): {res['nodeCount']}")
    print("top tags:", res["topTags"])
    print(f"=== HITS: {len(res['hits'])} ===")
    for h in res["hits"][:60]:
        print(f"  <{h['tag']}> aria={h['aria']!r} role={h['role']!r} type={h['type']!r} text={h['text']!r} @({h['x']},{h['y']} {h['w']}x{h['h']})")

    print("=== CONSOLE/ERRORS (last 40) ===")
    for l in logs[-40:]:
        print(" ", l)
    browser.close()
print("=== DIAG DONE ===")
