import Testing
import Foundation
import Core
import MahjongTiles
@testable import GameMahjongSolitaire

// MARK: - Mocks

private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var store: [String: Data] = [:]

    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
}

@MainActor
private func makeServices() -> GameServices {
    GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
}

/// 取れる 3 枚の絵柄がすべて違い、合う相方はいずれも覆われている盤面（`MahjongSolitaireModelTests`
/// の同名ヘルパーと同じ組み方。手詰まり = ヒントを出せない状態を確実に作るために要る）。
private func makeDeadlockedFaces() -> [MahjongFace?]? {
    func index(_ layer: Int, _ hx: Int, _ hy: Int) -> Int? {
        MahjongSolitaireLayout.turtle.index(layer: layer, hx: hx, hy: hy)
    }
    guard let freeA = index(0, 2, 0), let freeB = index(0, 24, 0),
          let freeC = index(4, 13, 7),
          let coveredA = index(3, 12, 6), let coveredB = index(3, 14, 6),
          let coveredC = index(3, 12, 8) else { return nil }
    var faces = [MahjongFace?](repeating: nil, count: MahjongSolitaireLayout.turtle.positions.count)
    faces[freeA] = .characters(1)
    faces[coveredA] = .characters(1)
    faces[freeB] = .circles(2)
    faces[coveredB] = .circles(2)
    faces[freeC] = .dragon(0)
    faces[coveredC] = .dragon(0)
    return faces
}

// MARK: - Model 側の門（広告だけ見せて何も起きない経路を作らない）

@Suite("麻雀ソリティアのヒントは対価に見合う結果を返す")
@MainActor
struct MahjongSolitaireHintGateTests {

    @Test("取れる組があるうちは canHint が true で、showHint は成功を返す")
    func hintSucceedsWhilePairsRemain() {
        let model = MahjongSolitaireModel(services: makeServices(), seed: 21)
        #expect(model.canHint)
        #expect(model.showHint(), "取れる組があるのに失敗したら、広告の対価が無くなる")
        #expect(model.hintPair.count == 2)
        #expect(model.hintCount == 1)
    }

    @Test("手詰まりでは canHint が false になり、showHint も失敗して回数を消費しない")
    func hintIsBlockedWhenDeadlocked() {
        guard let faces = makeDeadlockedFaces() else {
            Issue.record("盤面を組み立てられない")
            return
        }
        let model = MahjongSolitaireModel(services: makeServices(), seed: 31, faces: faces)
        #expect(model.isDeadlocked)
        #expect(!model.canHint, "ここが true だと広告を見せてから何も起きない")
        #expect(!model.showHint())
        #expect(model.hintPair.isEmpty)
        #expect(model.hintCount == 0, "不発のときは回数を消費しない")
    }

    @Test("取り切った後は canHint が false になり、showHint も失敗する")
    func hintIsBlockedAfterClear() {
        let model = MahjongSolitaireModel(services: makeServices(), seed: 2026)
        for pair in model.solution {
            model.tap(pair[0])
            model.tap(pair[1])
        }
        #expect(model.phase == .won)
        #expect(!model.canHint)
        #expect(!model.showHint())
        #expect(model.hintCount == 0)
    }
}

// MARK: - View 側の契約（ヒントが広告視聴後にのみ発動する）

/// ヒントの発動経路がリワード広告を経ていることを、View のソースを読んで確かめる（#336）。
///
/// SwiftUI の `Button` の action や `alert` はユニットテストから叩けないため、
/// 「`model.showHint()` の呼び出し箇所が `requestHint()` の中だけであること」を構文で押さえる。
/// **`firstIndex` で最初の1件だけを見ると、前方に別の呼び出しが足されたときに検証対象が
/// すり替わって green のまま空振りする**ので、ここでは常に全出現数を数える。
@Suite("麻雀ソリティアのヒントは広告視聴後にのみ発動する")
struct MahjongSolitaireHintAdContractTests {

    private static func viewSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameMahjongSolitaireTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources/GameMahjongSolitaire/MahjongSolitaireView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func occurrences(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    /// `private func <name>(` から、同じインデントで閉じる `    }` までを本体とみなして切り出す。
    private static func functionBody(_ name: String, in source: String) throws -> String {
        let lines = source.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.contains("private func \(name)(") }) else {
            throw HintContractError.functionNotFound(name)
        }
        guard let endOffset = lines[(start + 1)...].firstIndex(where: { $0 == "    }" }) else {
            throw HintContractError.functionNotFound(name)
        }
        return lines[start...endOffset].joined(separator: "\n")
    }

    private enum HintContractError: Error { case functionNotFound(String) }

    @Test("model.showHint() を呼ぶのは requestHint() の中だけ（ボタンから直接は呼ばない）")
    func hintIsOnlyTriggeredFromRequestHint() throws {
        let source = try Self.viewSource()
        let total = Self.occurrences(of: "model.showHint()", in: source)
        let inRequestHint = Self.occurrences(
            of: "model.showHint()", in: try Self.functionBody("requestHint", in: source)
        )
        #expect(total == 1, "showHint() の呼び出しが \(total) 箇所ある。広告を経ない経路が増えていないか確認する")
        #expect(inRequestHint == 1, "requestHint() の中から showHint() が呼ばれていない")
    }

    @Test("requestHint() は広告の視聴完了時だけヒントを出し、連打を塞いでいる")
    func requestHintIsGatedByRewardedAd() throws {
        let body = try Self.functionBody("requestHint", in: try Self.viewSource())
        #expect(body.contains("await services.ads.showRewardedAd()"), "リワード広告を経ていない")
        #expect(body.contains("guard !isRequestingHint else { return }"), "視聴中の連打ガードが無い")
        #expect(body.contains("showHintNotEarned = true"), "視聴未完了のときのアラートが無い")
        #expect(body.contains("showHintUnavailable = true"), "広告を見たのに出せなかったときのアラートが無い")
    }

    @Test("ヒントボタンは確認ダイアログを開くだけで、押した直後に広告を出さない")
    func hintButtonOpensConfirmationFirst() throws {
        let source = try Self.viewSource()
        #expect(
            source.contains(#"controlButton("ヒント", systemImage: "lightbulb.fill", tint: Theme.Fill.teal, showsTitle: showsTitle) {"#),
            "ヒントボタンの定義が見つからない（テストの走査が空振りしている）"
        )
        #expect(source.contains("showHintConfirm = true"), "確認ダイアログを開いていない")
        #expect(source.contains("Button(\"広告を見てヒントを見る\") { onWatchAd() }"), "確認ダイアログの視聴ボタンが無い")
        #expect(source.contains(".disabled(!model.canHint || isRequestingHint)"), "取れる組が無いときにボタンを塞いでいない")
    }

    @Test("視聴未完了のアラート文言が他ゲームと揃っている（#64）")
    func notEarnedAlertMatchesTheSharedWording() throws {
        let source = try Self.viewSource()
        #expect(
            Self.occurrences(
                of: "広告を最後まで視聴しなかったか、広告を読み込めませんでした。\\nもう一度お試しください。",
                in: source
            ) == 2,
            "並べ替えとヒントの2箇所で同じ文言を使っているはず"
        )
    }
}
