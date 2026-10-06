# あそびば (Asobiba)

iOS 向けの定番ゲーム集アプリ。将棋・麻雀・ナンプレなどの盤・カード系から、
チャリンコおじさん（横スクロールランナー）のようなアクション枠まで、
20 タイトルをひとつのハブから遊べる（未リリースのものを含む。詳細は `docs/spec-app.md`）。

- **Bundle ID**: `com.hirockysan1983.asobiba`
- **対応**: iOS 17.0+ / iPhone・iPad、縦画面固定、日本語
- **収益モデル**: AdMob バナー広告 + リワード広告

## 構成

```
App/                    ← iOS アプリ本体（GameRegistry・AppEnvironment・設定画面など）
Packages/GameKit/
  Sources/
    Core/               ← 共通基盤（GameModule プロトコル・広告・解析・永続化・救済導線）
    Game*/              ← ゲームごとのモジュール（1ゲーム = 1パッケージターゲット）
  Tests/                ← ゲームごとの単体テスト + 横断テスト（アクセシビリティ等）
web/                    ← LP（Next.js。利用規約・プライバシーポリシーも配信）
docs/                   ← 仕様・運営ドキュメント（下記）
Scripts/                ← 運営自動化（当番・週次レビュー等）と ASO 補助スクリプト
```

新しいゲームを追加するときは `Packages/GameKit/Sources/GameXxx` にモジュールを作り、
`App/AppGameServices.swift` の `registry` に 1 行追加するだけでハブに表示される。

## セットアップ / ビルド

```bash
brew install xcodegen
xcodegen generate
open GameCollection.xcodeproj
```

## テスト

```bash
swift test --package-path Packages/GameKit
```

CI（`.github/workflows/`）でも同じテストと、署名なしでの実機ビルド検証を行っている。

## ドキュメント

- `docs/ai-company.md` — 運営憲章（このプロジェクトは AI が社長として開発・運営の意思決定を担う）
- `docs/ai-devops.md` — 開発パイプライン（issue → 実装 → PR → リリースの運用ルール）
- `docs/spec-app.md` — アプリ全体のアーキテクチャ・広告・解析（Analytics）仕様
- `docs/spec-*.md` — 個別ゲームの詳細仕様（一部のゲームのみ）
- `docs/release-checklist.md` — リリース時のチェックリスト
- `docs/aso/` — ストア掲載文言・スクリーンショットの版ごとの記録
