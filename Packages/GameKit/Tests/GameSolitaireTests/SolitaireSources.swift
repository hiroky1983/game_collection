import Foundation
import Testing

/// ソース走査テストの読み口（#525）。
///
/// 演出・ドラッグ・開始シートの結線は「見た目そのもの」なので実行では確かめられず、
/// ソースの形で守っている。#525 で `SolitaireView.swift` を
/// 盤面・救済オーバーレイ・操作エリアの 3 つに割ったため、**1 ファイルを名指しで読むと
/// 規約が別ファイルへ移っただけで検査が空振りする**（走査対象からコードが消えても
/// 「0 件だから合格」になる形の条件が混ざっている）。
///
/// そこで読み口を**ディレクトリ全体**にする。どのファイルに置いても検査に掛かるので、
/// 以後ファイルを割っても足しても、テストの側を直す必要がない。
enum SolitaireSources {
    /// `Sources/GameSolitaire` のパス。
    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameSolitaireTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources/GameSolitaire")
    }

    /// ソースを名前順に連結して返す。件数を数える検査があるので順序は固定する。
    static func joined() throws -> String {
        let names = try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        // 空振り防止。取り違えでパスが外れたら 0 件になり、どの検査も素通りしてしまう。
        #expect(names.count >= 3, "ソースが読めていない（\(directory.path)）")
        return try names
            .map { try String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
    }
}
