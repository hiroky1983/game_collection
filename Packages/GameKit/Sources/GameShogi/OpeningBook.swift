import Foundation
import CoreEngine

/// 簡易定跡ブック。代表的な出だし手順を「局面(SFEN) → 次の一手(USI)」として持つ。
/// 手順の定義から開始局面を再生して構築するので、非合法手は構築時に自動で打ち切られる。
enum OpeningBook {
    /// 局面 SFEN に対する定跡手の候補（登録順・重複なし。無ければ空）。
    static func moves(for sfen: String) -> [String] { table[sfen] ?? [] }

    /// 局面 SFEN に対する定跡手（無ければ nil）。`seed` が無ければ最初に登録した手。
    /// 同じ局面に候補が複数あるときは、`seed`（対局ごとの種）と局面から 1 つに決める。
    /// 同じ種・同じ局面なら常に同じ手（テストと、1 局の中での一貫性のため）。
    static func move(for sfen: String, seed: UInt64? = nil) -> String? {
        let candidates = moves(for: sfen)
        guard let seed, candidates.count > 1 else { return candidates.first }
        return candidates[BookPicker.index(count: candidates.count, seed: seed, key: sfen)]
    }

    /// 代表的な静かな相居飛車／囲い形に向かう手順。先手・後手どちらの手番ぶんも含む。
    /// （多少間違っていても、構築時の合法手チェックで弾かれるだけで安全）
    private static let lines: [[String]] = [
        // 相居飛車・矢倉模様（玉を囲いに向かわせる出だし）
        ["7g7f", "3c3d", "2g2f", "8c8d", "6i7h", "7a6b", "3i3h", "6c6d", "5g5f", "4c4d"],
        // 先手が居飛車、後手も自然に駒組み
        ["7g7f", "8c8d", "2g2f", "8d8e", "8h7g", "3c3d", "7i6h", "2b2c"],
        // 先手が角道を止めて振り飛車模様
        ["7g7f", "3c3d", "6g6f", "8c8d", "5g5f", "5c5d", "4i5h"],
    ]

    private static let table: [String: [String]] = {
        var dict: [String: [String]] = [:]
        for line in lines {
            var pos = Position.start()
            for usi in line {
                guard let move = Move.fromUSI(usi),
                      pos.legalMoves().contains(move) else { break }
                let key = pos.toSFEN()
                if !(dict[key]?.contains(usi) ?? false) { dict[key, default: []].append(usi) }
                pos.make(move)
            }
        }
        return dict
    }()
}
