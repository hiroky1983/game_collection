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
    /// 31〜36 面。京都・奈良（古都・#1824。会長決裁 2026-10-06「もっと日本を横断してる感じを
    /// 出してから」海外へ）。秋の古都で、空は淡い藤色、山は紅葉の 2 階調、道は石畳。遠景に土塀・
    /// 鳥居・寺の本堂と石段・五重塔・紅葉の木。犬の枠は奈良の鹿（絵ごと着せ替え）、鳥は鳩、
    /// それ以外の障害は里山の着せ替え（用水路＝疎水・竹の子・田んぼ・古い木橋・石垣）を流用する。
    case kyotoNara
    /// 37〜42 面。温泉街（#1938）。初冬の山あいの湯の町。空は湯けむりに霞む淡い灰青、山は雪をかぶった
    /// 青灰の 2 階調、道は濡れた石畳で路肩に湯の川。遠景に旅館・外湯（のれん・提灯）・源泉の櫓・湯けむり。
    /// 犬の枠はニホンザル（絵ごと着せ替え）、鳥はトンビ、突き上げは湯柱（波しぶきを流用）、沈む床は泥湯。
    case onsen
    /// 43〜48 面。雪国（#2729・会長決裁 2026-10-23）。温泉街から北へ峠を越えた、雪に埋もれた町。空は淡い灰青
    /// （温泉街より少し白く）、丘は白の 2 階調、道は圧雪の灰白で路肩は雪、地盤は凍った土。遠景にかまくら・
    /// 雪をかぶった瓦屋根・枯れ木・道の奥の雪の壁、遠くだけに雪がちらつく（手前は隠さない）。
    /// 新しい仕掛けは**二段ジャンプでしか渡れない広い裂け目**（`RunnerHazardKind.chasm`・割れた氷の湖）。
    /// 犬の枠はキタキツネ（絵ごと着せ替え）、鳥はシロフクロウ、低い岩は雪だるま、台座は雪のブロック、
    /// 加速床はアイスバーン、突き上げは地吹雪の雪柱、沈む床は新雪、崩れる足場は薄氷の橋、高い塀は除雪の雪山。
    case snow
    /// 49〜54 面。東京（#2729・会長決裁 2026-10-23）。雪国から列車で着いた、夕暮れの東京。夜の繁華街（13〜18 面・紺の空）
    /// と被らないよう**宵の口の藤色の空に茜の地平線**で（会長 2026-10-24「東京は色を付けたほうが良さそう」）、ビル街は
    /// 青紫の 2 階調に黄色い窓の灯り、ネオン看板（桃・水色・黄）、道は暮れたアスファルト。遠景に遠くの高い塔のシルエット
    /// （赤く灯る鉄塔と針の塔。文言に実在の建物名は出さない）と航空灯・高架を流れる電車・信号機。
    /// 新しい仕掛けは**二段ジャンプでしか乗れない高い台座**（`RunnerRules.highPlatformHeight`・歩道橋）。
    /// 犬の枠は犬（秋田犬の色）、鳥は都会のハト、低い岩はカラーコーン、高い岩は自動販売機、イノシシの枠は黄色いタクシー、
    /// 台座は工事の足場（元の絵）、加速床は動く歩道、突き上げはマンホールの蒸気、沈む床は雨上がりの水たまり、
    /// 崩れる足場は古い歩道橋の板、高い塀は積まれたネオン看板。背景が暗いので手前は**明るく**する（夜と同じ組み立て）。
    case tokyo
    /// 55〜60 面。富士山（#2729・会長決裁 2026-10-23。設計書の元案「地獄」から差し替え）。東京のビル風に飛ばされた宝くじを追って
    /// 五合目から山頂へ登る、夜明け前の登山道。空は**暁の薄紅藤**（地平線に御来光の茜の帯と、昇りかけの朝日）、丘は火山の
    /// 斜面の淡い赤紫の 2 階調、道は火山礫の登山道。遠景に雲海・山小屋（石積みの壁）・登山道のロープ柵・ハイマツ・
    /// 山頂の鳥居。背景は淡いので手前は**暗く**して縁取りで締める（朝・雪国と同じ組み立て）。
    /// 新しい仕掛けは**斜面の上から転がってくる落石**（`RunnerHazardKind.rockfall`）。
    /// 犬の枠はニホンカモシカ、鳥はホシガラス、高い岩は道標、イノシシの枠は山小屋の荷を運ぶブルドーザー、
    /// 台座は石積み、加速床は砂走り、突き上げは砂煙、沈む床は火山礫のザレ場、穴と裂け目は火山岩の割れ目、
    /// 高い塀は溶岩の石垣（低い岩は火山岩＝岩塊のまま・崩れる足場は古い吊り橋のまま）。60 面で物語が完結する
    /// （山頂で初日の出・「…300円や」）。
    case fuji

    /// 1 つの世界が受け持つ面数。6 面ずつ（30 面 = 5 世界、#1824 で 36 面 = 6 世界、#1938 で 42 面 = 7 世界、
    /// #2729 で 48 面 = 8 世界 → 54 面 = 9 世界 → 60 面 = 10 世界）。
    public static let stagesPerWorld = 6

    /// ステージ番号（1 始まり）が属する世界。1〜6 面は朝、7〜12 面は夕方、13〜18 面は夜、
    /// 19〜24 面は里山、25〜30 面は港町、31〜36 面は京都・奈良、37〜42 面は温泉街、43〜48 面は雪国、49〜54 面は東京、
    /// 55〜60 面は富士山。
    ///
    /// 範囲外（0 以下と、最後の世界の後ろ＝ 61 以上）は `.night`。面を足して世界を足し忘れた
    /// ときに落ちずに描けるようにするため（どの世界にも収まらない面を本編に入れないことは
    /// `WorldTests.everyStageHasAWorld` が固定する）。
    ///
    /// **QA 用ショーケース（`RunnerStage.debugShowcase`・`number == 0`）はここを通らない**
    /// ——`RunnerScene.rebuildCourse` が 0 番を朝の下町へ倒す（#1010 で CodeRabbit が指摘）。
    public static func world(forStage number: Int) -> RunnerWorld {
        guard contains(stage: number) else { return .night }
        return allCases[(number - 1) / stagesPerWorld]
    }

    /// 読み上げ・見出しに使う名前。
    public var displayName: String {
        switch self {
        case .morning: return tr("朝の下町")
        case .evening: return tr("夕方の川沿い")
        case .night:   return tr("夜の繁華街")
        case .satoyama: return tr("里山")
        case .harbor:  return tr("港町")
        case .kyotoNara: return tr("京都・奈良")
        case .onsen: return tr("温泉街")
        case .snow: return tr("雪国")
        case .tokyo: return tr("東京")
        case .fuji: return tr("富士山")
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
        /// 道の奥に土塀、その後ろに鳥居・寺の本堂と石段・五重塔・紅葉の木（#1824）。
        case kyotoNara
        /// 道の奥に提灯の並ぶ柵、その後ろに旅館・外湯・源泉の櫓・湯けむり、山には雪（#1938）。
        case onsen
        /// 道の奥に雪の壁、その後ろにかまくら・雪をかぶった瓦屋根の家・枯れ木、遠くだけに雪がちらつく（#2729）。
        case snow
        /// 丘の代わりにビル街の 2 階調（窓の灯り・ネオン）、遠くに高い塔のシルエットと航空灯、道の奥に高架を流れる電車と信号機、
        /// 地平線に茜の帯（#2729）。
        case tokyo
        /// 丘は火山の斜面、その手前に雲海・山小屋・登山道のロープ柵・ハイマツ・山頂の鳥居、地平線に御来光の帯と朝日（#2729）。
        case fuji
    }

    public var scenery: Scenery {
        switch self {
        case .morning:  return .townHouses
        case .evening:  return .riverside
        case .night:    return .cityLights
        case .satoyama: return .satoyama
        case .harbor:   return .harbor
        case .kyotoNara: return .kyotoNara
        case .onsen: return .onsen
        case .snow: return .snow
        case .tokyo: return .tokyo
        case .fuji: return .fuji
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
        case .kyotoNara:
            // 石畳（#1824）。暖色寄りの石の灰で、明るさは朝・里山・港町の路面と同じ帯（相対輝度 0.45）。
            // 破線は石畳の明るい目地として読ませる生成り（路面より 60 以上明るい・`WorldTests`）。
            // 縁石は明るい石、路肩は苔の緑、地盤は土。
            return Road(asphalt: 0xB7B3AC, line: 0xF6F3EE, curb: 0xDAD5CC, shoulder: 0xA3B894, subsoil: 0xB39C84)
        case .onsen:
            // 濡れた石畳（#1938）。寒色の石の灰で明るさは京都と同じ帯。目地は雪まじりの白、縁石は雪、
            // 路肩は湯の川（淡い湯色の青緑）、地盤は濡れた暗い石。
            return Road(asphalt: 0xB3B7BE, line: 0xF4F6F8, curb: 0xE4E8EC, shoulder: 0x9ED0CB, subsoil: 0x7A838C)
        case .snow:
            // 圧雪の路面（#2729）。砂利の混じった圧雪の灰白で、明るさは朝・里山・港町の路面より一段明るい帯
            // （相対輝度 0.52。白線は路面より 60 以上明るい必要があるので、路面はこれが上限）。暗い縁取りの
            // 手前の物が 3:1 以上で乗る明るさは保つ（`WorldTests`）。縁石は雪、路肩は積もった雪、地盤は凍った土。
            return Road(asphalt: 0xB9BFC6, line: 0xFFFFFF, curb: 0xE6EBEF, shoulder: 0xF0F4F7, subsoil: 0x7E8690)
        case .tokyo:
            // 暮れた都心のアスファルト（#2729）。夜の繁華街（0x353A48）より少し青紫に寄せた暗い灰で、白線は街灯の下の
            // 明るさ、縁石は歩道の縁、路肩は歩道のタイル、地盤は地下の暗い紫灰。背景が暗いので手前の明るい物が 3:1 以上で
            // 乗る（`WorldTests`）。
            return Road(asphalt: 0x3C3E4E, line: 0xD9DCE6, curb: 0x8A8FA0, shoulder: 0x4E5268, subsoil: 0x262838)
        case .fuji:
            // 火山礫の登山道（#2729）。赤みを帯びた淡い灰（相対輝度 0.47。朝・里山の路面と同じ帯）で、暗い手前の物が
            // 3:1 以上で乗る。白線は登山道の縁の白い目印（路面より 60 以上明るい・`WorldTests`）、縁石は明るい火山岩、
            // 路肩は崩れたザレの斜面、地盤は黒い溶岩。
            return Road(asphalt: 0xC9B4AC, line: 0xFFF8F2, curb: 0xE6D8D0, shoulder: 0xB8A39E, subsoil: 0x8A6E68)
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
        case .kyotoNara:
            // 京都・奈良（#1824）。秋の古都。背景は淡く沈める組み立て（朝・里山・港町と同じ）で、
            // 空は淡い藤色（色相 263°。服の黄 45°・車体の赤 6° から 40° 以上離れる唯一の淡い寒色側で、
            // 青系の朝・港町、薄荷の里山とも見分けが付く）。山は紅葉の 2 階調（淡い杏と淡いテラコッタ）。
            // 遠景の鳥居・寺・五重塔・土塀・紅葉（`SceneryPalette`）と一緒に空と 2:1 未満に収める
            // （`WorldTests`）。岩（庭石）は朝と同じストーングレー——本体だけで紅葉の山 2 色と 3:1 以上。
            // 地面の色は道路化以降描かれないが、地盤（`road.subsoil`）に揃えておく。
            return Palette(
                sky: 0xE6DFF1,
                cloud: 0xFFFFFF,
                cloudAlpha: 0.9,
                hillFar: 0xE2C4A9,
                hillNear: 0xDBAE94,
                groundTop: 0xD9D2C8,
                groundBody: 0xB39C84,
                rockLight: 0x9CA4B2,
                rockBody: 0x585E6E,
                rockDark: 0x23272F
            )
        case .onsen:
            // 温泉街（#1938）。初冬。空は湯けむりに霞む淡い灰青（色相 214°）、山は雪をかぶった青灰の 2 階調。
            // 岩（湯けむりの岩）は朝と同じストーングレー。
            return Palette(
                sky: 0xDAE0E8,
                cloud: 0xFFFFFF,
                cloudAlpha: 0.9,
                hillFar: 0xC3CDD4,
                hillNear: 0xADBBC4,
                groundTop: 0xC9CDD2,
                groundBody: 0x7A838C,
                rockLight: 0x9CA4B2,
                rockBody: 0x585E6E,
                rockDark: 0x23272F
            )
        case .snow:
            // 雪国（#2729）。真冬。空は温泉街より少し白い淡い灰青（色相 210°。服の黄・車体の赤から 150° 以上
            // 離れる）、丘は雪の 2 階調（白と淡い青白）。背景はどれも白に近い帯（相対輝度 0.45〜0.88）で、
            // 手前は**暗く**して縁取りで締める（朝・里山と同じ組み立て。`WorldTests` が 3:1 を固定）。
            // 岩（雪をかぶった岩）は朝と同じストーングレーの本体に、頂の面だけ雪の白（`rockLight`）。
            return Palette(
                sky: 0xE3E9EF,
                cloud: 0xFFFFFF,
                cloudAlpha: 0.9,
                hillFar: 0xEEF2F5,
                hillNear: 0xDCE4EA,
                groundTop: 0xE6EAEE,
                groundBody: 0x7E8690,
                rockLight: 0xF3F5F7,
                rockBody: 0x585E6E,
                rockDark: 0x23272F
            )
        case .tokyo:
            // 東京（#2729）。宵の口。空は藤色（色相 253°。服の黄 46°・車体の赤 6° から 110° 以上離れ、夜の繁華街の紺
            // 0x2E4066 より明るく紫に寄る）で、地平線に茜の帯（`SceneryPalette.duskGlow`・`RunnerScene.buildBackdrop`）。
            // 丘の 2 階調は**遠くのビル街**の青紫で、遠景（`RunnerScene.addTokyo`）がその上に四角いビルの影を重ねて稜線を
            // 隠す。背景は相対輝度 0.03〜0.17 の暗い帯に沈め（空と 2:1 未満）、手前は夜と同じく**明るく**する
            // （`WorldTests` が 3:1 を固定）。雲は夕焼けの桃色で薄く。岩の色は夜より明るい灰（赤く灯る鉄塔とも 3:1）。
            return Palette(
                sky: 0x5A4E8C,
                cloud: 0xE8C2CC,
                cloudAlpha: 0.6,
                hillFar: 0x3F3F6E,
                hillNear: 0x2F3058,
                groundTop: 0x4E5268,
                groundBody: 0x262838,
                rockLight: 0xF4F6FA,
                rockBody: 0xE2E6EE,
                rockDark: 0x565D6B
            )
        case .fuji:
            // 富士山（#2729）。夜明け前〜御来光。空は暁の薄紅藤（色相 311°。服の黄 45°・車体の赤 5° から 50° 以上離れ、
            // 京都・奈良の藤色 263°・東京の宵の藤色 253° より紅に寄る）で、地平線に御来光の茜の帯と昇りかけの朝日
            // （`SceneryPalette.sunriseGlow` / `sun`・`RunnerScene.buildBackdrop`）。丘は**火山の斜面**の淡い赤紫の 2 階調。
            // 背景は相対輝度 0.47〜0.85 の淡い帯に沈め（空と 2:1 未満）、手前は**暗く**して縁取りで締める（朝・雪国と同じ
            // 組み立て。`WorldTests` が 3:1 を固定）。岩（火山岩）は赤みの黒褐色で、落石（`RunnerHazardKind.rockfall`）も
            // この 3 階調で描く（`RunnerPixelArt.fallingRock`）。
            return Palette(
                sky: 0xECD6E8,
                cloud: 0xFFFFFF,
                cloudAlpha: 0.9,
                hillFar: 0xDCCAD6,
                hillNear: 0xCDB8C2,
                groundTop: 0xC9B4AC,
                groundBody: 0x8A6E68,
                rockLight: 0x9A847E,
                rockBody: 0x5E4844,
                rockDark: 0x1E1414
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
        case .kyotoNara:
            // 京都・奈良（#1824）。背景は淡い帯なので手前は**暗く**。犬の枠は奈良の鹿——焦げ茶の体
            // （`dogBody`）に暗い脚・耳の内・枝角（`dogDark`）、生成りの斑点・腹・尻の白（`dogBelly`）。
            // イノシシは朝・里山と同じ焦げ茶。鳥は寺の鳩——青みの暗い灰 3 階調に明るい灰の腹。
            // 紅葉の山（色相 20° 前後）とは色相で 160° 以上離れる。縁取りは暖色寄りの黒。
            return Creatures(
                outline: 0x1A1410,
                dogBody: 0x6E4423, dogDark: 0x3B2412, dogBelly: 0xF2E4CC,
                boarBody: 0x5A3618, boarDark: 0x2E1A0C, boarSnout: 0xB88A6A,
                birdBody: 0x4C5466, birdWing: 0x363C4A, birdWingFar: 0x242832, birdBelly: 0xD9DAE2,
                birdHead: 0x4C5466, birdBeak: RunnerPalette.birdBeak
            )
        case .onsen:
            // 温泉街（#1938）。手前は暗く。犬の枠はニホンザル——灰茶の毛（`dogBody`）に暗い手足・耳（`dogDark`）、
            // 顔まわりと腹の薄い毛（`dogBelly`）、顔の赤は犬の首輪の赤 `R` を流用。鳥はトンビ（焦げ茶 3 階調に
            // 淡い腹）。イノシシは朝・里山と同じ焦げ茶。
            return Creatures(
                outline: 0x1A1410,
                dogBody: 0x5A4737, dogDark: 0x30241B, dogBelly: 0xDCCDB8,
                boarBody: 0x5A3618, boarDark: 0x2E1A0C, boarSnout: 0xB88A6A,
                birdBody: 0x5A4030, birdWing: 0x3E2A1E, birdWingFar: 0x2A1C12, birdBelly: 0xC9A882,
                birdHead: 0x5A4030, birdBeak: RunnerPalette.birdBeak
            )
        case .snow:
            // 雪国（#2729）。背景が白に近いので手前は**いちばん暗く**する。犬の枠はキタキツネ——
            // 濃い赤錆の毛（`dogBody`。白い背景のどれとも 3:1 以上にするには朝の柴より暗い赤茶が上限）に
            // 黒い脚・耳の先・鼻（`dogDark`）、胸・腹・尾の先の白（`dogBelly`）。イノシシは雪まみれの
            // 灰茶（`boarBody`）に薄い鼻先。鳥はシロフクロウ——**主色は暗い灰**（白い胴では白い背景に溶ける。
            // 港町のカモメと同じ理由）で、頭と腹を白にして白い鳥に見せる。くちばしは炭色（フクロウは黒いくちばし）。
            return Creatures(
                outline: 0x14181C,
                dogBody: 0x944218, dogDark: 0x2A1C14, dogBelly: 0xF4EFE6,
                boarBody: 0x5A4A3E, boarDark: 0x2E2219, boarSnout: 0xC9BEB4,
                birdBody: 0x4A5058, birdWing: 0x34393F, birdWingFar: 0x22262A, birdBelly: 0xF4F4F0,
                birdHead: 0xF4F4F0, birdBeak: 0x4A4A52
            )
        case .tokyo:
            // 東京（#2729）。背景は宵の暗い帯（相対輝度 0.17 以下）なので手前は**明るく**（夜・夕方と同じ向き。
            // 主色の相対輝度 0.61 以上で背景の全部と 3:1）。犬の枠は犬——秋田犬のクリーム（`dogBody`。夕方の柴と同じ
            // 明るい側）に濃い茶の耳と脚（`dogDark`）、白い胸と腹（`dogBelly`）。イノシシの枠はタクシー——**黄色い車体**
            // （`boarBody`。ハブの世界の色と同じ黄）に黒いタイヤ（`boarDark`）、銀の窓とバンパー（`boarSnout`）。
            // 鳥は都会のハト——明るい灰 3 階調に白い腹（京都の鳩の暗い灰とは逆向き）。縁取りは青みの黒。
            return Creatures(
                outline: 0x14161C,
                dogBody: 0xF3D9A6, dogDark: 0x6E4A2A, dogBelly: 0xFFF8EC,
                boarBody: 0xFFD24A, boarDark: 0x1A1C24, boarSnout: 0xD8DCE4,
                birdBody: 0xD4D6DE, birdWing: 0xA6A9B6, birdWingFar: 0x7A7D8A, birdBelly: 0xF2F2F6,
                birdHead: 0xD4D6DE, birdBeak: RunnerPalette.birdBeak
            )
        case .fuji:
            // 富士山（#2729）。背景は淡い帯（相対輝度 0.47 以上）なので手前は**暗く**（朝・雪国と同じ向き）。犬の枠は
            // ニホンカモシカ——暗い灰褐色の毛（`dogBody`）に黒い角・脚（`dogDark`）、喉と頬の白い毛（`dogBelly`）。
            // イノシシの枠は山小屋へ荷を運ぶブルドーザー——**錆びた橙の車体**（`boarBody`。暗い側に振った橙で、淡い背景の
            // 全部と 3:1）に黒い履帯（`boarDark`）、鋼の排土板とローラー（`boarSnout`）。鳥はホシガラス——焦げ茶の 3 階調に
            // 白い星の斑（腹 `birdBelly`）、くちばしは炭色。縁取りは赤みの黒。
            return Creatures(
                outline: 0x140E0C,
                dogBody: 0x4A4038, dogDark: 0x241C16, dogBelly: 0xD8CCBC,
                boarBody: 0x8A4410, boarDark: 0x1E1A18, boarSnout: 0xA8AEB4,
                birdBody: 0x3E3028, birdWing: 0x2C221C, birdWingFar: 0x1A1410, birdBelly: 0xE8E0D8,
                birdHead: 0x3E3028, birdBeak: 0x4A4A52
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

        // 京都・奈良（`Scenery.kyotoNara`・#1824）。どれも空（0xE6DFF1）と 2:1 未満に沈める淡い色。
        /// 鳥居の朱。彩度を落とした淡い朱（本物の朱 0xE34234 では空から浮く）。
        public static let toriiVermilion: UInt32 = 0xE09A86
        /// 五重塔の屋根（5 層）と相輪。淡い灰茶。
        public static let pagodaRoof: UInt32 = 0xB6AEA8
        /// 五重塔の軸部（白壁と柱の中間の淡い色）。
        public static let pagodaBody: UInt32 = 0xD9D0C4
        /// 寺の本堂の白壁。
        public static let templeWall: UInt32 = 0xF2ECE0
        /// 寺の本堂の瓦屋根（青灰）。
        public static let templeRoof: UInt32 = 0xB3B8C0
        /// 本堂へ上る石段。
        public static let templeSteps: UInt32 = 0xCBC5BA
        /// 道の奥に続く土塀（黄土の漆喰）。
        public static let earthenWall: UInt32 = 0xE4D9C3
        /// 土塀の瓦の笠と腰の線（灰）。
        public static let wallCoping: UInt32 = 0xB0B3BA
        /// 紅葉の木の葉（淡い紅）。山の紅葉より一段濃い。
        public static let mapleCanopy: UInt32 = 0xDD9484
        /// 紅葉の木の幹。
        public static let mapleTrunk: UInt32 = 0xB7A393

        // 温泉街（`Scenery.onsen`・#1938）。どれも空（0xDAE0E8）と 2:1 未満に沈める淡い色。
        /// 旅館の壁（漆喰）。
        public static let ryokanWall: UInt32 = 0xD4C3AC
        /// 旅館の柱・梁・窓枠・櫓の木。
        public static let ryokanTimber: UInt32 = 0xB49C82
        /// 旅館・外湯の瓦屋根（青灰）。
        public static let ryokanRoof: UInt32 = 0xA9B0BA
        /// 屋根と山に積もった雪。
        public static let snow: UInt32 = 0xF3F5F7
        /// 障子窓の灯り（暖色）。
        public static let windowGlow: UInt32 = 0xF0D59C
        /// 外湯ののれん（藍）。
        public static let noren: UInt32 = 0x93A0BE
        /// 提灯（鳥居と同じ淡い朱）。
        public static let lantern: UInt32 = 0xE09A86
        /// 湯けむり（白。半透明で重ねる）。
        public static let steam: UInt32 = 0xF6F7F8
        /// 道の奥の低い柵（提灯の並ぶ）。
        public static let fence: UInt32 = 0xC6BBA8

        // 雪国（`Scenery.snow`・#2729）。どれも空（0xE3E9EF）と 2:1 未満に沈める淡い色で、手前のいちばん暗い
        // キタキツネ（0x944218）とも 3:1 以上離れる（相対輝度 0.45 以上・`WorldTests`）。
        /// 道の奥の雪の壁・かまくらの陰（雪の影の淡い青灰）。
        public static let snowShade: UInt32 = 0xC9D6E0
        /// かまくらの入り口（中の暗がり。背景なので黒くはしない）。
        public static let kamakuraDoor: UInt32 = 0xAAB4C0
        /// 雪国の家の壁（板張り・灰がかった生成り）。屋根は温泉街と同じ青灰の瓦（`ryokanRoof`）に雪（`snow`）。
        public static let snowHouseWall: UInt32 = 0xD6CEC2
        /// 枯れ木の幹と枝。
        public static let bareTree: UInt32 = 0xBDB1A5
        /// ちらつく雪（白）。
        public static let snowflake: UInt32 = 0xFFFFFF

        // 東京（`Scenery.tokyo`・#2729）。面で塗る背景はどれも空（0x5A4E8C）と 2:1 未満に沈める暗い帯（相対輝度 0.17
        // 以下）で、手前の明るい犬・タクシー・ハト（0.61 以上）と 3:1 以上離れる（`WorldTests`）。ビルの影そのものは丘の
        // 2 階調（`palette.hillFar` / `hillNear`）で描く。**灯り（窓・ネオン・信号・航空灯）は小さな点なので背景の帯には
        // 入れない**（夜の繁華街の窓 `buildingWindow` と同じ扱い）。
        /// 地平線の茜の帯（宵の口の名残）。空と 2:1 未満。
        public static let duskGlow: UInt32 = 0xB8666E
        /// ビルの窓の灯り（暖色）。夜の繁華街の窓と同じ黄。
        public static let cityWindow: UInt32 = 0xFFD98A
        /// ネオン看板 3 色（桃・水色・黄）。
        public static let neonPink: UInt32 = 0xFF6FB5
        public static let neonCyan: UInt32 = 0x66E0F0
        public static let neonYellow: UInt32 = 0xFFE066
        /// 遠くの高い塔のシルエット（赤く灯る鉄塔）。
        public static let tower: UInt32 = 0x7A4050
        /// 針のような塔のシルエット。
        public static let needleTower: UInt32 = 0x4A4878
        /// 塔の航空灯（赤。点滅する）。
        public static let aviationLight: UInt32 = 0xFF5A5A
        /// 高架（コンクリートの桁と柱）。
        public static let viaduct: UInt32 = 0x474A62
        /// 高架を流れる電車の車体。
        public static let train: UInt32 = 0x687088
        /// 電車の帯（窓の下のライン）。
        public static let trainStripe: UInt32 = 0x6A7090
        /// 電車の窓の灯り。
        public static let trainWindow: UInt32 = 0xFFE9A8
        /// 信号機の柱と筐体。
        public static let signalPole: UInt32 = 0x4C5068
        /// 信号の青（進め）。
        public static let signalGreen: UInt32 = 0x7FE3A0
        /// 信号の赤（止まれ）。
        public static let signalRed: UInt32 = 0xFF6B6B

        // 富士山（`Scenery.fuji`・#2729）。どれも空（0xECD6E8）と 2:1 未満に沈める淡い色（相対輝度 0.47 以上）で、手前の
        // いちばん明るい暗色（ブルドーザーの錆橙 0x8A4410）とも 3:1 以上離れる（`WorldTests`）。火山の斜面そのものは
        // 丘の 2 階調（`palette.hillFar` / `hillNear`）で描く。
        /// 地平線の御来光の帯（茜〜杏）。空と 2:1 未満。
        public static let sunriseGlow: UInt32 = 0xF4CDB4
        /// 昇りかけの朝日（淡い金）。地平線の帯の上に半分だけ顔を出す。
        public static let sun: UInt32 = 0xFFE3B8
        /// 雲海（斜面の下に広がる白い雲の海）。
        public static let seaOfClouds: UInt32 = 0xF6F0F4
        /// 山小屋の石積みの壁。
        public static let hutWall: UInt32 = 0xCDBDB4
        /// 山小屋のトタン屋根（淡い紫灰）。
        public static let hutRoof: UInt32 = 0xB4A6B0
        /// 山頂の鳥居（淡い朱。京都の鳥居より少し淡い）。
        public static let summitTorii: UInt32 = 0xE2A694
        /// 登山道のロープ柵の杭と縄。
        public static let ropePost: UInt32 = 0xBFA99E
        /// ハイマツ（斜面に張り付く低い松。淡い緑灰）。
        public static let haimatsu: UInt32 = 0xAEBCA4
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
        case .kyotoNara:
            return [
                "hillFar": palette.hillFar, "hillNear": palette.hillNear, "asphalt": road.asphalt,
                "toriiVermilion": SceneryPalette.toriiVermilion,
                "pagodaRoof": SceneryPalette.pagodaRoof,
                "pagodaBody": SceneryPalette.pagodaBody,
                "templeWall": SceneryPalette.templeWall,
                "templeRoof": SceneryPalette.templeRoof,
                "templeSteps": SceneryPalette.templeSteps,
                "earthenWall": SceneryPalette.earthenWall,
                "wallCoping": SceneryPalette.wallCoping,
                "mapleCanopy": SceneryPalette.mapleCanopy,
                "mapleTrunk": SceneryPalette.mapleTrunk,
            ]
        case .onsen:
            return [
                "hillFar": palette.hillFar, "hillNear": palette.hillNear, "asphalt": road.asphalt,
                "ryokanWall": SceneryPalette.ryokanWall,
                "ryokanTimber": SceneryPalette.ryokanTimber,
                "ryokanRoof": SceneryPalette.ryokanRoof,
                "snow": SceneryPalette.snow,
                "windowGlow": SceneryPalette.windowGlow,
                "noren": SceneryPalette.noren,
                "lantern": SceneryPalette.lantern,
                "steam": SceneryPalette.steam,
                "fence": SceneryPalette.fence,
            ]
        case .snow:
            return [
                "hillFar": palette.hillFar, "hillNear": palette.hillNear, "asphalt": road.asphalt,
                "snow": SceneryPalette.snow,
                "snowShade": SceneryPalette.snowShade,
                "kamakuraDoor": SceneryPalette.kamakuraDoor,
                "snowHouseWall": SceneryPalette.snowHouseWall,
                "ryokanRoof": SceneryPalette.ryokanRoof,
                "windowGlow": SceneryPalette.windowGlow,
                "bareTree": SceneryPalette.bareTree,
                "snowflake": SceneryPalette.snowflake,
            ]
        case .tokyo:
            return [
                "hillFar": palette.hillFar, "hillNear": palette.hillNear, "asphalt": road.asphalt,
                "tower": SceneryPalette.tower,
                "needleTower": SceneryPalette.needleTower,
                "viaduct": SceneryPalette.viaduct,
                "train": SceneryPalette.train,
                "trainStripe": SceneryPalette.trainStripe,
                "signalPole": SceneryPalette.signalPole,
            ]
        case .fuji:
            return [
                "hillFar": palette.hillFar, "hillNear": palette.hillNear, "asphalt": road.asphalt,
                "seaOfClouds": SceneryPalette.seaOfClouds,
                "hutWall": SceneryPalette.hutWall,
                "hutRoof": SceneryPalette.hutRoof,
                "summitTorii": SceneryPalette.summitTorii,
                "ropePost": SceneryPalette.ropePost,
                "haimatsu": SceneryPalette.haimatsu,
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
        case .kyotoNara: return ["sky": palette.sky]
        case .onsen: return ["sky": palette.sky]
        case .snow: return ["sky": palette.sky]
        case .tokyo: return ["sky": palette.sky, "duskGlow": SceneryPalette.duskGlow]
        case .fuji: return ["sky": palette.sky, "sunriseGlow": SceneryPalette.sunriseGlow, "sun": SceneryPalette.sun]
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

    /// この世界が受け持つステージ番号（1 始まり）の範囲。朝 1…6・夕方 7…12・夜 13…18・里山 19…24・港町 25…30・
    /// 京都・奈良 31…36・温泉街 37…42・雪国 43…48・東京 49…54・富士山 55…60。
    var stageRange: ClosedRange<Int> {
        let first = (number - 1) * RunnerWorld.stagesPerWorld + 1
        return first...(first + RunnerWorld.stagesPerWorld - 1)
    }

    /// 世界の中での面の位置（1 始まり）。ワールドマップの「1-1」の右側。
    ///
    /// 範囲外（0 以下・61 以上）でも落ちないよう剰余で畳むだけなので、
    /// 呼び出し側で番号の妥当性（`contains(stage:)`）を確かめてから使う。
    static func index(ofStage number: Int) -> Int {
        ((number - 1) % stagesPerWorld + stagesPerWorld) % stagesPerWorld + 1
    }

    /// ワールドマップの短い表記「1-1」…「10-6」。
    ///
    /// 面に付けていた名前（「商店街のあさ」等）は #946 で外した（会長指示「ステージの名前は
    /// いらない。1-1 とか 3-1 とかだけでいい」）。画面・読み上げともこの表記だけを使う。
    static func code(forStage number: Int) -> String {
        "\(world(forStage: number).number)-\(index(ofStage: number))"
    }

    /// ステージ番号（1 始まり）がどれかの世界に収まるか（1…60）。
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
        // 京都・奈良（#1824）は紅葉の橙。隣の港町の青とは色相で正反対。
        case .kyotoNara: return 0xD9876A
        // 温泉街（#1938）は湯の青緑。隣の京都・奈良の橙とは色相で正反対。
        case .onsen: return 0x7FB8B2
        // 雪国（#2729）は冬の夕暮れの淡い藤青（色相 257°）。空の白では朝・港町と区別が付かず、氷の水色は
        // 温泉街の青緑（174°）と 20° 離せないので、夜の青紫（226°）からも 30° 離れたこの色相にする。
        case .snow: return 0xB8A8E0
        // 東京（#2729）はタクシーの黄（色相 47°）。朝の灰の空では朝・港町・雪国と見分けが付かない。京都・奈良の橙
        // （16°）とは 30° 離れ、里山の緑（115°）とは 70° 離れる（`mapColorsAreDistinguishable`）。
        case .tokyo: return 0xE2C34E
        // 富士山（#2729）は御来光の桜色（色相 343°）。暁の空の色そのものは京都・奈良の藤色と見分けが付かないので、
        // 朝日に染まった色で塗る。夕方の桃（322°）とは 20° 以上、京都・奈良の橙（15°）とは 30° 離れる
        // （`mapColorsAreDistinguishable`）。
        case .fuji: return 0xE58FA8
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
            /// 氷の裂け目（雪国・#2729。青白い氷の壁と黒い水面）。穴と、幅の広い裂け目（`RunnerHazardKind.chasm`）の両方に使う。
            case iceCrevasse
            /// 火山岩の割れ目（富士山・#2729。黒い溶岩の裂け目に明るい火山礫の縁）。穴と裂け目（`RunnerHazardKind.chasm`）の両方に使う。
            case volcanicCrack
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
            /// 湯桶（温泉街・案 B。低い岩の 4×5）。
            case yuoke
            /// 雪だるま（雪国・#2729。低い岩の 4×5）。
            case snowman
            /// カラーコーン（東京・#2729。低い岩の 4×5）。
            case trafficCone
            /// 自動販売機（東京・#2729。高い岩の 4×9）。
            case vendingMachine
            /// 登山道の道標（富士山・#2729。高い岩の 4×9）。小さな屋根の付いた木の柱に白い札。
            case signpost
        }
        /// 犬の枠（画面の右から歩いて来る動物）。
        public enum Walker: Equatable, Sendable {
            /// 犬（田舎の犬は同じ絵の色違い・`Creatures`）。
            case dog
            /// 野良猫。
            case cat
            /// 奈良の鹿（#1824）。犬と同じ格子・同じ動き。
            case deer
            /// ニホンザル（温泉街・#1938）。犬と同じ格子・同じ動き。
            case monkey
            /// キタキツネ（雪国・#2729）。犬と同じ格子・同じ動き。
            case fox
            /// ニホンカモシカ（富士山・#2729）。犬と同じ格子・同じ動き。
            case serow
        }
        /// イノシシの枠（右から向かってくるもの）。
        public enum Charger: Equatable, Sendable {
            case boar
            /// フォークリフト。
            case forklift
            /// タクシー（東京・#2729）。フォークリフトと同じ格子・同じ動きで、黒い車体に黄色い屋根の灯り。
            case taxi
            /// 山小屋へ荷を運ぶブルドーザー（富士山・#2729）。フォークリフトと同じ格子・同じ動きで、前に排土板・下に履帯。
            case bulldozer
        }
        /// 台座。
        public enum Platform: Equatable, Sendable {
            /// 工事の足場（`RunnerScene.makePlatform`）。
            case scaffold
            /// わら積み。
            case strawStack
            /// 木箱の山。
            case crateStack
            /// 雪のブロック（かまくらの壁・雪国 #2729。木箱の山と同じ組み立てで色だけ雪）。
            case snowBlocks
            /// 山小屋の石積み（富士山・#2729。木箱の山と同じ組み立てで色だけ火山岩）。
            case stoneStack
        }
        /// 下から突き上げる障害（#1010）。**動き・当たり判定・寸法は 1 つ**で、絵だけを替える。
        public enum Shoot: Equatable, Sendable {
            /// 竹の子（里山）。土が盛り上がる予告 → 竹の子がにょきっと伸びる。
            case bambooShoot
            /// 波しぶき（港町）。岸壁の縁に泡が立つ予告 → 水柱が上がる。
            case seaSpray
            /// 湯柱（温泉街・#1938）。白〜灰の湯気の柱（雪景色の中で氷柱に見えないよう青みを入れない）。
            /// 間欠泉（`RunnerHazardKind.geyser`）の絵。泡立つ予告 → 湯柱が噴き上がる。
            case steamColumn
            /// 地吹雪の雪柱（雪国・#2729）。雪が舞い上がる予告 → 青白い雪の柱が立つ。湯柱と同じ格子で色だけ雪。
            case snowSpout
            /// マンホールの蒸気（東京・#2729）。蓋がカタカタ浮く予告 → 灰白の蒸気の柱が噴き上がる。湯柱と同じ格子で色だけ灰白。
            case manholeSteam
            /// 砂煙（富士山・#2729）。火山礫が舞い上がる予告 → 赤茶の砂煙の柱が立つ。湯柱と同じ格子で色だけ砂礫。
            case dustSpout
        }
        /// 崩れる足場（#1090）。**動き・当たり判定・長さは 1 つ**で、絵だけを替える。
        public enum CrumblingPlatform: Equatable, Sendable {
            /// 古い吊り橋（里山）。渡した板が縄に吊られ、乗るとたわんで板が抜け落ちる。
            case suspensionBridge
            /// 古い木の桟橋（港町）。杭に載った板がきしみ、海へ落ちる。
            case woodenPier
            /// 薄氷の橋（雪国・#2729）。吊り橋と同じ組み立てで、板は氷・縄と柱は凍った木。
            case iceBridge
            /// 古い歩道橋の板（東京・#2729）。桟橋と同じ組み立て（杭に載った板）で、板は色あせたコンクリート・桁と杭は街灯に照らされた淡い緑の鉄骨。
            case oldFootbridge

            /// 桟橋の組み立て（板を載せる桁と、下へ落ちる杭）で描くか。吊り橋の組み立て（縄と袂の柱）でないもの。
            var isPierStyle: Bool {
                switch self {
                case .suspensionBridge, .iceBridge: return false
                case .woodenPier, .oldFootbridge: return true
                }
            }
        }
        /// 高い塀（#1091）。**当たり判定・高さは 1 つ**で、絵だけを替える。
        public enum Wall: Equatable, Sendable {
            /// 石垣（里山）。目地の通った四角い石を積んだ、田畑の境の石積み。
            case stoneWall
            /// 積まれたコンテナ（港町）。海上コンテナを 2 段積み。
            case containerStack
            /// 除雪の雪山（雪国・#2729）。石垣と同じ格子で、固く締まった雪を積んだ段々。
            case snowBank
            /// 積まれたネオン看板（東京・#2729）。コンテナと同じ格子で、水色に光る看板を 2 段積み。
            case signboardStack
            /// 溶岩の石垣（富士山・#2729）。石垣と同じ格子で、黒い溶岩を積んだ山小屋の風よけ。
            case lavaWall
        }
        /// 沈む床（#1089）。**動き・当たり判定・長さは 1 つ**で、絵だけを替える。
        public enum SinkFloor: Equatable, Sendable {
            /// 田んぼ（里山）。水面に苗の列、入ると泥が跳ねる。
            case paddy
            /// 干潟（港町）。ぬかるんだ泥にカニの穴、入ると泥が跳ねる。
            case tideland
            /// 足湯（温泉街・案 B）。濁った湯に湯けむりが立つ。
            case footBath
            /// 新雪（雪国・#2729）。青白い粉雪の吹き溜まりで、踏むと埋もれる。
            case freshSnow
            /// 雨上がりの水たまり（東京・#2729）。宵の空を映した青紫の水面に街の灯りが揺れ、踏むと沈む。
            case puddle
            /// 火山礫のザレ場（富士山・#2729）。足が埋まる崩れやすい砂礫の斜面で、踏むと沈む。
            case scree
        }
        /// 加速床。
        public enum BoostFloor: Equatable, Sendable {
            /// 青い加速帯（`RunnerScene.makeBoostFloor`）。
            case boostBand
            /// 舗装された農道（砂利道の中の黒いアスファルト）。
            case pavedFarmRoad
            /// ベルトコンベア。
            case conveyor
            /// アイスバーン（雪国・#2729）。舗装の農道と同じ組み立てで、面は深い青の氷。
            case iceSheet
            /// 動く歩道（東京・#2729）。ベルトコンベアと同じ組み立てで、街灯に照らされた明るい帯に暗い枠、暗い矢印。
            case movingWalkway
            /// 砂走り（富士山・#2729）。下山道の柔らかい火山砂の帯。舗装の農道と同じ組み立てで、面は黒い砂。
            case sandRun
        }

        public let pit: Pit
        public let lowBlock: Block
        public let tallBlock: Block
        public let dog: Walker
        public let boar: Charger
        public let platform: Platform
        public let boostFloor: BoostFloor
        public let shoot: Shoot
        public let sinkFloor: SinkFloor
        public let crumblingPlatform: CrumblingPlatform
        public let wall: Wall

        /// 岩の枠の着せ替え。岩でない種類は nil。
        public func block(for kind: RunnerHazardKind) -> Block? {
            switch kind {
            case .lowBlock:                        return lowBlock
            case .tallBlock:                       return tallBlock
            // 突き上げ（#1010）は岩の枠ではなく自分の着せ替え（`shoot`）を持つ。
            // 突き上げ（#1010）・高い塀（#1091）は岩の枠ではなく自分の着せ替え（`shoot` / `wall`）を持つ。
            // 落石（#2729）は岩の枠ではなく自分の絵（`RunnerPixelArt.fallingRock`）を持つ。
            case .pit, .chasm, .bird, .dog, .boar, .shoot, .geyser, .wall, .rockfall: return nil
            }
        }
    }

    /// 元の絵。1〜18 面はこれ（#1009 より前と同じ）。
    ///
    /// 突き上げ（#1010）・高い塀（#1091）は 19 面以降にしか置かないので、ここの `shoot` / `wall` が
    /// 本編で使われることは無い。竹の子・石垣にしてあるのは **QA 用ショーケース**
    /// （`RunnerStage.debugShowcase` は `number == 0` なので `RunnerScene.rebuildCourse` が
    /// 朝の下町で走らせる）で撮れるようにするため。
    static let originalDressing = Dressing(
        pit: .construction, lowBlock: .boulder, tallBlock: .boulder, dog: .dog, boar: .boar,
        platform: .scaffold, boostFloor: .boostBand, shoot: .bambooShoot, sinkFloor: .paddy,
        crumblingPlatform: .suspensionBridge, wall: .stoneWall
    )

    var dressing: Dressing {
        switch self {
        case .morning, .evening, .night:
            return RunnerWorld.originalDressing
        case .satoyama:
            // 穴＝用水路・低い岩＝切り株・高い岩＝大きな石（岩塊のまま）・犬＝田舎の犬（色違い）・
            // イノシシ＝イノシシ・台座＝わら積み・加速床＝舗装された農道・突き上げ＝竹の子（#1010）・
            // 沈む床＝田んぼ（#1089）・崩れる足場＝古い吊り橋（#1090）・高い塀＝石垣（#1091）。
            return Dressing(
                pit: .irrigationDitch, lowBlock: .stump, tallBlock: .boulder, dog: .dog, boar: .boar,
                platform: .strawStack, boostFloor: .pavedFarmRoad, shoot: .bambooShoot,
                sinkFloor: .paddy, crumblingPlatform: .suspensionBridge, wall: .stoneWall
            )
        case .harbor:
            // 穴＝岸壁の切れ目・低い岩＝ロープの束・高い岩＝ドラム缶・犬＝野良猫・イノシシ＝
            // フォークリフト・台座＝木箱の山・加速床＝ベルトコンベア・突き上げ＝波しぶき（#1010）・
            // 沈む床＝干潟（#1089）・崩れる足場＝古い木の桟橋（#1090）・高い塀＝積まれたコンテナ（#1091）。
            return Dressing(
                pit: .quayGap, lowBlock: .ropeCoil, tallBlock: .drum, dog: .cat, boar: .forklift,
                platform: .crateStack, boostFloor: .conveyor, shoot: .seaSpray,
                sinkFloor: .tideland, crumblingPlatform: .woodenPier, wall: .containerStack
            )
        case .kyotoNara:
            // 京都・奈良（#1824・会長決裁 2026-10-06 の案 A「鹿だけ新規・他は流用」）: 新しく描くのは犬の枠の
            // **鹿**だけ。穴＝疎水（用水路の絵を流用）・岩＝庭石（岩塊のまま）・イノシシ＝イノシシ・台座＝足場・
            // 加速床＝舗装の参道（農道の舗装を流用）・突き上げ＝竹の子（嵯峨野の竹林）・沈む床＝田んぼ（奈良盆地）・
            // 崩れる足場＝古い木橋（吊り橋を流用）・高い塀＝石垣。石灯籠・人力車・築地塀・縁側など古都らしい
            // 描き足し（決裁スレッドの案 B）は出荷後に別 Issue で足せる。
            return Dressing(
                pit: .irrigationDitch, lowBlock: .boulder, tallBlock: .boulder, dog: .deer, boar: .boar,
                platform: .scaffold, boostFloor: .pavedFarmRoad, shoot: .bambooShoot,
                sinkFloor: .paddy, crumblingPlatform: .suspensionBridge, wall: .stoneWall
            )
        case .onsen:
            // 温泉街（#1938）。新しく描くのは犬の枠の**サル**・低い岩の**湯桶**・沈む床の**足湯**（会長決定 案 B）。
            // 穴＝源泉の溝（用水路の絵を流用）・高い岩＝湯けむりの岩（岩塊のまま）・イノシシ＝イノシシ・
            // 台座＝木箱の山（旅館の荷）・加速床＝舗装の坂道（農道の舗装を流用）・突き上げ・間欠泉＝湯柱（新しい白〜灰の湯気の絵）・
            // 崩れる足場＝川の古い木橋（吊り橋を流用）・高い塀＝石垣。
            return Dressing(
                pit: .irrigationDitch, lowBlock: .yuoke, tallBlock: .boulder,
                dog: .monkey, boar: .boar,
                platform: .crateStack, boostFloor: .pavedFarmRoad, shoot: .steamColumn,
                sinkFloor: .footBath, crumblingPlatform: .suspensionBridge, wall: .stoneWall
            )
        case .snow:
            // 雪国（#2729・設計書 `docs/design/runner-60-stages/worlds-8-10.md` の着せ替え表）。新しく描くのは犬の枠の
            // **キタキツネ**と低い岩の**雪だるま**。穴と裂け目＝氷の裂け目（用水路の色替え）・高い岩＝雪をかぶった岩
            // （岩塊の頂だけ白）・イノシシ＝雪まみれのイノシシ（色替え）・台座＝雪のブロック（木箱の山の色替え）・
            // 加速床＝アイスバーン（農道の舗装の色替え）・突き上げ＝地吹雪の雪柱（湯柱の色替え）・沈む床＝新雪
            // （足湯の色替え）・崩れる足場＝薄氷の橋（吊り橋の色替え）・高い塀＝除雪の雪山（石垣の色替え）。
            return Dressing(
                pit: .iceCrevasse, lowBlock: .snowman, tallBlock: .boulder,
                dog: .fox, boar: .boar,
                platform: .snowBlocks, boostFloor: .iceSheet, shoot: .snowSpout,
                sinkFloor: .freshSnow, crumblingPlatform: .iceBridge, wall: .snowBank
            )
        case .tokyo:
            // 東京（#2729・設計書 `docs/design/runner-60-stages/worlds-8-10.md` の着せ替え表）。新しく描くのは低い岩の
            // **カラーコーン**・高い岩の**自動販売機**・イノシシの枠の**タクシー**（フォークリフトの格子を描き替え）・
            // 高い塀の**積まれた看板**。穴＝工事の切れ目（元の絵）・犬＝犬（秋田犬の色）・台座＝工事の足場（元の絵）・
            // 加速床＝動く歩道（コンベアの色替え）・突き上げ＝マンホールの蒸気（湯柱の色替え）・沈む床＝雨上がりの
            // 水たまり（足湯の色替え）・崩れる足場＝古い歩道橋の板（桟橋の色替え）。高い台座（歩道橋・`H`）は
            // 東京にしか無いので着せ替えの枠を持たず、`RunnerScene.makeFootbridge` が描く。
            return Dressing(
                pit: .construction, lowBlock: .trafficCone, tallBlock: .vendingMachine,
                dog: .dog, boar: .taxi,
                platform: .scaffold, boostFloor: .movingWalkway, shoot: .manholeSteam,
                sinkFloor: .puddle, crumblingPlatform: .oldFootbridge, wall: .signboardStack
            )
        case .fuji:
            // 富士山（#2729・会長決裁 2026-10-23）。新しく描くのは高い岩の**道標**・犬の枠の**ニホンカモシカ**・イノシシの枠の
            // **ブルドーザー**（フォークリフトの格子を描き替え）と、新しい仕掛けの**落石**（`RunnerPixelArt.fallingRock`）。
            // 穴と裂け目＝火山岩の割れ目（氷の裂け目の組み立ての色替え）・低い岩＝火山岩（岩塊のまま。色は世界の配色）・
            // 台座＝山小屋の石積み（木箱の山の色替え）・加速床＝砂走り（農道の舗装の色替え）・突き上げ＝砂煙（雪柱の色替え）・
            // 沈む床＝火山礫のザレ場（足湯の色替え）・崩れる足場＝古い吊り橋（元の絵）・高い塀＝溶岩の石垣（石垣の色替え）。
            // 高い台座（歩道橋・`H`）は東京にしか置かない。
            return Dressing(
                pit: .volcanicCrack, lowBlock: .boulder, tallBlock: .signpost,
                dog: .serow, boar: .bulldozer,
                platform: .stoneStack, boostFloor: .sandRun, shoot: .dustSpout,
                sinkFloor: .scree, crumblingPlatform: .suspensionBridge, wall: .lavaWall
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
        // 田んぼ（`Dressing.SinkFloor.paddy`・#1089）
        /// 田んぼの水面。砂利の農道（0xC2B8A6）と 3:1 以上あり、「乗る前に沈む床だと分かる」
        /// （決裁の受け入れ条件）ための色の差はここが担う。
        public static let paddyWater: UInt32 = 0x3C6274
        /// 水の底（沈む先の暗がり）。走者が沈むほどこの色に浸かって見える。
        public static let paddyDeep: UInt32 = 0x22414F
        /// 苗。水面から突き出る縦の線で、水面と 3:1 以上（模様として読める）。
        public static let paddySeedling: UInt32 = 0x8FD46A
        // 干潟（`Dressing.SinkFloor.tideland`・#1089）
        /// 干潟の泥。岸壁のコンクリート（0xB9BDBD）と 3:1 以上。
        public static let tidelandMud: UInt32 = 0x756244
        /// 泥の深いところ（沈む先）。
        public static let tidelandDeep: UInt32 = 0x3E3426
        /// カニの穴。泥と 3:1 以上で、点として読める暗さ。
        public static let tidelandHole: UInt32 = 0x171310
        /// 潮の照り（濡れた泥の光沢）。泥と 3:1 以上。
        public static let tidelandSheen: UInt32 = 0xDCE8EC
        // 足湯（`Dressing.SinkFloor.footBath`・温泉街 案 B）
        /// 濁った湯。濡れた石畳（0xB3B7BE）と 3:1 以上。
        public static let footBathWater: UInt32 = 0x2F6866
        /// 湯の底（沈む先）。
        public static let footBathDeep: UInt32 = 0x1E4442
        /// 湯けむり（水面から立つ白い湯気。踏み込む前に読める目印）。
        public static let footBathSteam: UInt32 = 0xF4F6F8
        // 崩れる足場（`Dressing.CrumblingPlatform`・#1090）
        /// 古びた板（吊り橋・桟橋で共通）。乗る面なので**いちばん明るい**
        /// ——台座（#674）と同じく、遊ぶ人が最初に読み取るべきは「どこに足が着くか」。
        ///
        /// **この色は背景との 3:1（#929）を担っていない**（淡い丘・あぜ道とは 1.0〜1.5:1）。
        /// 担うのは下の木目と柱・杭で、竹の子・波しぶきと同じ「濃い側が担う」形
        /// （`WorldTests.dressedForegroundStandsOutFromBackdrops`）。
        public static let crumbleDeck: UInt32 = 0xD8C49A
        /// 板の木目・板と板の継ぎ目。**板 1 枚ごとに下端へ入る**ので、抜け落ちていく途中でも
        /// 残った板の輪郭が読める。里山・港町の背景の全部と 3:1 以上（この足場には縁取りの
        /// ノードが無いので、主色だけで満たす必要がある）。
        public static let crumbleDeckSeam: UInt32 = 0x6B5233
        /// 吊り橋の縄（主索と吊り索）。板の上（空・丘を背に）へ張るので、こちらも背景と 3:1 以上。
        public static let crumbleRope: UInt32 = 0x6A4F2B
        /// 桟橋の杭と、吊り橋の袂の柱。**崩れても残る**ので、背景と 3:1 以上で「ここに橋があった」
        /// と読める濃さにしてある。
        public static let crumblePost: UInt32 = 0x4E3B27
        /// 崩れる予告のひび（揺れているあいだ板の上に出る）。板の面の上の模様なので板と 3:1 以上。
        public static let crumbleCrack: UInt32 = 0x3A2B18

        // 雪国（#2729）。路面は圧雪の灰白（0xB9BFC6・相対輝度 0.52）で背景も白い帯なので、
        // **「穴・床・橋だと分かる」ための 3:1 は暗い側（深い水・氷の底・氷の目地・凍った柱）が担う**。
        // 氷の裂け目（`Dressing.Pit.iceCrevasse`。穴と `RunnerHazardKind.chasm` で共通）
        /// 裂け目の底の黒い水。路面と 3:1 以上で「落ちる」と分かる暗さ。
        public static let crevasseWater: UInt32 = 0x1E3A50
        /// 水面の帯（深い水より明るい）。
        public static let crevasseSurface: UInt32 = 0x4F86AA
        /// 裂け目の両岸の氷の壁（青白）。路面より明るく、切れ目の縁を立てる（用水路の壁と同じ約束）。
        public static let iceWall: UInt32 = 0xDDEDF6
        // 雪のブロック（`Dressing.Platform.snowBlocks`）
        /// ブロックの面（固く締まった雪）。
        public static let snowBlockBody: UInt32 = 0xE9EFF4
        /// ブロックの継ぎ目・縁（雪の影の青灰）。
        public static let snowBlockLine: UInt32 = 0x8FA0B0
        /// 上面（歩く面。いちばん明るい——台座の床板と同じ約束）。
        public static let snowBlockTop: UInt32 = 0xF7FAFC
        // アイスバーン（`Dressing.BoostFloor.iceSheet`）
        /// 氷の面。圧雪の路面（0xB9BFC6）と 3:1 以上の深い青（白い氷では路面と見分けが付かない）。
        public static let iceSheet: UInt32 = 0x2F5F7E
        /// 氷の縁（上下の青白い線）。
        public static let iceSheetEdge: UInt32 = 0xDDEDF6
        /// 氷の上の白い矢印。
        public static let iceSheetArrow: UInt32 = 0xFFFFFF
        // 新雪（`Dressing.SinkFloor.freshSnow`）
        /// 粉雪の面（青白）。路面より明るい。
        public static let freshSnowSurface: UInt32 = 0xD3E5F0
        /// 吹き溜まりの底（沈む先の青い影）。路面と 3:1 以上。
        public static let freshSnowDeep: UInt32 = 0x2F5F7E
        /// 地面の線より上へ盛り上がった雪の塊の影（踏み込む前に読める目印）。白い背景と 3:1 以上。
        public static let freshSnowShade: UInt32 = 0x2F5F7E
        // 薄氷の橋（`Dressing.CrumblingPlatform.iceBridge`）
        /// 氷の板（乗る面。いちばん明るい）。
        public static let iceDeck: UInt32 = 0xDCEBF4
        /// 板の下端の濃い氷（板 1 枚ごとの輪郭。背景と 3:1 を担う）。
        public static let iceDeckSeam: UInt32 = 0x2F5F7E
        /// 凍った縄（主索・吊り索）。
        public static let iceRope: UInt32 = 0x3E5E74
        /// 袂の凍った柱（崩れても残る）。
        public static let icePost: UInt32 = 0x3E5E74
        /// 氷のひび（揺れているあいだ板の上に出る）。板と 3:1 以上。
        public static let iceCrack: UInt32 = 0x1E3A50

        // 東京（#2729）。宵の口で路面（0x3C3E4E・相対輝度 0.05）も背景も暗い帯なので、夜の繁華街と同じく
        // **3:1 は明るい側（街灯に照らされた帯・水面・淡い緑の鉄骨）が担う**（相対輝度 0.61 以上で背景の全部と 3:1）。
        // 動く歩道（`Dressing.BoostFloor.movingWalkway`）
        /// 街灯に照らされた明るい帯。路面と 3:1 以上。
        public static let walkwayBelt: UInt32 = 0xC9D3E0
        /// 暗い枠（黒いゴムの縁）。
        public static let walkwayFrame: UInt32 = 0x2A2E38
        /// ローラー（枠より明るい鋼）。
        public static let walkwayRoller: UInt32 = 0x6E7488
        /// 帯の上の暗い矢印。
        public static let walkwayArrow: UInt32 = 0x1A1C24
        // 雨上がりの水たまり（`Dressing.SinkFloor.puddle`）
        /// 宵の空を映した水面。路面と 3:1 以上で「乗る前に沈む床だと分かる」差はここが担う。
        public static let puddleSurface: UInt32 = 0x8792C4
        /// 水の底（沈む先）。
        public static let puddleDeep: UInt32 = 0x3E4474
        /// 水面に映る街の灯り（白。踏み込む前に読める目印）。
        public static let puddleGlint: UInt32 = 0xF2F4F6
        /// 水面の照り。
        public static let puddleSheen: UInt32 = 0xD8DCE2
        // 古い歩道橋の板（`Dressing.CrumblingPlatform.oldFootbridge`）
        /// 色あせたコンクリートの板（乗る面。いちばん明るい）。
        public static let footbridgeDeck: UInt32 = 0xD9DEDC
        /// 板の下端の鉄骨（板 1 枚ごとの輪郭。街灯に照らされた淡い緑で、背景と 3:1 を担う）。
        public static let footbridgeDeckSeam: UInt32 = 0xB9E4CC
        /// 桁と杭（淡い緑の鉄骨。崩れても杭は残る）。
        public static let footbridgePost: UInt32 = 0xB9E4CC
        /// 崩れる予告のひび。板と 3:1 以上。
        public static let footbridgeCrack: UInt32 = 0x1E3A2A
        // 歩道橋（高い台座 `H`。`RunnerScene.makeFootbridge`）
        /// 歩く面（コンクリートの床板。いちばん明るい——台座の床板と同じ約束で、世界の縁取りで浮かせる）。
        public static let footbridgeWalk: UInt32 = 0xE4E8F0
        /// 床板の下の桁（街灯に照らされた淡い緑の鉄骨）。背景の全部と 3:1 以上。
        public static let footbridgeGirder: UInt32 = 0xB9E4CC
        /// 鉄柵（床板の上に立つ手すり）と階段の段。桁より少し濃い緑（それでも背景と 3:1）。
        public static let footbridgeRail: UInt32 = 0xA3DEB8

        // 富士山（#2729）。路面は火山礫の登山道（0xC9B4AC・相対輝度 0.47）で背景も淡い帯なので、朝・雪国と同じく
        // **3:1 は暗い側（溶岩の底・黒い砂・石積みの目地・沈む火山礫）が担う**。
        // 火山岩の割れ目（`Dressing.Pit.volcanicCrack`。穴と `RunnerHazardKind.chasm` で共通）
        /// 割れ目の底の暗がり（黒い溶岩）。路面と 3:1 以上で「落ちる」と分かる暗さ。
        public static let volcanicCrackDeep: UInt32 = 0x2A1A1C
        /// 底の上の帯（赤みの溶岩の断面。底より明るい）。
        public static let volcanicCrackSurface: UInt32 = 0x6A4A46
        /// 割れ目の両岸の明るい火山礫（路面より明るく、切れ目の縁を立てる——用水路の壁・氷の壁と同じ約束）。
        public static let volcanicCrackLip: UInt32 = 0xEADDD6
        // 山小屋の石積み（`Dressing.Platform.stoneStack`）
        /// 石の面（淡い火山岩）。
        public static let stoneStackBody: UInt32 = 0xA89890
        /// 石の継ぎ目・縁（暗い溶岩）。背景と 3:1 を担う。
        public static let stoneStackLine: UInt32 = 0x3E2E2A
        /// 上面（歩く面。いちばん明るい——台座の床板と同じ約束）。
        public static let stoneStackTop: UInt32 = 0xDCD0C8
        // 砂走り（`Dressing.BoostFloor.sandRun`）
        /// 黒い火山砂の面。登山道（0xC9B4AC）と 3:1 以上。
        public static let sandRunSurface: UInt32 = 0x5A4440
        /// 砂の帯の縁（暗い）。
        public static let sandRunEdge: UInt32 = 0x2E2220
        /// 砂の上の白い矢印。
        public static let sandRunArrow: UInt32 = 0xFFF4E8
        // 火山礫のザレ場（`Dressing.SinkFloor.scree`）
        /// 崩れやすい砂礫の面。登山道と 3:1 以上で「乗る前に沈む床だと分かる」差はここが担う。
        public static let screeSurface: UInt32 = 0x6E5650
        /// 砂礫の底（沈む先）。
        public static let screeDeep: UInt32 = 0x3A2A26
        /// 面から転がる小石（踏み込む前に読める目印。淡い背景と 3:1 以上の黒い礫）。
        public static let screePebble: UInt32 = 0x241A16
        /// 面の照り（乾いた砂礫の光）。
        public static let screeSheen: UInt32 = 0xD8C8C0
    }
}
