# #209 ブラックジャックの公開・配布・勝敗表示の演出 — 実測

`feat/blackjack-animations` の実測。撮影は **iPhone 17 Pro Max / iOS 26.4**（当番が起動した
シミュレータ。確認後に `simctl shutdown` 済み。会長が使用中だった iPhone 17 Pro には触れていない）、
起動引数は `-screenshotMode -startGame blackjack`（広告は `NoopAdService` に差し替わる）。

シミュレータは自動タップができないため、**中断スナップショット**（`Scripts/aso-demo-snapshots.py` の
`blackjack`: あなた 10♠ 7♥ = 17 / ディーラー K♦ + 伏せ 5♣ = 15・チップ 950・ベット 50）を
アプリのコンテナへ注入して、伏せカードがある局面から始めた。

> **実装の所在**: この文書が説明している `BlackjackMotion` / `BJDealtCardView` / `BJFlipCardView` は
> **PR #<impl>（base `release/v1.1.2`）にある**。この PR の base は `main` で、規程どおり `main` は
> 「App Store で公開済みのバージョンの集合」なので、まだ実装は入っていない。
> 実装が main に現れるのは v1.1.2 が公開されて `release/v1.1.2` が main へ取り込まれた時点。

## 撮影の方法（プローブビルド）

製品の演出は 0.2〜0.5 秒で、`simctl io screenshot` の連続実行（実測 **約 0.18 秒/コマ**）では
中間状態がほとんど拾えない。そのため **長さを引き伸ばしたプローブビルド**でも撮っている。
**プローブの変更はコミットに含めていない**（この PR に入っているのは画像4枚とこの README のみ）。

| 定数 | プローブ | 製品 |
|---|---|---|
| `holeCardFlipDuration`（伏せカードの反転） | 2.4 秒 | **0.34 秒** |
| `dealCardDuration`（カード1枚が置かれる） | 1.8 秒 | **0.22 秒** |
| `dealStagger`（次の1枚までの遅れ） | 0.9 秒 | **0.09 秒** |
| `outcomeBadgeDuration`（勝敗バッジのフェード） | 1.2 秒 | **0.2 秒** |

プローブではさらに、タップ無しでスタンドまで進めるための一時的な自動進行
（`-bjProbe` で起動 9 秒後に `model.stand()`）を足している。これもコミットしていない。

長さと無関係な部分（トーンの大小関係・配る順・View への結線）は `BlackjackMotionTests` が固定する。

## 1. 配布（受け入れ条件2）

![配る順](https://raw.githubusercontent.com/hiroky1983/game_collection/main/docs/ui-review/209/deal-order.jpg)

プローブ（左上 → 右下、約 0.55 秒間隔）。**あなたの1枚目 → ディーラーの1枚目 → あなたの2枚目 →
ディーラーの2枚目（伏せ）** の順に、上から落ちながら薄く・小さい状態から実寸へ収まる。
実際のディールと同じ交互の順序で、`dealDelay(index:isDealer:)` が
`stagger × (index × 2 + (ディーラーなら 1))` を返すことで作っている。

製品の長さでの同じ場面（約 0.18 秒間隔・左上 → 右下）:

![製品の長さでの配布](https://raw.githubusercontent.com/hiroky1983/game_collection/main/docs/ui-review/209/deal-production.jpg)

4枚が置き終わるまでは `dealTotalDuration` = 0.22 + 0.09 × 3 = **0.49 秒**。上の6コマ（約 1.1 秒）の
うち最初の3〜4コマに収まっており、最後の2コマは静止した完成形になっている。

**ヒット・ディーラーの引きで後から増えた3枚目以降は遅らせない**（`dealDelay` が 0 を返す）。
1枚ずつ引く場面で段差ぶん待たされると操作そのものが重く感じられるため。

## 2. 伏せカードの公開（受け入れ条件1）

![伏せカードの公開](https://raw.githubusercontent.com/hiroky1983/game_collection/main/docs/ui-review/209/hole-card-reveal.jpg)

プローブ（左上 → 右下）。青い裏面 → 遠近で細くなる → **真横（進捗 0.5）で表に入れ替わる** →
5♣ が現れて実寸に戻る、という 180 度の Y 軸回転。同時にディーラーが 17 未満で引いた A♠ / 2♠ が
配布の演出で現れている（ディーラーの引きは3枚目以降なので段差なし）。

表裏の入れ替えは `showsFace(progress:)`、回転角は `flipDegrees(progress:)` という純関数で、
`BJFlipCardView` を `Animatable` にして進捗を補間している（ポーカーの `FlipRevealCardView`・#206 と同じ作り）。
`faceUp` フラグに `.gameAnimation` を掛けただけでは表裏が瞬時に入れ替わるだけで、返る動きにはならない。

## 3. 勝敗バッジ（受け入れ条件3）

![勝敗バッジ](https://raw.githubusercontent.com/hiroky1983/game_collection/main/docs/ui-review/209/outcome-badge.jpg)

プローブ（左上 → 右下）。**伏せカードが返り終わってから**、透明・0.8 倍の状態からフェードしつつ
実寸へ膨らむ。左上2コマではまだバッジが無く、3コマ目で薄いピンクの輪郭が現れ、最後に「負け」が読める。

先に出すと**答えを見せてから返す**ことになるため、`outcomeBadge` は `holeCardFlipDuration`
（0.34 秒）ぶん遅らせてある（ポーカーが役名を `showdownTotalDuration` だけ遅らせているのと同じ理由）。
この回はあなた 17 / ディーラー 18 で敗け。

## Reduce Motion

3つとも Core の `gameAnimation(_:value:)` / `withGameAnimation(_:_:)` 経由で書いてあるため、
OS の「視差効果を減らす」が ON のときは補間が落ちて、

- 伏せカードは回転せず即座に表になる
- カードは遅れも動きもなく置かれる
- バッジは遅れなくその場に出る

だけになり、**公開・配布・勝敗の表示そのものは従来どおり反映される**（#210）。
素の `.animation(` / `withAnimation(` が紛れ込んでいないことは `BlackjackMotionTests` が
`BlackjackView.swift` のソースを走査して固定している。
