# リリース前チェックリスト

> **注記（2026-09-11）**: これは初回リリース（v1.0）前に作成した準備チェックリストで、
> あそびばは既に v1.0〜v1.1.3 を App Store で公開済み。下記の一回きりの初期設定項目は
> 完了しているため実測に基づき更新した。**今後の版でも繰り返し使うのは末尾の
> 「審査提出時の必須手順」だけ**。

## アプリ設定

- [x] **Bundle ID 変更**
  - `com.hirockysan1983.asobiba`（`project.yml` の `PRODUCT_BUNDLE_IDENTIFIER`）

- [x] **バージョン番号**
  - `project.yml` の `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` で管理し、
    リリースのたびに更新している（例のように固定の数字ではない。現在値は `project.yml` を直接参照）

- [x] **アプリ表示名の確認**
  - `CFBundleDisplayName` は日本語 `"あそびば"`

- [x] **アプリアイコン**
  - 設定済み（`App/Assets.xcassets/AppIcon.appiconset`）

---

## 広告 (AdMob)

- [x] **AdMob アカウントの審査通過確認**
  - AdConfig.swift に本番ユニットIDは設定済み
    - App ID: `ca-app-pub-1869410932032409~4823987816`
    - Banner: `ca-app-pub-1869410932032409/5642245468`
    - Interstitial: `ca-app-pub-1869410932032409/6461337269`
  - 承認済み・実際に広告収益が発生している（2026-09 時点）

- [ ] **ATT ダイアログ文言確認**
  - `NSUserTrackingUsageDescription`: 「より関連性の高い広告を表示するために使用します。」
  - 審査でリジェクトされないよう内容が適切か確認

---

## 規約・法的コンテンツ

- [x] **利用規約の作成**
  - `SettingsView` から外部 URL（`https://web-murex-sigma-62.vercel.app/terms`）を
    `SFSafariViewController` の sheet で表示

- [x] **プライバシーポリシーの作成**
  - 同上（`.../privacy`）

- [x] **Privacy Manifest ファイル** (`PrivacyInfo.xcprivacy`)
  - `App/PrivacyInfo.xcprivacy` として存在

---

## App Store Connect

- [x] **アプリページ作成**
  - カテゴリ: ゲーム > パズル、対応年齢レーティング 4+ で公開済み（Issue #32・2026-08-11 会長決裁）。
    ポーカー・ブラックジャックの「シミュレートされたギャンブル」申告は据え置き方針のまま

- [x] **スクリーンショット用意**
  - `docs/aso/screenshots/`（iPhone・iPad 分）に版ごとの撮影一式あり。ゲーム数の増加に
    追従して入稿を都度更新する運用（直近は `docs/aso/metadata-v1.1.3.md` 参照）

- [x] **アプリ説明文 (日本語)**
  - `docs/aso/metadata-v1.1.*.md` に版ごとの確定文言・キーワードを記録

- [x] **サポートURL / マーケティングURL 設定**
  - LP（`web/`）を利用規約・プライバシーポリシーと同じドメインで運用

- [ ] **Game Center の設定**（#289・v1.1.1 で実装。**会長のコンソール操作が必要**）
  - バージョンページの「Game Center」を**有効化**する（これが無いと iOS 26「ゲーム」アプリの
    ソーシャル推薦・Top Played チャートに載る資格が得られない）
  - リーダーボード10件・実績4件を登録し、**Add for Review → Submit for Review** まで行う
    （登録しただけでは `Live` にならない）
  - 手順・ID・ソート順の一覧は **`docs/game-center-setup.md`**
  - 未実施でもアプリはクラッシュも遅延もしない（送信が黙って失敗するだけ）ため、**この項目を
    理由に提出を止めなくてよい**。ただし実施するまで本機能は誰にも見えない

---

## アプリ内リンク修正

- [x] **「アプリを評価する」ボタン**
  - `requestReview()` を実装済み

- [x] **「アプリをシェア」リンク**
  - 本番 App Store URL に差し替え済み

---

## テスト

- [ ] **実機テスト** (シミュレーターでは確認できない項目)
  - AdMob バナー・リワード広告の表示確認（インタースティシャルは現在どこからも呼んでいない）
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
