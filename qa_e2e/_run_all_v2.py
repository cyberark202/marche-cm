"""Mission 1 — V2 anti-regression runner. Runs every E2E batch in order against
the prod-connected local backend, tolerant of per-batch exceptions so one crash
never hides the rest. Results stream to artifacts/results.jsonl via qa.record()."""
import os
import sys
import traceback

# Must be set BEFORE importing qa (qa reads QA_BASE at import time).
os.environ.setdefault("QA_BASE", "http://127.0.0.1:8000")
os.environ.setdefault("QA_TRANSIT_ID", "7")

HERE = os.path.dirname(os.path.abspath(__file__))
os.chdir(HERE)
sys.path.insert(0, HERE)

import qa
qa.reset_results()
print(f"QA_BASE = {qa.BASE}")

MODULES = [
    "t1_auth", "t2_profile", "t3_products", "t5_wallet", "t6_orders",
    "t7_logistics_disputes", "t8_chat_notif", "t9_admin", "t10_security",
]

state = {}
for name in MODULES:
    print("\n" + "=" * 70)
    print(f"### RUN {name}")
    print("=" * 70)
    try:
        mod = __import__(name)
        out = mod.main()
        if isinstance(out, dict):
            state.update(out)
    except Exception:
        print(f"!!! {name} CRASHED:")
        traceback.print_exc()

print("\n### DONE. Shared state:", state)
