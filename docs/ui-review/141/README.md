# #141 麻雀牌のデザインを本来の絵柄に — 画面確認

シミュレータ iPhone 17 Pro Max / iOS 26.5、Debug ビルド（`-screenshotMode` で広告を出さない）。

## before-after.jpg

同じ画面（`-startGame mahjong`・ズーム OFF）の修正前後。配牌は乱数なので並びは一致しない。

- **Before**: 筒子が「円の輪郭＋算用数字」、索子が「角丸長方形＋算用数字」。白は「白」の字。
- **After**: 筒子は円を n 個、索子は竹を n 本、いずれも実物の牌と同じ配置。白は無地に枠のみ。

## tiles-all-sizes.jpg

全 42 種（標準 34 種＋ソリティア専用の花牌 4・季節牌 4）を 3 サイズで並べたもの。
アプリを `-showMahjongTiles` で起動すると出る（DEBUG 限定・`MahjongTileGallery`）。

| 幅 | 意味 |
|---|---|
| 18pt | 画面の狭い端末を想定した下限側の確認 |
| **22pt** | **iPhone 17 Pro Max でズーム OFF のときの盤面の実測値**（受け入れ条件の本命） |
| 40pt | ズーム ON（`MahjongSolitaireView.zoomedTileWidth`）と同じ大きさ |

22pt でも 42 種すべてが見分けられる。数牌は「数を数える」のではなく**並びの形**で見分ける
（六筒 = 2×3 / 八筒 = 2×4 / 九筒 = 3×3 など）ため、粒が小さくても種類が判別できる。

小さいときだけ落とす装飾は次の 2 つ。どちらも省いても種類の判別には影響しない。

- 筒の内側の輪（同心円）: 筒 1 つの直径が 7pt 未満なら塗り潰しの丸にする
- 竹の節: 竹 1 本の高さが 12pt 未満なら描かない

## board-zoom-off.jpg

実際の盤面（ズーム OFF）。牌が重なり、取れない牌が減光された状態でも絵柄が読める。

## 再現方法

```sh
xcodebuild -project GameCollection.xcodeproj -scheme GameCollection \
  -configuration Debug -sdk iphonesimulator -destination "id=$UDID" \
  -derivedDataPath /tmp/dd CODE_SIGNING_ALLOWED=NO build
xcrun simctl install "$UDID" /tmp/dd/Build/Products/Debug-iphonesimulator/GameCollection.app
xcrun simctl launch "$UDID" com.hirockysan1983.asobiba -screenshotMode -showMahjongTiles   # 牌一覧
xcrun simctl launch "$UDID" com.hirockysan1983.asobiba -screenshotMode -startGame mahjong  # 盤面
```

ズーム ON は画面内のボタンをタップしないと切り替わらず、シミュレータへの自動タップは使えないため、
牌一覧の 40pt の段（= `zoomedTileWidth` と同値）で描画の確認に代えている。
