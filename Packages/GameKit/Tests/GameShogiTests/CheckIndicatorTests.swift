import Testing
import Foundation
import SwiftUI
import Core
@testable import GameShogi

// MARK: - 共通の道具

private final class MemoryStore: Core.SnapshotStore, @unchecked Sendable {
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
private final class SpyFeedback: FeedbackService {
    private(set) var impacts: [FeedbackImpact] = []
    private(set) var notices: [FeedbackNotice] = []

    func impact(_ style: FeedbackImpact) { impacts.append(style) }
    func notify(_ type: FeedbackNotice) { notices.append(type) }
}

/// 任意の局面から始まるモデルを作る。`ShogiGameModel` は開始局面をスナップショット経由でしか
/// 受け取らないため、保存済みの中断データを先に置いてから読み込ませる。
@MainActor
private func makeModel(sfen: String, feedback: FeedbackService? = nil) -> ShogiGameModel {
    let store = MemoryStore()
    try? store.save(
        ShogiSnapshot(
            initialSfen: sfen,
            moves: [],
            phase: .playing,
            reviewPly: nil,
            sente: .human,
            gote: .ai,
            aiLevel: 1,
            startedAt: Date(timeIntervalSince1970: 0),
            undoUsed: false
        ),
        for: "shogi"
    )
    return ShogiGameModel(
        services: GameServices(
            snapshots: store,
            ads: NoopAdService(),
            feedback: feedback ?? NoopFeedbackService()
        )
    )
}

/// 平手から 3 手で先手の馬が後手玉に王手を掛ける手順（▲7六歩 △3四歩 ▲3三角成）。
///
/// 局面を SFEN で流し込むのではなく**実際に指して**作る。`apply` を通ることが
/// 王手の検知・触覚・イベント番号のすべての入口だから。
@MainActor
private func playIntoCheck(_ model: ShogiGameModel) {
    let line: [(Substring, Substring, Bool)] = [
        ("7g", "7f", false),   // ▲7六歩（角道を開ける）
        ("3c", "3d", false),   // △3四歩（3三を空ける）
        ("8h", "3c", true),    // ▲3三角成 → 馬が 4二を通して 5一の玉に利く
    ]
    for (from, to, promote) in line {
        let move = Move.board(from: Sq.fromUSI(from)!, to: Sq.fromUSI(to)!, promote: promote)
        #expect(model.legalMovesCache.contains(move), "\(from)\(to) が合法手でない（手順の前提が壊れている）")
        model.apply(move)
    }
}

// MARK: - 王手の検知と印

@MainActor
@Suite("王手の表示（#377）")
struct ShogiCheckIndicatorTests {

    @Test("王手でない間は玉の印を出さない")
    func noMarkerWhileNotInCheck() {
        let model = ShogiGameModel(services: nil)
        #expect(model.checkedKingSquare == nil)
        model.apply(.board(from: Sq.fromUSI("7g")!, to: Sq.fromUSI("7f")!, promote: false))
        #expect(model.checkedKingSquare == nil)
        #expect(model.checkEventID == 0)
    }

    @Test("王手が掛かると、王手されている側の玉のマスを返す")
    func marksTheCheckedKing() {
        let model = ShogiGameModel(services: nil)
        playIntoCheck(model)
        // 王手されているのは後手。玉は 5一。
        #expect(model.position.sideToMove == .white)
        #expect(model.checkedKingSquare == Sq.fromUSI("5a")!)
        #expect(model.lastCheckedSide == .white)
        #expect(model.checkEventID == 1)
    }

    @Test("王手を解消すると印が消える")
    func markerDisappearsWhenCheckIsResolved() {
        let model = ShogiGameModel(services: nil)
        playIntoCheck(model)
        // 後手は王手を解消する手しか指せない（合法手の定義そのもの）。どれを指しても印は消える。
        let escape = model.legalMovesCache.first!
        model.apply(escape)
        #expect(model.checkedKingSquare == nil)
        // 解消の手そのものは王手ではないので、イベント番号も増えない。
        #expect(model.checkEventID == 1)
    }

    @Test("検討ナビで戻しても印は局面どおりに出る（文字の契機は増えない）")
    func reviewNavigationRestoresMarkerWithoutFiringTheBanner() {
        let model = ShogiGameModel(services: nil)
        playIntoCheck(model)
        let escape = model.legalMovesCache.first!
        model.apply(escape)
        #expect(model.checkedKingSquare == nil)

        let idBefore = model.checkEventID
        // 王手が掛かっていた局面（3 手目まで）へ戻す。
        model.reviewGoTo(ply: 3)
        #expect(model.checkedKingSquare == Sq.fromUSI("5a")!, "検討中の表示局面から印が導かれていない")
        // 盤を戻しただけで「いま王手が掛かった」ことにはならない。
        #expect(model.checkEventID == idBefore, "検討ナビで文字の契機が増えている")

        // 1 手前（王手前）まで戻せば印も消える。
        model.reviewGoTo(ply: 2)
        #expect(model.checkedKingSquare == nil)
        #expect(model.checkEventID == idBefore)
    }

    @Test("中断復元で王手局面に戻ると印は出るが、文字は飛び出さない")
    func resumeRestoresMarkerButNotTheBanner() {
        let store = MemoryStore()
        let first = ShogiGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        playIntoCheck(first)
        #expect(first.checkedKingSquare == Sq.fromUSI("5a")!)

        let resumed = ShogiGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(resumed.moves.count == 3, "指し手列が復元されていない")
        // 印は局面から毎回導くので、復元のための専用処理なしにそのまま正しい。
        #expect(resumed.checkedKingSquare == Sq.fromUSI("5a")!)
        // 文字のほうは「掛かった瞬間」の合図なので、復元では出さない。
        #expect(resumed.checkEventID == 0)
        #expect(resumed.lastCheckedSide == nil)
    }

    @Test("新規対局でイベント番号は巻き戻さない（巻き戻すと View が合図と誤読する）")
    func newGameKeepsTheEventCounterMonotonic() {
        let model = ShogiGameModel(services: nil)
        playIntoCheck(model)
        #expect(model.checkEventID == 1)
        model.newGame(humanSide: .black)
        #expect(model.checkEventID == 1, "対局をまたいで単調に増えていない")
        #expect(model.lastCheckedSide == nil)
        #expect(model.checkedKingSquare == nil)
    }
}

// MARK: - 触覚

@MainActor
@Suite("王手の触覚フィードバック（#377）")
struct ShogiCheckFeedbackTests {

    @Test("王手を掛けた手では warning が鳴り、着手の impact は鳴らさない")
    func checkNotifiesWarningInsteadOfImpact() {
        let spy = SpyFeedback()
        let model = ShogiGameModel(
            services: GameServices(snapshots: MemoryStore(), ads: NoopAdService(), feedback: spy)
        )
        playIntoCheck(model)
        // 手順のうち王手になるのは 3 手目だけ。1 手目（人間）は impact、2 手目（後手）は無音。
        #expect(spy.impacts == [.medium], "王手の手で着手の impact まで鳴っている: \(spy.impacts)")
        #expect(spy.notices == [.warning], "王手の合図が鳴っていない: \(spy.notices)")
    }

    /// 「CPU の着手では鳴らさない」（`FeedbackCPUSilentTests`）は**着手の手応え**（`impact`）の話で、
    /// 王手は相手が掛けてきたときこそ知らせる必要がある。詰み・投了の `notify` を CPU 手番でも
    /// 鳴らしているのと同じ扱いにする。
    @Test("CPU が掛けてきた王手でも合図は鳴る（impact は鳴らさない）")
    func cpuCheckAlsoNotifies() async {
        let spy = SpyFeedback()
        // 後手（CPU）の合法手は 5b5c の 1 手だけで、それが先手（人間）玉への王手になる局面。
        // 後手玉 1a は 1c・3b の金に逃げ場を塞がれていて動けず、王手も掛かっていない。
        let model = makeModel(sfen: "8k/4p1G2/8G/4K4/9/9/9/9/9 w - 1", feedback: spy)
        #expect(model.isAITurn, "CPU の手番になっていない")
        #expect(model.legalMovesCache.count == 1, "CPU の手が 1 手に絞れていない（局面の前提が壊れている）")

        await model.performAIMoveIfNeeded()
        #expect(model.moves.last?.usi == "5b5c")
        #expect(model.checkedKingSquare == Sq.fromUSI("5d")!, "人間の玉に印が付いていない")
        #expect(model.lastCheckedSide == .black)
        #expect(model.checkEventID == 1)
        #expect(spy.notices == [.warning], "CPU の王手で合図が鳴っていない: \(spy.notices)")
        #expect(spy.impacts.isEmpty, "CPU の着手で手応えまで鳴っている: \(spy.impacts)")
    }

    /// 詰みも「王手が掛かっている」局面だが、合図は決着のほうを鳴らす。
    /// ここを分けておかないと、投了・詰みの瞬間に王手の警告音まで重なる。
    @Test("詰みでは王手ではなく決着の合図を鳴らし、文字の契機も増やさない")
    func mateNotifiesTheResultNotTheCheck() {
        let spy = SpyFeedback()
        // 頭金の一手詰め: 後手玉 5一・先手金 5三・先手の持ち駒に金。5二へ打つと、
        // 逃げ場（4一/6一/4二/6二）はすべて金の利きにあり、5二の金は 5三の金が支えていて取れない。
        let model = makeModel(sfen: "4k4/9/4G4/9/9/9/9/9/8K b G 1", feedback: spy)
        let mate = Move.drop(type: .gold, to: Sq.fromUSI("5b")!)
        #expect(model.legalMovesCache.contains(mate), "頭金が合法手でない（局面の前提が壊れている）")

        model.apply(mate)
        #expect(model.gameOver)
        #expect(model.checkEventID == 0, "詰みで王手の文字まで飛び出している")
        #expect(spy.notices == [.success], "決着の合図が鳴っていない: \(spy.notices)")
    }
}

// MARK: - 読み上げ

@Suite("王手の読み上げ（#377）")
struct ShogiCheckAccessibilityTests {

    @Test("王手されている玉のマスは、そのことを駒名のすぐ後に読む")
    func checkedKingSquareIsAnnounced() {
        let label = ShogiAccessibility.squareLabel(
            index: Sq.fromUSI("5a")!,
            piece: Piece(type: .king, color: .white),
            isSelected: false,
            isTarget: false,
            isLastMove: false,
            isCheckedKing: true
        )
        #expect(label.contains("王手されています"))
        // 「なぜ動かせないのか」に直結するので、選択・直前手より先に読ませる。
        #expect(label == "5一、後手の玉、王手されています")
    }

    @Test("王手でないマスの読み上げは従来どおり")
    func normalSquareLabelIsUnchanged() {
        let label = ShogiAccessibility.squareLabel(
            index: Sq.fromUSI("5a")!,
            piece: Piece(type: .king, color: .white),
            isSelected: false,
            isTarget: false,
            isLastMove: false
        )
        #expect(label == "5一、後手の玉")
    }
}

// MARK: - 配色

/// 王手の色は「差し色の面 + 白文字」の 27 例目にならないことを固定する（#220・#377）。
///
/// #220 は既存の差し色（`Theme.coral` 等）に白文字を載せている 26 箇所が WCAG AA 未達である、
/// という未決裁の稟議。決裁がどの案に転んでも直す必要が出ないよう、新しく足すこの色だけは
/// 先に基準を満たしておく。
@Suite("王手の配色（#377）")
struct ShogiCheckColorTests {
    private static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ raw: UInt32) -> Double {
            let v = Double(raw) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF)
            + 0.7152 * channel((hex >> 8) & 0xFF)
            + 0.0722 * channel(hex & 0xFF)
    }

    private static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    @Test("「王手」の札は白文字で WCAG AA(4.5:1) を満たす")
    func bannerMeetsAA() {
        let ratio = Self.contrast(BoardStyle.checkHex, 0xFFFFFF)
        #expect(ratio >= 4.5, "白文字とのコントラストが \(ratio):1 しかない")
    }

    @Test("玉のマスの枠は盤地に対して 3:1 以上（非テキストの図形・WCAG 1.4.11）")
    func kingMarkerMeetsNonTextMinimum() {
        // 盤の地は上→下のグラデーション。明るいほうの端（`frameTop`）で見ておけば下端は必ず上振れする。
        let ratio = Self.contrast(BoardStyle.checkHex, 0xEDC178)
        #expect(ratio >= 3.0, "盤地とのコントラストが \(ratio):1 しかない")
    }
}
