import Testing
import Foundation
import GameKitTestSupport

/// `.buttonStyle(.plain)` の新規追加を止める（#2887）。
///
/// `.plain` は押下フィードバックも消すため、自前で背景を描いたボタンは `.pop` を使う（#195）。
/// 盤のマス・列・札など、選択のせり上がりと二重になるものだけを許可リストに理由付きで登録する。
struct PlainButtonStyleScanTests {

    /// 許可する `.plain` の数（ファイル名 → 件数）と理由。
    private static let allowed: [String: Int] = [
        "MancalaView.swift": 1,   // 盤のくぼみ（盤上のマス）
        "YonmokuView.swift": 1,   // 列ごとの透明な当たり判定だけ（見た目なし）
        "ShogiView.swift": 1,     // 持ち駒（駒は選択で持ち上がる）
        "SpeedView.swift": 1,     // 場の山札（札）
        "HanafudaView.swift": 2,  // 場札・手札（選択のせり上がりと二重になる）
    ]

    private static func counts() throws -> [String: Int] {
        let roots = [
            SourceScan.packageRoot.appendingPathComponent("Sources"),
            SourceScan.repositoryRoot.appendingPathComponent("App"),
        ]
        var result: [String: Int] = [:]
        var scanned = 0
        for root in roots {
            let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                scanned += 1
                let source = SourceScan.strippingComments(try String(contentsOf: url, encoding: .utf8))
                let n = SourceScan.matchCount(of: #"buttonStyle\(\.plain\)"#, in: source)
                if n > 0 { result[url.lastPathComponent, default: 0] += n }
            }
        }
        // 空振り防止。パスの導出が外れて 0 件になると「見つからない」が緑になる。
        #expect(scanned > 100)
        return result
    }

    @Test("許可リスト以外に .buttonStyle(.plain) が無い（自前背景のボタンは .pop）")
    func noUnlistedPlain() throws {
        let found = try Self.counts()
        #expect(found == Self.allowed,
                "`.plain` は押下フィードバックを消す。`.pop` に替えるか、盤・札なら理由付きで許可リストへ（#2887）。実際: \(found)")
    }
}
