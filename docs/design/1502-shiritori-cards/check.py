#!/usr/bin/python3
"""外周テスト: 行 0/39・列 0/39 が . か K のみ / 全行 40 文字・40 行 / 未定義の文字なし / K が 3A2A2A。"""
import json, sys

import os
OUT = os.path.dirname(os.path.abspath(__file__))
data = json.load(open(f"{OUT}/sprites_new.json", encoding="utf-8"))
ok = True
for name, sp in data.items():
    rows, pal = sp["rows"], sp["palette"]
    errs = []
    if len(rows) != 40:
        errs.append(f"rows={len(rows)}")
    for i, r in enumerate(rows):
        if len(r) != 40:
            errs.append(f"row {i} len={len(r)}")
    if pal.get("K") != "3A2A2A":
        errs.append("K != 3A2A2A")
    used = {ch for r in rows for ch in r if ch != "."}
    undefined = used - set(pal)
    if undefined:
        errs.append(f"undefined {sorted(undefined)}")
    edge = set(rows[0]) | set(rows[-1]) | {r[0] for r in rows} | {r[-1] for r in rows}
    bad = edge - {".", "K"}
    if bad:
        errs.append(f"edge has {sorted(bad)}")
    opaque = sum(1 for r in rows for ch in r if ch != ".")
    status = "OK " if not errs else "NG "
    ok &= not errs
    print(f"{status}{name:12s} colors={len(pal):2d} opaque={opaque:4d}/1600 {' ; '.join(errs)}")
print("ALL OK" if ok else "FAILED")
sys.exit(0 if ok else 1)
