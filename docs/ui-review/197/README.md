# #197 麻雀ソリティア: 表示切り替えの発見性とタップ領域 — 画面確認

**前提**: #196 で**既定が入れ替わっている**。起票時（#157 M4）は「既定 = 全体表示・虫めがねで拡大」だったが、
現在は「既定 = 牌 44pt でスクロール・虫めがねで全体表示」。したがって本 Issue の対象は
**「拡大モードへの入口」ではなく「全体表示 ⇄ 拡大の切り替えボタンそのもの」**である。
このボタンは #196 以降「盤面の全体像を取り戻す唯一の入口」になっており、
そこが 31.7×25.0pt の記号 1 つだったことが問題の本体。

**数値の出し方**: pt = 実測ピクセル ÷ 画面の倍率（iPhone 17 Pro は 3、iPhone SE 第3世代は 2）。
ボタンは面（`Theme.teal` = `#22C3BE`）の連結成分の外接矩形で測る。カードの帯と盤面領域は
「カードの白が続く区間」の境界で測る（#196 README と同じ測り方）。

## 実測値

### 切り替えボタンのタップ標的（iPhone 17 Pro）

| | 修正前 | 修正後 | Apple HIG |
|---|---|---|---|
| ボタンの大きさ | **31.7 × 25.0pt** | **66.7 × 44.0pt** | 44 × 44pt 以上 |

- 修正前の値は Issue 本文の見積り「約 29×23pt」とおおむね一致する（本 README は面の外接矩形、
  Issue は padding + フォントサイズからの計算のため 2pt ほど差が出る）。
- 修正後は iPhone SE 第3世代でも **44.0pt**（`04-iphone-se.jpg`）。高さは端末によらず 44pt に固定される。

### ステータスバーの帯と盤面領域

44pt のボタンは帯の高さを押し上げるため、上下の余白を 8 → 4 に詰めて相殺している。

| 端末 | 帯の下端（修正前 → 修正後） | 操作カードの上端 | 盤面領域（修正前 → 修正後） |
|---|---|---|---|
| iPhone 17 Pro | 181.3 → 183.7pt | 649.0pt（**変化なし**） | 467.7 → **465.3pt**（−2.4pt / −0.5%） |
| iPhone SE 第3世代 | 129.0 → 131.5pt | 475.5pt（**変化なし**） | 346.5 → **344.0pt**（−2.5pt / −0.7%） |

- 修正前の盤面領域は #196 README の実測（467.7pt / 346.5pt）と**完全に一致**する。同じ測り方で測れている。
- **牌の大きさはどちらの表示でも変わらない**。全体表示の牌の並びの外接幅は修正前後で **1px も同じ**
  （iPhone 17 Pro: 1170px = 390.0pt → 牌 25.06pt、iPhone SE: 727px = 363.5pt → 牌 23.36pt）。
  全体表示の牌は**幅**で決まっており（`min(byWidth, byHeight)` の `byWidth` 側）、高さが 2.4pt 減っても
  律速が入れ替わらないため。既定表示の牌は `max(44, …)` なので元から高さに依存しない。
- 帯の高さの見積りは `MahjongSolitaireBoardMetricsTests.statusBarStaysAsShortAsBefore` で
  「増加 3pt 以内」として固定してある（実測 +2.4 / +2.5pt）。

## 変更の中身

1. **タップ標的 44pt**（`Metrics.toggleButtonMinSide`）。値を Metrics に集約し、縮んだら swift test で落ちる。
2. **記号だけをやめた**。虫めがねアイコンに「全体」／「拡大」の文字を併記した。
   受け入れ条件の「初回プレイ時に案内される」は**常時表示**で満たしている
   （一度きりのヒントと違い、初回でも 2 回目以降でも同じように読める。
   `HowToPlayHint` は 1 行・`HowToPlayGuide.lines` は 3 行までという既存の制約があり、
   そこへ押し込むより機能の場所そのものに書くほうが確実だと判断した）。
3. **押していない側に輪郭を付けた**。従来の面は `Theme.surface`（= カードと同じ白）で、
   ライトモードではボタンの境界がどこにも見えなかった（`01-toggle-tap-target.jpg` 左）。
   薄い差し色（`teal` 12%）+ 枠線（`teal` 55%）にし、文字は `Theme.ink`（こげ茶）にした。
   **薄い面 + 白文字にはしていない**（#220 で議論中の「差し色の面 + 白文字」を増やさないため。
   押している側の teal 面 + 白文字は #196 からの既存の組み合わせで、本 PR では変えていない）。
4. **拡大表示のスクロールバーを出した**（`showsIndicators: false` → `true`）。

## 画像

### 01-toggle-tap-target.jpg — ステータスバーの拡大（iPhone 17 Pro・既定 = 拡大中）

左が修正前（虫めがねアイコンのみ・31.7×25.0pt、白い面がカードと同化してボタンに見えない）、
右が修正後（「🔍 全体」・66.7×44.0pt）。

### 02-toggle-states.jpg — 全体表示中の状態

全体表示にしている間はボタンが teal で塗られ、文字が「拡大」に変わる（押すと拡大に戻る、の意）。

### 03-iphone17pro.jpg — 画面全体（iPhone 17 Pro・iOS 26.4）

左から 修正前の既定 / 修正後の既定 / 修正後の全体表示。牌の大きさは修正前後で変わらない
（盤面の絵柄が違うのは、起動のたびに新しい盤面が配られるため）。

### 04-iphone-se.jpg — iPhone SE 第3世代（375×667pt・iOS 17.0）

いちばん狭い対象機種（対応 OS は iOS 17 以上なので 320pt 幅の機種は対象外）。
ボタンの高さは 44.0pt のままで、時計とぶつからずに収まる。

## 確認できていないこと（正直な記録）

**スクロールバーは静止画に写らない**。iOS の標準挙動としてスクロール中だけ表示され数秒でフェードするため、
起動直後 0.4 / 0.8 / 1.2 / 2.0 秒で撮っても現れなかった（右端に見える暗い画素は牌の輪郭で、
修正前のスクリーンショットにも同じように出る）。シミュレータは自動でスワイプできないので、
この 1 点だけは `showsIndicators: false → true` というコード変更としてのみ確認している。

なお、受け入れ条件3「往復操作で全体像を失わない工夫」の本体は**スクロールバーではなく
1 タップの往復そのもの**であり、そちらは #196 で入り、本 PR で「そのボタンがどこにあり何をするか」が
画面から読めるようになった（`01` / `02`）。

## 再現方法

```sh
BUNDLE_ID=com.hirockysan1983.asobiba
xcodegen generate
xcodebuild -project GameCollection.xcodeproj -scheme GameCollection \
  -configuration Debug -sdk iphonesimulator -destination "id=$UDID" \
  -derivedDataPath /tmp/dd197 CODE_SIGNING_ALLOWED=NO build
xcrun simctl install "$UDID" /tmp/dd197/Build/Products/Debug-iphonesimulator/GameCollection.app
# 既定（拡大 = 牌 44pt）
xcrun simctl launch "$UDID" "$BUNDLE_ID" -screenshotMode -startGame mahjong
# 全体表示（DEBUG 限定の起動引数）
xcrun simctl launch "$UDID" "$BUNDLE_ID" -screenshotMode -startGame mahjong -mahjongWholeBoard
```

- `xcrun simctl launch` は **bash から実行する**。zsh のインラインだと `-startGame mahjong` が
  1 引数として渡り、ハブ画面のまま起動する。
- 初回の遊び方ヒント 1 行が入ると盤面領域の高さが変わるため、撮影前に 2 回空打ちする。
- 前のセッションの中断データを持ち越さないよう、撮影前に `simctl uninstall` して入れ直す。
