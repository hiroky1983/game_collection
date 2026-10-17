# カードしりとり 新しい札 20 枚のドット絵モック（#1502）

会長の修正指示（2026-09-28）「画像データのモックを載せてください」に応える成果物。実装は札の案の決裁後（#1502）。

- `gen.py` — 生成器。図形を部品ごとに描き、部品単位で縁取り `K` を付けて重ねる（`ObjectCardSprites` と同じ手順）。実行すると `sprites_new.json` を書く
- `sprites_new.json` — 新 20 種の rows / palette / 表読み（識別子は仮）
- `check.py` — 外周テスト（40×40・外周は `.` か `K` のみ・未定義文字なし）
- `parse_existing.py` — `ObjectCardArt.swift` から既存 30 種を読み `sprites_existing.json` を書く（一覧の比較用。コミットはしない）
- `render.py` / `sheets.py` / `sheet_ura.py` — 一覧 PNG（`sheet-new` / `sheet-all` / `sheet-ura`）を書く。出力先はこのディレクトリ（コミットしない。掲載は GitHub リリース `ui-review` の `1502-shiritori-*.png`）
- `check_readings.py` — 裏読みの検算（`ShiritoriRulesTests` の 3 制約を Python で写したもの。Swift 側の正典はテスト）

実行は `/usr/bin/python3`（PIL が要る）。
