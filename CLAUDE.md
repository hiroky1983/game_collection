# CLAUDE.md

このリポジトリは AI（Claude Code）が社長として開発・運営の意思決定を担う体制で動いている。
**このファイルはナビゲーション用の薄い入口**で、運営方針・開発ルールの正典は以下に置く
（重複させると乖離するため、方針そのものはここへ書き足さずリンク先を更新すること）。

- `docs/ai-company.md` — 運営憲章。ミッション・KPI・意思決定の経緯（会長=人間の決裁、社長=AI の実装指揮）
- `docs/ai-devops.md` — 開発パイプラインの正典。ブランチ運用（**アプリコードの PR は `release/vX.Y.Z` 向け、
  `docs/` `Scripts/` `.github/` `web/` のみ `main` 直**）、issue のラベル運用、当番（自動化された巡回）の仕事内容
- `docs/spec-app.md` — アプリ全体の仕様（アーキテクチャ・広告・解析イベント）。新しい仕組みを足したらここも更新する
- `docs/release-checklist.md` — リリース時に確認する項目

## よく使うコマンド

```bash
# GameKit のテスト
swift test --package-path Packages/GameKit

# アプリ本体のプロジェクト生成（project.yml 変更後は毎回必要）
xcodegen generate
```

## 迷ったら

- ゲーム追加の作法・ゲーム一覧: `docs/spec-app.md` の「パッケージ構成」と `App/AppGameServices.swift`
- 解析イベント（`game_start`/`game_end`/`reward_ad`）を増減させたいとき: `docs/spec-app.md` の「解析仕様」を
  先に読む。`game_id` の一覧はドキュメントで持たず `GameRegistry` から実行時に作る設計なので、
  ドキュメント側に個々のゲーム ID を書き足さない
- 上記だけで判断できない運営判断（マージ主体・リリース構成・issue の切り方など）は `docs/ai-company.md` /
  `docs/ai-devops.md` の該当箇所を必ず確認してから進める
