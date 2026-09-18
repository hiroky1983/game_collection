import Core
import Foundation
import SpriteKit

/// SpriteKit の描画・配色（#494）。
///
/// **SpriteKit の面は SwiftUI の `Theme` に追従しない**（`SKColor` はライト / ダークの動的色を
/// 持てる形で使えず、シーンの背景も自前で塗る）。盤・駒・牌と同じ「モードによらず固定の面」
/// として扱う（基盤規約 §4。値はブロック崩しの `BlocksPalette` と揃えてある）。
///
/// 空・雲・丘・地面・岩は**世界（`RunnerWorld`）ごとに差し替わる**（#703）。ここにある
/// `sky` 〜 `rockDark` は 13〜18 面の夜の値であり、描画側は `RunnerWorld.palette` を読む。
/// 定数を残してあるのは、ここに書かれた「なぜこの色か」の注記（脚と空の被り・岩の茶系 NG）が
/// 世界ごとの配色を選ぶときの物差しになるため。
enum RunnerPalette {
    /// 空。ブロック崩しの地（`0x1E2233`）より明るくして、屋外の昼に見せる。
    static let sky: UInt32 = 0x2E4066
    /// 地面の上面（草）。
    static let groundTop: UInt32 = 0x22C3BE
    /// 地面の断面（土）。**空と系統の違う暖色にする**。同じ寒色の濃淡で塗ると、
    /// 地面と空の境目も穴の切れ目も見分けが付かない（最初の実機確認で判明）。
    static let groundBody: UInt32 = 0x6B4A32
    /// 障害物（岩）の明るい面（日の当たる頂の面）。**茶系は使えない**。地面の断面
    /// （`groundBody`）と同系になり、実機では遠景の丘（紺）とも地面とも見分けが付かず
    /// 「何なのか分からない」というQAが続いた（会長 2026-09-10「岩のデザインはNG」）。
    /// 空・丘の紺、地表のティール、断面の茶のどれとも系統の違う明るいストーングレー
    /// 3階調にして、輪郭線なしでも岩塊が浮き出るようにする。
    static let rockLight: UInt32 = 0xC2C8D2
    /// 障害物（岩）の本体（中間色）。
    static let rockBody: UInt32 = 0x939AA8
    /// 障害物（岩）の陰（陰の面・接地陰）。
    static let rockDark: UInt32 = 0x565D6B
    /// 生成りの白（旗の棒）。走者が図形だった頃の車輪の色で、名前はその名残。
    /// 走者の色はドット絵のパレット（`OjisanPixel.palette`・#701）が持ち、ここには置かない。
    static let wheel: UInt32 = 0xFFF6EC
    /// 遠景の飾り（川・夕焼けの帯・ビル・家並み）の色は世界ごとの純データに置いてある
    /// （`RunnerWorld.SceneryPalette` / `RunnerWorld.TownHouse.Palette`・#929）。
    /// 穴の縁の警告帯。地面と同系色だと縁が分からず、落ちるかどうかの判断がつかない
    /// というQAを受けて追加（会長QA）。工事の柵らしく黒（`pitEdgeDark`）と交互に塗る。
    static let pitEdge: UInt32 = 0xFFD447
    static let pitEdgeDark: UInt32 = 0x2B2B33
    /// 穴の中身（奈落）。縁の帯だけでは「穴の中はただの空」に見え、幅の実感が湧かない
    /// というQAを受けて追加（会長QA）。地面の断面よりさらに暗い色で、地面と穴を塗り分ける。
    static let pitVoid: UInt32 = 0x141824
    /// 雲。空より明るい半透明の白。
    static let cloud: UInt32 = 0xFFFFFF
    /// 遠景の丘（奥）。空より一段暗い寒色で、空との境目が分かる程度の差に留める。
    static let hillFar: UInt32 = 0x263A5C
    /// 近景の丘（手前）。奥の丘よりさらに暗く、地面（`groundBody`）との重なりでも
    /// 手前にあると分かるようにする。
    static let hillNear: UInt32 = 0x1F2F4C
    /// チェックポイントの旗。ゴールの宝くじ（`RunnerPixelArt.lotteryTicket`・#1092）とは
    /// 形も色も別物で、こちらだけが旗として残っている。
    static let checkpoint: UInt32 = 0x5FA8FF
    /// チェックポイントの旗の陰（奥側）。ゴールの旗と同じ厚みの出し方を踏襲する。
    static let checkpointShade: UInt32 = 0x3D7BD9
    /// チェックポイントの旗の文字。白抜き（`wheel`）は旗の水色に対して薄く、実機で
    /// 読めなかった（会長QA「旗の文字もいまだに見えない」）。旗より十分暗い紺で
    /// コントラストを取る。
    static let checkpointText: UInt32 = 0x14284A
    /// 鳥（`RunnerHazardKind.bird`）・犬（#800）・イノシシ（#801）の胴・翼・脚の色は世界ごとに
    /// 変わる（`RunnerWorld.creatures`・#929。朝は暗く、夜は明るく）。ここに残すのは世界に
    /// よらない差し色だけ。
    /// 鳥のくちばし・畳んだ足。胴体と対比が付く暖色にする（「何の生き物か分からない」対策）。
    static let birdBeak: UInt32 = 0xFFB648
    /// 鳥の目（小さな黒丸）。生き物だと分かる最小限の要素。
    static let birdEye: UInt32 = 0x1F2B22
    /// イノシシの牙・目の白。
    static let boarTusk: UInt32 = 0xF4EFE6
    /// スピードアップアイテムの後光（丸）。「電気を帯びた玉」に見えるよう寒色にする。
    static let pickupAura: UInt32 = 0x5CE1E6
    /// スピードアップアイテムの稲妻（本体）。後光との対比を出すため明るい暖色にする。
    /// 以前は細い矩形2枚で稲妻を表していたが小さすぎて読めなかった（会長QA
    /// 「何なのかパッと見てわからない」・2026-09-10）ため、太い稲妻の1枚絵に描き直した。
    static let pickupBolt: UInt32 = 0xFFE066
    /// 稲妻の縁取り。後光と同系色の玉の上に置いても輪郭が沈まないようにする。
    static let pickupBoltOutline: UInt32 = 0xB8860B
    /// たこ焼き（#797）の色はドット絵のパレット（`RunnerPixelArt.palette`・#956）が持ち、ここには置かない。
    /// 台座（#674）の上面＝歩く床板。**ここがいちばん明るい**——「乗れる場所」は上面なので、
    /// 画面の中で最初に目に入るのが上面になるよう、コースのどの面よりも明るい色を当てる。
    /// 地表のティール（`groundTop`）・岩のストーングレー・空の紺のどれとも系統が違う
    /// 木肌寄りのクリーム。
    static let platformDeck: UInt32 = 0xF4E3C1
    /// 台座の骨組み（工事の足場の単管）。安全色のオレンジ。自転車の車体（`bike` = サーモン）
    /// より明確に濃く、岩のグレー・地面の茶とも系統が違う。
    static let platformFrame: UInt32 = 0xC2571F
    /// 台座の骨組みの陰（支柱・筋交いの奥側）と、床板の下の影。骨組みより一段暗くして、
    /// 輪郭線を引かずに「床板が骨組みの上に載っている」段差を出す（岩・鳥と同じ作法）。
    static let platformShade: UInt32 = 0x7A3310

    /// スピードアップ床の路面（#672）。ふつうの地表（`groundTop` のティール）と
    /// **一目で違う区間だ**と分かる必要があるので、アイテムの後光（`pickupAura`）と
    /// 同じ寒色系にして「この色＝速さ」で揃える。地表より明るくして、走者の足元でも沈まない。
    static let boostFloorTop: UInt32 = 0x2FC4E6
    /// スピードアップ床の縁取り（路面より暗い青）。帯の上下に引いて「路面に貼られた加速帯」に見せる。
    /// 旧 0x1B7FA3 は朝の淡い路面（0xB8BCC4）と 2.4:1、夕方の路面と 1.9:1 しかなく、帯の色
    /// そのものも路面と明度が並ぶので、縁だけで 3:1 以上になる暗い青緑にする（#929・`WorldTests`）。
    static let boostFloorEdge: UInt32 = 0x061E2A
    /// スピードアップ床の矢印。路面より明るい暖色にして、床の色に埋もれないようにする。
    /// 進行方向（右）を向いた三角を並べ、「乗ると前へ押される区間」だと色以外でも伝える
    /// （色だけに頼らない・基盤規約のアクセシビリティ要件）。
    static let boostFloorArrow: UInt32 = 0xFFE066

    static func color(_ hex: UInt32) -> SKColor {
        SKColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
