import Foundation

public enum ConcentrationDifficulty: Int, CaseIterable {
    case easy = 0
    case normal = 1
    case hard = 2

    var pairCount: Int {
        switch self {
        case .easy:   return 8
        case .normal: return 12
        case .hard:   return 18
        }
    }

    var displayName: String {
        switch self {
        case .easy:   return "かんたん"
        case .normal: return "ふつう"
        case .hard:   return "むずかしい"
        }
    }

    var subtitle: String {
        switch self {
        case .easy:   return "8ペア"
        case .normal: return "12ペア"
        case .hard:   return "18ペア"
        }
    }

    /// CPU が表向きにされたカードを記憶する確率
    var cpuMemoryAccuracy: Double {
        switch self {
        case .easy:   return 0.3
        case .normal: return 0.6
        case .hard:   return 1.0
        }
    }
}

public enum ConcentrationPlayer {
    case human, cpu

    var next: ConcentrationPlayer { self == .human ? .cpu : .human }
    var displayName: String { self == .human ? "あなた" : "CPU" }
}

public struct ConcentrationCard: Identifiable {
    public let id: Int
    public let symbol: String
    public var isFaceUp: Bool = false
    public var isMatched: Bool = false
}

// 36種まで対応できるシンボルセット
let concentrationSymbols: [String] = [
    "🍎", "🍊", "🍋", "🍇", "🍓", "🍒", "🍑", "🥝",
    "🌸", "🌻", "🌈", "⭐", "🎵", "🎃", "🎄", "🎁",
    "🐶", "🐱", "🐸", "🐯", "🦁", "🐻", "🐼", "🦊",
    "🚀", "🌙", "☀️", "⚡", "🔥", "💎", "🏆", "🎯",
    "🍕", "🍔", "🍩", "🎂"
]
