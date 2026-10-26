/// 15 パズルの純粋ロジック。盤は長さ `size * size` の配列（行優先）で、0 が空白、1〜(マス数 - 1) がタイル。
/// 盤の大きさ（#2869）は 3×3・4×4・5×5。大きさは配列の長さから決まるので、関数は盤だけを受け取る。
public enum FifteenLogic {
    /// 選べる盤の大きさ（一辺のマス数）。
    public static let sizes = 3...5
    /// 既定の大きさ。4×4 は従来どおりの盤で、記録も区分なしの従来の保存先を使う。
    public static let defaultSize = 4
    /// 既定の大きさのマス数。
    public static let cellCount = defaultSize * defaultSize
    /// 既定の大きさで揃った盤。
    public static let solved: [Int] = solved(size: defaultSize)

    /// 揃った盤。1〜 が左上から並び、右下が空白。
    public static func solved(size: Int) -> [Int] { Array(1..<(size * size)) + [0] }

    /// 盤の長さから一辺のマス数を求める。3×3・4×4・5×5 のどれでもなければ nil（中断データの健全性検査にも使う）。
    public static func size(ofCellCount count: Int) -> Int? {
        sizes.first { $0 * $0 == count }
    }

    /// 空白が 1 つとタイルが 1 つずつ並んだ盤か（中断データの健全性検査にも使う）。
    public static func isPermutation(_ tiles: [Int]) -> Bool {
        size(ofCellCount: tiles.count) != nil && Set(tiles) == Set(0..<tiles.count)
    }

    public static func isSolved(_ tiles: [Int]) -> Bool {
        guard let size = size(ofCellCount: tiles.count) else { return false }
        return tiles == solved(size: size)
    }

    /// 空白を動かして揃えられる盤か。
    ///
    /// 幅が奇数（3・5）の盤では、「空白を除いた転倒数」が**偶数**のときに限り解ける。
    /// 幅が偶数（4）の盤では、転倒数と「空白が下から数えて何行目か（1 始まり）」の和が
    /// **奇数**のときに限り解ける（揃った盤は転倒数 0・空白が 1 行目で和 1）。
    public static func isSolvable(_ tiles: [Int]) -> Bool {
        guard isPermutation(tiles), let size = size(ofCellCount: tiles.count) else { return false }
        if size % 2 == 1 { return inversions(tiles) % 2 == 0 }
        let blankRowFromBottom = size - tiles.firstIndex(of: 0)! / size
        return (inversions(tiles) + blankRowFromBottom) % 2 == 1
    }

    /// 空白を除いた転倒数（自分より後ろにある、自分より小さいタイルの組の数）。
    public static func inversions(_ tiles: [Int]) -> Int {
        var count = 0
        for i in tiles.indices where tiles[i] != 0 {
            for j in (i + 1)..<tiles.count where tiles[j] != 0 && tiles[j] < tiles[i] {
                count += 1
            }
        }
        return count
    }

    /// 必ず解ける、揃っていない盤を作る。
    ///
    /// ランダムな並べ替えの半分は解けない配置なので、解けなければタイル 2 枚を入れ替えて偶奇を直す
    /// （転倒数の偶奇が 1 つ変わり、空白の位置は動かないので、必ず解ける側へ移る）。
    public static func shuffled<G: RandomNumberGenerator>(size: Int = defaultSize, using generator: inout G) -> [Int] {
        while true {
            var tiles = Array(0..<(size * size)).shuffled(using: &generator)
            if !isSolvable(tiles) {
                let filled = tiles.indices.filter { tiles[$0] != 0 }
                tiles.swapAt(filled[0], filled[1])
            }
            if !isSolved(tiles) { return tiles }
        }
    }

    /// `index` のタイルをタップしたときの盤。空白と同じ行・列にあれば、空白までの間のタイルを
    /// まとめて 1 マスずつ寄せる。動かせなければ nil。`distance` は動いたタイルの枚数（= 手数）。
    public static func slide(_ tiles: [Int], at index: Int) -> (tiles: [Int], distance: Int)? {
        guard let size = size(ofCellCount: tiles.count),
              tiles.indices.contains(index), let blank = tiles.firstIndex(of: 0), index != blank else { return nil }
        let sameRow = index / size == blank / size
        let sameColumn = index % size == blank % size
        guard sameRow || sameColumn else { return nil }
        let step = sameRow ? 1 : size
        let direction = index > blank ? step : -step
        var result = tiles
        var position = blank
        var distance = 0
        while position != index {
            result[position] = result[position + direction]
            position += direction
            distance += 1
        }
        result[index] = 0
        return (result, distance)
    }
}
