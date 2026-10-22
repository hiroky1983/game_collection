# トランプの効果音（CC0 素材）の出所とライセンス

Issue #2697（会長決裁 2026-10-23・案 A）。トランプの配る・めくる・出す・切るの効果音に使う同梱ファイルの出所を記録する。
**この文書はライセンス条件の記録のみ**。実装は release ブランチ側（`Packages/GameKit/Sources/CoreEngine/CardSound.swift`、
素材は `Packages/GameKit/Sources/CoreEngine/Resources/Sounds/`）。

## 1. 出所

| 項目 | 内容 |
|---|---|
| 素材名 | Casino Audio（v1.1・全 50 ファイル。うちカード系 23 ファイルから 4 つを使用） |
| 作者 | Kenney Vleugels（Kenney.nl） |
| 配布元 | <https://kenney.nl/assets/casino-audio> |
| ダウンロード | <https://kenney.nl/media/pages/assets/casino-audio/2472606a04-1721639069/kenney_casino-audio.zip>（取得日 2026-10-23） |
| ライセンス | **Creative Commons Zero（CC0 1.0）** <https://creativecommons.org/publicdomain/zero/1.0/> |
| 確認方法 | 配布ページの License 欄が「Creative Commons CC0」であること、zip 内の `License.txt` に「You may use these assets in personal and commercial projects. Credit (Kenney or www.kenney.nl) would be nice but is not mandatory.」とあることを 2026-10-23 に確認 |
| クレジット表記 | **不要**（任意）。アプリ内のクレジット表示は追加しない |

## 2. 使ったファイル

| 同梱ファイル | 場面 | 元ファイル（zip 内 `Audio/`） | 加工 |
|---|---|---|---|
| `card-deal.caf` | 配る・山から引く | `card-slide-4.ogg` | 無音の頭を除去・0.27 秒に切り詰め（末尾 50ms フェード）・音量正規化・22.05kHz モノラル 16bit |
| `card-flip.caf` | めくる | `card-shove-1.ogg` | 同上 |
| `card-place.caf` | 出す・置く | `card-place-2.ogg` | 同上 |
| `card-shuffle.caf` | 切る | `card-shuffle.ogg` | 無音の頭を除去・先頭 0.9 秒（末尾 150ms フェード）・音量正規化（+4dB で他とそろえる）・同形式 |

加工は ffmpeg（`silenceremove` → `atrim` → `afade` → `loudnorm`）と `afconvert`（CAF 化）。ピークは -3〜-4dB、4 ファイル合計 約 92KB。
`CardSoundTests` が長さ（配る・めくる・出すは 0.3 秒未満、切るは 1 秒以内）・ピーク・合計 200KB 以内を固定している。

## 3. 差し替えるとき

CC0 と配布元のページで確認できた素材だけを使い、この表に出所・元ファイル・加工を追記する。CC0 と確かめられない素材は使わない。
