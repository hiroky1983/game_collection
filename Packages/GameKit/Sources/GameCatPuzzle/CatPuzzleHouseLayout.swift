import Foundation

/// 盤（部屋の形）から家具・ドア・窓の置き場所を決める（#2250・会長決裁 2026-10-22「ドールハウス」）。
/// 手で置かず、どの盤でも同じ規則で自動で決める。モック `house.js` の `analyze` をそのまま移した。
///
/// - 家具: 部屋に完全に入る最大の長方形を取り、部屋の種類ごとの小物（こたつ・縁側は 2×2 / 1×1、それ以外は
///   2×1 / 1×2 / 1×1）のうち入る最大のものを、札のマスから最も遠い位置に置く。
/// - ドア: 部屋の隣接グラフの全域木（玄関から幅優先、無ければ部屋 0）の辺ごとに 1 枚。共有する壁の最長の直線区間の
///   中央のマス辺に置き、扉の前に家具が無い側へ開く。
/// - 窓: 外周に接する部屋ごとに 1 つ、最長の外周区間の中央（押し入れは無し、玄関は玄関戸）。
///
/// 計算は盤ごとに 1 回で済むよう `cached(for:)` で持つ（描画のたびに計算しない）。
struct CatPuzzleHouseLayout: Equatable, Sendable {
    /// 家具 1 つ（マス単位の箱。`row`/`col` は左上のマス）。
    struct Furniture: Equatable, Sendable {
        let room: Int
        let kind: CatPuzzleHouse.Furniture
        let row: Int
        let col: Int
        let width: Int
        let height: Int

        /// 箱が覆うマス。
        func cells(side n: Int) -> [Int] {
            (row..<(row + height)).flatMap { r in (col..<(col + width)).map { r * n + $0 } }
        }
    }

    /// 壁の 1 辺。マス（`row`, `col`）の右辺（`vertical`）か下辺（`horizontal`）。
    struct WallSegment: Hashable, Sendable {
        enum Orientation: Hashable, Sendable { case vertical, horizontal }
        let orientation: Orientation
        let row: Int
        let col: Int
        /// 左（上）の部屋。
        let roomA: Int
        /// 右（下）の部屋。
        let roomB: Int

        /// 壁の手前のマス（A 側）と向こうのマス（B 側）。
        func cells(side n: Int) -> (a: Int, b: Int) {
            let a = row * n + col
            return (a, orientation == .vertical ? a + 1 : a + n)
        }
    }

    /// ドア 1 枚。
    struct Door: Equatable, Sendable {
        let segment: WallSegment
        /// 扉が B 側（右／下）へ開くか。
        let opensTowardB: Bool
    }

    /// 窓（玄関は玄関戸）。
    struct Window: Equatable, Sendable {
        enum Side: Hashable, Sendable { case top, bottom, left, right }
        let room: Int
        let side: Side
        /// 窓を付ける外周のマス。
        let cell: Int
        let isEntrance: Bool
    }

    let side: Int
    let furniture: [Furniture]
    /// 部屋の境目の壁（行優先の順）。
    let walls: [WallSegment]
    let doors: [Door]
    let windows: [Window]

    /// ドアのある壁の辺（壁を描くとき、ここだけ切る）。
    var doorSegments: Set<WallSegment> { Set(doors.map(\.segment)) }

    // MARK: - キャッシュ

    @MainActor private static var cache: [CatPuzzle: CatPuzzleHouseLayout] = [:]

    /// 盤ごとに 1 回だけ計算した配置。直近の数問ぶんだけ持つ。
    @MainActor
    static func cached(for puzzle: CatPuzzle) -> CatPuzzleHouseLayout {
        if let hit = cache[puzzle] { return hit }
        let layout = compute(for: puzzle)
        if cache.count >= 8 { cache.removeAll() }
        cache[puzzle] = layout
        return layout
    }

    // MARK: - 計算

    @MainActor
    static func compute(for puzzle: CatPuzzle) -> CatPuzzleHouseLayout {
        let n = puzzle.side
        let rooms = puzzle.rooms
        let roomCount = (rooms.max() ?? -1) + 1
        func roomOf(_ r: Int, _ c: Int) -> Int { rooms[r * n + c] }
        let cellsOfRoom = (0..<roomCount).map { puzzle.cells(inRoom: $0) }
        let kinds = (0..<roomCount).map { CatPuzzleHouse.room($0).furniture }

        // 札のマス（本番の `labelPlacement` と同じ: 左上から最初の答えでないマス）。
        let label = (0..<roomCount).map { room -> (r: Int, c: Int) in
            let cell = CatPuzzleBoardCanvas.labelPlacement(room: room, in: puzzle, wide: false)?.cell ?? cellsOfRoom[room].first ?? 0
            return (cell / n, cell % n)
        }

        // 部屋に完全に入る最大の長方形（同じ面積なら正方形に近いほう）。
        func largestRect(_ room: Int) -> (r0: Int, c0: Int, w: Int, h: Int) {
            var best: (r0: Int, c0: Int, w: Int, h: Int, area: Int)?
            for r0 in 0..<n {
                for c0 in 0..<n where roomOf(r0, c0) == room {
                    var h = 1
                    while r0 + h <= n {
                        var ok = true
                        var w = 1
                        while c0 + w <= n && ok {
                            rows: for r in r0..<(r0 + h) {
                                for c in c0..<(c0 + w) where roomOf(r, c) != room { ok = false; break rows }
                            }
                            if !ok { break }
                            let area = w * h
                            if best == nil || area > best!.area || (area == best!.area && min(w, h) > min(best!.w, best!.h)) {
                                best = (r0, c0, w, h, area)
                            }
                            w += 1
                        }
                        if r0 + h < n && roomOf(r0 + h, c0) != room { break }
                        h += 1
                    }
                }
            }
            let b = best ?? (0, 0, 1, 1, 1)
            return (b.r0, b.c0, b.w, b.h)
        }

        // 家具: 最大長方形の中に入る最大の小物を、札のマスから最も遠い位置に。
        var furniture: [Furniture] = []
        for room in 0..<roomCount {
            let rect = largestRect(room)
            let kind = kinds[room]
            let square = kind.isSquare
            var fw = 1, fh = 1
            if rect.w >= 2 && rect.h >= 2 { fw = 2; fh = square ? 2 : 1 }
            else if rect.w >= 2 { fw = 2; fh = 1 }
            else if rect.h >= 2 { fw = 1; fh = 2 }
            // 縦長の部屋では 2 マスの小物を縦向きにする。
            if !square && rect.w >= 2 && rect.h >= 2 && rect.h > rect.w { fw = 1; fh = 2 }
            let l = label[room]
            var best: (r: Int, c: Int, d: Int)?
            for r in rect.r0...(rect.r0 + rect.h - fh) {
                for c in rect.c0...(rect.c0 + rect.w - fw) {
                    // 中心の距離の 2 乗（座標を 2 倍して整数で比べる）。
                    let dr = 2 * r + fh - 1 - 2 * l.r, dc = 2 * c + fw - 1 - 2 * l.c
                    let d = dr * dr + dc * dc
                    if best == nil || d > best!.d { best = (r, c, d) }
                }
            }
            let place = best ?? (rect.r0, rect.c0, 0)
            furniture.append(Furniture(room: room, kind: kind, row: place.r, col: place.c, width: fw, height: fh))
        }
        let furnitureCells = Set(furniture.flatMap { $0.cells(side: n) })

        // 壁の辺（部屋の境目）。行優先の順。
        var walls: [WallSegment] = []
        for r in 0..<n {
            for c in 0..<n {
                if c < n - 1, roomOf(r, c) != roomOf(r, c + 1) {
                    walls.append(WallSegment(orientation: .vertical, row: r, col: c, roomA: roomOf(r, c), roomB: roomOf(r, c + 1)))
                }
                if r < n - 1, roomOf(r, c) != roomOf(r + 1, c) {
                    walls.append(WallSegment(orientation: .horizontal, row: r, col: c, roomA: roomOf(r, c), roomB: roomOf(r + 1, c)))
                }
            }
        }

        // 隣接グラフ → 全域木（玄関があれば玄関から、無ければ部屋 0 から幅優先）。
        var adjacency = [Set<Int>](repeating: [], count: roomCount)
        for s in walls {
            adjacency[s.roomA].insert(s.roomB)
            adjacency[s.roomB].insert(s.roomA)
        }
        let entrance = kinds.firstIndex(of: .genkan)
        let start = entrance ?? 0
        var seen: Set<Int> = roomCount > 0 ? [start] : []
        var queue = roomCount > 0 ? [start] : []
        var tree: [(u: Int, v: Int)] = []
        var head = 0
        while head < queue.count {
            let u = queue[head]; head += 1
            for v in adjacency[u].sorted() where !seen.contains(v) {
                seen.insert(v)
                tree.append((u, v))
                queue.append(v)
            }
        }

        // 辺ごとに、共有する壁の最長の直線区間の中央のマス辺にドア。
        struct Run { let key: (WallSegment.Orientation, Int); var min: Int; var max: Int; var segments: [WallSegment] }
        var doors: [Door] = []
        for (u, v) in tree {
            let shared = walls.filter { ($0.roomA == u && $0.roomB == v) || ($0.roomA == v && $0.roomB == u) }
            var runs: [Run] = []
            for s in shared {
                let key = (s.orientation, s.orientation == .vertical ? s.col : s.row)
                let pos = s.orientation == .vertical ? s.row : s.col
                if let i = runs.firstIndex(where: { $0.key == key && ($0.max + 1 == pos || $0.min - 1 == pos) }) {
                    runs[i].min = min(runs[i].min, pos)
                    runs[i].max = max(runs[i].max, pos)
                    runs[i].segments.append(s)
                } else {
                    runs.append(Run(key: key, min: pos, max: pos, segments: [s]))
                }
            }
            // 最長の区間（同じ長さなら先に見つかったもの）。
            guard var run = runs.first else { continue }
            for candidate in runs where candidate.max - candidate.min > run.max - run.min { run = candidate }
            let mid = (run.min + run.max) / 2
            guard let segment = run.segments.first(where: { ($0.orientation == .vertical ? $0.row : $0.col) == mid }) else { continue }
            // 開く向き: 扉の前のマスに家具が無い側へ（両方にあれば大きい部屋へ）。
            let cells = segment.cells(side: n)
            var towardB = true
            if furnitureCells.contains(cells.b) && !furnitureCells.contains(cells.a) {
                towardB = false
            } else if furnitureCells.contains(cells.b) && furnitureCells.contains(cells.a) {
                towardB = !(cellsOfRoom[segment.roomA].count > cellsOfRoom[segment.roomB].count)
            }
            doors.append(Door(segment: segment, opensTowardB: towardB))
        }

        // 窓: 外周に接する部屋ごとに最長区間の中央（押し入れは無し）。
        struct Edge { let side: Window.Side; let pos: Int; let cell: Int }
        var windows: [Window] = []
        for room in 0..<roomCount where kinds[room] != .oshiire {
            var edges: [Edge] = []
            for cell in cellsOfRoom[room] {
                let r = cell / n, c = cell % n
                if r == 0 { edges.append(Edge(side: .top, pos: c, cell: cell)) }
                if r == n - 1 { edges.append(Edge(side: .bottom, pos: c, cell: cell)) }
                if c == 0 { edges.append(Edge(side: .left, pos: r, cell: cell)) }
                if c == n - 1 { edges.append(Edge(side: .right, pos: r, cell: cell)) }
            }
            guard !edges.isEmpty else { continue }
            // 位置の順（同じ位置は見つけた順のまま）。
            let ordered = edges.enumerated().sorted { ($0.element.pos, $0.offset) < ($1.element.pos, $1.offset) }.map(\.element)
            struct EdgeRun { let side: Window.Side; var min: Int; var max: Int; var items: [Edge] }
            var runs: [EdgeRun] = []
            for e in ordered {
                if let i = runs.firstIndex(where: { $0.side == e.side && $0.max + 1 == e.pos }) {
                    runs[i].max = e.pos
                    runs[i].items.append(e)
                } else {
                    runs.append(EdgeRun(side: e.side, min: e.pos, max: e.pos, items: [e]))
                }
            }
            guard var run = runs.first else { continue }
            for candidate in runs where candidate.max - candidate.min > run.max - run.min { run = candidate }
            let mid = run.items[run.items.count / 2]
            windows.append(Window(room: room, side: run.side, cell: mid.cell, isEntrance: kinds[room] == .genkan))
        }

        return CatPuzzleHouseLayout(side: n, furniture: furniture, walls: walls, doors: doors, windows: windows)
    }
}


