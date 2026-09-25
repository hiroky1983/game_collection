import Foundation

/// 1 ステージぶんのコースと速さ（#494）。
///
/// コースは**区画記号の文字列**で書く。1 文字 = 1 区画（`RunnerRules.segmentTiles` タイル）で、
/// 区画の中央に障害を 1 つだけ置く。タイルを直に並べると 1 ステージが数百文字になり、
/// 打ち間違いが静かに「詰むステージ」になるため、間隔を構造で保証する形にしてある。
///
/// | 記号 | 区画の中身 |
/// |---|---|
/// | `-` | 平地 |
/// | `1` `2` `3` | 穴（1〜3 タイル） |
/// | `n` | 低い障害物 |
/// | `t` | 高い障害物 |
/// | `b` | 飛び立つ鳥（#796） |
/// | `d` | 犬（#800） |
/// | `i` | イノシシ（#801） |
/// | `^` | 下から突き上げる障害（#1010。里山＝竹の子・港町＝波しぶき。19 面以降だけ） |
/// | `w` | 二段ジャンプでしか越えられない高い塀（#1091。里山＝石垣・港町＝積まれたコンテナ。19 面以降だけ） |
/// | `s` | スピードアップアイテム（平地 + アイテム。障害としては扱わない） |
/// | `k` | たこ焼き（平地 + 一定時間無敵になるアイテム。障害としては扱わない・#797） |
/// | `P` | 乗れる台座（区画まるごと。**連続する `P` は 1 つの台座にまとまる**） |

/// | `=` | スピードアップ床（平地 + 加速区間。障害としては扱わない。連続すると 1 つの床になる） |
/// | `~` | 沈む床（#1089。里山＝田んぼ・港町＝干潟。平地 + 減速して沈む区間。連続すると 1 つになる） |
/// | `C` | 崩れる足場（#1090。里山＝古い吊り橋・港町＝古い木の桟橋。台座の一種で、乗ると崩れて穴になる） |
public struct RunnerStage: Equatable, Sendable {
    /// 1 始まりのステージ番号。
    public let number: Int
    /// 区画記号の並び。
    public let pattern: String
    /// 走る速さ（ワールド単位 / 秒）。**コース先頭での値**。
    ///
    /// ステージ制ではコース全体で一定。エンドレス（#675）は距離に応じて上がるので、
    /// 走行中の基準速は `speed(at:)` で引く。
    public let speed: Double
    /// 1 ワールド単位進むごとに基準速が上がる量（#675）。ステージ制は 0（一定）。
    public let speedGain: Double
    /// 基準速の上限。`speedGain` が 0 なら `speed` と同じ。
    ///
    /// `RunnerField.step` はこの値で 1 サブステップの移動量を見積もる（速くなる余地を
    /// 最初から見込んでおくので、加速してもすり抜けは起きない）。
    public let speedCap: Double
    /// コースの全長。
    public let length: Double
    /// 左から順に並んだ障害。
    public let hazards: [RunnerHazard]
    /// 左から順に並んだアイテム（スピードアップ `s` とたこ焼き `k`・#797）。
    ///
    /// **`hazards` とは別の配列**。触れて失敗する障害と、触れて得するアイテムを
    /// 同じ配列に混ぜると「越えられるか」の成立条件チェック（`RunnerStageTests`）に
    /// アイテムまで巻き込んでしまう。種類が違っても 1 本の配列に並べる——取得済みの管理
    /// （`RunnerField.collectedPickupIndices`）と描画の消し込み（`RunnerScene`）が添字で
    /// 対応しているので、種類ごとに配列を分けるとその対応を 2 重に持つことになる。
    public let pickups: [RunnerPickup]
    /// 左から順に並んだ乗れる台座（#674）。
    ///
    /// **`hazards` とは別の配列**。台座は「越えるもの」ではなく「上に乗るもの」で、
    /// 接地面そのものを差し替える（`RunnerField.surfaceY(at:)`）。障害と同じ配列に入れると
    /// 「すべての障害が越えられる」という成立条件チェック（`RunnerStageTests`）が
    /// 意味を成さない判定を台座にまで掛けてしまう。
    public let platforms: [RunnerPlatform]

    /// 左から順に並んだスピードアップ床（#672）。
    ///
    /// `pickups` と同じ理由で **`hazards` とは別の配列**。床は障害としては平地なので、
    /// 成立条件チェック（`RunnerStageTests`）にも当たり判定にも巻き込まない。
    public let boostFloors: [RunnerBoostFloor]

    /// 左から順に並んだ沈む床（#1089。里山＝田んぼ・港町＝干潟）。
    ///
    /// `boostFloors` と同じ理由で **`hazards` とは別の配列**（地形としては平地で、越える相手ではない）。
    public let sinkFloors: [RunnerSinkFloor]

    /// `platforms` のうち崩れる足場だけ（#1090）。数え上げ・描画の分岐が何度も書く読み口。
    public var crumblingPlatforms: [RunnerPlatform] {
        platforms.filter { $0.kind == .crumbling }
    }
    /// チェックポイント（コースの中ほど）の x。
    ///
    /// **必ず平地に置く**。障害の上に置くと、再開した瞬間にまたミスになって進めない。
    /// 台座も避ける（#674）——台座の範囲から再開すると、地面の高さに置かれた走者が
    /// 台座の中にめり込んだ状態で始まる。
    /// 中点から右へずらしながら、障害と重ならず着地に必要な余白もある位置を探す。
    /// 走行中に毎サブステップ参照するので、初期化時に 1 度だけ求めて持つ。
    public let checkpoint: Double

    /// チェックポイントの到達率（`checkpoint / length` を四捨五入した整数パーセント）。
    ///
    /// `makeCheckpoint` が障害を避けて中点から後ろへずらすため、ステージによって
    /// ちょうど 50% とは限らない（40〜90% 程度でばらつく）。見た目の標識にはこの
    /// 実際の値をそのまま出す——「50% と書かれた旗」のように固定の数字に見せない
    /// （会長QA「中間地点のデザインも変えたほうがいい。現状何なのかわからん」への対応）。
    ///
    /// 空の `pattern` で作られたステージは `length` が 0 になる。`0 / 0` は NaN で、
    /// `Int(_:)` は NaN を変換できずクラッシュするため、その場合は 0 を返す。
    public var checkpointPercent: Int {
        guard length > 0 else { return 0 }
        return Int((checkpoint / length * 100).rounded())
    }

    /// - Parameters:
    ///   - speedGain: 距離あたりの加速（#675）。既定の 0 で従来どおり一定の速さ。
    ///   - speedCap: 加速の上限。省略すると `speed`（= 加速しない）。
    public init(
        number: Int, pattern: String, speed: Double,
        speedGain: Double = 0, speedCap: Double? = nil
    ) {
        self.number = number
        self.pattern = pattern
        self.speed = speed
        self.speedGain = speedGain
        self.speedCap = max(speed, speedCap ?? speed)
        let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let length = Double(pattern.count) * segmentWidth
        let hazards = Self.makeHazards(pattern: pattern)
        let platforms = Self.makePlatforms(pattern: pattern)
        let sinkFloors = Self.makeSinkFloors(pattern: pattern)
        self.length = length
        self.hazards = hazards
        self.pickups = Self.makePickups(pattern: pattern)
        self.platforms = platforms
        self.checkpoint = Self.makeCheckpoint(
            length: length, hazards: hazards, platforms: platforms, sinkFloors: sinkFloors
        )

        self.boostFloors = Self.makeBoostFloors(pattern: pattern)
        self.sinkFloors = sinkFloors
    }

    /// その地点での基準速（#675）。`speed` から `speedGain` の傾きで上がり、`speedCap` で頭打ち。
    ///
    /// ステージ制（`speedGain` = 0）では常に `speed` を返す。**空中の横速度もこの値**
    /// （`RunnerField.currentSpeed`）なので、跳んでいるあいだに進んだぶんだけごくわずかに
    /// 速くなる——1 回のジャンプ（45 単位）で 0.05 程度で、踏み切りの余裕（`RunnerAutoPilot.baseLead`
    /// の半タイル = 2）に比べて無視できる。生成器はこの差も見込み、成立条件を区画の手前の
    /// 速さ（越えられるか）と先の速さ（間隔）の両方で判定する（`RunnerEndlessCourse`）。
    public func speed(at distance: Double) -> Double {
        guard speedGain > 0 else { return speed }
        return min(speedCap, speed + speedGain * max(0, distance))
    }

    /// 区画記号を障害の並びへ展開する。
    ///
    /// イノシシ（#801）は展開後に岩の並びを見て「どこで止まるか」（`stopAt`）を焼き込む。
    /// 走行中に毎サブステップ岩を探さないため。
    static func makeHazards(pattern: String) -> [RunnerHazard] {
        let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let offset = Double(RunnerRules.hazardTileOffset) * RunnerRules.tileWidth
        var result: [RunnerHazard] = []
        for (index, symbol) in pattern.enumerated() {
            guard let spec = Self.segmentSpec(symbol) else { continue }
            result.append(RunnerHazard(
                kind: spec.kind,
                start: Double(index) * segmentWidth + offset,
                length: Double(spec.tiles) * RunnerRules.tileWidth
            ))
        }
        return result.map { hazard in
            guard hazard.kind == .boar else { return hazard }
            return RunnerHazard(
                kind: .boar, start: hazard.start, length: hazard.length,
                stopAt: boarStop(for: hazard, among: result)
            )
        }
    }

    /// イノシシが止まる x（#801）。出会いの地点（`start`）と出現点（`boarSpawn`）のあいだにある
    /// 岩のうち、**出現点にいちばん近い岩の右端**。走者に出会うより先にぶつかる岩が無ければ nil。
    ///
    /// 出会いの地点より手前の岩は数えない——イノシシはそこへ着く前に走者と出会っている
    /// （出会った時点で跳ばれたか当たったかのどちらかで、その先の動きは見た目にしか関わらない）。
    static func boarStop(for boar: RunnerHazard, among hazards: [RunnerHazard]) -> Double? {
        hazards
            .filter { $0.kind.isRock && $0.end > boar.start && $0.end <= boar.boarSpawn }
            .map(\.end)
            .max()
    }

    /// 区画記号 1 文字の中身。`-`（平地）と未知の文字は nil。
    ///
    /// 穴（`1`〜`3`）は**表記の数字 + 1 タイル**ぶんの幅にする。走者の見た目の横幅
    /// （`RunnerField.Metrics.playerWidth` = 8）に対して数字どおりの1タイル（4）だと
    /// 穴が走者より狭く見え、跳んで越えるべきものに見えなかった（会長QA）。
    /// 区画の並び（`hazardTileOffset`・`segmentTiles`）は変えていないので、
    /// 隣の障害までの間隔は従来どおり保たれる——広がるのは穴の幅だけ。
    ///
    /// `pickupSymbol`（`s`）・`takoyakiSymbol`（`k`）と `boostFloorSymbol`（`=`）・
    /// `sinkFloorSymbol`（`~`）・`crumblingPlatformSymbol`（`C`）はここには
    /// 含めない。**アイテムも床も台座も障害ではない**ので `makeHazards`/`RunnerStageTests` の
    /// 対象から自然に外れる（床は地形としては平地そのもので、台座は越えるのではなく乗るもの）。
    static func segmentSpec(_ symbol: Character) -> (kind: RunnerHazardKind, tiles: Int)? {
        switch symbol {
        case "1": return (.pit, 2)
        case "2": return (.pit, 3)
        case "3": return (.pit, 4)
        case "n": return (.lowBlock, 1)
        case "t": return (.tallBlock, 1)
        case "b": return (.bird, 1)
        case "d": return (.dog, 1)
        case "i": return (.boar, 1)
        case "^": return (.shoot, 1)
        case "w": return (.wall, 1)
        default:  return nil
        }
    }

    /// スピードアップアイテムの区画記号。
    static let pickupSymbol: Character = "s"
    /// たこ焼き（無敵・#797）の区画記号。既存の記号（`-123ntbsP=`）と被らない小文字 1 つ。
    static let takoyakiSymbol: Character = "k"

    /// 区画記号をアイテムの並びへ展開する。障害と同じ「区画の中央」に置く。
    static func makePickups(pattern: String) -> [RunnerPickup] {
        let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let offset = Double(RunnerRules.hazardTileOffset) * RunnerRules.tileWidth
        var result: [RunnerPickup] = []
        for (index, symbol) in pattern.enumerated() {
            let kind: RunnerPickupKind
            switch symbol {
            case pickupSymbol:   kind = .speed
            case takoyakiSymbol: kind = .invincible
            default:             continue
            }
            result.append(RunnerPickup(kind: kind, start: Double(index) * segmentWidth + offset))
        }
        return result
    }

    /// 乗れる台座の区画記号（#674）。
    ///
    /// `=`（スピードアップ床・別 Issue）と紛れないよう大文字 1 文字にしてある。
    static let platformSymbol: Character = "P"

    /// 崩れる足場の区画記号（#1090。Crumble の C）。
    ///
    /// 台座（`P`）と同じ大文字にしてあるのは、**同じ「乗るもの」の仲間だから**
    /// ——置き方の規則（前後の区画は素の平地・上には何も置かない）も同じものが掛かる。
    static let crumblingPlatformSymbol: Character = "C"

    /// その区画記号が作る台座の種類。台座でない記号は nil。
    static func platformKind(_ symbol: Character) -> RunnerPlatform.Kind? {
        switch symbol {
        case platformSymbol:          return .solid
        case crumblingPlatformSymbol: return .crumbling
        default:                      return nil
        }
    }

    /// 区画記号を台座の並びへ展開する。
    ///
    /// **障害と違い、台座は区画をまるごと占める**（`hazardTileOffset` を使わない）。台座は
    /// 上を走るものなので、区画の中央に短く置くと乗った直後に降りることになって用を成さない。
    /// **連続する `P` は 1 つの台座にまとめる**ので、`PPP` は 3 区画ぶんの長さの台座 1 つになる
    /// ——隣り合う 2 つの台座として展開すると、継ぎ目に「端から落ちる」判定が生まれてしまう。
    /// 崩れる足場（`C`・#1090）も同じ規則でまとめるが、**種類が違えばまとめない**
    /// （`PC` は崩れない台座と崩れる足場の 2 基。崩れたときに残る側と消える側が分かれるので、
    /// 1 基に融合させてはいけない）。
    ///
    /// 崩れる足場だけは、まとめたあとに**両端から岸**（`RunnerRules.crumbleBankTiles`）を
    /// 削って板張りぶんの長さにする（岸が無いと、渡り切る距離が区画まるごとになって
    /// 公平さの上限 `RunnerRules.crumbleMaxLength(at:)` に収まらない）。
    static func makePlatforms(pattern: String) -> [RunnerPlatform] {
        let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let bank = Double(RunnerRules.crumbleBankTiles) * RunnerRules.tileWidth
        var result: [RunnerPlatform] = []
        var run: (start: Int, kind: RunnerPlatform.Kind)?

        func close(at index: Int) {
            guard let run else { return }
            let inset = run.kind == .crumbling ? bank : 0
            result.append(RunnerPlatform(
                start: Double(run.start) * segmentWidth + inset,
                length: Double(index - run.start) * segmentWidth - inset * 2,
                kind: run.kind
            ))
        }

        for (index, symbol) in pattern.enumerated() {
            let kind = platformKind(symbol)
            if run?.kind != kind {
                close(at: index)
                run = kind.map { (start: index, kind: $0) }
            }
        }
        close(at: pattern.count)
        return result
    }

    /// スピードアップ床の区画記号（#672）。見た目のとおり「地面が続いている区間」を表す。
    static let boostFloorSymbol: Character = "="

    /// 区画記号をスピードアップ床の並びへ展開する。
    ///
    /// アイテム（点で持つ `RunnerPickup`）と違い、床は**区画まるごと**を占める区間にする。
    /// 「乗っているあいだずっと効く」ものなので、区画の中央に点で置いても踏んだ実感が出ない。
    /// **連続する `=` は 1 つの床にまとめる**——隣り合う区画を別々の床にすると、境目で
    /// 効果が一瞬切れる可能性を残すうえ、描画も継ぎ目が出る。
    static func makeBoostFloors(pattern: String) -> [RunnerBoostFloor] {
        let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        var result: [RunnerBoostFloor] = []
        for (index, symbol) in pattern.enumerated() where symbol == boostFloorSymbol {
            let start = Double(index) * segmentWidth
            // 直前の床の右端にぴたりと続くなら、新しい床を作らず伸ばす。
            if let last = result.last, last.end == start {
                result[result.count - 1] = RunnerBoostFloor(
                    start: last.start, length: last.length + segmentWidth
                )
            } else {
                result.append(RunnerBoostFloor(start: start, length: segmentWidth))
            }
        }
        return result
    }

    /// 沈む床の区画記号（#1089）。水面のさざ波をそのまま字にした 1 文字。
    static let sinkFloorSymbol: Character = "~"

    /// 区画記号を沈む床の並びへ展開する。
    ///
    /// **連続する `~` は 1 本にまとめる**（加速床と同じ理由。境目で効果が切れる余地を作らない）。
    /// 加速床と違うのは、**両端に岸（`RunnerRules.sinkFloorBankTiles`）を残す**こと——
    /// 区画まるごとを水面にすると 1 区画ぶんでも二段ジャンプで跳び越せなくなる
    /// （`RunnerRules.sinkFloorBankTiles` の説明を参照）。岸は連続した並びの**外側だけ**に残す。
    /// 内側にも残すと、まとめた意味が無くなって境目に乾いた地面ができてしまう。
    static func makeSinkFloors(pattern: String) -> [RunnerSinkFloor] {
        let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let bank = Double(RunnerRules.sinkFloorBankTiles) * RunnerRules.tileWidth
        var runs: [(start: Int, count: Int)] = []
        for (index, symbol) in pattern.enumerated() where symbol == sinkFloorSymbol {
            if let last = runs.last, last.start + last.count == index {
                runs[runs.count - 1].count += 1
            } else {
                runs.append((start: index, count: 1))
            }
        }
        return runs.map { run in
            RunnerSinkFloor(
                start: Double(run.start) * segmentWidth + bank,
                length: Double(run.count) * segmentWidth - bank * 2,
                segments: run.count
            )
        }
    }

    /// 中点から右へずらしながら、障害と重ならず着地に必要な余白もある位置を探す。
    ///
    /// 沈む床（#1089）も避ける——水の上から再開すると、走り出した瞬間から沈みが溜まり始め、
    /// 助走の無いまま連打を強いられる（台座を避けるのとまったく同じ理由）。
    /// 台座（#674）も同じ扱いで避ける。再開は必ず地面の高さで始まる
    /// （`RunnerField.init(stage:startingAt:passedCheckpoint:)`）ので、台座の範囲に置くと
    /// 走者が台座にめり込んだ状態から走り出すことになる。
    /// 動く障害（#796）は当たり判定の位置ではなく**関わる距離の範囲**（`RunnerHazard.activeRange`）
    /// を避ける——飛び立つ最中の鳥・突進の予告中のイノシシの目の前から走り出させない。
    static func makeCheckpoint(
        length: Double, hazards: [RunnerHazard], platforms: [RunnerPlatform],
        sinkFloors: [RunnerSinkFloor] = []
    ) -> Double {
        let step = RunnerRules.tileWidth
        // 走者の前後に体 1 つぶんの余白を要求する（縁ぎりぎりから再開させない）。
        let margin = RunnerField.Metrics.playerWidth
        var x = (length / 2 / step).rounded(.down) * step
        let limit = length - step * 4
        while x < limit {
            let onHazard = hazards.contains {
                $0.activeRange.lowerBound - margin < x && x < $0.activeRange.upperBound + margin
            }
            let onPlatform = platforms.contains { $0.start - margin < x && x < $0.end + margin }
            let onSinkFloor = sinkFloors.contains { $0.start - margin < x && x < $0.end + margin }
            if !onHazard, !onPlatform, !onSinkFloor { return x }
            x += step
        }
        return x
    }
}


#if DEBUG
public extension RunnerStage {
    /// QA用: 低い障害物・高い障害物・鳥・犬・イノシシ・穴3サイズ・スピードアップ床・台座を1本で見比べられるステージ
    /// （起動引数 `-simulateRunner showcase`）。`.all`（本番のステージ）には含めない
    /// ——`number` を 0 にして「実ステージではない」ことを型で示す。
    ///
    /// 鳥（`b`）・犬（`d`）・イノシシ（`i`）を入れてあるのは、飛び立つ・前から歩いて来る・
    /// 突進してくる（#796/#955/#801）を本番の面まで遊ばずに確かめるため。狙った瞬間は
    /// `-simulateRunner bird` / `bird-low` / `bird-up` / `dog` / `boar` が 1 枚ずつ撮れる。
    ///
    /// 間隔は他ステージよりゆったり取ってある（QA中に慌てて次の障害へ突っ込まないため）。
    /// 速さは1面と同じ `RunnerRules.baseSpeed` で固定。
    ///
    /// スピードアップ床（`=`・#672）は**走り出しの直後に2区画続けて**置いてある。
    /// 既存15ステージには置かない（本番への投入は新ステージ 16〜18・#674）ので、
    /// 実機スクリーンショットを撮れる場所はここだけ——最初の障害より手前に置くことで、
    /// 走り出してすぐ床の上の状態を撮れる。障害としては平地なので、障害の間隔・
    /// 跳び越しの条件は従来どおり（`makeBoostFloors` を参照）。
    ///
    /// たこ焼き（`k`・#797）は床の直後の素の平地を 1 区画挟んだ次、最初の岩の直前に置いてある。
    /// 取った直後に岩・高い岩を無敵で突っ切る画が `-simulateRunner invincible` で撮れる。
    /// 突き上げ（`^`・#1010）はイノシシの次に置いてある。`-simulateRunner shoot` / `shoot-up` で
    /// 「伸びかけ」と「伸び切り」が 1 枚ずつ撮れる（絵は世界の着せ替え——ショーケースは
    /// **朝の下町**で走る（`RunnerScene.rebuildCourse` が `number == 0` を朝に倒す）ので、
    /// `RunnerWorld.originalDressing` の竹の子が出る）。
    /// 沈む床（`~`・#1089）は突き上げの次に **2 区画続けて**置いてある。本番の短い床（1 区画）では
    /// 自動操縦が 1 回跳ぶだけで抜けてしまい、沈みかけ・溺れた瞬間（`-simulateRunner sink` /
    /// `sink-failed`）を撮る間が無い。2 区画ぶん（= 長い床）なら、跳ばずに走らせれば必ず沈み切る。
    /// 崩れる足場（`C`・#1090）は台座の次に 1 区画。**連続では置けない**——2 区画ぶんの板張りは
    /// どの面の速さでも渡り切れず（`RunnerRules.crumbleMaxLength(at:)`）、
    /// `RunnerCrumblingPlatformTests.crumblingPlatformsAreCrossableAtMinimumPedal` が弾く。
    /// 高い塀（`w`・#1091）は崩れる足場の次に 1 区画、前後を素の平地にして置いてある。
    /// `-simulateRunner wall`（塀の手前）・`wall-double`（二段目の頂点）が 1 枚ずつ撮れる。
    /// 本番の 24・27・28・30 面（石垣・コンテナ）は `-simulateRunner wall:24` のように面を指定して撮る。
    static let debugShowcase = RunnerStage(
        number: 0,
        pattern: "--==-kn--t--b--d--i--^--~~--PP--C--w--1--2--3--",
        speed: RunnerRules.baseSpeed
    )
}
#endif
