import Testing
import Foundation

// MARK: - 内部トラフィックの分別（#347 → #382）

/// 実ユーザーの指標に開発ビルドを混ぜないための仕掛けは App ターゲット
/// （`BuildChannel` / `AdConfig` / `Info.plist`）にあり、GameKit のテストからは import できない。
/// そのため `GameCenterEntryPointTests` と同じくソースと plist を走査して固定する。
///
/// 固定する事実は2つ（#382 で会長決裁 A）:
/// 1. Firebase の収集は `Info.plist` で**既定オフ**。`applyAnalyticsCollectionState()` が
///    許可した経路でだけ ON になる（`FirebaseApp.configure()` 直後の窓を塞ぐ）
/// 2. App Store のレシートが確認できないビルドは `appstore` に倒れない
///    （倒れると本番広告ユニットを叩き、GA4 でも実ユーザーとして数えられる）
@Suite("内部トラフィックの分別")
struct InternalTrafficSeparationTests {
    private static var appDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AnalyticsTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // GameKit/
            .deletingLastPathComponent()   // Packages/
            .deletingLastPathComponent()   // リポジトリのルート
            .appendingPathComponent("App")
    }

    private func appSource(_ fileName: String) throws -> String {
        try String(contentsOf: Self.appDirectory.appendingPathComponent(fileName), encoding: .utf8)
    }

    /// コメント行を落としたソース。`BuildChannel.swift` は判定の理由を doc コメントで説明しており、
    /// そこに `sandboxReceipt` などの語が**コードより前に**現れる。素の文字列で位置を比べると
    /// コメントの側にヒットして、順序の検証が意味を失う。
    private func appCode(_ fileName: String) throws -> String {
        try appSource(fileName)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    @Test("Firebase の収集は Info.plist で既定オフになっている")
    func analyticsCollectionIsDisabledByDefault() throws {
        let data = try Data(contentsOf: Self.appDirectory.appendingPathComponent("Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let info = try #require(plist as? [String: Any], "Info.plist が辞書として読めない")

        let value = try #require(
            info["FIREBASE_ANALYTICS_COLLECTION_ENABLED"] as? Bool,
            "FIREBASE_ANALYTICS_COLLECTION_ENABLED が無い。configure() 直後から自動収集が走る（#382）"
        )
        #expect(value == false, "収集の既定が ON に戻っている")
        // 恒久無効化のキーとは別物。こちらを立てると設定を ON にしても二度と収集できなくなる。
        #expect(info["FIREBASE_ANALYTICS_COLLECTION_DEACTIVATED"] == nil,
                "DEACTIVATED は runtime で戻せないため使ってはならない")
    }

    @Test("収集を ON にするのは許可された経路だけ")
    func collectionIsEnabledOnlyForAllowedChannels() throws {
        let code = try appCode("AppGameServices.swift")
        // 撮影モード・非許可チャネル・設定オフのどれか1つでも欠けると内部トラフィックが混ざる。
        #expect(
            code.range(
                of: #"!isScreenshotMode\s*&&\s*isAllowedChannel\s*&&\s*settings\.analyticsEnabled"#,
                options: .regularExpression
            ) != nil,
            "収集を ON にする条件（撮影モード / チャネル / 設定）の結線が変わっている"
        )
        #expect(code.contains("BuildChannel.current != .debug"),
                "debug チャネルを除外する判定が消えている")
    }

    @Test("レシートを確認できないビルドは appstore に倒れない")
    func missingReceiptDoesNotFallBackToAppStore() throws {
        let code = try appCode("BuildChannel.swift")

        // Xcode からビルドしたアプリは appStoreReceiptURL が URL を返すのにファイルが無い。
        // nil チェックだけでは Release 構成の Xcode 実行・シミュレータを弾けない。
        #expect(code.contains("FileManager.default.fileExists(atPath: receiptURL.path)"),
                "レシートの実在確認が無い。URL の有無だけでは内部の Release ビルドを弾けない（#382）")

        // 「レシートが無ければ debug」が「sandboxReceipt なら testflight」より**前**にあること。
        // 順序が入れ替わると、レシート不在のビルドが最後の return で appstore に落ちる。
        let fallback = try #require(
            code.range(of: #"else \{\s*return \.debug"#, options: .regularExpression),
            "レシート不在時のフォールバックが見つからない（走査のパターンが壊れている可能性）"
        )
        let sandboxCheck = try #require(
            code.range(of: "sandboxReceipt"),
            "TestFlight 判定が見つからない"
        )
        #expect(fallback.lowerBound < sandboxCheck.lowerBound,
                "レシート不在の判定より先に配布経路を確定させている")

        // 無条件の `return .appstore` が残っていると上の順序を満たしても素通りする。
        let unconditionalAppStore = code.split(separator: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("///")
                && trimmed == "return .appstore"
        }
        #expect(unconditionalAppStore.isEmpty,
                "無条件に appstore を返す経路が残っている: \(unconditionalAppStore)")
    }

    @Test("本番の広告ユニットを使うのは appstore チャネルだけ")
    func productionAdUnitsAreLimitedToAppStore() throws {
        let code = try appCode("AdConfig.swift")
        #expect(code.contains("BuildChannel.current == .appstore"),
                "本番広告の許可条件が appstore 限定でなくなっている")
        // 3種すべてが同じゲートを通ること。1つでも直に本番 ID を返すと内部ビルドが叩く。
        for unit in ["Banner", "Interstitial", "Rewarded"] {
            #expect(
                code.range(
                    of: #"static var effective\#(unit)ID: String \{\s*isProductionAdsAllowed"#,
                    options: .regularExpression
                ) != nil,
                "effective\(unit)ID が isProductionAdsAllowed を通っていない"
            )
        }
        // Google 公式のテストユニット ID（テスト側にも直書きして、差し替えを検知できるようにする）。
        for testUnitID in [
            "ca-app-pub-3940256099942544/2934735716",
            "ca-app-pub-3940256099942544/4411468910",
            "ca-app-pub-3940256099942544/1712485313",
        ] {
            #expect(code.contains(testUnitID), "テスト広告ユニット \(testUnitID) が消えている")
        }
    }

    @Test("build_channel は GA4 に登録済みの3値のまま")
    func buildChannelValuesAreUnchanged() throws {
        let code = try appCode("BuildChannel.swift")
        // GA4 のカスタム定義（#214・会長のコンソール操作）は値の集合を前提にしている。
        // #382 では値を増やさず、レシート不在を既存の `debug` にまとめる決着にした。
        let cases = code.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("case ") else { return nil }
            return String(trimmed.dropFirst("case ".count))
        }
        #expect(cases == ["debug", "testflight", "appstore"],
                "build_channel の取りうる値が変わっている。GA4 のカスタム定義との整合を確認すること: \(cases)")
    }
}
