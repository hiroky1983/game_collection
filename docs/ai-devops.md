# AI 主導開発パイプライン（ai-devops）

企画 → 実装 → テスト → リリースを AI が一貫して回し、人間は**意思決定**と**ごく一部の操作**に集中するための設計と運用手順。

2026-08-10 の壁打ちでの決定事項:

- **実行基盤**: 実装はこの Mac のローカル Claude Code 中心、CI は GitHub ホステッドランナー（パブリックリポジトリのため無料）。必要に応じてクラウドのスケジュール実行（ルーティン）を併用。
- **マージ権限**: リスク階層化（下記）。
- **着手順**: Phase 1（リリース基盤）と Phase 2（実装ループ）を同時に構築。

---

## 全体ループ

```text
┌─ 企画 ── AI: ロードマップ / App Store レビューから機能案を Issue 化（ai:proposed）
│            人間: ★ Issue を読んで ai:approved ラベルを付与（却下なら close）
├─ 実装 ── AI: ai:approved の Issue を拾い branch → 実装 → テスト → PR
│            AI: verifier / code-review による敵対的レビュー
│            人間: ★ risk:ui / risk:sensitive の PR のみマージ判断
├─ テスト ─ CI: swift test + アプリビルド検証（.github/workflows/ci.yml、全自動）
├─ 配信 ── fastlane beta: 署名 → TestFlight 自動アップロード
│            人間: ★ 実機で数分さわって体感確認（唯一の「操作」）
└─ 提出 ── AI: リリースノート生成 → App Store Connect API で審査提出
             人間: ★ 提出の最終承認 / リジェクト時の対応方針決定
```

人間の関所は 4 つ（★）。すべて「判断」であり、作業は TestFlight での実機確認のみ。

## リスク階層とマージ規則

PR には必ずいずれかの `risk:*` ラベルを付ける（実装 AI が自己申告し、レビュー AI が検証する）。

| ラベル | 対象 | マージ条件 |
|---|---|---|
| `risk:logic` | ゲームロジック・AI 強化・バグ修正など UI/収益に触れない変更 | CI グリーン + AI レビュー通過で**自動マージ可** |
| `risk:ui` | 画面・操作感に影響する変更 | スクリーンショット添付 + **人間がマージ** |
| `risk:sensitive` | 広告・課金・ATT/プライバシー・審査事項に関わる変更 | **必ず人間がマージ**。自動化しない |

判断に迷う場合は上位（より人間寄り）の階層に倒す。

## PR レビュー指摘（CodeRabbit）の消化ルール

PR に付いた CodeRabbit の指摘は、**全スレッドを消化してからマージする**（`risk:logic` の自動マージでも同様）。

**CodeRabbit のレビューは CI と無関係に数分遅れて付く**（非同期）。すり抜けを防ぐ三重の仕組み（2026-08-10 稼働）:

1. **機械的ゲート**: main のブランチ保護で「CI の test 必須」+「未解決スレッドがあるとマージ不可
   (required_conversation_resolution)」を有効化済み。遅れて付いた指摘も未解決のままではマージできない。
   緊急時は会長（admin）のみバイパス可。
2. **webhook 自動対応**: PR にレビューが投稿されると（pull_request_review イベント）、クラウドの
   「CodeRabbit指摘対応係」ルーティンが自動起動し、下記トリアージを実行する。ポーリング不要。
3. **フォールバック掃き**: 同ルーティンが毎朝 7:00 JST にも起動し、取りこぼした未解決スレッドを掃く。

対応係（または PR 作成エージェント）のトリアージ3分類:

- **妥当かつ小規模** → 修正してプッシュし、スレッドに対応コミットのハッシュを返信
- **妥当でない・陳腐化**（対象コードが削除済み等）→ 理由をスレッドに返信して resolve
- **判断に迷う Security / Major・挙動を変える大きな修正** → 修正せず「【要決裁あり】」コメントで会長にエスカレーション（勝手に見送らない）

共通ルール: 修正後は CI グリーンを再確認。一括 resolve（`@coderabbitai resolve`）は**全スレッドに返信を残した後**にのみ使ってよい（無言 resolve 禁止）。対応係は対象ゼロなら何もせず終了する（自己発火ループ防止）。

## Issue ラベル（パイプライン状態）

- `ai:proposed` — AI が起案、人間の承認待ち（Issue テンプレート: 機能提案）
- `ai:approved` — 人間承認済み。実装エージェントの着手対象
- `ai:in-progress` — 実装中（二重着手防止のため着手時に AI が付ける）

## 各フェーズの実装

### テスト（稼働中）

- `.github/workflows/ci.yml` が push / PR で `swift test --package-path Packages/GameKit` とアプリの署名なしビルドを実行。
- GameKit は macOS プラットフォームを含むため、シミュレータ不要で高速にテストできる。
- 実行環境は **GitHub ホステッド macOS ランナー**（パブリックリポジトリのため無料。2026-08-10 に self-hosted から変更）。

### 実装ループ（Phase 2）

ローカルの Claude Code を起点にする。基本の運用:

1. 人間が Issue に `ai:approved` を付ける。
2. Claude Code に「承認済み Issue を実装して」と依頼（または ralph-loop / スケジュール実行で定期起動）。
3. エージェントの手順: `gh issue list --label ai:approved` → 最も優先度の高い 1 件に `ai:in-progress` を付与 → feature ブランチ作成 → 受け入れ条件を満たす実装 + テスト → verifier で敵対的検証 → PR 作成（base は現行のリリースブランチ、`risk:*` ラベル付与、受け入れ条件との対応と検証結果を本文に記載。UI 変更ならスクリーンショット添付）。
4. 並列実装させる場合は worktree 分離必須（同一ワークツリーでの並列編集は禁止）。

### 配信（Phase 1）

- `bundle exec fastlane beta` で TestFlight に自動アップロード（`fastlane/Fastfile`）。
- ビルド番号は日時 (`YYYYMMDDHHmm`) で自動採番。`MARKETING_VERSION` は `project.yml` で管理。
- リリースノートは環境変数 `TESTFLIGHT_CHANGELOG` で渡す（AI がマージ済み PR から生成する）。

### 審査提出（Phase 1.5、TestFlight 運用が安定してから）

- fastlane `deliver` でメタデータ・スクリーンショット込みの提出も自動化できる。
- 提出前に必ず人間の承認を取る。リジェクト時は AI が Resolution Center の内容を要約し、対応方針は人間が決める。

### 企画（Phase 3、最後に構築）

- スケジュール実行（クラウドルーティンまたはローカル cron）で定期的に起動し、
  `docs/` の仕様・ロードマップメモリ・App Store レビューを読んで機能案を
  「機能提案」Issue テンプレートの形式で起案（`ai:proposed`）。
- 実行系（Phase 1/2）の信頼性が上がるまでは着手しない。ネタ出しより実行の確実性が先。

---

## セットアップ（残りは人間にしかできない作業）

- [ ] **App Store Connect API キーの作成**（人間のみ・5分）
  - App Store Connect > ユーザとアクセス > 統合 > App Store Connect API でキー作成（ロール: App Manager）
  - `.p8` をダウンロードし、Mac 上の安全な場所（例: `~/.appstoreconnect/`）に保存
  - `~/.zshrc` に `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_PATH` を設定
- [ ] **fastlane のインストール**: `brew install fastlane` または `bundle install`
- [ ] **初回署名の確認**: Xcode で Team を選択し一度 Archive が通ることを確認（以後は自動）
- [ ] **GitHub Actions 設定**: リポジトリ Settings > Actions > General で
      「Require approval for all outside collaborators」を有効化（フォーク PR の実行を承認制に）
- [ ] `docs/release-checklist.md` の残項目（アプリアイコン等）の解消

## セキュリティ上の注意（重要）

このリポジトリは **PUBLIC**。

1. CI は GitHub ホステッドランナーで実行する（隔離された使い捨て VM。フォーク PR には
   シークレットが渡らない）。self-hosted runner をこのリポジトリに登録しないこと。
2. Actions 設定で外部コラボレーターの実行に承認を必須にする（上記チェックリスト）。
3. `.p8` キーや証明書は絶対にリポジトリにコミットしない（環境変数 + ローカルファイルのみ）。

## 既存の運用ルール（変更なし）

- PR のベースブランチは現行リリースブランチ（現在は `1.0.1`）。
- コミット・プッシュ・マージの最終責任は従来どおり本人（自動マージは `risk:logic` のみ、導入時期も人間が決める）。
