# Game Center の App Store Connect 設定（会長の操作用・#289）

アプリ側の実装（認証・リーダーボード送信・実績送信）は完了している。**この文書の登録が済むまで、
送信は App Store Connect 側に受け皿が無いため黙って失敗する**（アプリはクラッシュも遅延もしない）。

憲章のハンコ事項6（各種コンソール操作）に当たるため、実施は会長。作業は App Store Connect の
Web UI のみで完結し、コードの再ビルドは不要。

## 0. 前提（段階①で引き渡し済み）

- App Store Connect → あそびば → **対象バージョンのページ**で「Game Center」を有効にする。
- これを有効にしないと、iOS 26「ゲーム」アプリの Home / Friends タブのソーシャル推薦と
  Top Played チャート（App Store 上にも出る）に載る資格が得られない。

## 1. リーダーボード（10件）

App Store Connect → あそびば → 「Game Center」→ リーダーボード → **クラシックリーダーボード**を追加。

「リーダーボード ID」は下表の文字列と**1文字も違わないこと**（アプリ側がこの文字列で送る）。
スコアフォーマットの「ソート順」を間違えると順位が逆になるので、下表の指定に従う。

| リーダーボード ID | 表示名（日本語・推奨） | フォーマット | ソート順 |
|---|---|---|---|
| `asobiba.2048.score` | 2048 ハイスコア | 整数 | High to Low（高い順） |
| `asobiba.poker.chips` | ポーカー 最高チップ | 整数 | High to Low |
| `asobiba.blackjack.chips` | ブラックジャック 最高チップ | 整数 | High to Low |
| `asobiba.minesweeper.time.beginner` | マインスイーパー 初級 最短タイム | 経過時間（秒） | **Low to High（短い順）** |
| `asobiba.minesweeper.time.intermediate` | マインスイーパー 中級 最短タイム | 経過時間（秒） | **Low to High** |
| `asobiba.minesweeper.time.expert` | マインスイーパー 上級 最短タイム | 経過時間（秒） | **Low to High** |
| `asobiba.sudoku.time.easy` | 数独 かんたん 最短タイム | 経過時間（秒） | **Low to High** |
| `asobiba.sudoku.time.normal` | 数独 ふつう 最短タイム | 経過時間（秒） | **Low to High** |
| `asobiba.sudoku.time.hard` | 数独 むずかしい 最短タイム | 経過時間（秒） | **Low to High** |
| `asobiba.mahjongsolitaire.time` | 麻雀ソリティア 最短タイム | 経過時間（秒） | **Low to High** |

**送る値の単位は「秒」**（整数）。フォーマットに「経過時間 - 分:秒」等を選ぶ場合も、アプリが送るのは
秒数そのもの。

### 対象を10件に絞った理由

- 出すのは「同じ条件で誰でも挑める、客観的に比較できる記録」だけ。盤面や配牌が毎回変わる対 CPU 戦
  （将棋・五目並べ・オセロ・大富豪・四人打ち麻雀・神経衰弱）は勝敗しか残らず、順位表にすると
  「たくさん遊んだ人」が上に来るだけなので対象外にした。
- 難易度・盤サイズがあるゲームは区分ごとに別の表にする。初級と上級のタイムを同じ表に混ぜると、
  初級を選んだ人が常に上位に来て意味を成さない。
- マインスイーパーは**プリセット3種だけ**。カスタム盤（任意の行列・地雷数）は区分が無限に増え、
  ここに登録しきれないため送らない。

## 2. 実績（4件）

App Store Connect → あそびば → 「Game Center」→ 実績 を追加。ポイントの合計は 1000 以内である必要が
あるため、下表は合計 300 に収めてある（後から増やせる）。

| 実績 ID | 表示名（推奨） | 説明（推奨） | ポイント | 解除条件（アプリ側の実装） |
|---|---|---|---|---|
| `asobiba.achievement.firstwin` | はじめての勝利 | どれか1つのゲームで初めて勝つ / クリアする | 25 | 通算勝利数 1 |
| `asobiba.achievement.wins10` | 常連 | 通算10勝 | 75 | 通算勝利数 10 |
| `asobiba.achievement.wins50` | あそびばの主 | 通算50勝 | 150 | 通算勝利数 50 |
| `asobiba.achievement.playall` | 全制覇 | すべてのゲームを1回ずつ遊ぶ | 50 | 遊んだゲーム数がハブの登録数に達する |

`asobiba.achievement.playall` は進捗つき（遊んだ本数 ÷ 登録ゲーム数）で送るため、Game Center 上でも
途中経過が見える。**登録ゲーム数はアプリ側の登録数（現在12本）**で、ゲームが増えれば分母も自動で増える。

実績には画像が必要（512×512）。用意が無い場合は App Store Connect の既定のプレースホルダで登録し、
後から差し替えてよい。

### 実績を4件に絞った理由

ゲーム1本ごとに実績を作ると12個になり、そのぶん名前・説明・画像の登録作業が積み上がる。ここでは
ゲーム横断で意味を持つ4個に絞り、いずれも**すでにアプリが持っている値**（通算勝利数・遊んだゲーム数）
だけから計算している（新しい保存項目を増やしていない）。ゲーム別の実績は、必要になったら
`Packages/GameKit/Sources/Core/GameCenter.swift` の対応表に足すだけで増やせる。

## 3. 登録しなかった場合に起きること

- アプリはクラッシュしない・遅くならない。送信は投げっぱなしで、失敗は握りつぶす。
- リーダーボード・実績が Game Center 上に現れないだけ。
- **段階①（認証）は独立して効く**ため、この文書の登録が未了でも Top Played チャートと
  ソーシャル推薦の資格そのものは（バージョンページの Game Center を有効にしていれば）得られる。

## 4. 実装側の参照

- 対応表と選定理由: `Packages/GameKit/Sources/Core/GameCenter.swift`
- 送信の実体（Apple の GameKit 呼び出し）: `App/AppGameCenterService.swift`
- 認証（段階①）: `App/GameCenterAuth.swift`
- ID の食い違い・重複を落とすテスト: `Packages/GameKit/Tests/GameCenterTests/GameCenterTests.swift`
