import Foundation

/// ステージが属する世界（#703。#627 の時間帯バリエーションはここに吸収）。
///
/// 18 面が全部同じ場所に見える——「世界（ワールド）の概念が無い」（#703 の要素分解）——
/// を、ステージ番号で固定に切り替える 3 つの景色で埋める（会長決裁 2026-09-14）:
/// 1〜6 面は朝の下町、7〜12 面は夕方の川沿い、13〜18 面は夜の繁華街。
/// ランダムや周回で変えない（同じ面はいつ遊んでも同じ景色。撮影・QA で毎回同じ画になる）。
///
/// **変えるのは背景・地面・岩の色だけ**。乗り手・自転車・台座・床・アイテム・鳥の色は
/// `RunnerPalette` の固定値のままで、当たり判定・速さ・ジャンプ（`RunnerRules`）にも触れない。
/// SpriteKit に依存しない値型なので、境界と配色は `WorldTests` がそのまま固定できる。
public enum RunnerWorld: CaseIterable, Equatable, Sendable {
    /// 1〜6 面。明るい水色の空・若草色の丘・暖色の地面。
    case morning
    /// 7〜12 面。橙〜桃色の空・紫がかった丘・遠景に川。
    case evening
    /// 13〜18 面。**現行の配色をそのまま夜として使う**（既に遊ばれている後半の配色は変えない。
    /// 足すのは遠景のビルの窓だけ）。
    case night

    /// 1 つの世界が受け持つ面数。18 面を 3 等分。
    public static let stagesPerWorld = 6

    /// ステージ番号（1 始まり）が属する世界。
    ///
    /// 範囲外（0 以下・19 以上）は `.night`——QA 用ショーケース（`RunnerStage.debugShowcase`、
    /// `number == 0`）は従来どおりの見た目で出したいのと、ステージを足したときに
    /// 「新しい面だけ配色が無い」状態にならないようにするため。
    public static func world(forStage number: Int) -> RunnerWorld {
        switch number {
        case 1...stagesPerWorld:                       return .morning
        case (stagesPerWorld + 1)...(stagesPerWorld * 2): return .evening
        default:                                       return .night
        }
    }

    /// 読み上げ・見出しに使う名前。
    public var displayName: String {
        switch self {
        case .morning: return "朝の下町"
        case .evening: return "夕方の川沿い"
        case .night:   return "夜の繁華街"
        }
    }

    /// 世界に依存する配色。`RunnerPalette` の同名の定数のうち、空・雲・丘・地面・岩だけを
    /// 世界ごとに差し替える。値は `0xRRGGBB`。
    public struct Palette: Equatable, Sendable {
        /// 空（シーンの背景色）。
        public let sky: UInt32
        /// 雲。
        public let cloud: UInt32
        /// 雲の不透明度（0...1）。白い雲は暗い空では半透明でも見えるが、明るい空では溶ける。
        public let cloudAlpha: Double
        /// 遠景の丘（奥）。
        public let hillFar: UInt32
        /// 近景の丘（手前）。
        public let hillNear: UInt32
        /// 地面の上面。
        public let groundTop: UInt32
        /// 地面の断面。
        public let groundBody: UInt32
        /// 岩の明るい面。
        public let rockLight: UInt32
        /// 岩の本体。
        public let rockBody: UInt32
        /// 岩の陰。
        public let rockDark: UInt32
    }

    /// 遠景に足す飾り。丘と同じ無限ループのタイルに載せる（ノード数を増やしすぎない）。
    public enum Scenery: Equatable, Sendable {
        /// 丘の手前に下町の家並み（会長 QA 2026-09-14「ステージが山なのか何なのか分からない」）。
        case townHouses
        /// 丘の手前に川の帯、地平線に夕焼けの帯。
        case riverside
        /// 丘の手前にビルの影と窓の灯り。
        case cityLights
    }

    public var scenery: Scenery {
        switch self {
        case .morning: return .townHouses
        case .evening: return .riverside
        case .night:   return .cityLights
        }
    }

    /// 道路の配色（会長 QA 2026-09-14「断崖絶壁から緑の上を走る世界観が違和感」）。
    ///
    /// 地面は「土の塊」ではなく**おじさんが走っている道路の断面**として描く: 上からアスファルト
    /// （白い破線つき）・縁石・路肩（世界ごとに草／土手／歩道）・その下の地盤。物理の地面の高さ
    /// （`RunnerField.Metrics.groundY`）は変えず、見た目の層だけをこの色で塗り分ける。
    public struct Road: Equatable, Sendable {
        /// アスファルト（路面）。
        public let asphalt: UInt32
        /// 路面の白線。
        public let line: UInt32
        /// 縁石。
        public let curb: UInt32
        /// 路肩（朝＝草、夕方＝土手の砂、夜＝歩道のコンクリート）。
        public let shoulder: UInt32
        /// 路肩の下の地盤（画面の下端まで）。
        public let subsoil: UInt32
    }

    public var road: Road {
        switch self {
        case .morning:
            // 明るいグレーの路面に緑の路肩。地盤は従来の赤茶（`palette.groundBody`）。
            return Road(asphalt: 0x8A8F9A, line: 0xFFFFFF, curb: 0xE8E2D2, shoulder: 0x6CBF6A, subsoil: 0x8C5A3C)
        case .evening:
            // 夕日で暖色に寄ったグレーの路面。路肩は川の土手の砂色。
            return Road(asphalt: 0x7A6E78, line: 0xFFE9C8, curb: 0xE7C9A0, shoulder: 0xB98A5E, subsoil: 0x7A4A3A)
        case .night:
            // 夜のアスファルト。白線は少し落として街灯の下の見え方に。路肩は歩道のコンクリート。
            return Road(asphalt: 0x353A48, line: 0xD9DCE6, curb: 0x9AA0B0, shoulder: 0x4A5163, subsoil: 0x2C2A38)
        }
    }

    /// 配色。**乗り手の色との被りをここで確かめてある**（`RunnerPalette` の注記のとおり、
    /// 脚 `pants` = 0xE0B27C・車体 `bike` = 0xFF8A7E・服 `shirt` = 0xB3A6F0 は空を背に描かれる）。
    public var palette: Palette {
        switch self {
        case .morning:
            // 朝の下町。空は明るい水色（寒色）——脚の黄土・車体のサーモン・服の薄紫のどれとも
            // 系統が違い、白い雲だけが空に溶けかけるので雲の不透明度を上げる。
            // 丘は若草色（黄緑）2 階調。鳥（`birdBody` = 緑・色相 141°）は 5・6 面にも出て丘を背に飛ぶので、
            // 丘の色相を 80° 台まで黄色側へ寄せて鳥から 55° 以上離す（#818。以前の緑 130° だと紛れた）。
            // 地面は「暖色の地面」——上面をテラコッタ、断面をそれより暗い赤茶にして、
            // 穴の縁の黄（`pitEdge`）・台座の橙（`platformFrame`）とは明度と色相で分ける。
            // 岩はストーングレーのまま**夜より 2 段暗く**する（#920）。夜と同じ 0x939AA8 だと
            // 明るい若草色の丘・灰色の路面（`road.asphalt` = 0x8A8F9A）と明度が並んで輪郭が立たず、
            // 「色味が明るいと岩がみえにくい」（会長 QA 2026-09-15）。本体は丘 2 色・空と 3:1 以上
            // （`RunnerWorldTests` が固定）、縁取り（`rockDark`）は路面と 4:1 以上。
            return Palette(
                sky: 0x6FC3EE,
                cloud: 0xFFFFFF,
                cloudAlpha: 0.9,
                hillFar: 0xBEE07E,
                hillNear: 0x94C24A,
                groundTop: 0xD98B4F,
                groundBody: 0x8C5A3C,
                rockLight: 0x9CA4B2,
                rockBody: 0x585E6E,
                rockDark: 0x23272F
            )
        case .evening:
            // 夕方の川沿い。空は桃色寄りの茜——**サーモン（`bike`）と近い橙は使えない**。
            // 車体の管は空を背に描かれるので、橙の空だと自転車が消える。紫寄りの桃にして
            // 車体・脚（黄土）から色相を離し、橙は地平線の帯（`RunnerPalette.sunsetGlow`）で
            // 「橙〜桃色」のグラデーションに見せる。丘は紫 2 階調、川は丘より暗い群青
            // （`RunnerPalette.riverWater`）——走者の下半身はこの川を背にするので、
            // サーモンの車体がいちばん映える組み合わせ。地面は夕日に染まった砂色。
            // 岩は夕日を受けた**明るい桃灰**にする（#920）。紫の丘 2 色と暖色グレーの路面
            // （`road.asphalt` = 0x7A6E78）はどれも中〜暗の明度なので、中間グレー（旧 0xA08F9E）では
            // 奥の丘（0x7C5FA3）と 1.7:1 しか差が付かなかった。暗くして離す道は無い（近景の丘が
            // 0x4E3B7A と暗く、黒に近づけないと 3:1 に届かない）ので明るい側へ振り、本体を丘 2 色・
            // 路面と 3:1 以上にする（`RunnerWorldTests` が固定）。縁取りは暗い葡萄色。
            return Palette(
                sky: 0xBE6AA0,
                cloud: 0xFFD9C2,
                cloudAlpha: 0.7,
                hillFar: 0x7C5FA3,
                hillNear: 0x4E3B7A,
                groundTop: 0xE0A868,
                groundBody: 0x7A4A3A,
                rockLight: 0xFBF8FA,
                rockBody: 0xD8CCD4,
                rockDark: 0x2A2230
            )
        case .night:
            // 夜の繁華街。**現行の配色そのもの**（`RunnerPalette` の定数と同じ値）。
            // 値をここに書き写してあるのは、`WorldTests` が「夜 = 従来の見た目」をリテラルで
            // 固定するため——定数参照にすると、定数を変えたときにテストが黙って追随する。
            // 岩は紺の丘・暗い路面（`road.asphalt` = 0x353A48）に対して本体だけで 4:1 以上あるので
            // #920 でも触らない（縁取りは全世界共通で入る）。
            return Palette(
                sky: 0x2E4066,
                cloud: 0xFFFFFF,
                cloudAlpha: 0.55,
                hillFar: 0x263A5C,
                hillNear: 0x1F2F4C,
                groundTop: 0x22C3BE,
                groundBody: 0x6B4A32,
                rockLight: 0xC2C8D2,
                rockBody: 0x939AA8,
                rockDark: 0x565D6B
            )
        }
    }
}

// MARK: - ワールドマップ（#798）

public extension RunnerWorld {
    /// 世界の番号（1 始まり）。ワールドマップの「1-1」の左側。
    var number: Int {
        (RunnerWorld.allCases.firstIndex(of: self) ?? 0) + 1
    }

    /// この世界が受け持つステージ番号（1 始まり）の範囲。朝 1…6・夕方 7…12・夜 13…18。
    var stageRange: ClosedRange<Int> {
        let first = (number - 1) * RunnerWorld.stagesPerWorld + 1
        return first...(first + RunnerWorld.stagesPerWorld - 1)
    }

    /// 世界の中での面の位置（1 始まり）。ワールドマップの「1-1」の右側。
    ///
    /// 範囲外（0 以下・19 以上）でも落ちないよう剰余で畳むだけなので、
    /// 呼び出し側で番号の妥当性を確かめてから使う（`stageName(forStage:)` は nil を返す）。
    static func index(ofStage number: Int) -> Int {
        ((number - 1) % stagesPerWorld + stagesPerWorld) % stagesPerWorld + 1
    }

    /// ワールドマップの短い表記「1-1」…「3-6」。
    static func code(forStage number: Int) -> String {
        "\(world(forStage: number).number)-\(index(ofStage: number))"
    }

    /// 面の名前の上限（文字数）。iPhone SE（幅 375pt）で 3 列の格子に 1 行で収めるため
    /// （`WorldTests` が全 18 面について固定する）。
    static let maxStageNameLength = 8

    /// この世界の 6 面の名前（面の順）。
    ///
    /// 「ステージ N / 18」の数字だけでは次に何が来るかの期待が作れない（#798）ので、
    /// 世界の景色に合う短い名前を付ける。遠景の飾り（`scenery`）と同じ景色を言葉にしてあり、
    /// 実在の店名・地名は使わない。長さは `maxStageNameLength` 以内。
    var stageNames: [String] {
        switch self {
        case .morning:
            // 朝の下町。家並み（`townHouses`）の前を走る、目覚めたばかりの町。
            return ["商店街のあさ", "とうふ屋のかど", "こうえんの前", "ふみきり待ち", "さかみちの上", "銭湯のえんとつ"]
        case .evening:
            // 夕方の川沿い。川の帯と夕焼け（`riverside`）の土手道。
            return ["土手のゆうひ", "鉄橋のした", "つり人のいる岸", "すすきの原", "川風のカーブ", "夕焼けの大橋"]
        case .night:
            // 夜の繁華街。ビルの窓の灯り（`cityLights`）。最終面だけ夜明けが近い名前にして
            // 18 面で 1 日が終わる形にする。
            return ["ネオンの入口", "やたいの通り", "ちょうちん横丁", "歩道橋のうえ", "終電のガード下", "夜あけの大通り"]
        }
    }

    /// ステージ番号（1 始まり）の名前。範囲外は nil。
    static func stageName(forStage number: Int) -> String? {
        guard number >= 1, number <= stagesPerWorld * allCases.count else { return nil }
        return world(forStage: number).stageNames[index(ofStage: number) - 1]
    }

    /// ワールドマップで世界を塗り分ける色（`0xRRGGBB`）。
    ///
    /// 朝と夕方は空の色（`palette.sky`）そのまま。夜だけは空（0x2E4066）がダークモードの
    /// カード面（`Theme.surface` の暗色）に溶けて見えないので、同じ青紫の系統で明るめの値にする。
    /// **文字はこの色の上に載せない**（薄い色味の面・上端の帯・見出しの丸にだけ使う）ので、
    /// 文字とのコントラストは `Theme` の面と文字の組み合わせがそのまま効く。
    var mapColor: UInt32 {
        switch self {
        case .morning: return palette.sky
        case .evening: return palette.sky
        case .night:   return 0x6B7FC2
        }
    }
}
