# アプリ全体仕様

## 概要

**アプリ名**: あそびば (Asobiba)
**プラットフォーム**: iOS 17.0+
**向き**: 縦固定 (Portrait only)
**言語**: 日本語
**収益モデル**: AdMob バナー広告 + インタースティシャル広告

---

## アーキテクチャ

### パッケージ構成

```
App/                    ← iOS アプリ本体
Packages/GameKit/
  Sources/
    Core/               ← 共通基盤 (Protocol, Theme, AdService, SnapshotStore)
    Game2048/           ← 2048
    GameShogi/          ← 将棋
    GameGomoku/         ← 五目並べ
    GameMinesweeper/    ← マインスイーパー
```

### 主要プロトコル

**`GameModule`**: ゲームをプラグイン形式で登録するプロトコル
- `id: String` — ユニーク識別子
- `title: String` — 表示名
- `icon: Image` — ハブカードのアイコン
- `makeView(services:) -> AnyView` — ゲーム画面を生成

**`AdService`**: 広告サービスの境界
- `makeBannerView() -> AnyView?` — バナー広告
- `showInterstitial() async` — インタースティシャル広告（待機付き）

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
| 規約 | 利用規約 / プライバシーポリシー (現在 WIP プレースホルダー) |
| その他 | アプリを評価する / アプリをシェア |

- 並び順・非表示設定は `UserDefaults` に保存 (キー: `gameOrder_v1`, `hiddenGames_v1`)
- 新ゲーム追加時は末尾に自動追記

---

## 広告仕様

| 種別 | 配置 |
|------|------|
| バナー (320×50 適応型) | ハブ画面・各ゲーム画面の最下部 |
| リワード | 「待った」2回目以降（将棋・五目並べ・オセロ・神経衰弱）/ マインスイーパー・2048 のコンティニュー / ポーカー・ブラックジャックのチップ回復 |

報酬を約束する広告（上表のリワード）は**視聴完了したときだけ**報酬を渡す（`showRewardedAd()` が `true` を返した場合のみ）。
視聴中断・ロード失敗時は報酬を与えず、その旨をアラートで伝える。インタースティシャルは現在どこからも使っていない。

- `DEBUG` ビルドでは自動的に Google 公式テスト広告 ID に切り替わる
- ATT 許可ダイアログ → AdMob 初期化 の順序を保証 (`ATTPermission.swift`)
- 許可・拒否どちらでも広告表示（拒否時は非パーソナライズ広告）

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
