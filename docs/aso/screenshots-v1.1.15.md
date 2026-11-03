# App Store スクリーンショット（v1.1.15・撮影素材）

会長決裁（2026-11-04）の並び: v1.1.14 の並びからチャリンコおじさんを外し、9 枚目におじさんちのねこさがしを入れた。
**撮影して `docs/aso/screenshots/v1.1.15/` に置いたところまで**。ASC への入稿は提出前に社長が API で行う
（読み戻して全枚 `COMPLETE` を確認する）。審査提出は会長の職掌。

## 1. 並び（4 セット共通・`ja-iphone/` `ja-ipad/` `en-iphone/` `en-ipad/`）

| # | 画面 | ファイル |
|---|---|---|
| 1 | 大富豪 | `01-daifugo.png` |
| 2 | ブラックジャック | `02-blackjack.png` |
| 3 | スピード | `03-speed.png` |
| 4 | 将棋 | `04-shogi.png` |
| 5 | 麻雀（4 人） | `05-mahjong4.png` |
| 6 | ソリティア | `06-solitaire.png` |
| 7 | ナンプレ | `07-sudoku.png` |
| 8 | おじさんの荷物運びパズル | `08-luggage.png` |
| 9 | おじさんちのねこさがし（ステージモードの対局中） | `09-catpuzzle.png` |
| 10 | ハブ | `10-hub.png` |

## 2. 撮り方

- ツリー: `origin/release/v1.1.15`（`23b18b62`）。main の `Scripts/capture-aso-screenshots.sh` と `Scripts/aso-demo-snapshots.py` を
  release のツリーへ上書きコピーし（コミットしない）、`SHOTS` を上の並びに差し替えて実行。`PATH=/usr/bin:$PATH`。
- 端末: 撮影用に新規作成（iPhone 17 Pro Max・iPad Pro 13-inch (M5)、iOS 26.5）して UDID で指定し、撮影後に削除。
  iPad は端末の言語・ロケールも ja / en に合わせた（ステータスバーの日付表記が出るため）。
- 起動引数: 共通 `-screenshotMode`、ステータスバー 9:41。英語は `-appLanguage en -AppleLanguages (en) -AppleLocale en_US`。
- 画面ごとの指定:
  - スピード: `-startGame speed -speedScenario both`（♥5 が左右どちらの台札にも出せる静止局面）
  - おじさんの荷物運びパズル: `-startGame ojisanpuzzle -simulateOjisanPain 50`
  - **おじさんちのねこさがし: `-startGame catpuzzle`＋中断データ `catpuzzle.json`**。既存の `-catpuzzleScenario` には
    「猫が何匹か見つかって × も付いている途中の盤」を作る指定が無いため、アプリのコードは変えずに
    `aso-demo-snapshots.py` の `snapshot_catpuzzle` で中断データを作った（この PR で main に追加）。
    中身はステージ 33 面目（8×8・鍵の面ではない）、8 部屋（4〜12 マス）、答えは 1 通り、猫 4 匹を見つけて
    その行・列・隣に × を付けた局面（残り 4 匹・ミス 0/3）。中断データがあると開始シートは出ず、そのまま盤が開く。
  - ソリティア: `-startGame solitaire -solitaireMidgame`
  - 4 人麻雀: `-startGame mahjong4`（中断データ `mahjong4.json`。`mahjong` は麻雀ソリティアの ID なので使わない）
  - 大富豪・ブラックジャック・将棋・ナンプレは `aso-demo-snapshots.py` の中断データ
- **ハブはアプリを入れ直した直後に最初に撮る**。他の画面を先に撮ると、荷物運びパズルの遊んだ記録が残って
  ハブの先頭が「続きから・最近遊んだ」の行（Ojisan's Box Puzzle / Play again）に変わる（en-iphone の 1 回目で発生）。
  各セットは `xcrun simctl uninstall` してから撮った。
- 起動待ち 4 秒で真っ白になった画面（en-iphone の大富豪・ねこさがし）と、Dynamic Island の黒い帯が写った画面
  （en-iphone のナンプレ・荷物運び）は撮り直した。撮影後に `ls -lS` と一覧画像で全 40 枚を目で確かめた。
- 撮影後に新しい `GameCollection-*.ips`（クラッシュログ）が増えていないことを確認した。
- 解像度: iPhone は 1320×2868（6.9"）、iPad は 2064×2752（13" 枠にそのまま入る）。

## 3. 既知の注意

- ハブ（10 枚目）は「はじめてなら、これ（ブラックジャック）」の行が写る。v1.1.14 で写っていた NEW の印
  （ねこさがし・スピード・ババ抜き・ハーツ）は v1.1.15 のツリーでは出ず、先頭は柵越えおじさん・いろリレー。
- 倉庫ゲーム・「ショーケース」の見出し・開発用の表示は写っていない。
- 英語の麻雀の盤面は、卓の中央の点数表示まで英語化されているが、牌の絵は漢字のまま（牌の絵柄なので仕様どおり）。
