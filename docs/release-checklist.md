# リリース前チェックリスト

## アプリ設定

- [ ] **Bundle ID 変更**
  - 現在: `com.example.gamecollection`
  - `project.yml` の `PRODUCT_BUNDLE_IDENTIFIER` を本番IDに変更 → `xcodegen generate`

- [ ] **バージョン番号**
  - 現在: `MARKETING_VERSION = "0.1.0"`
  - `project.yml` を `1.0.0` に変更 → `xcodegen generate`

- [ ] **アプリ表示名の確認**
  - `CFBundleDisplayName` が `"Asobiba"` になっている
  - 日本語 `"あそびば"` にするか要確認

- [ ] **アプリアイコン**
  - 現在設定なし。1024×1024px の PNG を用意して `project.yml` に追加

---

## 広告 (AdMob)

- [ ] **AdMob アカウントの審査通過確認**
  - AdConfig.swift に本番ユニットIDは設定済み
    - App ID: `ca-app-pub-1869410932032409~4823987816`
    - Banner: `ca-app-pub-1869410932032409/5642245468`
    - Interstitial: `ca-app-pub-1869410932032409/6461337269`
  - AdMob コンソールでアプリが承認されているか確認

- [ ] **ATT ダイアログ文言確認**
  - `NSUserTrackingUsageDescription`: 「より関連性の高い広告を表示するために使用します。」
  - 審査でリジェクトされないよう内容が適切か確認

---

## 規約・法的コンテンツ

- [ ] **利用規約の作成**
  - 現在: SettingsView に「準備中」プレースホルダー
  - 本番前に実際の利用規約テキストを用意して差し替え

- [ ] **プライバシーポリシーの作成**
  - 同上。AdMob 使用のため広告に関する記載が必須
  - App Store Connect にも URL 登録が必要

- [ ] **Privacy Manifest ファイル** (`PrivacyInfo.xcprivacy`)
  - Apple が 2024年春以降必須化
  - UserDefaults / ファイルシステム使用の申告が必要

---

## App Store Connect

- [ ] **アプリページ作成**
  - カテゴリ: ゲーム > パズル
  - 対応年齢レーティング設定 → **4+ で確定**（Issue #32・2026-08-11 会長決裁「これは指摘を受けてから
    対応にしましょう」）。ポーカー・ブラックジャックの「シミュレートされたギャンブル」申告は行わず、
    Apple から指摘が来た時点で対応する。**この項目を理由に提出を止めない**

- [ ] **スクリーンショット用意**
  - 6.5インチ (iPhone 15 Pro Max 等): 必須
  - 5.5インチ (iPhone 8 Plus 等): 必須
  - 各ゲーム画面・ハブ画面を撮影

- [ ] **アプリ説明文 (日本語)**
  - 短い説明 (170文字以内)
  - 長い説明 (4000文字以内)
  - キーワード設定

- [ ] **サポートURL / マーケティングURL 設定**

---

## アプリ内リンク修正

- [ ] **「アプリを評価する」ボタン**
  - 現在: 空のクロージャ（何もしない）
  - App Store の URL が決まったら `SKStoreReviewController.requestReview()` または
    `UIApplication.shared.open(appStoreURL)` に差し替え

- [ ] **「アプリをシェア」リンク**
  - 現在: `URL(string: "https://apps.apple.com")!` プレースホルダー
  - 本番 App Store URL に差し替え

---

## テスト

- [ ] **実機テスト** (シミュレーターでは確認できない項目)
  - AdMob バナー・インタースティシャルの表示確認
  - ATT ダイアログ表示確認
  - 各ゲームの動作確認

- [ ] **機種バリエーション確認**
  - iPhone SE (小画面)
  - iPhone 15 Pro / 15 Pro Max (大画面)

- [ ] **パフォーマンス確認**
  - 将棋 AI の思考時間 (特に「強」レベル)
  - メモリ使用量

## 審査提出時の必須手順（2026-08-13 追加）

提出のたびに必ず実施する。省略すると「どこまでが審査に入っているか」が後から判別できなくなる。

1. 提出したビルドのコミットにタグを打つ: `git tag vX.Y.Z-build<N> <sha> && git push origin vX.Y.Z-build<N>`
2. その release ブランチを凍結する:
   ```
   gh api -X PUT repos/hiroky1983/game_collection/branches/release%2FvX.Y.Z/protection \
     --input <(echo '{"required_status_checks":null,"enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null,"lock_branch":true}')
   ```
3. 次版の release ブランチを作成し、保護を設定する（以降の作業先）。
4. 公開後に main へ取り込むのは **タグの地点まで**（凍結後に誤って積まれた分を main に入れないため）。
