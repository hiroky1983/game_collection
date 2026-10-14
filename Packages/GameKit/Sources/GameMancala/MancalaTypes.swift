import Foundation

/// 対局者。人間は常に手前（南）で、CPU は奥（北）。
public enum MancalaSide: Int, Codable, Sendable, CaseIterable {
    case south = 0
    case north = 1

    public var opponent: MancalaSide { self == .south ? .north : .south }
}

/// 盤面。`slots` は 14 個の置き場で、種をまく向き（反時計回り）に並ぶ。
///
/// | 添字 | 中身 |
/// |---|---|
/// | 0〜5 | 南（人間）の穴。左から右へ |
/// | 6 | 南のストア（右端） |
/// | 7〜12 | 北（CPU）の穴。右から左へ |
/// | 13 | 北のストア（左端） |
///
/// 値型なので探索はコピーで済む。
public struct MancalaBoard: Equatable, Hashable, Sendable, Codable {
    /// 片側の穴の数。
    public static let pitsPerSide = 6
    /// 開始時に 1 つの穴へ入れる種の数。
    public static let initialSeeds = 4
    /// 置き場の総数（穴 12 + ストア 2）。
    public static let slotCount = 14
    /// 種の総数（終局まで変わらない）。
    public static let totalSeeds = pitsPerSide * 2 * initialSeeds

    public var slots: [Int]

    /// 初期配置（各穴に 4 個・ストアは空）。
    public init() {
        var s = Array(repeating: Self.initialSeeds, count: Self.slotCount)
        s[Self.storeIndex(.south)] = 0
        s[Self.storeIndex(.north)] = 0
        slots = s
    }

    public init(slots: [Int]) {
        self.slots = slots
    }

    /// そちらのストアの添字。
    public static func storeIndex(_ side: MancalaSide) -> Int { side == .south ? 6 : 13 }

    /// そちらの `pit` 番目（0〜5・まく向きの順）の穴の添字。
    public static func slotIndex(_ side: MancalaSide, pit: Int) -> Int { side == .south ? pit : 7 + pit }

    /// 向かいの穴の添字（0 ↔ 12、5 ↔ 7）。ストアには向かいが無い。
    public static func oppositeIndex(_ slot: Int) -> Int { 12 - slot }

    /// その置き場の持ち主。
    public static func owner(ofSlot slot: Int) -> MancalaSide { slot <= 6 ? .south : .north }

    /// 穴か（ストアでないか）。
    public static func isPit(_ slot: Int) -> Bool { slot != 6 && slot != 13 }

    public func seeds(_ side: MancalaSide, pit: Int) -> Int { slots[Self.slotIndex(side, pit: pit)] }

    public func store(_ side: MancalaSide) -> Int { slots[Self.storeIndex(side)] }

    /// そちらの穴に残っている種の合計（ストアは含まない）。
    public func pitTotal(_ side: MancalaSide) -> Int {
        (0..<Self.pitsPerSide).reduce(0) { $0 + seeds(side, pit: $1) }
    }
}

/// 1 手をまいた結果。
public struct MancalaMoveResult: Equatable, Sendable {
    /// まいたあと（取り・終局の回収まで済んだ）の盤。
    public let board: MancalaBoard
    /// 最後の種が入った置き場の添字。
    public let lastSlot: Int
    /// 最後の種が自分のストアに入り、もう一度続けて打てるか。終局した手では false。
    public let extraTurn: Bool
    /// 向かいの穴から取った種の数（最後の 1 個は含まない）。取らなければ 0。
    public let captured: Int
    /// この手で片側の穴がすべて空になり、対局が終わったか。
    public let gameEnded: Bool
}
