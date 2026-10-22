# App Store スクリーンショット（v1.1.14・撮影素材）

#2053（会長決裁 2026-10-23）の新しい並び。**撮影して `docs/aso/screenshots/v1.1.14/` に置いたところまで**。ASC への入稿は
提出前に社長が API で行う（読み戻して全枚 `COMPLETE` を確認する）。審査提出は会長の職掌。

## 1. 並び（4 セット共通・`ja-iphone/` `ja-ipad/` `en-iphone/` `en-ipad/`）

| # | 画面 | ファイル |
|---|---|---|
| 1 | 大富豪 | `01-daifugo.png` |
| 2 | ブラックジャック | `02-blackjack.png` |
| 3 | スピード | `03-speed.png` |
| 4 | 将棋 | `04-shogi.png` |
| 5 | 麻雀（4 人） | `05-mahjong4.png` |
| 6 | ソリティア | `06-solitaire.png` |
| 7 | ナンプレ（パズル） | `07-sudoku.png` |
| 8 | おじさんの荷物運びパズル（おじさん） | `08-luggage.png` |
| 9 | チャリンコおじさん（おじさん） | `09-runner.png` |
| 10 | ハブ（32 本が並ぶ画面） | `10-hub.png` |

決裁文は「1〜3 枚目：大富豪・ブラックジャック・スピード／4 枚目：将棋／以降：麻雀・ソリティア・パズル・おじさん」。
「以降」の 4 項目に 7〜9 の 3 枚（パズル = ナンプレ・荷物運び、おじさん = 荷物運び・チャリンコ）を当て、10 枚目はハブにした
（ハブは 1 枚目から外れるので、32 本の一覧は最後に置いた）。**並びの入れ替えは ASC 側で自由にできる**（撮影は 10 本ぶん揃っている）。

## 2. 撮り方

- ツリー: `origin/release/v1.1.14`（`0a7c42a6`）。main の `Scripts/capture-aso-screenshots.sh` と `Scripts/aso-demo-snapshots.py` を
  release のツリーへ上書きコピーし（コミットしない）、`SHOTS` を上の並びに差し替えて実行。`PATH=/usr/bin:$PATH`。
- 端末: 撮影用に新規作成（iPhone 17 Pro Max・iPad Pro 13-inch (M5)、iOS 26.5）して UDID で指定し、撮影後に削除。
  iPad は端末の言語・ロケールも ja / en に合わせた（ステータスバーの日付表記が出るため）。
- 起動引数: 共通 `-screenshotMode`、ステータスバー 9:41。英語は `-appLanguage en -AppleLanguages (en) -AppleLocale en_US`。
- 画面ごとの指定:
  - スピード: `-startGame speed -speedScenario both`（♥5 が左右どちらの台札にも出せる静止局面）
  - おじさんの荷物運びパズル: `-startGame ojisanpuzzle -simulateOjisanPain 50`
  - チャリンコおじさん: `-startGame runner -simulateRunner bird:5`
  - ソリティア: `-startGame solitaire -solitaireMidgame`
  - 大富豪・ブラックジャック・将棋・麻雀・ナンプレは `aso-demo-snapshots.py` の中断データ
- 撮影後に新しい `GameCollection-*.ips`（クラッシュログ）が増えていないことを確認した。
- 解像度: iPhone は 6.9"、iPad は 2064×2752（13" 枠にそのまま入る）。

## 3. 既知の注意

- ハブ（10 枚目）は「はじめてなら、これ（ブラックジャック）」の行と NEW の印（おじさんちのねこさがし・スピード・ババ抜き・ハーツ）が写る。
  iPad の ja ハブには「イベント開催中」の印が出ている。
- 英語の麻雀の盤面は、卓の中央の点数表示まで英語化されているが、牌の絵は漢字のまま（牌の絵柄なので仕様どおり）。
