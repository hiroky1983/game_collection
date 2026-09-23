import Foundation

/// くっつきフルーツ（#1319）の果物の種類。小さい順に並び、同じ種類が触れると 1 つ上の種類になる。
///
/// 顔ぶれ・並び・大きさ・配色はすべてこのアプリのオリジナル（Issue #1319 の権利面の注意）。
/// 既存の同型ゲームの果物の並びや絵柄は参照していない。**並びを変えると保存済みの中断データの
/// `rawValue` がずれる**ので、種類を足すときは末尾に足す（メロンより大きい果物を足すなら
/// `next` の定義も見直す）。
public enum FruitKind: Int, Codable, CaseIterable, Sendable, Comparable {
    case blueberry
    case cherry
    case strawberry
    case lime
    case mandarin
    case kiwi
    case peach
    case apple
    case grape
    case pineapple
    case melon

    public static func < (lhs: FruitKind, rhs: FruitKind) -> Bool { lhs.rawValue < rhs.rawValue }

    /// 画面に出す名前。
    public var name: String {
        switch self {
        case .blueberry:  return "ブルーベリー"
        case .cherry:     return "さくらんぼ"
        case .strawberry: return "いちご"
        case .lime:       return "ライム"
        case .mandarin:   return "みかん"
        case .kiwi:       return "キウイ"
        case .peach:      return "もも"
        case .apple:      return "りんご"
        case .grape:      return "ぶどう"
        case .pineapple:  return "パイナップル"
        case .melon:      return "メロン"
        }
    }

    /// 半径（盤の抽象単位。盤の幅は `FruitField.Metrics.width` = 100）。
    ///
    /// いちばん大きいメロンの直径が盤の幅の 45% になるようにしてある。これより大きいと 2 個並べた
    /// 時点で盤が埋まり、小さいと合体の手応えが薄い。ブルーベリーからメロンまでを等比（約 1.21 倍）で
    /// 刻み、「1 つ上」が見た目で分かる差にしてある（`KindTests` が比の範囲を固定する）。
    public var radius: Double {
        switch self {
        case .blueberry:  return 3.4
        case .cherry:     return 4.1
        case .strawberry: return 5.0
        case .lime:       return 6.0
        case .mandarin:   return 7.3
        case .kiwi:       return 8.8
        case .peach:      return 10.6
        case .apple:      return 12.8
        case .grape:      return 15.5
        case .pineapple:  return 18.7
        case .melon:      return 22.6
        }
    }

    /// 同じ種類が 2 つ触れたときにできる 1 つ上の種類。メロンは上が無い（2 つ触れると消える）。
    public var next: FruitKind? { FruitKind(rawValue: rawValue + 1) }

    /// この種類を**作った**ときに入る得点（三角数）。ブルーベリーは作れないので 0。
    ///
    /// 大きい果物ほど手数がかかるので、得点も加速度的に増やす。メロン 2 個を消したときの得点は
    /// `FruitKind.melonVanishPoints`。
    public var points: Int {
        guard self != .blueberry else { return 0 }
        let n = rawValue + 1
        return n * (n + 1) / 2
    }

    /// メロン 2 個が触れて消えたときの得点。メロンを作る得点（66）より大きくして、盤を空ける
    /// 行為そのものに見返りを付ける。
    public static let melonVanishPoints = 100

    /// 落とす果物として出てくる種類（小さい 5 種）。大きい果物は合体でしか作れない。
    public static let dropPool: [FruitKind] = [.blueberry, .cherry, .strawberry, .lime, .mandarin]

    /// 質量。面積に比例させる（大きい果物ほど押されにくく、小さい果物を押しのける）。
    public var mass: Double { radius * radius }

    // MARK: - 配色（オリジナル）

    /// 地の色（RGB）。SpriteKit と SwiftUI の両方でこの値から色を作る。
    /// 隣りあう種類が似た色にならないよう、色相を散らしてある（赤系はさくらんぼ・いちご・りんごの
    /// 3 つだが、大きさが 1 : 1.7 : 4.4 と離れているので取り違えない）。
    public var baseColor: UInt32 {
        switch self {
        case .blueberry:  return 0x5A63C9
        case .cherry:     return 0xC8203C
        case .strawberry: return 0xFF5E7A
        case .lime:       return 0x8FD14F
        case .mandarin:   return 0xFFA232
        case .kiwi:       return 0x9B7B52
        case .peach:      return 0xFFB6C1
        case .apple:      return 0xE8453C
        case .grape:      return 0x7E57C2
        case .pineapple:  return 0xF5C242
        case .melon:      return 0x7BC47F
        }
    }

    /// 縁と模様に使う濃い色。
    public var shadeColor: UInt32 {
        switch self {
        case .blueberry:  return 0x3B4390
        case .cherry:     return 0x8A1029
        case .strawberry: return 0xC93A57
        case .lime:       return 0x5E9A2E
        case .mandarin:   return 0xD07A12
        case .kiwi:       return 0x6E5233
        case .peach:      return 0xE07A93
        case .apple:      return 0xA82A24
        case .grape:      return 0x54368F
        case .pineapple:  return 0xB8862A
        case .melon:      return 0x4E8F55
        }
    }
}
