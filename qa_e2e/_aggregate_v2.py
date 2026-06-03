"""Aggregate V2 results.jsonl into a summary + per-failure evidence (matched
from calls.jsonl). Writes artifacts/aggregated_v2.json and prints a digest."""
import json
import os
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "artifacts")
RES = os.path.join(ART, "results.jsonl")
CALLS = os.path.join(ART, "calls.jsonl")


def load(path):
    out = []
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        out.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
    return out


results = load(RES)
calls = load(CALLS)

# index calls by endpoint substring for evidence lookup (best-effort)
by_sev = defaultdict(lambda: {"pass": 0, "fail": 0})
failures = []
for r in results:
    sev = r.get("severity", "?")
    if r.get("passed"):
        by_sev[sev]["pass"] += 1
    else:
        by_sev[sev]["fail"] += 1
        failures.append(r)

total = len(results)
passed = sum(1 for r in results if r.get("passed"))
failed = total - passed

summary = {
    "total": total,
    "passed": passed,
    "failed": failed,
    "by_severity": {k: dict(v) for k, v in by_sev.items()},
    "failures": failures,
}

with open(os.path.join(ART, "aggregated_v2.json"), "w", encoding="utf-8") as f:
    json.dump(summary, f, ensure_ascii=False, indent=2, default=str)

print(f"TOTAL {total}  PASS {passed}  FAIL {failed}")
print("By severity (pass/fail):")
for sev in ("critical", "major", "minor"):
    v = by_sev.get(sev)
    if v:
        print(f"  {sev:9} pass={v['pass']} fail={v['fail']}")
print("\nFAILURES:")
for r in failures:
    print(f"  [{r.get('severity')}] {r.get('test_id')} {r.get('name')}")
    print(f"       endpoint: {r.get('endpoint')}")
    print(f"       expected: {r.get('expected')}")
    print(f"       observed: {r.get('observed')}")
