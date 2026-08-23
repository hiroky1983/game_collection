# #196 麻雀ソリティア: 牌の実効タップ標的を 44pt 以上にする — 画面確認

**数値の出し方**: pt = 実測ピクセル ÷ 画面の倍率（iPhone 17 Pro は 3、iPhone SE 第3世代は 2）。
牌の幅は 2 通りで測っている。

- **全体表示**: 牌の並びの外接幅を実測し、盤面の広さ **15.56 枚ぶん**で割る。
- **既定表示（拡大）**: 盤面が画面より広く外接幅が測れないため、走査線上の輪郭の**自己相関で横ピッチ**を取る。

## 実測値

| 端末（盤面領域） | 修正前（既定） | 修正後（既定） | 修正後（全体表示） |
|---|---|---|---|
| iPhone 17 Pro（402×467.7pt） | 牌の並び 390.3pt ÷ 15.56 = **25.1pt** | 横ピッチ 132px ÷ 3 = **44.0pt** | 牌の並び 390.3pt ÷ 15.56 = **25.1pt** |
| iPhone SE 第3世代（375×346.5pt） | 牌の並び 363.5pt ÷ 15.56 = **23.4pt** | 横ピッチ 88px ÷ 2 = **44.0pt** | 牌の並び 363.5pt ÷ 15.56 = **23.4pt** |

- 修正前の値は `docs/ui-review/148/README.md` の実測（iPhone 17: 390.7pt / SE: 364.0pt）と
  0.4pt / 0.5pt の差に収まる（機種と OS が違い、輪郭の拾い方も同じではないため完全一致はしない）。
- 盤面領域の高さは**この README の実測値**（iPhone 17 Pro 467.7pt / iPhone SE 346.5pt）で統一している。
  `MahjongSolitaireBoardMetricsTests` が使う端末条件も同じ値。#148 の 469.7pt / 349.5pt とは
  2.0pt / 3.0pt 違うが、これは #148 が別の測り方（カードの外形）をしているためで、
  本 README は「白が行の 8 割以上を占める帯」の境界で測っている。44pt の判定はどちらでも変わらない。
- **全体表示は修正前の既定と 1px も違わない**（外接幅の実測ピクセルが iPhone 17 Pro: 1171px、
  iPhone SE: 727px で完全一致）。既定が入れ替わっただけで、全体表示そのものは変えていない。
- 対応 OS は iOS 17 以上なので、いちばん狭い実機は **iPhone SE 第2/第3世代の 375pt**。
  Issue 本文の「320pt 幅」に該当する機種（iPhone SE 第1世代・iPhone 5s 等）は iOS 15 までで、
  このアプリの対象外。**375pt が最狭**という前提で 44pt を確認している。

## 44pt と「盤面全体が 1 画面」が両立しない理由

亀型レイアウトは横 **15.56 枚**ぶんある（`MahjongSolitaireRules.halfWidth`=30 / `topLayer`=4 ×
奥行きのずれ 0.14）。牌の幅を 44pt にすると盤面の幅は **44 × 15.56 = 684.6pt** 必要になる。
iPhone の画面幅は最大でも 440pt 程度（iPhone 17 Pro Max）なので、**どの iPhone でも成立しない**。
受け入れ条件の 2 番目「または全体像を失わない手段（ミニマップ・ピンチズーム等）がある」に沿い、
**既定を 44pt 側に置き、全体像はステータスバーの虫めがねボタン 1 タップで取り戻せる**形にした。

## 画像

### 01-tap-target-before-after.jpg — iPhone 17 Pro・対局中

左が修正前（既定 = 全体表示・牌 25.1pt）、右が修正後（既定 = 牌 44.0pt・スクロールで見て回る）。
スクロールの開始位置は中央（亀型の山が中央にあり、上下左右へ同じだけ動かせるため）。

### 02-whole-board-toggle.jpg — 全体像の取り戻し方

ステータスバー右端の虫めがねボタン 1 タップで全体表示に戻る（右）。
記号だけのボタンなので VoiceOver 用に「盤面全体を表示」／「牌を大きくする」のラベルを付けた。

### 03-iphone-se.jpg — iPhone SE 第3世代（375×667pt・iOS 17.0）

いちばん狭い対象機種。左から修正前（23.4pt）・修正後の既定（44.0pt）・修正後の全体表示（23.4pt）。

### 04-finished-layout-unchanged.jpg — #148（決着で盤面が縮まない）の維持

決着後の画面。**修正前後でカードの位置が完全に一致**する。
対局中・決着後の両方で、ステータスバーのカード下端 → 操作カード上端の距離は
iPhone 17 Pro **467.7pt**、iPhone SE **346.5pt** で before/after ともに同じ。

## 再現方法

```sh
BUNDLE_ID=com.hirockysan1983.asobiba
xcrun simctl install "$UDID" GameCollection.app
# 既定（牌 44pt）
xcrun simctl launch "$UDID" "$BUNDLE_ID" -screenshotMode -startGame mahjong
# 全体表示（DEBUG 限定の起動引数。シミュレータは自動タップができず、
# 既定でない側の表示を撮る手段がこれしかない）
xcrun simctl launch "$UDID" "$BUNDLE_ID" -screenshotMode -startGame mahjong -mahjongWholeBoard
```

- `xcrun simctl launch` は **bash から実行する**。zsh のインラインだと `-startGame mahjong` が
  1 引数として渡り、ハブ画面のまま起動する。
- 初回だけ出る遊び方ヒントの 1 行が入ると盤面領域の高さが変わるため、撮影前に 2 回空打ちする。
- 前のセッションの中断データが残っていると決着後の画面が写るため、撮影前に `simctl uninstall` して入れ直す。
- 決着後の画面は `Library/Application Support/Snapshots/mahjong.json` に
  「`faces` が 144 個すべて `null`」のスナップショットを置いて復元する。JSON は次のコマンドで作る
  （`[null × 144]` と直接書くのは JSON として不正なので、生成させる）:

  ```sh
  /usr/bin/python3 -c 'import json; json.dump(
    {"faces": [None] * 144, "elapsedSeconds": 218, "shuffleCount": 1, "hintCount": 2},
    open("mahjong.json", "w"))'
  ```
