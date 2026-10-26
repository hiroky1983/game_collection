/// 定跡ブックで、同じ局面に複数ある候補から 1 つを選ぶ（将棋・チェス #2800）。
///
/// 種（対局ごとに 1 つ）と局面のキーだけで決まるので、同じ種なら同じ局面で必ず同じ手になる
/// （テストが決定的になり、1 局の中で同じ局面に戻っても手が揺れない）。
/// `String.hashValue` はプロセスごとに値が変わるため使わず、FNV-1a で文字列を数値にする。
public enum BookPicker {
    /// `0..<count` の添字を返す。`count` は 1 以上。
    public static func index(count: Int, seed: UInt64, key: String) -> Int {
        precondition(count > 0)
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        var rng = SplitMix64(seed: seed ^ hash)
        return Int(rng.next() % UInt64(count))
    }
}
