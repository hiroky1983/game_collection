# App Store スクリーンショット（v1.1.12）

v1.1.12 の ASC（App Store Connect）入稿スクショの最終の並び。2026-10-17 に API で入稿し、読み戻して
4 セットとも 10 枚・順番どおり・全枚 `COMPLETE` を確認済み。**審査提出はしていない**。

## 0. 経緯と決裁（#2271）

- v1.1.11 公開（2026-10-12）からのダウンロード急落の対策として、柵越えおじさんを 1 枚に減らし、1〜3 枚目でゲーム集だと
  分かる並びにする（会長決裁 2026-10-17）。
- **ja の iPhone は会長が ASC で自分で並べ替えた**（2026-10-17）。社長側で変えたのは **1 枚目のハブの画像だけ**
  （v1.1.12 の新しいハブに差し替え）。2〜10 枚目は会長が入れた画像のまま触っていない。
- ja の iPad と英語版（en-US）の iPhone・iPad は、この ja iPhone と**同じ 10 枚・同じ順**にそろえた。
- 「体験版」の文字はどの枚にも写っていない（#2338。ハブの柵越えのタイル・打席の画面とも印なし）。

## 1. 並び（4 セット共通の順）

| # | 画面 | ja iPhone（6.9"） | ja iPad（13"） | en-US iPhone（6.9"） | en-US iPad（13"） |
|---|---|---|---|---|---|
| 1 | ハブ | **v1.1.12 で撮影** `01-hub.png` | **v1.1.12 で撮影** `01-hub.png` | 撮影 `01-hub.png` | 撮影 `01-hub.png` |
| 2 | ナンプレ | 会長の画像 `03-sudoku.png` | v1.1.11 の画像 `05-sudoku.png` | 撮影 `02-sudoku.png` | 撮影 `02-sudoku.png` |
| 3 | 麻雀 | 会長の画像 `04-mahjong4.png` | v1.1.11 の画像 `09-mahjong4.png` | 撮影 `03-mahjong4.png` | 撮影 `03-mahjong4.png` |
| 4 | オセロ | 会長の画像 `13-othello.png` | v1.1.11 の画像 `08-othello.png` | 撮影 `04-othello.png` | 撮影 `04-othello.png` |
| 5 | 将棋 | 会長の画像 `02-shogi.png` | v1.1.11 の画像 `04-shogi.png` | 撮影 `05-shogi.png` | 撮影 `05-shogi.png` |
| 6 | ソリティア | 会長の画像 `18-solitaire.png` | v1.1.11 の画像 `06-solitaire.png` | 撮影 `06-solitaire.png` | 撮影 `06-solitaire.png` |
| 7 | ポーカー | 会長の画像 `07-poker.png` | v1.1.11 の画像 `10-poker.png` | 撮影 `07-poker.png` | 撮影 `07-poker.png` |
| 8 | チャリンコおじさん | 会長の画像 `07-runner.png` | v1.1.11 の画像 `07-runner.png` | 撮影 `08-runner.png` | 撮影 `08-runner.png` |
| 9 | おじさんの荷物運びパズル | 会長の画像 `04-luggage.png` | **v1.1.12 で撮影** `09-luggage.png` | 撮影 `09-luggage.png` | 撮影 `09-luggage.png` |
| 10 | 柵越えおじさん（結果カード） | 会長の画像 `03-homerun-card.png` | v1.1.11 の画像 `03-homerun-card.png` | 撮影 `10-homerun-card.png` | 撮影 `10-homerun-card.png` |

ファイル名は ASC 上の名前。「v1.1.11 の画像」は v1.1.11 の iPad セットにあったものをそのまま残して並べ替えた
（再アップロードなし）。v1.1.11 の iPad セットから外したのはハブ（旧）と柵越えのスイングの 2 枚。

撮影した画像は `docs/aso/screenshots/v1.1.12/` に置いた（`ja-iphone/` `ja-ipad/` `en-iphone/` `en-ipad/`）。
ja は新しく撮った枚だけ、en は 10 枚すべて。

## 2. 撮り方

- ツリーは `origin/release/v1.1.12`。ja は `a357fdaa`（#2311 まで）、en は `4b433ecd`（#2341 オセロの英語名 Osero・
  #2342/#2346 体験版の印の削除・#2343 規約リンクの英語化・#2344 おじさんシリーズと大富豪のローマ字名 がすべて入った後）。
  main の `Scripts/capture-aso-screenshots.sh` と `Scripts/aso-demo-snapshots.py` を上書きコピーし、`PATH=/usr/bin:$PATH` で実行。
  撮影用に新規作成したシミュレータ（iPhone 17 Pro Max・iPad Pro 13-inch (M5)、iOS 26.5）を UDID で指定し、撮影後に削除した。
- 起動引数: 共通で `-screenshotMode`、ステータスバー 9:41。英語は `-appLanguage en -AppleLanguages (en) -AppleLocale en_US`
  （#2109 の言語の上書き）。iPad はステータスバーに日付が出るため、端末の言語も ja / en に合わせた。
- スクリプトの `SHOTS` に無い画面の指定:
  - おじさんの荷物運びパズル: `-startGame ojisanpuzzle -simulateOjisanPain 50`（会長の iPhone の画像と同じ盤）
  - チャリンコおじさん: `-startGame runner -simulateRunner bird:5`
  - ソリティア: `-startGame solitaire -solitaireMidgame`
  - 柵越えおじさんの結果カード: 起動引数では出せないため、XCUITest（main の `GameCollectionUITests/HomerunE2ETests.swift`
    の打ち方を流用した撮影用の一時テスト。コミットしていない）で柵越えが出るまで振り、カードが出た瞬間を撮った。
- ハブの「つづき・最近」: 初回の端末だと代わりに「はじめてなら、これ」（ブラックジャック）が出る。4 セットで見え方を
  そろえるため、荷物運びパズルを 1 回遊んだ状態のプレイ記録を入れてから撮った（行に「おじさんの荷物運び…」が 1 件出る）。
  NEW の印（荷物運びパズル・ぱっと暗算）は v1.1.12 のハブの仕様（`NewGames.currentVersionIDs`）なのでそのまま。
- 撮影後にファイルサイズを確認し、真っ白（極端に小さい）の外れ値は無し。
