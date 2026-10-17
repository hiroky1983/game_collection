#!/usr/bin/python3
"""sheet-new.png（新規 20 種・5×4・6 倍）と sheet-all.png（既存 30 + 新規 20・10×5・4 倍）を出す。"""
import json
from render import sheet, OUT

new = json.load(open(f"{OUT}/sprites_new.json", encoding="utf-8"))
old = json.load(open(f"{OUT}/sprites_existing.json", encoding="utf-8"))

new_items = [(sp, sp["reading"]) for sp in new.values()]
sheet(new_items, 5, 6, f"{OUT}/sheet-new.png", label_size=22)

old_items = [(old["sprites"][n], old["readings"][n]) for n in old["order"]]
sheet(old_items + new_items, 10, 4, f"{OUT}/sheet-all.png", label_size=18, cell_pad=8)
print("sheet-new.png / sheet-all.png")
