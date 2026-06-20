import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from playwright.sync_api import sync_playwright
from pw_driver import FlutterApp

URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:5000"
LABEL = sys.argv[2] if len(sys.argv) > 2 else "clients"

with sync_playwright() as p:
    browser = p.chromium.launch(headless=False)
    ctx = browser.new_context(viewport={"width": 420, "height": 900})
    page = ctx.new_page()
    page.on("pageerror", lambda e: print(f"[pageerror] {str(e)[:200]}"))
    app = FlutterApp(page, LABEL)
    app.boot(URL)
    app.shot("login_screen")
    app.dump()
    browser.close()
print("=== LOGIN TEST DONE ===")
