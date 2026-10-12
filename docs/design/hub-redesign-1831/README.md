# ハブ刷新モック（issue #1831）

issue #1831 の検討用に作った、ホーム（ハブ）画面刷新のモック一式。案0（現状）〜案4b の
HTML/PNG と、タイル絵の生成スクリプトをまとめて保存する。

## 会長決裁（2026-10-12）

**案1「絵のタイル2列」＋ 案4b「カテゴリーのチップ」で実装する。**

- タイル部分は案1の「アプリ内の絵をそのまま使った正方形〜縦長タイルの2列グリッド」を採用
- カテゴリー導線は案4b の「チップ（横スクロールのピル型ボタン）でカテゴリーに絞り込む」方式を採用
- 案2（画像セクション1列/2列）・案3（おすすめヒーロー3列＋カテゴリー入口）は不採用

## ファイル一覧と各案の対応

| ファイル | 内容 |
|---|---|
| `hub-redesign/00-current.png` | 案0: 現状のハブ画面（比較用スクショ） |
| `hub-redesign/01-picture-tiles.html` / `.png` | **案1（採用）**: 絵のタイル2列 |
| `hub-redesign/se-01-picture-tiles.html` / `.png` | 案1の iPhone SE 幅での見え方確認 |
| `hub-redesign/02a-image-section-1col.html` / `.png` | 案2a: 画像セクション1列（不採用） |
| `hub-redesign/02b-image-section-2col.html` / `.png` | 案2b: 画像セクション2列（不採用） |
| `hub-redesign/03-recommended-hero-3col.html` / `.png` | 案3: おすすめヒーロー＋3列グリッド（不採用） |
| `hub-redesign/se-03-recommended-hero-3col.html` / `.png` | 案3の iPhone SE 幅での見え方確認 |
| `hub-redesign/04a-category-entrance.html` / `.png` | 案4a: カテゴリー入口カード（不採用） |
| `hub-redesign/04b-category-chips.html` / `.png` | **案4b（採用）**: カテゴリーのチップ |
| `hub-redesign/se-04b-category-chips.html` / `.png` | 案4b の iPhone SE 幅での見え方確認 |
| `hub-redesign/assets/` | 上記 HTML が参照する素材（タイル絵・スプライト・ヒーロー画像） |
| `tiles/tiles.py` | 実機スクショを元にタイル絵（JPG）を切り出し合成するスクリプト |
| `tiles/tile_art.py` | HTML/SVG を組んで Chrome ヘッドレスでレンダリングし、タイル絵（PNG）を生成するスクリプト。**AI 生成は使っていない** |
| `tiles/tiles_sheet3.png` | `tile_art.py` 系で生成したタイル絵の確認用シート |
| `mock-build.diff` | モック作成時に当てた作業用パッチ（参考用） |

比較用の合成画像 `compare.png` / `compare-se.png`（各案を並べた一覧画像）はサイズが大きいため、
このディレクトリには同梱していない。GitHub の Release アセットとして以下に保存している。

- https://github.com/hiroky1983/game_collection/releases/download/ui-review/1831-compare.png
- https://github.com/hiroky1983/game_collection/releases/download/ui-review/1831-compare-se.png

## タイル絵は AI 不使用

タイルの絵（`hub-redesign/assets/tiles/*.png` および `tiles/` 配下のスクリプトが生成するもの）は
AI 画像生成を使っていない。`tiles/tile_art.py` が HTML/SVG でアプリ内の部品（トランプ・石・駒・牌・
ドット絵スプライト等）を組み直し、色の強い背景の上に大きく・傾けて・影付きで配置し、Chrome の
ヘッドレスモードでレンダリングして PNG 化している（`tiles/tiles.py` は実機スクショからの切り出し版）。
実装時にタイル絵を作り直す・差し替える場合も、同じ方式（AI 生成なし）を踏襲すること。

## 実装時の注意: 荷物運びパズルのタイルは差し替えが必要

`hub-redesign/assets/tiles/ojisanpuzzle.png`（および生成元の `tiles/tile_art.py` 内の
`TILES["ojisanpuzzle"]`）で使っている荷物の絵は、荷物運びパズルの**旧仕様時代の古い絵**
（`luggage_beer.png` 等、`hub-redesign/assets/sprites/` 配下の古いスプライト）を使っている。
実装時はこのタイルの絵を、現行のゲーム内で使っている荷物・おじさんの顔の絵に差し替えること。

## パスについて（コピー時に修正済み）

- `hub-redesign/*.html` および `hub-redesign/assets/tiles/*.html` は元から相対パス参照のみで、
  絶対パスの修正は不要だった。
- `tiles/tiles.py` と `tiles/tile_art.py` は、元は作業用スクラッチパッド
  （`/private/tmp/claude-501/.../scratchpad`）の絶対パスをハードコードしていたが、
  スクリプト自身の位置（`os.path.dirname(os.path.abspath(__file__))`）を基準にした相対パスに
  書き換え済み。再実行する場合、`tiles/` の1つ上の階層（このディレクトリ）を基準に
  `hub-redesign/assets/tiles/` へ出力する。
- `tiles/tiles.py` が入力に使う実機/シミュレータのスクリーンショット一式（元は `scratchpad/shots/`）は
  このモック一式には同梱していない。`tiles.py` を再実行する場合は、このディレクトリに `shots/` を
  別途用意すること。
