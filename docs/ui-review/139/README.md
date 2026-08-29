# #139 対局終了時に盤面が縮む — 画面確認

シミュレータ iPhone 17 / iOS 26.5。盤面は**赤枠の外接矩形をピクセル単位で実測**し、
一辺の長さ（pt = 実測ピクセル ÷ 3）を各パネルに添えている。

## before-after.jpg

修正前後の「決着直前 → 決着直後（投了）」の比較。

| | 対局中 | 決着直後 | 差 |
|---|---|---|---|
| 修正前 | 334pt | 175pt | **-159pt（-48%）** |
| 修正後 | 321pt | 321pt | **0pt** |

修正前の終局後は、記録ラベル・検討ナビ・「もう一度」・レコメンドの4つが縦に積み増しになり、
`board`（`aspectRatio(1, .fit)` + `layoutPriority(1)`）が帳尻合わせに縮んでいた。

## after-all-cases.jpg

修正後、終局後に出るものの組み合わせが変わっても盤は 321pt のまま。

- 対局中
- 決着直後（投了・レコメンドあり）
- 決着直後（詰み・レコメンドなし。CPU が実際に詰ませた局面）
- 検討で手を戻した状態（6/12手）

## 再現方法

シミュレータの**データコンテナ配下**（ホストのホームではない）に中断スナップショットを書き込み、
`-startGame shogi` で起動する。

```sh
BUNDLE_ID=com.hirockysan1983.asobiba
DATA_CONTAINER="$(xcrun simctl get_app_container booted "$BUNDLE_ID" data)"
SNAPSHOT_DIR="$DATA_CONTAINER/Library/Application Support/Snapshots"
mkdir -p "$SNAPSHOT_DIR"
# "$SNAPSHOT_DIR/shogi.json" に ShogiSnapshot の JSON を書く
xcrun simctl launch booted "$BUNDLE_ID" -startGame shogi
```

記録ラベル（`playLog_records_v1`）を出すときは、コンテナの plist を直接書くと cfprefsd に
上書きされるため `xcrun simctl spawn booted defaults write "$BUNDLE_ID" ...` を使う。レコメンドは
`-simulateRecommendation gomoku`（DEBUG 限定の起動引数）で条件を通さずに出せる。
詰みの検証には「後手の合法手が金 5g→5h の 1 手だけで、それが詰み」になる局面
（SFEN `9/9/9/9/9/4l4/3pgp3/3p1p3/3pKp3 w - 1`）を使い、CPU に実際に詰ませている。
