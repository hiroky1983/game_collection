#!/usr/bin/python3
"""裏読みを持つ札（既存の ねこ + 新しい案の 10 枚）を「表読み → 裏読み」で並べる。"""
import json
from render import sheet, OUT

new = json.load(open(f"{OUT}/sprites_new.json", encoding="utf-8"))
old = json.load(open(f"{OUT}/sprites_existing.json", encoding="utf-8"))
by_reading = {old["readings"][n]: old["sprites"][n] for n in old["order"]}
by_reading.update({sp["reading"]: sp for sp in new.values()})

pairs = [("ねこ", "にゃんこ"), ("かめ", "うみがめ"), ("くま", "こぐま"), ("きつね", "こぎつね"),
         ("まふらー", "すかーふ"), ("にく", "すてーき"), ("きのこ", "しいたけ"), ("うし", "ぎゅう"),
         ("すし", "にぎり"), ("にわとり", "こっこ"), ("くつ", "しゅーず")]
items = [(by_reading[a], f"{a} → {b}") for a, b in pairs]
sheet(items, 4, 6, f"{OUT}/sheet-ura.png", label_size=22)
print("sheet-ura.png")
