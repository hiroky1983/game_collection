# 柵越えおじさんのハブの横長タイルの元絵（#2273）

ハブ先頭の柵越えおじさんの横長タイル（`hubtile-homerun-wide` / `-wide-pad` と英語版 `-en`）は、この
`source.png` を `Scripts/generate-hub-tiles.py` が切り抜いて作る。以前はロゴ入りのキービジュアル
（`HomerunHubHeroArtLogo.jpg`）を切り抜いていたが、会長 QA（2026-10-15・#2273）で文字（ロゴ）の無いこの絵に替えた。

| ファイル | 内容 | 出所 | 受領日 |
|---|---|---|---|
| `source.png` | 1254×1254 の正方形。球場で打つおじさん（ヘルメット・バット・手前に飛んでくるボール）。文字・ロゴ無し | 会長が ChatGPT（OpenAI）で作成し提供 | 2026-10-15 |

- 加工はしていない（受け取ったファイルそのまま。SHA-256 `290f075f95a7937886c8c6319e8c2c7a18af42294bfcc3d6851cde12e3cb7502`）。
- 権利: ChatGPT 生成物の所有権・商用利用の扱いは `../assets-license.md` 4 章（OpenAI の規約）と同じ。帰属表示は不要。
- release ブランチには docs が無いので、タイルを書き直すときは main から取り出して渡す:

```bash
git archive origin/main docs/design/homerun/hub-tile | tar -x -C /tmp/mock
python3 Scripts/generate-hub-tiles.py --only homerun-wide --hero /tmp/mock/docs/design/homerun/hub-tile/source.png
```

## 切り抜き（`generate-hub-tiles.py` の `WIDE_TILES`）

左上のゲーム名と右下の残り回数のボールに、おじさんの顔・ボールが重ならない位置で切る。

- iPhone 用（370×215pt）: 幅いっぱい・上端から `(0, 0, 1254, 729)`。ヘルメットの頭頂が名前の下線の高さに来て、顔・バット・
  ボールがまるごと入る。右下は観客席と照明。
- iPad 用（752×215pt）: 絵の幅のままでは背が足りず名前がヘルメットに重なるので、絵の左端 150px（おじさんより左の青空と照明塔）を
  鏡写しで 2 回継ぎ足して左へ 300px 広げ、`(0, 85, 1554, 529)` で切る。名前は継ぎ足した空の上、ボールは上が少し切れる。
