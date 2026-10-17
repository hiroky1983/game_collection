import Foundation

/// おじさんの盆栽（#2361。もとは くっつきフルーツ #1319）の盆栽の段。小さい順に並び、同じ段が触れると
/// 1 つ上の段になる。
///
/// 並びは会長決裁（2026-10-17・#2361）: 桜 → 椿 → 藤 → 梅 → みかん → 銀杏 → 南天 → 紅葉 → 真柏 → 黒松 → 金の松。
/// 盆栽の格付けの順（花物 → 実物 → 葉物 → 松柏）で「出世」させ、隣どうしで色と形がかぶらないように並べてある。
/// 型の名前（`FruitKind`）と半径・得点は くっつきフルーツのまま引き継いだ（段の対応だけを差し替え）。
///
/// **並びを変えると保存済みの中断データの `rawValue` がずれる**ので、段を足すときは末尾に足す
/// （金の松より大きい段を足すなら `next` の定義も見直す）。くっつきフルーツ時代の中断データは
/// 同じ `rawValue` の段（ブルーベリー → 桜 … メロン → 金の松）としてそのまま読める。
public enum FruitKind: Int, Codable, CaseIterable, Sendable, Comparable {
    case sakura
    case tsubaki
    case fuji
    case ume
    case mikan
    case icho
    case nanten
    case momiji
    case shinpaku
    case kuromatsu
    case kinmatsu

    public static func < (lhs: FruitKind, rhs: FruitKind) -> Bool { lhs.rawValue < rhs.rawValue }

    /// 画面に出す名前。
    public var name: String {
        switch self {
        case .sakura:    return tr("桜")
        case .tsubaki:   return tr("椿")
        case .fuji:      return tr("藤")
        case .ume:       return tr("梅")
        case .mikan:     return tr("みかん")
        case .icho:      return tr("銀杏")
        case .nanten:    return tr("南天")
        case .momiji:    return tr("紅葉")
        case .shinpaku:  return tr("真柏")
        case .kuromatsu: return tr("黒松")
        case .kinmatsu:  return tr("金の松")
        }
    }

    /// 絵の素材名（`Resources/Bonsai/<名前>.png`）。会長提供の盆栽シート（ChatGPT 生成・2026-10-17）から
    /// 切り出し、段ごとに鉢の形を変えたもの（#2388・`docs/design/bonsai/make_pots.py`）。
    /// 出どころは docs/design/bonsai/assets-license.md。
    public var artName: String {
        let index = String(format: "%02d", rawValue + 1)
        return "Bonsai_\(index)_\(slug)"
    }

    private var slug: String {
        switch self {
        case .sakura:    return "sakura"
        case .tsubaki:   return "tsubaki"
        case .fuji:      return "fuji"
        case .ume:       return "ume"
        case .mikan:     return "mikan"
        case .icho:      return "icho"
        case .nanten:    return "nanten"
        case .momiji:    return "momiji"
        case .shinpaku:  return "shinpaku"
        case .kuromatsu: return "kuromatsu"
        case .kinmatsu:  return "kinmatsu"
        }
    }

    /// 半径（盤の抽象単位。盤の幅は `FruitField.Metrics.width` = 100）。当たり判定の円の半径で、
    /// 絵はこれより大きく描く（`BonsaiArt.canvasScale`）。
    ///
    /// いちばん大きい金の松の直径が盤の幅の 45% になるようにしてある。これより大きいと 2 個並べた
    /// 時点で盤が埋まり、小さいと合体の手応えが薄い。桜から金の松までを等比（約 1.21 倍）で
    /// 刻み、「1 つ上」が見た目で分かる差にしてある（`KindTests` が比の範囲を固定する）。
    public var radius: Double {
        switch self {
        case .sakura:    return 3.4
        case .tsubaki:   return 4.1
        case .fuji:      return 5.0
        case .ume:       return 6.0
        case .mikan:     return 7.3
        case .icho:      return 8.8
        case .nanten:    return 10.6
        case .momiji:    return 12.8
        case .shinpaku:  return 15.5
        case .kuromatsu: return 18.7
        case .kinmatsu:  return 22.6
        }
    }

    /// 同じ段が 2 つ触れたときにできる 1 つ上の段。金の松は上が無い（2 つ触れると消える）。
    public var next: FruitKind? { FruitKind(rawValue: rawValue + 1) }

    /// この段を**作った**ときに入る得点（三角数）。桜は作れないので 0。
    ///
    /// 大きい盆栽ほど手数がかかるので、得点も加速度的に増やす。金の松 2 鉢を消したときの得点は
    /// `FruitKind.kinmatsuVanishPoints`。
    public var points: Int {
        guard self != .sakura else { return 0 }
        let n = rawValue + 1
        return n * (n + 1) / 2
    }

    /// 金の松 2 鉢が触れて消えたときの得点。金の松を作る得点（66）より大きくして、盤を空ける
    /// 行為そのものに見返りを付ける。
    public static let kinmatsuVanishPoints = 100

    /// 落とす盆栽として出てくる段（小さい 5 段）。大きい盆栽は合体でしか作れない。
    public static let dropPool: [FruitKind] = [.sakura, .tsubaki, .fuji, .ume, .mikan]

    /// 質量。面積に比例させる（大きい盆栽ほど押されにくく、小さい盆栽を押しのける）。
    public var mass: Double { radius * radius }
}
