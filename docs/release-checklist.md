# リリース前チェックリスト（v1.0 初回リリース用・完了済み）

**この一覧は v1.0 を初めて App Store に提出する前に作った初回限定のチェックリストで、
一回きりの初期設定項目は 2026 年 8 月までに解消済み。** 以後のバージョンごとの審査提出手順
（タグ付け・ブランチ凍結など）は `docs/ai-devops.md`「運用ルール」に一本化した。
**このファイルを今後の審査提出手順の正典として参照しないこと**（旧タグ命名規則
`vX.Y.Z-build<N>` は `vX.Y.Z-submitted` に変更済みなど、ai-devops.md 側でのみ追従している）。

## 完了した初回対応（履歴として保持）

- **Bundle ID**: `com.hirockysan1983.asobiba`（`project.yml`）
- **バージョン番号運用**: `project.yml` の `MARKETING_VERSION` を手動管理、ビルド番号は
  fastlane が日時 (`YYYYMMDDHHmm`) で自動採番
- **アプリ表示名**: `あそびば`（`CFBundleDisplayName`）
- **アプリアイコン**: `App/Assets.xcassets/AppIcon.appiconset` 設定済み
- **AdMob**: 本番ユニット ID 設定済み（`AdConfig.swift`）、アカウント審査通過・収益発生済み
- **ATT ダイアログ文言**: 確定済み（`NSUserTrackingUsageDescription`）
- **利用規約・プライバシーポリシー**: `SettingsView`（規約セクション）から外部 URL を
  `SFSafariViewController` の sheet で表示（「準備中」プレースホルダーは解消済み）
- **Privacy Manifest** (`App/PrivacyInfo.xcprivacy`): 追加済み
- **App Store Connect アプリページ**: 作成済み。対応年齢レーティングは **4+ で確定**
  （Issue #32・2026-08-11 会長決裁。ポーカー・ブラックジャックの「シミュレートされたギャンブル」
  申告は行わず、Apple から指摘が来た時点で対応する運用）
- **スクリーンショット・説明文・キーワード**: 版ごとに `docs/aso/metadata-vX.Y.Z.md` で管理
- **アプリ内リンク**: 「アプリを評価する」（`requestReview()`）「アプリをシェア」（本番 App Store URL）
  ともに実装済み（`App/SettingsView.swift`）

## Game Center（ゲーム追加のたびに続く作業・完了ではない）

一回きりの初期設定ではなく、**新しいスコア系ゲームを追加するたびに続く作業**。手順・ID一覧は
`docs/game-center-setup.md`。憲章のハンコ事項6に当たるため登録・Submit for Review は会長が行う
（未実施でもアプリはクラッシュも遅延もしない。送信が黙って失敗するだけ）。

- v1.1.3 までの12ゲーム分（2048・ポーカー・ブラックジャック・ブロック崩し・マインスイーパー・
  ナンプレ・麻雀ソリティア・ソリティア 等）は登録・Submit for Review 済み
- v1.1.4 で追加したチャリンコおじさん・ブロックならべ・フリーセルの3件は
  **2026-09-11 時点で会長操作依頼が未消化**（issue #543 / #539 / #536）

## テスト（リリースのたびに確認）

- [ ] **実機テスト**（シミュレーターでは確認できない項目）
  - AdMob バナー・リワード広告の表示確認（インタースティシャルは現在どこからも呼んでいない）
  - ATT ダイアログ表示確認
  - 各ゲームの動作確認
- [ ] **機種バリエーション確認**（iPhone SE / iPhone Pro・Pro Max / iPad）
- [ ] **パフォーマンス確認**（将棋 AI の思考時間、メモリ使用量）
