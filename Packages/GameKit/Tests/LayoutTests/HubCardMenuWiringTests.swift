import Foundation
import Testing
import GameKitTestSupport

/// ハブのカードの長押しメニュー（#662）の**結線**。
///
/// ハブは App ターゲットにあり GameKit のテストから import できないため、`HubPressFeedbackWiringTests`（#716）
/// と同じくソースを走査して固定する。読み口は `App/` のディレクトリ一式で、行コメントは落としてから見る。
@Suite("ハブのカードの長押しメニュー")
struct HubCardMenuWiringTests {
    /// `private func <name>(` から次の `private func` / `}` だけの行までの本体。
    private static func functionBody(_ name: String, in source: String) throws -> Substring {
        let start = try #require(source.range(of: "private func \(name)("), "\(name) が見つからない")
        let rest = source[start.upperBound...]
        let end = rest.range(of: "\n    }\n")?.upperBound ?? rest.endIndex
        return source[start.lowerBound..<end]
    }

    @Test("グリッドのカードは .pop のあとに長押しメニューを持ち、先頭へ移動と非表示の2項目を呼ぶ")
    func gridCardHasContextMenu() throws {
        let source = try SourceScan.appSources()
        // カード → `.pop` → メニューの**結線**まで見る。メニューの項目名だけを contains で見ると、
        // 別の場所に同じ文言があっても緑になる。
        #expect(
            source.range(
                of: #"GameCard\([^{}]*\)\s*\}\s*\.buttonStyle\(\.pop\)[\s\S]{0,400}?\.contextMenu \{\s*Button \{\s*moveToTop\(module\.id\)\s*\} label: \{\s*Label\("いちばん上に置く"[^\n]*\n\s*\}\s*\.disabled\(settings\.orderedIDs\.first == module\.id\)\s*Button \{\s*hide\(module\)\s*\} label: \{\s*Label\("非表示にする""#,
                options: .regularExpression
            ) != nil,
            "グリッドのカードに「いちばん上に置く」「非表示にする」のメニューが結線されていない"
        )
    }

    @Test("メニューは設定シートと同じ GameSettings の操作だけを呼ぶ（二重の状態を作らない）")
    func menuActionsGoThroughGameSettings() throws {
        let source = try SourceScan.appSources()
        let moveToTop = try Self.functionBody("moveToTop", in: source)
        #expect(moveToTop.contains("settings.orderedIDs.firstIndex(of: id)"),
                "先頭へ移動の位置が、非表示も含む orderedIDs から数えられていない（設定シートと座標がずれる）")
        #expect(moveToTop.contains("settings.move(from: IndexSet(integer: from), to: 0)"),
                "先頭へ移動が GameSettings.move を通っていない")

        let hide = try Self.functionBody("hide", in: source)
        #expect(hide.contains("settings.toggleHidden(module.id)"), "非表示が GameSettings.toggleHidden を通っていない")
        #expect(hide.contains("AccessibilityNotification.Announcement("), "非表示の案内が VoiceOver で読まれない")
        #expect(moveToTop.contains("AccessibilityNotification.Announcement("), "先頭へ移動の完了が VoiceOver で読まれない（#1602）")
        #expect(moveToTop.contains("withGameAnimation("), "先頭へ移動が Reduce Motion 追従のアニメーションを通っていない（#1602）")
        #expect(!moveToTop.contains("UserDefaults") && !hide.contains("UserDefaults"),
                "メニューが GameSettings を通さずに独自に保存している")
    }

    @Test("非表示の案内は回ごとの ID で消える時間を数え、Reduce Motion に従って出し入れする")
    func noticeLifecycle() throws {
        let source = try SourceScan.appSources()
        #expect(
            source.range(
                of: #"private struct HiddenNotice: Equatable \{\s*let moduleID: String\s*let title: String\s*let id = UUID\(\)"#,
                options: .regularExpression
            ) != nil,
            "案内に回ごとの ID が無い（同じゲームを続けて隠すと数え直さない）"
        )
        #expect(
            source.range(
                of: #"\.task\(id: hiddenNotice\) \{\s*guard hiddenNotice != nil else \{ return \}\s*try\? await Task\.sleep"#,
                options: .regularExpression
            ) != nil,
            "案内を消す時間が hiddenNotice ごとに数えられていない"
        )
        #expect(source.contains(".gameAnimation(.easeOut(duration: 0.2), value: hiddenNotice)"),
                "案内の出し入れが Reduce Motion に従っていない")
    }

    @Test("非表示の案内の「元に戻す」は toggleHidden で戻し、並び（orderedIDs）には触れない（#2047）")
    func undoRestoresInPlace() throws {
        let source = try SourceScan.appSources()
        let undo = try Self.functionBody("undoHide", in: source)
        #expect(undo.contains("settings.hiddenIDs.contains(notice.moduleID)"),
                "先に設定シートで戻されていても、元に戻すが再び隠してしまう")
        #expect(undo.contains("settings.toggleHidden(notice.moduleID)"), "元に戻すが GameSettings.toggleHidden を通っていない")
        #expect(!undo.contains("orderedIDs") && !undo.contains("UserDefaults"), "元に戻すが並びや保存に直接触れている")
        // 戻す先の位置は toggleHidden が並びを動かさないことで決まる。
        let gameSettings = try String(
            contentsOf: SourceScan.repositoryRoot.appendingPathComponent("App/GameSettings.swift"), encoding: .utf8)
        let toggle = SourceScan.functionSource(startingWith: "func toggleHidden(", in: gameSettings)
        #expect(toggle.contains("hiddenIDs.insert(id)") && toggle.contains("hiddenIDs.remove(id)"), "toggleHidden が見つからない")
        #expect(!toggle.contains("orderedIDs"), "toggleHidden が並びを動かしている（戻した位置がずれる）")
        #expect(source.contains("HubHiddenNotice(title: hiddenNotice.title) { undoHide(hiddenNotice) }"), "案内に元に戻すが結線されていない")
        #expect(source.contains(".frame(minHeight: 44)"), "元に戻すボタンが 44pt に満たない")
        #expect(source.contains("Task.sleep(for: .seconds(5))"), "案内が押せる長さ（5 秒）で出ていない")
    }
}
