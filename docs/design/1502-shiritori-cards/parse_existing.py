#!/usr/bin/python3
"""既存 30 種を ObjectCardArt.swift / ShiritoriCard.swift からパースして JSON に落とす（読み取り専用）。"""
import json, os, re, sys

OUT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(OUT, "..", "..", ".."))

src = open(f"{REPO}/Packages/GameKit/Sources/Core/ObjectCardArt.swift", encoding="utf-8").read()
sprites = {}
order = []
for m in re.finditer(r"static let (\w+) = PixelSprite\(\s*rows: \[(.*?)\],\s*palette: \[(.*?)\]\s*\)", src, re.S):
    name, rows_s, pal_s = m.group(1), m.group(2), m.group(3)
    rows = re.findall(r'"([^"]*)"', rows_s)
    pal = {k: f"{int(v, 16):06X}" for k, v in re.findall(r'"(.)":\s*0x([0-9A-Fa-f]+)', pal_s)}
    sprites[name] = {"rows": rows, "palette": pal}
    order.append(name)

deck_src = open(f"{REPO}/Packages/GameKit/Sources/GameShiritori/ShiritoriCard.swift", encoding="utf-8").read()
deck = re.findall(r'ShiritoriCard\(\.(\w+), "([^"]+)"', deck_src)
readings = {k: r for k, r in deck}

json.dump({"order": order, "sprites": sprites, "readings": readings},
          open(f"{OUT}/sprites_existing.json", "w", encoding="utf-8"), ensure_ascii=False, indent=0)
print(len(order), "sprites;", len(readings), "readings")
for n in order:
    s = sprites[n]
    assert len(s["rows"]) == 40 and all(len(r) == 40 for r in s["rows"]), n
    print(n, readings.get(n), "colors:", len(s["palette"]))
