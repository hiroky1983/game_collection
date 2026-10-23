# 盤ゲームの着手音（CC0 素材）の出所とライセンス

Issue #2767（会長指示 2026-10-23）。将棋・囲碁・五目並べ・オセロ・チェスの「自分の着手」の効果音に使う同梱ファイルの出所を記録する。
**この文書はライセンス条件の記録のみ**。実装は release ブランチ側（`Packages/GameKit/Sources/CoreEngine/BoardSound.swift`、
素材は `Packages/GameKit/Sources/CoreEngine/Resources/Sounds/`）。トランプ側は `docs/design/card-sfx/assets-license.md`。

## 1. 出所

| 項目 | Impact Sounds | Casino Audio |
|---|---|---|
| 作者 | Kenney Vleugels（Kenney.nl） | 同左 |
| 配布元 | <https://kenney.nl/assets/impact-sounds> | <https://kenney.nl/assets/casino-audio> |
| ダウンロード | <https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip>（取得日 2026-10-23） | <https://kenney.nl/media/pages/assets/casino-audio/2472606a04-1721639069/kenney_casino-audio.zip>（取得日 2026-10-23） |
| ライセンス | **Creative Commons Zero（CC0 1.0）** <https://creativecommons.org/publicdomain/zero/1.0/> | 同左 |
| 確認方法 | 配布ページの License 欄が「Creative Commons CC0」、zip 内 `License.txt` に「License: (Creative Commons Zero, CC0)」とあることを 2026-10-23 に確認 | 配布ページ・`License.txt` とも CC0（#2697 の記録と同じ） |
| クレジット表記 | **不要**（任意）。アプリ内のクレジット表示は追加しない | 同左 |

## 2. 使ったファイル

| 同梱ファイル | 場面 | 元ファイル（zip 内 `Audio/`） | 加工 |
|---|---|---|---|
| `shogi-piece.caf` | 将棋：指す・打つ・成る | Impact Sounds `impactWood_medium_000.ogg` | 無音の頭を除去・0.27 秒に切り詰め（末尾 50ms フェード）・音量正規化・22.05kHz モノラル 16bit |
| `shogi-capture.caf` | 将棋：駒を取る（少し重い） | Impact Sounds `impactWood_heavy_000.ogg` | 同上 |
| `go-stone.caf` | 囲碁・五目並べ：石を置く | Casino Audio `chip-lay-1.ogg` | 同上（元の音が短く 0.12 秒） |
| `othello-disc.caf` | オセロ：石を置く | Casino Audio `chip-lay-3.ogg` | 同上（0.18 秒） |
| `chess-piece.caf` | チェス：駒を置く | Impact Sounds `impactWood_light_000.ogg` | 同上 |

加工は ffmpeg（`silenceremove` → `atrim` → `afade` → `loudnorm` I=-18 / TP=-3）と `afconvert`（CAF 化）。ピークは約 -3〜-4dB、5 ファイル合計 約 69KB。
`BoardSoundTests` が長さ（0.1〜0.3 秒）・ピーク・頭の無音・合計 200KB 以内を固定している。

## 3. 差し替えるとき

CC0 と配布元のページで確認できた素材だけを使い、この表に出所・元ファイル・加工を追記する。CC0 と確かめられない素材は使わない。
