# アプリ全体仕様

## 概要

**アプリ名**: あそびば (Asobiba)
**プラットフォーム**: iOS 17.0+
**向き**: 縦固定 (Portrait only)
**言語**: 日本語
**収益モデル**: AdMob バナー広告 + リワード広告（インタースティシャルは実装はあるがどこからも呼んでいない）

---

## アーキテクチャ

### パッケージ構成

```
App/                    ← iOS アプリ本体（GameRegistry・AppEnvironment 等）
Packages/GameKit/
  Sources/
    Core/               ← 共通基盤 (Protocol, Theme, AdService, Analytics, SnapshotStore, RewardedRescue)
    Game2048/           ← 2048
    GameBlockPuzzle/    ← ブロックならべ（未リリース。2026-09-10 時点）
    GameShogi/          ← 将棋
    GameMahjong/        ← 麻雀（4人打ち）
    GameSudoku/         ← ナンプレ
    GameOthello/        ← オセロ
    GameGo/             ← 囲碁
    GameChess/          ← チェス
    GameMahjongSolitaire/ ← 麻雀ソリティア
    GameSolitaire/      ← ソリティア（クロンダイク）
    GameFreeCell/       ← フリーセル（未リリース。2026-09-10 時点）
    GameDaifugo/        ← 大富豪
    GamePoker/          ← ポーカー
    GameBlackjack/      ← ブラックジャック
    GameMinesweeper/    ← マインスイーパー
    GameGomoku/         ← 五目並べ
    GameConcentration/  ← 神経衰弱
    GameBlocks/         ← ブロック崩し（未リリース。2026-09-10 時点）
    GameRunner/         ← チャリンコおじさん（横スクロールランナー・未リリース。2026-09-10 時点）
    GameHanafuda/       ← 花札こいこい（未リリース。2026-09-10 時点）
```

登録順・表示順の正典は `App/AppGameServices.swift` の `registry`（新ゲームは 1 行追加するだけ）。
「未リリース」は App Store 配信中のバイナリにまだ含まれていないという意味で、コード上は
他のゲームと同格に動く（`GameRegistry` はストア配信状態を持たない）。配信中かどうかは
別途 ASO ドキュメント（`docs/aso/`）やリリースノートで確認すること。

### 主要プロトコル

**`GameModule`**: ゲームをプラグイン形式で登録するプロトコル
- `id: String` — ユニーク識別子
- `title: String` — 表示名
- `icon: Image` — ハブカードのアイコン
- `makeView(services:) -> AnyView` — ゲーム画面を生成

**`AdService`**: 広告サービスの境界
- `makeBannerView(width:) -> AnyView?` — バナー広告
- `showInterstitial() async` — インタースティシャル広告（待機付き。プロトコルには残っているが呼び出し箇所は無い）
- `showRewardedAd() async -> Bool` — リワード広告（視聴完了で true）。`GameServices` 経由で
  呼ぶと `game_id` / `purpose` 付きで `reward_ad` イベントも送られる（後述の解析仕様）

**`SnapshotStore`**: ゲーム状態の永続化
- `save(_:for:)` / `load(_:for:)` / `exists(for:)` / `clear(for:)`
- 実装: `FileSnapshotStore`（JSON → アプリの Documents/snapshots/）

### 依存注入

`AppEnvironment` にシングルトンで集約:
```swift
AppEnvironment.services  // GameServices (SnapshotStore + AdService)
AppEnvironment.registry  // GameRegistry (登録ゲーム一覧)
AppEnvironment.settings  // GameSettings (並び順・表示設定)
```

---

## ハブ画面 (HubView)

- `NavigationStack` ベース
- 登録ゲームをカード形式で 2 列グリッド表示（全ゲームが 1 画面に収まることを優先。#119）
- カード: ゲームアイコン / タイトル / 1 行（プレイ記録があれば記録・無ければゲームの説明） /
  右上に「続きから」バッジ（スナップショットあり時）
- 右上: ⚙️ 設定ボタン → `SettingsView` (sheet)
- 下部: AdMob バナー

---

## 設定画面 (SettingsView)

Sheet で表示。`List` + `EditMode` 常時有効。

| セクション | 内容 |
|------|------|
| アプリ | バージョン表示 |
| あそび | ゲームの並び替え (ドラッグ) + 表示/非表示トグル |
| 規約 | 利用規約 / プライバシーポリシー（外部 URL を `SFSafariViewController` の sheet で表示） |
| その他 | アプリを評価する / アプリをシェア |

- 並び順・非表示設定は `UserDefaults` に保存 (キー: `gameOrder_v1`, `hiddenGames_v1`)
- 新ゲーム追加時は末尾に自動追記

---

## 広告仕様

| 種別 | 配置 |
|------|------|
| バナー (320×50 適応型) | ハブ画面・各ゲーム画面の最下部 |
| リワード | ほぼ全ゲーム共通の「救済」導線（`RewardedRescue` 経由。下表） |

報酬を約束する広告（リワード）は**視聴完了したときだけ**報酬を渡す（`showRewardedAd()` が `true` を返した場合のみ）。
視聴中断・ロード失敗時は報酬を与えず、その旨をアラートで伝える。インタースティシャルは現在どこからも使っていない。

- `DEBUG` ビルドでは自動的に Google 公式テスト広告 ID に切り替わる
- ATT 許可ダイアログ → AdMob 初期化 の順序を保証 (`ATTPermission.swift`)
- 許可・拒否どちらでも広告表示（拒否時は非パーソナライズ広告）

### リワード救済（`RewardedRescue`・#526）

各ゲームの View に同じ形で散っていた「連打ガード → 広告視聴 → 局ガード照合 → 適用 → 失敗アラート」の
5点セットを `Core/RewardedRescue.swift` の1か所に集約したもの（この設計により、新しい救済を足しても
連打ガードや局ガードの実装漏れが起きない）。ほぼ全ゲーム（2048・将棋・五目並べ・麻雀・麻雀ソリティア・
ソリティア・フリーセル・ポーカー・ブラックジャック・マインスイーパー・オセロ・囲碁・チェス・神経衰弱・
ブロック崩し・ブロックならべ・チャリンコおじさん、2026-09-11 時点）が採用している。
救済の種類（`RewardPurpose`）は次の7つに閉じる:

| purpose | 内容 |
|---|---|
| `undo` | 「戻す」「待った」の補充 |
| `continue` | ゲームオーバーからそのまま続ける（盤面を保ったまま再開） |
| `revival` | 失った残機・持ち駒などを回復して復活 |
| `hint` | ヒントの表示・補充 |
| `joker` | ジョーカー（万能札）の付与 |
| `checkpoint` | チェックポイントからのやり直し |
| `shuffle` | 手詰まりの盤面を、取り切れる配置へ並べ替える（麻雀ソリティア） |

---

## 解析仕様（Analytics・#158 / #500）

`Core/Analytics.swift` に**送信するイベントを3種だけに閉じた** `AnalyticsEvent` enum がある。
呼び出し側（各ゲーム）は任意のキー・値を足せず、イベントを増やすには enum にケースを足す必要がある
（＝意図しないイベント発生や、ドキュメントと実装が知らないうちに乖離することを型で防ぐ設計）。

| イベント名 | 発火タイミング | パラメータ |
|---|---|---|
| `game_start` | 1プレイの開始（冪等。中断からの復元では送らない） | `game_id`、難易度を持つゲームのみ `level` |
| `game_end` | 1プレイの終わり（決着 win/loss/draw、または途中離脱 quit） | `game_id` / `result`(win\|loss\|draw\|quit) / `duration_sec` |
| `reward_ad` | リワード広告の**視聴完了**（`RewardedRescue` 経由） | `game_id` / `purpose`（上表の7値） |

- `game_id` の全量は**コード上の一覧を文書側で持たない**（`App/AppGameServices.swift` の
  `registry.modules.map(\.id)` から実行時に作られる）。新ゲームを `registry` に登録するだけで
  自動的に対象へ入るため、**このドキュメントに `game_id` の値そのものを列挙しない**
  （列挙すると新ゲーム追加のたびに手動同期が要り、漏れの温床になる。実際の値は各ゲームの
  `GameModule.id` を参照すること）
- `level`（`AnalyticsLevel`）はゲームごとの難易度呼称をゲーム横断で読める4段階
  （`beginner`/`normal`/`hard`/`expert`）か、面を進めるゲームは `stage-N` に正規化して送る。
  写像は各ゲームの `analyticsLevel` に置く
- 送信は `GameAnalytics`（`Core/Analytics.swift`）が一括管理し、二重発火の抑制・経過秒の計測・
  離脱と休憩の切り分けをここ1か所に閉じ込める。個々のゲームは
  「開始した」「1手指した」「やり直した」「終局した」「画面を離れた」を伝えるだけでよい
- 設定でオン/オフした境界をまたいだプレイは `game_start`/`game_end` の対応を保証しないため、
  トグル時点で計測中の状態を丸ごと捨てる（`discardPlayState()`。#212）

---

## テーマ / デザイン

`Theme.swift` で一元管理:
- メインカラー: `Theme.coral` (オレンジ系)
- アクセント: `Theme.teal` (青緑) / `Theme.yellow` / `Theme.ink`
- カードスタイル: `.popCard()` modifier (白背景 + 影)
- 背景: `.popBackground()` modifier
- フォント: `.rounded` デザイン

ゲームカードのアクセントカラーは `Theme.palette` からインデックス順に自動割り当て。

---

## アクセシビリティ

### アニメーション（Reduce Motion 追従・#210）

**新規のアニメーションは必ず `Core` の `Motion` ヘルパー経由で書く**（素の `withAnimation` /
`.animation(_:value:)` を直接使わない）。

| 用途 | 使うもの |
|---|---|
| 宣言的な指定 | `.gameAnimation(_:value:)`（`.animation(_:value:)` の代わり） |
| 命令的な指定 | `withGameAnimation(_:_:)`（`withAnimation(_:_:)` の代わり） |

OS の「視差効果を減らす」が ON のときはアニメーションを `nil`（＝即時反映）に落とし、
**状態変更そのものは必ず実行する**。OFF のときは要求どおりのアニメーションを通すので、
既定の見た目は変わらない。

理由は2つ。①盤面の駒・カード・牌が動く演出は前庭障害・動揺病のあるユーザーに直接影響する。
②App Store の Accessibility Nutrition Labels に **Reduced Motion** の宣言項目があり、
基準は「アニメーションを減らした状態でもすべての一般的なタスクを完了できること」。
1箇所でも追従しないと申告が成立しない。

この規約は `AccessibilityTests` の「アニメーションは Core のヘルパー経由でのみ書かれている」で
機械的に担保している（`Sources/Core` 以外に素の呼び出しが混じるとテストが落ちる）。
