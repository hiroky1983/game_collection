import Foundation

/// ソース走査テストの共通の読み口（#529）。
///
/// 見た目や App ターゲットとの結線は実行では確かめられないため、各テストはソースの形で守っている。
/// その読み込み・コメント除去・件数の数え方が各テストターゲットに同じ形でコピーされていたので、ここに集約する。
public enum SourceScan {
    /// パッケージ（`Packages/GameKit`）のルート。
    public static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameKitTestSupport/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // GameKit/
    }

    /// リポジトリのルート。
    public static var repositoryRoot: URL {
        packageRoot
            .deletingLastPathComponent()   // Packages/
            .deletingLastPathComponent()   // リポジトリのルート
    }

    /// パッケージのルートからの相対パス（例 `Sources/GameOthello/OthelloView.swift`）でソースを読む。
    public static func packageSource(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// `App/` の Swift ソース一式を名前順に連結し、行頭が `//` の行を落として返す。
    ///
    /// 読み口を単一ファイルではなくディレクトリ一式にするのは、View をファイルへ割っただけで
    /// 走査が空振りする形にしないため。行コメントを落とすのは、説明文の言及が `contains` に当たって
    /// 「実装が消えても緑」になるのを防ぐため。
    public static func appSources() throws -> String {
        let appDir = repositoryRoot.appendingPathComponent("App")
        let files = try FileManager.default
            .contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
        // 空振り防止。パスの導出が外れて 0 件になると、「含まない」を見る検査が素通りしてしまう。
        guard !files.isEmpty else { throw SourceScanError.noSources(appDir.path) }
        return try files
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// 各行の `//` 以降（行コメント）を落とす。`https://` のように直前が `:` の `//` はコメントとみなさない。
    public static func strippingComments(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            var search = line.startIndex
            while let slashes = line.range(of: "//", range: search..<line.endIndex) {
                let precedesURL = slashes.lowerBound > line.startIndex
                    && line[line.index(before: slashes.lowerBound)] == ":"
                if !precedesURL { return line[line.startIndex..<slashes.lowerBound] }
                search = slashes.upperBound
            }
            return line[...]
        }.joined(separator: "\n")
    }

    /// 正規表現 `pattern` が `source` に重ならずに現れる回数。パターンが不正なら 0。
    public static func matchCount(of pattern: String, in source: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(
            in: source, range: NSRange(source.startIndex..., in: source)
        )
    }
}

public enum SourceScanError: Error, CustomStringConvertible {
    case noSources(String)

    public var description: String {
        switch self {
        case .noSources(let path): "ソースが読めていない（\(path)）"
        }
    }
}
