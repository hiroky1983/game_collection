# #263 麻雀の鳴き（ポン・チー・カン）— 実機（シミュレータ）確認

PR: hiroky1983/game_collection#263 の実装（`feat/mahjong-melds-263`）を
iPhone SE (3rd generation) / iPhone 17 Pro（どちらも iOS 26.4）で撮影したもの。

`-startGame mahjong4 -screenshotMode` で起動し、中断スナップショットを注入して
狙った局面を作っている（シミュレータはタップの自動化ができないため）。

ビルド元は **`release/v1.1.1` から切った `feat/mahjong-melds-263`**。この README を置く PR の base が
`main` なのは `docs/` だけの変更だからで、`main` 側にはまだ麻雀（#106）が入っていない
（`main` = App Store で公開済みのバージョンの集合。公開版は 1.0.2）。

| ファイル | 局面 |
|---|---|
| `call-se.jpg` / `call-17pro.jpg` | CPU1 が 5萬 を切り、自分にポンが提示されている（`.callOffer`） |
| `melds-se.jpg` / `melds-17pro.jpg` | 中をポン・234筒をチーして晒した状態。カンできる牌があるので「カン」ボタンが出て、鳴いたので「立直」が押せなくなっている |
