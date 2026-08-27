# #296 LP を12ゲームに追従（麻雀（四人打ち）・数独）

`web/app/lib/games.ts` に麻雀（四人打ち・`mahjong4`）と数独（`sudoku`）を追加し、並びを
`App/AppGameServices.swift` の `GameRegistry`（`origin/release/v1.1.1`）と揃えたあとの LP。

撮影方法: `npm run build && npx next start -p 3111` したローカルの本番ビルドを、
headless Chrome（`--force-device-scale-factor=2`）で撮影し、幅1000の JPEG に変換したもの。

| 画面 | 画像 |
|---|---|
| トップ（12本・登録順） | `home.jpg` |
| /games/mahjong4（新規） | `mahjong4.jpg` |
| /games/sudoku（新規） | `sudoku.jpg` |

トップの「定番ゲーム12種の詰め合わせ」「収録ゲーム（12本）」は `games` 配列の長さから
導出しているため、本数のベタ書きは無い（`web/app/page.tsx`）。
