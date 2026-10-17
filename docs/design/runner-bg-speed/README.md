# チャリンコおじさん: 背景の流れる速さを一定にする（#2255 モック）

会長の指摘（2026-10-14）「難易度が上がると背景のスクロールも速くなり、酔う人がいそう」への案A の試作と比較動画。
**本実装・release へのマージはまだ**（会長が見て決めてから）。

## 比較動画（左＝今 / 右＝案A）

| 場面 | 動画 | 0.5 秒あけた 2 コマ |
| --- | --- | --- |
| エンドレス・最高速（基準速 60 ＝ 序盤 34 の約 1.8 倍） | [endless-compare.mp4](endless-compare.mp4) | [endless-frames-0.5s.png](endless-frames-0.5s.png) |
| 港町 ステージ 30（5-6・基準速 57.2 ＝ 序盤の約 1.7 倍） | [harbor-stage30-compare.mp4](harbor-stage30-compare.mp4) | [harbor-stage30-frames-0.5s.png](harbor-stage30-frames-0.5s.png) |

各 10 秒。シミュレータ（iPhone 17 Pro / iOS 26.5）で自動操縦を走らせ `xcrun simctl io recordVideo` で撮影し、
ゲーム部分を切り出して左右に並べた。左右は別々に撮ったので、障害の位置・タイミングは一致しない。

## 今の作り（コードで確認）

- **おじさんは画面上の固定位置**（`Metrics.playerX`）で、世界のほうが流れる。地面・障害物は `courseLayer` に載っていて、
  `courseLayer.position.x = playerX − field.distance` で毎フレーム動かす（`RunnerScene+Sync.swift`）。
- 背景は奥から: 空（シーンの背景色・動かない）→ 雲（`cloudLayer`）→ 夕方の地平線の帯（`backdropLayer`・動かない）→
  丘・街並み・港のコンテナや船など（`hillLayer`。家並み・港の絵は丘のタイルに載っている）→ コース。
- 雲と丘は **`field.distance` × 視差の係数** で流れる（`RunnerParallax.wrappedX`）。係数は雲 0.3・丘 0.55（`RunnerScene.swift`）。
  `field.distance` は `currentSpeed`（基準速 × 乗り × 床の倍率）で進むので、**背景は速度に完全に連動**していて、
  基準速が 1.8 倍になれば背景も 1.8 倍の速さで流れる。
- 速度の上がり方: ステージ制は 1 面ごとに +0.8（34 → 60 で頭打ち）。エンドレスは距離に比例して上がり
  （約 853 進むごとに +0.8）、距離 2 万 2 千ほどで上限 60 に達する（`RunnerEndlessCourse.speed(atDistance:)`）。

## 案A の試作の中身

- 背景（雲・丘）を流す距離だけ、進んだぶんに **「序盤の速さ 34 ÷ その地点の基準速」** を掛けて積み上げる。
  難易度で上がった基準速のぶんだけ打ち消すので、背景は 1 面目・エンドレスの走り出しと同じ速さで流れ続ける。
- 乗り（漕ぎ）・アイテム・加速床による加速は基準速に含まれないので、そのぶんは今どおり背景にも乗る（加速した感じは残る）。
- 地面・障害物・当たり判定・ジャンプの物理は `field.distance` のままで一切変えていない。
- 試作ブランチ: `mock/2255-runner-bg-speed`（`release/v1.1.12` から。push していない）。
  DEBUG 限定の起動引数 `-runnerBackdropFixedSpeed` で切り替え、録画用に `-simulateRunner endless-autopilot-fast`
  （エンドレスを速さの上限から自動操縦）と `-simulateRunner stage-autopilot:N`（N 面を自動操縦）を足した。

## 所見

- 背景の動きは狙いどおり減った。0.5 秒あたりの雲の移動量が、エンドレス最高速で約 51px → 28px（34/60 ≒ 0.57 倍）、
  港町 30 面で約 45px → 28px（34/57.2 ≒ 0.59 倍）。画面の面積の大半を占める空・丘が序盤と同じ速さになるので、
  画面全体の「流れている量」ははっきり少なく見える。
- 一方で、**地面と背景の速さの差は大きくなる**。今は丘・街並みが地面の 0.55 倍で流れるのに対し、案A では最高速で
  約 0.31 倍（雲は 0.3 → 約 0.17 倍）。特に**家並み（朝の下町）と港のコンテナ・船は道路のすぐ上に接して描かれている**ので、
  道路の白線・障害物が速く流れる真上で家だけがゆっくり滑る形になり、「家が道路に対してずるずる後ろへ滑る」
  ように見える場面がある。遠くの山として見れば自然だが、家並みは「道沿いの家」に見えるぶん違和感が出やすい。
- 雲と山の稜線については違和感は小さい（もともと遠景で、ゆっくり流れても不自然に見えない）。
- 速さの変化そのもの（面が進むごとに速くなる）は、地面・障害物・白線で今どおり十分に伝わる。背景だけで速さを感じさせていた
  わけではないので、難しさの体感が落ちる心配は小さいと見ている。
- 本実装に向けた論点（会長判断）:
  1. 家並み・港の絵（丘タイルに載っているもの）も一定速にするか、それとも「家並みは地面寄りの速さ、山・雲だけ一定」に分けるか
     （分けるなら家並みを丘から別レイヤーへ出す作業が要る）。
  2. 一定にする基準を序盤（34）にするか、少し上（例: 中盤の速さ）にして地面との差を縮めるか。
  3. 補足案の「視差効果を減らす」オン時にさらに抑えるかどうか。

## 再現手順

```bash
# mock/2255-runner-bg-speed をビルドしてシミュレータに入れたあと
xcrun simctl launch <UDID> com.hirockysan1983.asobiba -screenshotMode -startGame runner \
  -simulateRunner endless-autopilot-fast [-runnerBackdropFixedSpeed]
xcrun simctl launch <UDID> com.hirockysan1983.asobiba -screenshotMode -startGame runner \
  -simulateRunner stage-autopilot:30 [-runnerBackdropFixedSpeed]
```
