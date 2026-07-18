import sys, time
from pathlib import Path
from playwright.sync_api import sync_playwright

URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:5000"
LABEL = sys.argv[2] if len(sys.argv) > 2 else "clients"
OUT = Path(__file__).parent / "artifacts" / "pw"; OUT.mkdir(parents=True, exist_ok=True)

logs = []
with sync_playwright() as p:
    browser = p.chromium.launch(headless=False)
    ctx = browser.new_context(viewport={"width": 420, "height": 900})
    page = ctx.new_page()
    page.on("console", lambda m: logs.append(f"[{m.type}] {m.text[:220]}"))
    page.on("pageerror", lambda e: logs.append(f"[PAGEERROR] {str(e)[:400]}"))
    page.on("requestfailed", lambda r: logs.append(f"[REQFAIL] {r.url[:140]}"))

    page.goto(URL, wait_until="domcontentloaded", timeout=60000)
    time.sleep(6)
    try:
        ph = page.locator("flt-semantics-placeholder")
        if ph.count() > 0:
            ph.first.dispatch_event("click")
            logs.append("[INFO] clicked enable-accessibility")
    except Exception as e:
        logs.append(f"[INFO] enable err {e}")
    time.sleep(20)
    page.screenshot(path=str(OUT / f"{LABEL}_console_wait.png"))
    n = page.evaluate("() => { let c=0; function w(r){r.querySelectorAll('*').forEach(e=>{c++; if(e.shadowRoot) w(e.shadowRoot);});} w(document); return c; }")
    print(f"DOM nodes (pierced) after 26s: {n}")
    print(f"=== ALL CONSOLE ({len(logs)}) ===")
    for l in logs:
        print(" ", l)
    browser.close()
