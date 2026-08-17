# #156 LP のゲーム一覧を実装（10本）に追従 — 画面確認

`web` を `npm run build` → `npm start`（ローカル・ポート 3111）で立ち上げ、
headless Chrome（`--headless=new --window-size=900,<高さ> --screenshot`）で撮影したもの。

## top.jpg

トップページ。**本数・ゲーム名の列挙はすべて `web/app/lib/games.ts` の `games` から導出**していて、
ベタ書きの「8」は残っていない。

- 見出し「定番ゲーム**10**種の詰め合わせ」
- 導入文のゲーム名がアプリの登録順（`App/AppGameServices.swift`）どおり10本
- 「通信不要。電波の無い場所でも**10**本すべて動きます」
- 「収録ゲーム（**10**本）」＋カード10枚（末尾に大富豪・麻雀ソリティア）

## daifugo.jpg

新規追加した `/games/daifugo`。遊び方・特徴は `Packages/GameKit/Sources/GameDaifugo` の
実装（`DaifugoRules` の革命・8切り・反則上がり・カード交換、`DaifugoView` のルール表示、
`DaifugoModel` の中断保存）で確認できる範囲だけを書いている。

## mahjong-solitaire.jpg

新規追加した `/games/mahjong-solitaire`。同じく `GameMahjongSolitaire` の実装
（144枚の亀型レイアウト、`isFree` の「上に載っていない かつ 左右どちらかが空いている」、
花牌・季節牌どうしが組になる `MahjongFace.matches`、ヒント／並べ替えが無制限・広告不要、
必ず取り切れる盤面のみ配る `solution`、クリアタイムの自己ベスト）に基づく。

「上海」は本実装（亀型に積んだ牌を2枚ずつ消す）の一般的な別名なのでそのまま採用したが、
**「二角取り」は平面の盤で線をつないで消す別ゲーム**なので、検索語としては入れつつ
「とは別ルールです」と明記して誤誘導にならないようにしている。

## og-daifugo.jpg / og-mahjong-solitaire.jpg

`web/scripts/generate-og-images.mjs` で生成した OGP 画像（実体は 1200×630 PNG。
ここに置いているのは確認用に JPEG 化したもの）。フッターの「無料ゲーム**10**種」も
`games.length` から導出するよう直したので、全11枚（default + 10ゲーム）を再生成している。

## 撮影上の注意

viewport 幅 430px（モバイル相当）でも撮ってみたが、headless Chrome では**本 PR で触っていない
`/privacy` でも同じように右端が切れる**ため、コンテンツ幅の判断材料にならないと考えて採用しなかった。
レイアウト自体は既存のまま（`max-w-2xl mx-auto px-6`）で、本 PR では文言の生成方法しか変えていない。

## 再現方法

`npm start` はフォアグラウンドで動き続けるため、**サーバーの起動と撮影は別のターミナルで**行う。

ターミナル1（サーバー。撮影が終わるまで起動したままにする）:

```sh
cd web
export PATH="$HOME/.nodenv/shims:$PATH"   # システム既定の node v14 では npm ci が失敗する
npm ci && npm run build
npm start -- -p 3111
```

ターミナル2（撮影）:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --disable-gpu --hide-scrollbars --window-size=900,1960 \
  --screenshot=top.png "http://localhost:3111/"
```
