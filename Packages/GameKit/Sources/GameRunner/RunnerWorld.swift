import Foundation

/// ステージが属する世界（#703。#627 の時間帯バリエーションはここに吸収）。
///
/// 18 面が全部同じ場所に見える——「世界（ワールド）の概念が無い」（#703 の要素分解）——
/// を、ステージ番号で固定に切り替える景色で埋める（会長決裁 2026-09-14）:
/// 1〜6 面は朝の下町、7〜12 面は夕方の川沿い、13〜18 面は夜の繁華街。
/// #1009（会長決裁 2026-09-17〜18）で 30 面に増やし、19〜24 面の里山と 25〜30 面の港町を足した
/// （どちらも現実にある場所。竜宮城のようなファンタジーはやらない）。
/// ランダムや周回で変えない（同じ面はいつ遊んでも同じ景色。撮影・QA で毎回同じ画になる）。
///
/// **変えるのは背景・地面・岩・動く障害（犬・イノシシ・鳥）の色だけ**。乗り手・自転車・台座・床・
/// アイテムの色は `RunnerPalette` の固定値のままで、当たり判定・速さ・ジャンプ（`RunnerRules`）にも
/// 触れない。SpriteKit に依存しない値型なので、境界と配色は `WorldTests` がそのまま固定できる。
/// 里山・港町（#1009）だけは今ある障害を**絵ごと**着せ替える（`dressing`。穴・岩・台座・床も別の
/// 物に見せるが、当たり判定・寸法は同じ）。
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
    /// 19〜24 面。田んぼ・竹林・農道（#1009）。昼の里なので朝の下町と同じ「淡い背景に暗い手前」の
    /// 組み立てで、空は淡い薄荷色・丘は緑の 2 階調・遠景に田んぼと竹林。今ある障害は用水路・切り株・
    /// 大きな石・カラス・田舎の犬・イノシシ・わら積み・舗装された農道に着せ替える（`dressing`）。
    case satoyama
    /// 25〜30 面。岸壁・桟橋・コンテナ・貨物船（#1009）。海辺の昼で、空は淡い空色・丘は遠い岬の青灰・
    /// 遠景に海と桟橋とコンテナと貨物船。今ある障害は岸壁の切れ目・ロープの束・ドラム缶・カモメ・
    /// 野良猫・フォークリフト・木箱の山・ベルトコンベアに着せ替える（`dressing`）。
    case harbor

    /// 1 つの世界が受け持つ面数。30 面を 5 等分。
    public static let stagesPerWorld = 6

    /// ステージ番号（1 始まり）が属する世界。1〜6 面は朝、7〜12 面は夕方、13〜18 面は夜、
    /// 19〜24 面は里山、25〜30 面は港町。
    ///
    /// 範囲外（0 以下と、最後の世界の後ろ＝ 31 以上）は `.night`——QA 用ショーケース
    /// （`RunnerStage.debugShowcase`、`number == 0`）は従来どおりの見た目で出したいのと、
    /// 面を足して世界を足し忘れたときに落ちずに描けるようにするため（どの世界にも収まらない面を
    /// 本編に入れないことは `WorldTests.everyStageHasAWorld` が固定する）。
    public static func world(forStage number: Int) -> RunnerWorld {
        guard contains(stage: number) else { return .night }
        return allCases[(number - 1) / stagesPerWorld]
    }

    /// 読み上げ・見出しに使う名前。
    public var displayName: String {
        switch self {
        case .morning: return "朝の下町"
        case .evening: return "夕方の川沿い"
        case .night:   return "夜の繁華街"
        case .satoyama: return "里山"
        case .harbor:  return "港町"
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
        /// 丘の手前に田んぼの帯（水面に苗の列）とあぜ道、近景の丘の手前に竹林（#1009）。
        case satoyama
        /// 丘の手前に海の帯と桟橋、岸壁にコンテナの山、沖に貨物船（#1009）。
        case harbor
    }

    public var scenery: Scenery {
        switch self {
        case .morning:  return .townHouses
        case .evening:  return .riverside
        case .night:    return .cityLights
        case .satoyama: return .satoyama
        case .harbor:   return .harbor
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
        /// 路肩（朝＝草、夕方＝土手の砂、夜＝歩道のコンクリート、里山＝あぜ道の草、港町＝岸壁のコンクリート）。
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
        case .satoyama:
            // 砂利の農道（#1009）。淡い土色がかった灰で、明るさは朝の路面と同じ帯に置き、暗い縁取りの
            // 手前の物が 3:1 以上で乗るようにする（`WorldTests`）。白線は轍の砂色——真っ白だと
            // 舗装に見える（白線は路面より 60 以上明るい必要があるので生成りの上限に置く）。
            // 路肩はあぜ道の草、地盤は田の土。舗装された区間は加速床（`Dressing.BoostFloor.pavedFarmRoad`）。
            return Road(asphalt: 0xC2B8A6, line: 0xFFFAF0, curb: 0xE3DCC8, shoulder: 0x9FCB8C, subsoil: 0xB89A7A)
        case .harbor:
            // 岸壁のコンクリート（#1009）。淡い灰に白線、縁石は明るいコンクリート、路肩は岸壁の
            // 側面の灰、地盤は海面下の暗い青灰（画面の下端は海の中）。
            return Road(asphalt: 0xB9BDBD, line: 0xFFFFFF, curb: 0xE2E4E2, shoulder: 0xC9CDCB, subsoil: 0x8E9AA2)
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
        case .satoyama:
            // 里山（#1009）。朝の下町と同じく**背景は淡く沈め、手前は暗く**する組み立て。空は淡い
            // 薄荷色（色相 158°。服の黄 46°・車体の赤 6° から 110° 以上離れる）、丘は朝の黄緑
            // （90° 前後）より緑に寄せた 2 階調で、遠景の田んぼの苗・竹林（`SceneryPalette`）と
            // 一緒に相対輝度 0.41〜0.80 に収める（空と 2:1 未満・`WorldTests`）。岩（大きな石）は
            // 朝と同じストーングレー——本体だけで丘・路面・田んぼ・竹林の全部と 3:1 以上。
            // 地面の色は道路化以降描かれないが、地盤（`road.subsoil`）に揃えておく。
            return Palette(
                sky: 0xD6ECE4,
                cloud: 0xFFFFFF,
                cloudAlpha: 0.9,
                hillFar: 0xB9D6B4,
                hillNear: 0xA2C79E,
                groundTop: 0xDCC8A8,
                groundBody: 0xB89A7A,
                rockLight: 0x9CA4B2,
                rockBody: 0x585E6E,
                rockDark: 0x23272F
            )
        case .harbor:
            // 港町（#1009）。空は海辺の淡い空色（色相 200°）、丘は遠くの岬の青灰 2 階調。海・桟橋・
            // コンテナ・貨物船（`SceneryPalette`）もすべて相対輝度 0.41〜0.74 の淡い帯に沈める。
            // 岩は朝と同じストーングレー（港町ではドラム缶・ロープの束に着せ替えるが、`rockDark` は
            // 岩の縁取りとしてエンドレス（朝）にも使われるので触らない）。
            return Palette(
                sky: 0xCAE3F0,
                cloud: 0xFFFFFF,
                cloudAlpha: 0.9,
                hillFar: 0xB6CFDA,
                hillNear: 0xA4C1CE,
                groundTop: 0xD2D6D4,
                groundBody: 0x8E9AA2,
                rockLight: 0x9CA4B2,
                rockBody: 0x585E6E,
                rockDark: 0x23272F
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
        /// 手前の物に共通の縁取り。`RunnerScene` が鳥・台座の床板・旗の輪郭に 0.4 単位（iPhone で
        /// 1.5pt 相当）で引き、犬・イノシシのドット絵（#975）では縁取りの文字 `K` の色になる。
        /// 岩の縁取りは `Palette.rockDark`。
        public let outline: UInt32
        /// 犬の体（主色）。ドット絵の `O`（`RunnerPixelArt.creaturePalette`）。
        public let dogBody: UInt32
        /// 犬の耳の内側と奥の脚。体より暗い（ドット絵の `o`）。
        public let dogDark: UInt32
        /// 犬の腹・胸・頬・口元・巻き尾の内側の差し色（ドット絵の `W`）。
        public let dogBelly: UInt32
        /// イノシシの体（主色）。ドット絵の `B`。
        public let boarBody: UInt32
        /// イノシシのたてがみ・奥の脚・蹄・耳。体より暗い（ドット絵の `b`）。
        public let boarDark: UInt32
        /// イノシシの鼻先（ドット絵の `S`）。
        public let boarSnout: UInt32
        /// 鳥の胴・頭（主色）。
        public let birdBody: UInt32
        /// 鳥の手前の翼・尾羽の 1 枚。胴より一段暗い。
        public let birdWing: UInt32
        /// 鳥の奥の翼・尾羽の奥の 1 枚。手前の翼よりさらに暗い（羽ばたきで 2 枚が重なっても別の翼と分かる）。
        public let birdWingFar: UInt32
        /// 鳥の腹・白目。
        public let birdBelly: UInt32
        /// 鳥の頭（胴と別に持つ・#1009）。カモメは白い頭に灰色の背、それ以外の世界は胴と同じ色。
        public let birdHead: UInt32
        /// 鳥のくちばし・畳んだ足（#1009）。カラスだけ黒に近い灰で、それ以外の世界は
        /// `RunnerPalette.birdBeak` の橙そのまま。
        public let birdBeak: UInt32
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
                birdBody: 0x1C6337, birdWing: 0x144A28, birdWingFar: 0x0C331A, birdBelly: 0xE8F5E0,
                birdHead: 0x1C6337, birdBeak: RunnerPalette.birdBeak
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
                birdBody: 0xF2EFE4, birdWing: 0xC9C4C0, birdWingFar: 0x9A9498, birdBelly: 0xFFFFFF,
                birdHead: 0xF2EFE4, birdBeak: RunnerPalette.birdBeak
            )
        case .night:
            // 夜は世界を分ける前の値（`RunnerPalette` にあった定数）そのまま——背景が暗いので
            // 明るい主色だけで 3:1 以上ある。例外はイノシシ: 旧 0x6B4226 は夜の路面（0x353A48）と
            // 1.3:1 だったので、街灯に照らされた明るめの茶 0xB08060 に上げる。
            return Creatures(
                outline: 0x0E1420,
                dogBody: 0xD9944A, dogDark: 0x5A3418, dogBelly: 0xF6E7CF,
                boarBody: 0xB08060, boarDark: 0x3E2414, boarSnout: 0xD8B098,
                birdBody: 0x4FAE71, birdWing: 0x2F7D4E, birdWingFar: 0x1F5C38, birdBelly: 0xE8F5E0,
                birdHead: 0x4FAE71, birdBeak: RunnerPalette.birdBeak
            )
        case .satoyama:
            // 里山（#1009）。背景は朝と同じ淡い帯なので手前は**暗く**。田舎の犬は黒柴のような
            // 黒に近い焦げ茶に黄土の裏白（朝の柴とは色で見分けが付く）、イノシシは朝と同じ焦げ茶、
            // 鳥はカラス——黒に近い 3 階調で、腹（＝白目にも使う）だけ青みの灰にして目が読めるようにする。
            // くちばしは炭色（橙のままだと黒い鳥がクロウタドリになる）。縁取りは暖色寄りの黒で、
            // カラスの胴（相対輝度 0.017）より暗い 0.005。
            return Creatures(
                outline: 0x14100C,
                dogBody: 0x3A2A20, dogDark: 0x1E1410, dogBelly: 0xD9B98C,
                boarBody: 0x5A3618, boarDark: 0x2E1A0C, boarSnout: 0xB88A6A,
                birdBody: 0x23232B, birdWing: 0x18181F, birdWingFar: 0x0E0E12, birdBelly: 0x7A7A88,
                birdHead: 0x23232B, birdBeak: 0x4A4A52
            )
        case .harbor:
            // 港町（#1009）。手前は暗く。野良猫は暗い灰の縞（`dogDark` が縞・`dogBelly` が胸と口元の
            // 薄灰）、フォークリフトは錆びた橙の車体（`boarBody`）に黒いタイヤ・マスト（`boarDark`）・
            // 鋼のフォーク（`boarSnout`）、鳥はカモメ——**主色は背の暗い青灰**（白い胴では淡い背景に
            // 溶けて #929 の 3:1 を満たせない）で、頭と腹を白にして海鳥に見せる。くちばしは橙のまま。
            return Creatures(
                outline: 0x101418,
                dogBody: 0x3E3A46, dogDark: 0x221E28, dogBelly: 0xC9C4CC,
                boarBody: 0x86320A, boarDark: 0x2A2530, boarSnout: 0x9AA0AA,
                birdBody: 0x3E4A56, birdWing: 0x2C3640, birdWingFar: 0x1C232B, birdBelly: 0xF4F4F0,
                birdHead: 0xF4F4F0, birdBeak: RunnerPalette.birdBeak
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

        // 里山（`Scenery.satoyama`・#1009）。どれも空（0xD6ECE4）と 2:1 未満に沈める淡い色。
        /// 田んぼの水面。空を映した淡い青緑で、丘より明るい（走者の下半身はこの帯を背にする）。
        public static let paddyWater: UInt32 = 0xC4DDDA
        /// 田んぼの苗の列。水面より一段濃い緑の細い縦線。
        public static let paddySeedling: UInt32 = 0x93BB80
        /// あぜ道（田んぼの手前の土手）。路面と同系の淡い土色。
        public static let fieldPath: UInt32 = 0xD2C2A0
        /// 竹の幹。近景の丘（0xA2C79E）よりわずかに明るい黄緑で、丘の上に立っていると読める。
        public static let bambooStalk: UInt32 = 0xA8CC90
        /// 竹の節と葉。幹より濃い緑（背景の中でいちばん暗い 0x8FB87E でも空と 1.8:1）。
        public static let bambooLeaf: UInt32 = 0x8FB87E

        // 港町（`Scenery.harbor`・#1009）。どれも空（0xCAE3F0）と 2:1 未満に沈める淡い色。
        /// 海面。丘の岬より少し濃い青灰。
        public static let seaWater: UInt32 = 0x9FC0D4
        /// 波の照り返し（細い帯）。
        public static let seaGlint: UInt32 = 0xE4F0F6
        /// 桟橋の板。
        public static let pierPlank: UInt32 = 0xC9B594
        /// 桟橋の杭。板より一段暗い（空と 1.8:1 に留める）。
        public static let pierPost: UInt32 = 0xB8A78C
        /// コンテナ 3 色（錆色・青灰・くすんだ緑）。どれも彩度を落とした淡い色で、手前の犬（猫）の
        /// 暗い灰・フォークリフトの錆橙とは 3:1 以上離れる。
        public static let containerRust: UInt32 = 0xD4A08E
        public static let containerBlue: UInt32 = 0x9FB9CC
        public static let containerGreen: UInt32 = 0xA9C5A6
        /// コンテナの波板の筋。暗い線で刻むと空と 2:1 を超えるので、明るい筋で刻む。
        public static let containerRib: UInt32 = 0xE8ECEA
        /// 貨物船の船体（青灰）と喫水線の錆色、船橋（白っぽい灰）、煙突。
        public static let shipHull: UInt32 = 0xA3AFBC
        public static let shipWaterline: UInt32 = 0xD0A094
        public static let shipBridge: UInt32 = 0xD8D3C8
        public static let shipFunnel: UInt32 = 0xC9A79A
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
        case .satoyama:
            return [
                "hillFar": palette.hillFar, "hillNear": palette.hillNear, "asphalt": road.asphalt,
                "paddyWater": SceneryPalette.paddyWater,
                "paddySeedling": SceneryPalette.paddySeedling,
                "fieldPath": SceneryPalette.fieldPath,
                "bambooStalk": SceneryPalette.bambooStalk,
                "bambooLeaf": SceneryPalette.bambooLeaf,
            ]
        case .harbor:
            return [
                "hillFar": palette.hillFar, "hillNear": palette.hillNear, "asphalt": road.asphalt,
                "seaWater": SceneryPalette.seaWater,
                "seaGlint": SceneryPalette.seaGlint,
                "pierPlank": SceneryPalette.pierPlank,
                "pierPost": SceneryPalette.pierPost,
                "containerRust": SceneryPalette.containerRust,
                "containerBlue": SceneryPalette.containerBlue,
                "containerGreen": SceneryPalette.containerGreen,
                "containerRib": SceneryPalette.containerRib,
                "shipHull": SceneryPalette.shipHull,
                "shipWaterline": SceneryPalette.shipWaterline,
                "shipBridge": SceneryPalette.shipBridge,
                "shipFunnel": SceneryPalette.shipFunnel,
            ]
        }
    }

    /// 空と、丘の後ろに敷く帯（夕方の夕焼け）。鳥は帯 13〜22 まで上がるので、丘の稜線の
    /// 切れ目でこれらを背にする。
    var skyBackdrops: KeyValuePairs<String, UInt32> {
        switch self {
        case .morning:  return ["sky": palette.sky]
        case .evening:  return ["sky": palette.sky, "sunsetGlow": SceneryPalette.sunsetGlow]
        case .night:    return ["sky": palette.sky]
        case .satoyama: return ["sky": palette.sky]
        case .harbor:   return ["sky": palette.sky]
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

    /// この世界が受け持つステージ番号（1 始まり）の範囲。朝 1…6・夕方 7…12・夜 13…18・里山 19…24・港町 25…30。
    var stageRange: ClosedRange<Int> {
        let first = (number - 1) * RunnerWorld.stagesPerWorld + 1
        return first...(first + RunnerWorld.stagesPerWorld - 1)
    }

    /// 世界の中での面の位置（1 始まり）。ワールドマップの「1-1」の右側。
    ///
    /// 範囲外（0 以下・31 以上）でも落ちないよう剰余で畳むだけなので、
    /// 呼び出し側で番号の妥当性（`contains(stage:)`）を確かめてから使う。
    static func index(ofStage number: Int) -> Int {
        ((number - 1) % stagesPerWorld + stagesPerWorld) % stagesPerWorld + 1
    }

    /// ワールドマップの短い表記「1-1」…「5-6」。
    ///
    /// 面に付けていた名前（「商店街のあさ」等）は #946 で外した（会長指示「ステージの名前は
    /// いらない。1-1 とか 3-1 とかだけでいい」）。画面・読み上げともこの表記だけを使う。
    static func code(forStage number: Int) -> String {
        "\(world(forStage: number).number)-\(index(ofStage: number))"
    }

    /// ステージ番号（1 始まり）がどれかの世界に収まるか（1…30）。
    static func contains(stage number: Int) -> Bool {
        number >= 1 && number <= stagesPerWorld * allCases.count
    }

    /// ワールドマップで世界を塗り分ける色（`0xRRGGBB`）。
    ///
    /// 夜以外は空の色（`palette.sky`）そのまま。夜だけは空（0x2E4066）がダークモードの
    /// カード面（`Theme.surface` の暗色）に溶けて見えないので、同じ青紫の系統で明るめの値にする。
    /// **文字はこの色の上に載せない**（薄い色味の面・上端の帯・見出しの丸にだけ使う）ので、
    /// 文字とのコントラストは `Theme` の面と文字の組み合わせがそのまま効く。
    var mapColor: UInt32 {
        switch self {
        case .morning:  return palette.sky
        case .evening:  return palette.sky
        case .night:    return 0x6B7FC2
        // 里山・港町（#1009）の空はどちらも朝と同じ淡い帯（0xD6ECE4 / 0xCAE3F0）で、並べると
        // 3 つが同じ色に見える。空ではなく世界の主役の色——里山は田の緑、港町は海の青——で塗る
        // （`RunnerStageCodeTests.mapColorsAreDistinguishable` が隣り合う世界と色相か明度で離れていることを固定）。
        case .satoyama: return 0x8FC48A
        case .harbor:   return 0x6FB1CF
        }
    }
}

// MARK: - 今ある障害の着せ替え（#1009）

public extension RunnerWorld {
    /// 今ある障害を世界ごとに着せ替える指定（#1009・会長決裁 2026-09-17〜18）。
    ///
    /// **動き・当たり判定・寸法は変えず、絵だけ替える**。`RunnerScene` はここを見て描く部品を
    /// 選ぶだけで、`RunnerHazardKind` / `RunnerField` / `RunnerRules` は世界を知らない。
    /// 朝・夕方・夜（1〜18 面）は全部が元の絵（`.construction` / `.boulder` / `.dog` / `.boar` /
    /// `.scaffold` / `.boostBand`）で、**そちらの描画経路は変えていない**（`WorldTests.dressings` が固定）。
    /// たこ焼きはどの世界でも着せ替えない。
    struct Dressing: Equatable, Sendable {
        /// 穴。
        public enum Pit: Equatable, Sendable {
            /// 工事の切れ目（黄黒の柵・奈落）。
            case construction
            /// 用水路（コンクリートの壁・深い水）。
            case irrigationDitch
            /// 岸壁の切れ目（黒いゴムの防舷材・海）。
            case quayGap
        }
        /// 低い岩・高い岩。
        public enum Block: Equatable, Sendable {
            /// 岩塊（`RunnerScene.makeRock`）。
            case boulder
            /// 切り株（低い岩の 4×5 に収まるドット絵）。
            case stump
            /// ロープの束（低い岩）。
            case ropeCoil
            /// ドラム缶（高い岩の 4×9）。
            case drum
        }
        /// 犬の枠（画面の右から歩いて来る動物）。
        public enum Walker: Equatable, Sendable {
            /// 犬（田舎の犬は同じ絵の色違い・`Creatures`）。
            case dog
            /// 野良猫。
            case cat
        }
        /// イノシシの枠（右から向かってくるもの）。
        public enum Charger: Equatable, Sendable {
            case boar
            /// フォークリフト。
            case forklift
        }
        /// 台座。
        public enum Platform: Equatable, Sendable {
            /// 工事の足場（`RunnerScene.makePlatform`）。
            case scaffold
            /// わら積み。
            case strawStack
            /// 木箱の山。
            case crateStack
        }
        /// 下から突き上げる障害（#1010）。**動き・当たり判定・寸法は 1 つ**で、絵だけを替える。
        public enum Shoot: Equatable, Sendable {
            /// 竹の子（里山）。土が盛り上がる予告 → 竹の子がにょきっと伸びる。
            case bambooShoot
            /// 波しぶき（港町）。岸壁の縁に泡が立つ予告 → 水柱が上がる。
            case seaSpray
        }
        /// 加速床。
        public enum BoostFloor: Equatable, Sendable {
            /// 青い加速帯（`RunnerScene.makeBoostFloor`）。
            case boostBand
            /// 舗装された農道（砂利道の中の黒いアスファルト）。
            case pavedFarmRoad
            /// ベルトコンベア。
            case conveyor
        }

        public let pit: Pit
        public let lowBlock: Block
        public let tallBlock: Block
        public let dog: Walker
        public let boar: Charger
        public let platform: Platform
        public let boostFloor: BoostFloor
        public let shoot: Shoot

        /// 岩の枠の着せ替え。岩でない種類は nil。
        public func block(for kind: RunnerHazardKind) -> Block? {
            switch kind {
            case .lowBlock:                        return lowBlock
            case .tallBlock:                       return tallBlock
            // 突き上げ（#1010）は岩の枠ではなく自分の着せ替え（`shoot`）を持つ。
            case .pit, .bird, .dog, .boar, .shoot: return nil
            }
        }
    }

    /// 元の絵。1〜18 面はこれ（#1009 より前と同じ）。
    ///
    /// 突き上げ（#1010）は 19 面以降にしか置かないので、ここの `shoot` が本編で使われることは
    /// 無い。竹の子にしてあるのは **QA 用ショーケース**（`RunnerStage.debugShowcase` は
    /// `number == 0` なので夜の世界で走る）で撮れるようにするため。
    static let originalDressing = Dressing(
        pit: .construction, lowBlock: .boulder, tallBlock: .boulder, dog: .dog, boar: .boar,
        platform: .scaffold, boostFloor: .boostBand, shoot: .bambooShoot
    )

    var dressing: Dressing {
        switch self {
        case .morning, .evening, .night:
            return RunnerWorld.originalDressing
        case .satoyama:
            // 穴＝用水路・低い岩＝切り株・高い岩＝大きな石（岩塊のまま）・犬＝田舎の犬（色違い）・
            // イノシシ＝イノシシ・台座＝わら積み・加速床＝舗装された農道・突き上げ＝竹の子（#1010）。
            return Dressing(
                pit: .irrigationDitch, lowBlock: .stump, tallBlock: .boulder, dog: .dog, boar: .boar,
                platform: .strawStack, boostFloor: .pavedFarmRoad, shoot: .bambooShoot
            )
        case .harbor:
            // 穴＝岸壁の切れ目・低い岩＝ロープの束・高い岩＝ドラム缶・犬＝野良猫・イノシシ＝
            // フォークリフト・台座＝木箱の山・加速床＝ベルトコンベア・突き上げ＝波しぶき（#1010）。
            return Dressing(
                pit: .quayGap, lowBlock: .ropeCoil, tallBlock: .drum, dog: .cat, boar: .forklift,
                platform: .crateStack, boostFloor: .conveyor, shoot: .seaSpray
            )
        }
    }

    /// 着せ替えのうち図形で組む部品（穴・台座・加速床）の色。値は `0xRRGGBB`。ドット絵の部品
    /// （切り株・ロープ・ドラム缶・猫・フォークリフト）の色は `RunnerPixelArt` のパレットにある。
    /// どれも手前の物なので、主色か縁取り（`outline`）が背景の全部と 3:1 以上（`WorldTests`）。
    enum DressingPalette {
        // 用水路（`Dressing.Pit.irrigationDitch`）
        /// 用水路の深い水。路面（0xC2B8A6）と 3:1 以上で「穴」だと分かる暗さ。
        public static let ditchWater: UInt32 = 0x285E78
        /// 用水路の水面の帯（明るい）。深い水との段差で水面の位置が読める。
        public static let ditchSurface: UInt32 = 0x7DB4CC
        /// 用水路のコンクリートの壁。路面より明るい灰で、切れ目の縁を立てる。
        public static let ditchWall: UInt32 = 0xD9D6CC
        /// 水面の照り返し（用水路・岸壁の切れ目で共通の細い明るい線）。
        public static let waterGlint: UInt32 = 0xE4F0F6
        // 岸壁の切れ目（`Dressing.Pit.quayGap`）
        /// 岸壁の切れ目の海（深い）。
        public static let gapSea: UInt32 = 0x24507A
        /// 岸壁の切れ目の海面の帯。
        public static let gapSurface: UInt32 = 0x6FA3C6
        /// 岸壁に吊るした黒いゴムの防舷材（タイヤ）。
        public static let fender: UInt32 = 0x1C1E24
        // わら積み（`Dressing.Platform.strawStack`）
        /// わらの本体。
        public static let strawBody: UInt32 = 0xD9B45C
        /// わらの筋（暗い）。
        public static let strawShade: UInt32 = 0xA8863A
        /// わら積みの上面（歩く面。いちばん明るい——台座の床板と同じ約束）。
        public static let strawTop: UInt32 = 0xEACB7A
        /// わらを縛る縄。
        public static let strawRope: UInt32 = 0x6E4A22
        // 木箱の山（`Dressing.Platform.crateStack`）
        /// 木箱の板。
        public static let crateWood: UInt32 = 0xC89A5E
        /// 木箱の板の継ぎ目と箱の縁（暗い）。
        public static let crateLine: UInt32 = 0x5A3A1A
        /// 木箱の山の上面（歩く面。いちばん明るい）。
        public static let crateTop: UInt32 = 0xE0BC84
        // 舗装された農道（`Dressing.BoostFloor.pavedFarmRoad`）
        /// 舗装のアスファルト。砂利道（0xC2B8A6）と 3:1 以上の黒に近い灰。
        public static let pavedAsphalt: UInt32 = 0x585C64
        /// 舗装の縁（暗い）。
        public static let pavedEdge: UInt32 = 0x2A2C30
        /// 舗装の上の白い矢印。
        public static let pavedArrow: UInt32 = 0xFFFFFF
        // ベルトコンベア（`Dressing.BoostFloor.conveyor`）
        /// ベルトのゴム。岸壁（0xB9BDBD）と 3:1 以上。
        public static let conveyorBelt: UInt32 = 0x2A2E36
        /// コンベアの枠（鋼）。
        public static let conveyorFrame: UInt32 = 0x8A9098
        /// ローラー（枠より明るい鋼）。
        public static let conveyorRoller: UInt32 = 0xB8BEC6
        /// ベルトの上の矢印（青い加速帯と同じ黄）。
        public static let conveyorArrow: UInt32 = RunnerPalette.boostFloorArrow
    }
}
