import Foundation

/// ステージが属する世界（#703。#627 の時間帯バリエーションはここに吸収）。
///
/// 18 面が全部同じ場所に見える——「世界（ワールド）の概念が無い」（#703 の要素分解）——
/// を、ステージ番号で固定に切り替える 3 つの景色で埋める（会長決裁 2026-09-14）:
/// 1〜6 面は朝の下町、7〜12 面は夕方の川沿い、13〜18 面は夜の繁華街。
/// ランダムや周回で変えない（同じ面はいつ遊んでも同じ景色。撮影・QA で毎回同じ画になる）。
///
/// **変えるのは背景・地面・岩・動く障害（犬・イノシシ・鳥）の色だけ**。乗り手・自転車・台座・床・
/// アイテムの色は `RunnerPalette` の固定値のままで、当たり判定・速さ・ジャンプ（`RunnerRules`）にも
/// 触れない。SpriteKit に依存しない値型なので、境界と配色は `WorldTests` がそのまま固定できる。
///
/// 配色の規則（会長指示 2026-09-15・#929）: **背景は淡く沈め、手前は濃く縁取る**。
/// 背景（空・丘・路面・遠景の飾り）は彩度を落として互いの明度差を 2:1 未満に収め、
/// 手前の物（岩・犬・イノシシ・鳥・たこ焼き・台座・旗）は主色か暗い縁取り（`outline`）の
/// どちらかが背景のどれに対しても 3:1 以上の相対輝度比を持つ（`WorldTests` が固定）。
/// 朝は背景が明るいので手前を**暗く**、夜は背景が暗いので手前を**明るく**し、
/// 夕方は背景が中間の明度なので手前を明るくして縁取りで締める。
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
            // 淡いグレーの路面に淡い緑の路肩、地盤は淡い土色（#929「背景を全部淡い色にする」。
            // 旧 0x8A8F9A / 0x6CBF6A / 0x8C5A3C）。路面は暗い縁取りの手前の物が 3:1 以上で
            // 乗る明るさ（相対輝度 0.50）にし、白線は路面より 60 以上明るい（`WorldTests`）。
            return Road(asphalt: 0xB8BCC4, line: 0xFFFFFF, curb: 0xE8E2D2, shoulder: 0xA9D59A, subsoil: 0xC9AA8E)
        case .evening:
            // 夕日で暖色に寄ったグレーの路面。路肩は川の土手の砂色。路面は #929 でも変えない——
            // 明るくすると夕方の手前の物（明るい側に振った犬・イノシシ・岩）との差が失われる。
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
            // 朝の下町。**背景は全部パステル**（会長指示 2026-09-15・#929「昼の背景だと犬が全く
            // 見えない」）。空は淡い水色（旧 0x6FC3EE）、丘は彩度を落とした淡い黄緑 2 階調
            // （旧 0xBEE07E / 0x94C24A）で、空・丘・路面・家の壁と屋根の相対輝度は 0.45〜0.80 に
            // 収めて互いに沈ませる（`WorldTests` が背景同士 2:1 未満で固定）。白に近づけすぎない
            // ——走者の白い車輪・手や雲と被る（会長）。雲は白のままだが淡い空では溶けかけるので
            // 不透明度は 0.9 のまま。空の色相（寒色）は脚の黄土・車体のサーモン・服の薄紫から
            // 離れている（`skiesAreFarFromRiderHues`）。
            // 手前の物は逆に**暗く**する: 岩は #920 のストーングレー（本体 0x585E6E）のまま——
            // 本体だけで路面・丘・壁・屋根の全部と 3:1 以上ある。犬・イノシシ・鳥も `creatures` で
            // 暗い主色にし、縁取り（`creatures.outline`）で締める。
            // 地面（`groundTop` / `groundBody`）は道路化以降描かれないが、路肩の下の地盤
            // （`road.subsoil`）と同じ淡い土色に揃えておく。
            return Palette(
                sky: 0xCFE6F5,
                cloud: 0xFFFFFF,
                cloudAlpha: 0.9,
                hillFar: 0xC6DDB0,
                hillNear: 0xB2CF9C,
                groundTop: 0xE6C9A8,
                groundBody: 0xC9AA8E,
                rockLight: 0x9CA4B2,
                rockBody: 0x585E6E,
                rockDark: 0x23272F
            )
        case .evening:
            // 夕方の川沿い。空は桃色寄りの茜——**サーモン（`bike`）と近い橙は使えない**。
            // 車体の管は空を背に描かれるので、橙の空だと自転車が消える。紫寄りの桃にして
            // 車体・脚（黄土）から色相を離し、橙は地平線の帯（`SceneryPalette.sunsetGlow`）で
            // 「橙〜桃色」のグラデーションに見せる。丘は紫 2 階調、川は丘より暗い群青
            // （`SceneryPalette.riverWater`）——走者の下半身はこの川を背にするので、
            // サーモンの車体がいちばん映える組み合わせ。地面は夕日に染まった砂色。
            // 岩は夕日を受けた**明るい桃灰**にする（#920）。紫の丘 2 色と暖色グレーの路面
            // （`road.asphalt` = 0x7A6E78）はどれも中〜暗の明度なので、中間グレー（旧 0xA08F9E）では
            // 奥の丘（0x7C5FA3）と 1.7:1 しか差が付かなかった。暗くして離す道は無いので明るい側へ
            // 振り、本体を丘 2 色・路面と 3:1 以上にする（`RunnerWorldTests` が固定）。縁取りは暗い葡萄色。
            // #929 で近景の丘を 0x4E3B7A → 0x6E5A96 に**淡く**した（川も `SceneryPalette.riverWater`
            // で同様）。暗いままだと暗い縁取り（`creatures.outline`）がそこで 2:1 しか付かず、
            // 「背景は淡く沈め、手前は縁取りで浮かせる」規則の縁取り側が効かない。明るい岩の本体は
            // 淡くした丘とも 3:1 以上を保つ。
            return Palette(
                sky: 0xBE6AA0,
                cloud: 0xFFD9C2,
                cloudAlpha: 0.7,
                hillFar: 0x7C5FA3,
                hillNear: 0x6E5A96,
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

// MARK: - 手前の物の色と縁取り（#929）

public extension RunnerWorld {
    /// 動く障害（犬 #800・イノシシ #801・鳥 #796）の配色と、手前の物に共通の縁取りの色。
    /// 値は `0xRRGGBB`。
    ///
    /// 世界ごとに持つのは、**主色が背景（丘・路面・遠景の飾り）と 3:1 以上**という要件
    /// （#929 の受け入れ条件）が世界で正反対の向きになるため——朝は背景が明るいので暗い主色、
    /// 夜は背景が暗いので明るい主色、夕方は中間なので明るい側へ振る。当たり判定・寸法は
    /// 色と無関係（`RunnerHazardKind`）。
    struct Creatures: Equatable, Sendable {
        /// 手前の物に共通の縁取り。`RunnerScene` が犬・イノシシ・鳥・たこ焼き・台座の床板・旗の
        /// 輪郭に 0.4 単位（iPhone で 1.5pt 相当）で引く。岩の縁取りは `Palette.rockDark`。
        public let outline: UInt32
        /// 犬の体（主色）。
        public let dogBody: UInt32
        /// 犬の耳・鼻・目と脚。体より暗い。
        public let dogDark: UInt32
        /// 犬の腹・口元の差し色。
        public let dogBelly: UInt32
        /// イノシシの体（主色）。
        public let boarBody: UInt32
        /// イノシシのたてがみ・脚・耳。体より暗い。
        public let boarDark: UInt32
        /// イノシシの鼻先。
        public let boarSnout: UInt32
        /// 鳥の胴・頭（主色）。
        public let birdBody: UInt32
        /// 鳥の手前の翼・尾羽の 1 枚。胴より一段暗い。
        public let birdWing: UInt32
        /// 鳥の奥の翼・尾羽の奥の 1 枚。手前の翼よりさらに暗い（羽ばたきで 2 枚が重なっても別の翼と分かる）。
        public let birdWingFar: UInt32
        /// 鳥の腹・白目。
        public let birdBelly: UInt32
    }

    var creatures: Creatures {
        switch self {
        case .morning:
            // 背景がパステルなので主色は**暗く、彩度は保つ**。犬は焦げた柴色（旧 0xD9944A の明るい茶は
            // 淡い路面と 1.3:1 しかない）、イノシシはさらに暗い焦げ茶、鳥は深緑（色相は夜の緑 141° と
            // 同じ系統。丘の黄緑 90° 前後から 50° 離れ、明るさでも離れる——#818）。
            // 縁取りは暖色寄りの黒。
            return Creatures(
                outline: 0x241A14,
                dogBody: 0x8A4A1A, dogDark: 0x3A1E0C, dogBelly: 0xF6E7CF,
                boarBody: 0x5A3618, boarDark: 0x2E1A0C, boarSnout: 0xB88A6A,
                birdBody: 0x1C6337, birdWing: 0x144A28, birdWingFar: 0x0C331A, birdBelly: 0xE8F5E0
            )
        case .evening:
            // 背景（紫の丘・群青の川・暖色グレーの路面）は中〜暗の明度で、暗い主色では届かない
            // （近景の丘と 3:1 にするには黒に近づけるしかない）ので、岩（#920）と同じく**夕日を
            // 受けた明るい側**へ振る。犬は淡いクリームの柴、イノシシは淡い砂色、鳥は川沿いの白鷺。
            // 縁取りは暗い葡萄色寄りの黒で、淡くした丘・川（相対輝度 0.13 以上）と 3:1 以上。
            return Creatures(
                outline: 0x120E16,
                dogBody: 0xF3D9A6, dogDark: 0x5A3418, dogBelly: 0xFFF8EC,
                boarBody: 0xE5CDB8, boarDark: 0x3E2414, boarSnout: 0xB88A6A,
                birdBody: 0xF2EFE4, birdWing: 0xC9C4C0, birdWingFar: 0x9A9498, birdBelly: 0xFFFFFF
            )
        case .night:
            // 夜は世界を分ける前の値（`RunnerPalette` にあった定数）そのまま——背景が暗いので
            // 明るい主色だけで 3:1 以上ある。例外はイノシシ: 旧 0x6B4226 は夜の路面（0x353A48）と
            // 1.3:1 だったので、街灯に照らされた明るめの茶 0xB08060 に上げる。
            return Creatures(
                outline: 0x0E1420,
                dogBody: 0xD9944A, dogDark: 0x5A3418, dogBelly: 0xF6E7CF,
                boarBody: 0xB08060, boarDark: 0x3E2414, boarSnout: 0xD8B098,
                birdBody: 0x4FAE71, birdWing: 0x2F7D4E, birdWingFar: 0x1F5C38, birdBelly: 0xE8F5E0
            )
        }
    }

    /// 手前の物に共通の縁取り（`creatures.outline` の別名。たこ焼き・台座・旗が使う）。
    var outline: UInt32 { creatures.outline }
}

// MARK: - 遠景の飾りの色（#929）

public extension RunnerWorld {
    /// 世界に固有の遠景の飾り（川・夕焼けの帯・ビル）の色。値は `0xRRGGBB`。
    /// 家並みの色は `TownHouse.Palette`。
    enum SceneryPalette {
        /// 夕方の川（`Scenery.riverside`）の水面。丘の紫より暗い群青にして、走者の下半身
        /// （サーモンの車体・黄土の脚）がこの上でいちばん映えるようにする。
        /// #929 で 0x3E3E7E → 0x6664A8 に淡くした（近景の丘と同じ理由——暗い縁取りが効く明るさにする）。
        public static let riverWater: UInt32 = 0x6664A8
        /// 川面の照り返し（細い帯）。夕日の色を水面に落として「川」だと読めるようにする。
        public static let riverGlint: UInt32 = 0xF2B08A
        /// 夕方の地平線の帯。空の桃色（`RunnerWorld.evening`）に対して橙を足し、
        /// 「橙〜桃色の空」を 2 色で作る。丘の後ろに置くので走者とは重ならない。
        public static let sunsetGlow: UInt32 = 0xF0955C
        /// 夜のビルの影（`Scenery.cityLights`）。近景の丘（`hillNear`）よりさらに暗い紺。
        public static let building: UInt32 = 0x16223A
        /// ビルの窓の灯り。暖色の小さな矩形で、夜の空と影に対して唯一の明るい点になる。
        public static let buildingWindow: UInt32 = 0xFFD98A
    }

    /// 遠景の飾りのタイル幅（`RunnerScene.hillSpacing`）。家並み（`townHouses`）の `dx` はこの幅の中の位置。
    static let sceneryTileWidth: Double = 60

    /// 手前の物が重なりうる背景の色（名前つき）。`WorldTests` が「手前の主色か縁取りが
    /// これら全部と 3:1 以上」「背景同士は 2:1 未満で沈む」を固定する。
    ///
    /// 載せるのは地面（`RunnerField.Metrics.groundY`）より**上**にある面だけ——手前の物は地面の
    /// 上に立つので、路面（`road.asphalt`）は足元で接する面として入れ、その下の縁石・路肩・地盤は
    /// 入れない。空は鳥だけが背にする（丘の稜線の切れ目）ので `skyBackdrops` に分けてある。
    var groundBackdrops: KeyValuePairs<String, UInt32> {
        switch self {
        case .morning:
            return [
                "hillFar": palette.hillFar, "hillNear": palette.hillNear, "asphalt": road.asphalt,
                "houseWall": TownHouse.Palette.wall,
                "houseRoofTile": TownHouse.Palette.roofTile,
                "houseRoofSlate": TownHouse.Palette.roofSlate,
                "houseRoofSage": TownHouse.Palette.roofSage,
            ]
        case .evening:
            return [
                "hillFar": palette.hillFar, "hillNear": palette.hillNear, "asphalt": road.asphalt,
                "river": SceneryPalette.riverWater,
            ]
        case .night:
            return [
                "hillFar": palette.hillFar, "hillNear": palette.hillNear, "asphalt": road.asphalt,
                "building": SceneryPalette.building,
            ]
        }
    }

    /// 空と、丘の後ろに敷く帯（夕方の夕焼け）。鳥は帯 13〜22 まで上がるので、丘の稜線の
    /// 切れ目でこれらを背にする。
    var skyBackdrops: KeyValuePairs<String, UInt32> {
        switch self {
        case .morning: return ["sky": palette.sky]
        case .evening: return ["sky": palette.sky, "sunsetGlow": SceneryPalette.sunsetGlow]
        case .night:   return ["sky": palette.sky]
        }
    }
}

// MARK: - 朝の下町の家並み（#929）

public extension RunnerWorld {
    /// 家並み（`Scenery.townHouses`）の 1 軒。寸法はコースの単位（`RunnerField.Metrics`）。
    ///
    /// 純データにしてあるのは、「細長い家が無い（幅 ≥ 高さ）」「画面の高さの 1/5 以下」
    /// 「タイルの中で重ならない」を `WorldTests` が SpriteKit 抜きで固定するため
    /// （会長 QA 2026-09-15「細長い家の形が下品」）。
    struct TownHouse: Equatable, Sendable {
        /// 家並みの色。壁はクリーム（旧 0xFFF1DC）ではなく丘に近い淡いグレージュ、屋根は彩度を
        /// 落とし、どれも**背景として沈む**明度（相対輝度 0.42〜0.80）にする。手前の犬（暗い茶）
        /// はこれらのどれとも 3:1 以上（`WorldTests`）。
        public enum Palette {
            /// 壁。
            public static let wall: UInt32 = 0xEDE6DA
            /// 瓦の屋根（くすんだ赤茶。旧 0xC9624A の赤瓦は「赤い三角屋根」として浮いていた）。
            public static let roofTile: UInt32 = 0xD9A99A
            /// スレートの屋根（青灰）。
            public static let roofSlate: UInt32 = 0xB9C0CC
            /// 銅板の緑青の屋根（くすんだ薄緑）。
            public static let roofSage: UInt32 = 0xC5CBA8
            /// 窓（くすんだ水色）。
            public static let window: UInt32 = 0xA9C4D6
            /// 玄関の戸（淡い木の色）。
            public static let door: UInt32 = 0xC3AA95
        }

        /// タイル（幅 `sceneryTileWidth`）の中での左端の x。
        public let dx: Double
        /// 幅。**必ず高さ（`height`）以上**。
        public let width: Double
        /// 壁の高さ（地面から軒まで）。
        public let wallHeight: Double
        /// 屋根の高さ（軒から棟まで）。低い寄棟にするので幅の 2 割以下。
        public let roofHeight: Double
        /// 階数。窓の段数になる。
        public let floors: Int
        /// 屋根の色（`Palette` のいずれか）。
        public let roof: UInt32

        /// 地面から棟までの高さ。
        public var height: Double { wallHeight + roofHeight }
    }

    /// 1 タイルぶんの家並み。平屋（瓦）・二階建て（スレート）・平屋（緑青）の 3 軒で、
    /// 幅は全部高さ以上、いちばん高い二階建てでも 11.6（画面の高さ 115 の 1/5 = 23 の半分）。
    /// 道路の奥の帯（地面の上）に 1 段で並べ、近景の丘（高さ 19 まで）の手前に置く。
    static let townHouses: [TownHouse] = [
        TownHouse(dx: 2, width: 14, wallHeight: 5.2, roofHeight: 2.4, floors: 1, roof: TownHouse.Palette.roofTile),
        TownHouse(dx: 23, width: 13, wallHeight: 9.0, roofHeight: 2.6, floors: 2, roof: TownHouse.Palette.roofSlate),
        TownHouse(dx: 43, width: 15, wallHeight: 5.6, roofHeight: 2.6, floors: 1, roof: TownHouse.Palette.roofSage),
    ]
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
    /// 呼び出し側で番号の妥当性（`contains(stage:)`）を確かめてから使う。
    static func index(ofStage number: Int) -> Int {
        ((number - 1) % stagesPerWorld + stagesPerWorld) % stagesPerWorld + 1
    }

    /// ワールドマップの短い表記「1-1」…「3-6」。
    ///
    /// 面に付けていた名前（「商店街のあさ」等）は #946 で外した（会長指示「ステージの名前は
    /// いらない。1-1 とか 3-1 とかだけでいい」）。画面・読み上げともこの表記だけを使う。
    static func code(forStage number: Int) -> String {
        "\(world(forStage: number).number)-\(index(ofStage: number))"
    }

    /// ステージ番号（1 始まり）が 3 世界のどこかに収まるか（1…18）。
    static func contains(stage number: Int) -> Bool {
        number >= 1 && number <= stagesPerWorld * allCases.count
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
