import Foundation

public enum ConcentrationPairCount: Int, CaseIterable {
    case small = 8
    case medium = 12
    case large = 18

    var displayName: String {
        switch self {
        case .small:  return "8ペア"
        case .medium: return "12ペア"
        case .large:  return "18ペア"
        }
    }

    var subtitle: String {
        switch self {
        case .small:  return "16枚"
        case .medium: return "24枚"
        case .large:  return "36枚"
        }
    }
}

public enum ConcentrationCPULevel: Int, CaseIterable {
    case weak = 0
    case normal = 1
    case strong = 2

    var displayName: String {
        switch self {
        case .weak:   return "よわい"
        case .normal: return "ふつう"
        case .strong: return "つよい"
        }
    }

    var subtitle: String {
        switch self {
        case .weak:   return "記憶30%"
        case .normal: return "記憶60%"
        case .strong: return "記憶80%"
        }
    }

    var memoryAccuracy: Double {
        switch self {
        case .weak:   return 0.3
        case .normal: return 0.6
        case .strong: return 0.8
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
    /// 対にする手掛かり。**中身は見ず、等しいかどうかだけで対を判定する**（CPU の記憶も同じ）。
    /// 盤を組むときに入るのは `ConcentrationFigure` の識別子で、旧版（v1.1.3 まで）の
    /// 中断データから復元したときだけ当時の絵文字が入る。
    public let symbol: String
    public var isFaceUp: Bool = false
    public var isMatched: Bool = false

    /// 画面に描く図案（#601）。`symbol` が読み替えられなければ `nil`。
    ///
    /// 実際には `nil` にならない。盤を組むときは図案の識別子しか入れず、中断データからの
    /// 復元は `ConcentrationModel` が「全札が図案に読み替えられること」を確かめてからしか
    /// 通さないため。ここで `nil` を既定の図案へ倒すと、見た目だけ対になった札ができる。
    public var figure: ConcentrationFigure? { ConcentrationFigure.decode(symbol) }
}
