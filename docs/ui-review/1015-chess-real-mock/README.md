# #1015 チェス駒「リアル」意匠のモック（第1段階）

アプリ本体には入れない比較用モック。`bash build.sh <作業dir>` で macOS 上にビルドし、比較画像を出す。
現行の立体駒の描画コード（`ChessPieceShapes.swift` / `ChessPieceStyle.swift`）はリポジトリのものをそのまま使う。

- **A′**（`RealMockA2D.swift`）: 回転体の断面を細い帯に刻み、帯ごとに円筒のグラデーションを敷いた 2D ベクター描画。輪郭線なし・接地影あり。ナイトだけ面分割。
- **C**（`RealMockScene.swift`）: 同じ断面を回転した 3D モデル（自作）を SceneKit で描画。ナイトは横顔を押し出し。焼き画像（透明 PNG）にして容量を測る。
- 両者は同じ断面（`RealMockProfiles.swift`）を使うので、差は描き方だけ。

画像はすべて自作。他者の画像・3D 素材・フォントは使っていない。
容量の実測は `bake-size.txt`。
