"""Driver Playwright pour piloter les apps Flutter web (build release statique).

Flutter rend dans un shadow root OUVERT : les locators Playwright le percent
automatiquement, mais document.querySelector (raw) non. On utilise donc les
locators Playwright pour interagir, et un JS shadow-piercant juste pour le dump.
"""
import time
from pathlib import Path

ART = Path(__file__).parent / "artifacts" / "pw"
ART.mkdir(parents=True, exist_ok=True)

PIERCE_JS = r"""
() => {
  const hits = []; const tags = {}; let n = 0;
  function walk(root) {
    root.querySelectorAll('*').forEach(el => {
      n++; const t = el.tagName.toLowerCase(); tags[t]=(tags[t]||0)+1;
      const aria = el.getAttribute && el.getAttribute('aria-label');
      const role = el.getAttribute && el.getAttribute('role');
      if (t==='input'||t==='textarea'||t==='flt-semantics-placeholder'||aria||role) {
        const r = el.getBoundingClientRect();
        hits.push({tag:t, aria:aria||'', role:role||'',
          type:(el.getAttribute&&el.getAttribute('type'))||'',
          val:(el.value!==undefined?String(el.value).slice(0,30):''),
          text:(el.textContent||'').trim().slice(0,40),
          x:Math.round(r.x),y:Math.round(r.y),w:Math.round(r.width),h:Math.round(r.height)});
      }
      if (el.shadowRoot) walk(el.shadowRoot);
    });
  }
  walk(document);
  return {n, hits};
}
"""


class FlutterApp:
    def __init__(self, page, label):
        self.page = page
        self.label = label
        self._step = 0

    def boot(self, url, timeout=60):
        print(f"[{self.label}] GOTO {url}")
        self.page.goto(url, wait_until="domcontentloaded", timeout=timeout * 1000)
        end = time.time() + timeout
        while time.time() < end:
            if self.page.locator("flt-semantics-placeholder").count() > 0:
                break
            if self.page.locator("flt-glass-pane, flutter-view").count() > 0:
                break
            time.sleep(0.5)
        time.sleep(2)
        self.enable_semantics()
        time.sleep(1.5)
        return self

    def enable_semantics(self):
        try:
            ph = self.page.locator("flt-semantics-placeholder")
            if ph.count() > 0:
                ph.first.dispatch_event("click")
                print(f"[{self.label}] semantics enabled")
                return True
        except Exception as e:
            print(f"[{self.label}] enable_semantics err: {e}")
        return False

    def dump(self, limit=80):
        res = self.page.evaluate(PIERCE_JS)
        hits = res["hits"]
        print(f"[{self.label}] DOM={res['n']} nodes | {len(hits)} semantic hits:")
        for h in hits[:limit]:
            print(f"   <{h['tag']}> aria={h['aria']!r} role={h['role']!r} type={h['type']!r} "
                  f"val={h['val']!r} text={h['text']!r} @({h['x']},{h['y']} {h['w']}x{h['h']})")
        return hits

    def shot(self, name=""):
        self._step += 1
        fn = ART / f"{self.label}_{self._step:02d}_{name}.png"
        self.page.screenshot(path=str(fn))
        print(f"[{self.label}] shot -> {fn.name}")
        return str(fn)

    def tap_label(self, label, exact=False, timeout=8000):
        loc = self.page.get_by_label(label, exact=exact)
        loc.first.click(timeout=timeout, force=True)
        print(f"[{self.label}] tap label={label!r}")

    def tap_text(self, text, exact=False, timeout=8000):
        loc = self.page.get_by_text(text, exact=exact)
        loc.first.click(timeout=timeout, force=True)
        print(f"[{self.label}] tap text={text!r}")

    def fill_label(self, label, value, exact=False, timeout=8000):
        loc = self.page.get_by_label(label, exact=exact)
        loc.first.click(timeout=timeout, force=True)
        loc.first.fill(value, timeout=timeout)
        print(f"[{self.label}] fill label={label!r} <- {value!r}")

    def type_into_nth_input(self, idx, value):
        inp = self.page.locator("input, textarea").nth(idx)
        inp.click(force=True)
        inp.fill(value)
        print(f"[{self.label}] typed into input#{idx} <- {value!r}")
