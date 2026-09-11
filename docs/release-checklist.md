# リリース前チェックリスト（v1.0 初回リリース用・完了済み）

**この一覧は v1.0 を初めて App Store に提出する前に作った初回限定のチェックリストで、
全項目 2026 年 8 月までに解消済み。** 以後のバージョンごとの審査提出手順（タグ付け・
ブランチ凍結など）は `docs/ai-devops.md`「ブランチ戦略とマージ規則」に一本化した。
**このファイルを今後の審査手順の正典として参照しないこと**（旧タグ命名規則
`vX.Y.Z-build<N>` は `vX.Y.Z-submitted` に変更済みなど、ai-devops.md 側でのみ追従している）。

## 完了した初回対応（履歴として保持）

- **Bundle ID**: `com.hirockysan1983.asobiba`（`project.yml`）
- **バージョン番号運用**: `project.yml` の `MARKETING_VERSION` を手動管理、ビルド番号は
  fastlane が日時 (`YYYYMMDDHHmm`) で自動採番
- **アプリ表示名**: `あそびば`（`CFBundleDisplayName`）
- **アプリアイコン**: `App/Assets.xcassets/AppIcon.appiconset/AppIcon.png` 設定済み
- **AdMob**: 本番ユニット ID 設定済み（`AdConfig.swift`）、アカウント審査通過済み
- **ATT ダイアログ文言**: 確定済み
- **利用規約・プライバシーポリシー**: 本文を用意し `SettingsView`（規約セクション）から
  遷移可能（「準備中」プレースホルダーは解消済み）
- **Privacy Manifest** (`App/PrivacyInfo.xcprivacy`): 追加済み
- **App Store Connect アプリページ**: 作成済み。対応年齢レーティングは **4+ で確定**
  （Issue #32・2026-08-11 会長決裁。ポーカー・ブラックジャックの「シミュレートされたギャンブル」
  申告は行わず、Apple から指摘が来た時点で対応する運用）
- **スクリーンショット・説明文・キーワード**: 版ごとに `docs/aso/metadata-vX.Y.Z.md` で管理
- **Game Center**: リーダーボード・実績を登録済み。手順・ID 一覧は `docs/game-center-setup.md`
- **アプリ内リンク**: 「アプリを評価する」「アプリをシェア」ともに実装済み
  （`App/SettingsView.swift`。空クロージャ・プレースホルダー URL は解消済み）
