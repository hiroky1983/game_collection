import Core
import Foundation
import Testing
@testable import GameBlocks

/// 盤を画面へ載せるときの寸法（#597）。
///
/// 盤の縦横比は `BlocksField.Metrics.height` ひとつで決まり、**縦長すぎると縦で頭打ちになって
/// 横幅が余る**。値が余白の量に直結するのに画面を見ないと気づけないため、対象実機で実測した
/// 枠を入れて結果を固定する。
@Suite("ブロック崩しの画面寸法")
struct BlocksLayoutTests {

    /// 対象実機で `playfield` に渡っている枠（pt）。
    ///
    /// **2026-09-11 04:00 JST**（= 2026-09-10 19:00 UTC）に Debug ビルドを
    /// `-startGame blocks -simulateBlocks playing` で起動して実測した値。
    /// 幅は「画面幅 - `.padding()` の左右 16pt ずつ」。高さは、盤の比を極端に縦長（400）にした
    /// プローブビルドで盤が縦いっぱいに伸びたときの高さ（横で頭打ちになる機種は、
    /// 実測できた盤の高さ = 使える高さの**下限**を入れてある。狭いほうへ倒しているので、
    /// この表が実機より甘い判定になることはない）。
    struct Device {
        let name: String
        let availableWidth: Double
        let availableHeight: Double
        /// 使い切ってほしい幅の割合。
        let minimumWidthUse: Double
    }

    static let devices: [Device] = [
        // 初回だけ「なぞってパドルを動かそう」のヒントが盤の下に出て、その 32pt ぶん
        // 盤が縮む。iPhone SE はもともと縦が足りないので、この 1 プレイだけ 89% に落ちる
        // （2 プレイ目以降は下の行の 98.7%）。ここだけは詰めきれないことを値として残す。
        Device(name: "iPhone SE（初回・ヒント表示中）", availableWidth: 343,
               availableHeight: 306.5, minimumWidthUse: 0.89),
        Device(name: "iPhone SE (3rd generation)", availableWidth: 343,
               availableHeight: 338.5, minimumWidthUse: 0.98),
        Device(name: "iPhone 17 Pro", availableWidth: 370,
               availableHeight: 459.7, minimumWidthUse: 0.98),
        Device(name: "iPhone 17 Pro Max", availableWidth: 408,
               availableHeight: 407.7, minimumWidthUse: 0.98),
        Device(name: "iPad Pro 11-inch (M5)", availableWidth: 802,
               availableHeight: 834.5, minimumWidthUse: 0.98),
    ]

    @Test("どの対象実機でも盤が横幅をほぼ使い切る（#597 の受け入れ条件）")
    func boardFillsTheWidth() {
        for device in Self.devices {
            let board = BlocksField.Metrics.boardSize(
                availableWidth: device.availableWidth,
                availableHeight: device.availableHeight
            )
            let used = board.width / device.availableWidth
            #expect(
                used >= device.minimumWidthUse,
                "\(device.name) で盤が幅の \(String(format: "%.1f", used * 100))% しか使っていない"
            )
        }
    }

    @Test("盤は枠からはみ出さず、比は Metrics のとおり")
    func boardFitsInsideTheBox() {
        for device in Self.devices {
            let board = BlocksField.Metrics.boardSize(
                availableWidth: device.availableWidth,
                availableHeight: device.availableHeight
            )
            #expect(board.width <= device.availableWidth + 1e-9, "\(device.name) で横にはみ出した")
            #expect(board.height <= device.availableHeight + 1e-9, "\(device.name) で縦にはみ出した")
            #expect(
                abs(board.width / board.height - BlocksField.Metrics.aspectRatio) < 1e-9,
                "\(device.name) で盤の比が崩れた（シーンの .aspectFit と食い違う）"
            )
        }
    }

    /// 幅・高さのどちらで頭打ちになっても、返す枠は必ず比を保つ。
    ///
    /// **比は 1 以外も入れて確かめる**。現在の盤は 100 × 100 なので、比が 1 のままだと
    /// `boardSize` の中で幅と高さを取り違えても結果が変わらず、変異を見逃す。
    @Test("極端に横長・縦長の枠でも比を保って収まる")
    func boardSizeHandlesExtremeBoxes() {
        let wide = BlocksField.Metrics.boardSize(availableWidth: 2000, availableHeight: 100)
        #expect(abs(wide.height - 100) < 1e-9, "縦で頭打ちになるはずが縦を使い切っていない")
        #expect(wide.width <= 2000)

        let tall = BlocksField.Metrics.boardSize(availableWidth: 100, availableHeight: 2000)
        #expect(abs(tall.width - 100) < 1e-9, "横で頭打ちになるはずが横を使い切っていない")
        #expect(tall.height <= 2000)

        // #597 以前の縦長の比（100 : 150）で、頭打ちの向きと返す値を確かめる。
        let legacyRatio = 100.0 / 150.0
        let heightLimited = BlocksField.Metrics.boardSize(
            availableWidth: 370, availableHeight: 428, ratio: legacyRatio
        )
        #expect(abs(heightLimited.height - 428) < 1e-9)
        #expect(abs(heightLimited.width - 428 * legacyRatio) < 1e-9)

        let widthLimited = BlocksField.Metrics.boardSize(
            availableWidth: 200, availableHeight: 1000, ratio: legacyRatio
        )
        #expect(abs(widthLimited.width - 200) < 1e-9)
        #expect(abs(widthLimited.height - 200 / legacyRatio) < 1e-9)

        // 枠が無いときは 0 を返す（GeometryReader の初回など）。
        #expect(BlocksField.Metrics.boardSize(availableWidth: 0, availableHeight: 300) == (0, 0))
        #expect(BlocksField.Metrics.boardSize(availableWidth: 300, availableHeight: 0) == (0, 0))
        #expect(
            BlocksField.Metrics.boardSize(availableWidth: 300, availableHeight: 300, ratio: 0)
                == (0, 0)
        )
    }

    /// 盤が広がっても、バーと玉は盤に対する比で描かれるので見た目の比率は変わらない。
    /// 変わるのは pt 換算の実寸だけ、ということをここで固定する。
    @Test("バーと玉の pt 実寸は盤幅に比例する")
    func paddleAndBallScaleWithTheBoard() {
        for device in Self.devices {
            let board = BlocksField.Metrics.boardSize(
                availableWidth: device.availableWidth,
                availableHeight: device.availableHeight
            )
            let pointsPerUnit = BlocksField.Metrics.pointsPerUnit(boardWidth: board.width)
            let paddle = BlocksField.Metrics.paddleWidth * pointsPerUnit
            let ball = BlocksField.Metrics.ballRadius * 2 * pointsPerUnit
            #expect(
                abs(paddle / board.width - 0.17) < 1e-9,
                "\(device.name) でバーの占める割合が変わった"
            )
            // 最も狭い iPhone SE でもバーが指で追える太さ（HIG の 44pt 相当）を保つ。
            #expect(paddle >= 44, "\(device.name) でバーが \(paddle)pt しかない")
            #expect(ball >= 12, "\(device.name) で玉が \(ball)pt しかない")
        }
    }

    @Test("タップ位置が盤の座標へまっすぐ写る")
    func tapMapsToFieldCoordinates() {
        for device in Self.devices {
            let width = BlocksField.Metrics.boardSize(
                availableWidth: device.availableWidth,
                availableHeight: device.availableHeight
            ).width
            #expect(BlocksField.Metrics.fieldX(viewX: 0, viewWidth: width) == 0)
            #expect(
                abs(BlocksField.Metrics.fieldX(viewX: width, viewWidth: width)
                    - BlocksField.Metrics.width) < 1e-9
            )
            #expect(
                abs(BlocksField.Metrics.fieldX(viewX: width / 2, viewWidth: width)
                    - BlocksField.Metrics.width / 2) < 1e-9,
                "\(device.name) で盤の中央と指の中央がずれた"
            )
            // 枠の外へ出た指は端に丸める（ドラッグが盤からはみ出しても暴れない）。
            #expect(BlocksField.Metrics.fieldX(viewX: -50, viewWidth: width) == 0)
            #expect(
                BlocksField.Metrics.fieldX(viewX: width + 50, viewWidth: width)
                    == BlocksField.Metrics.width
            )
        }
        // 幅ゼロ（レイアウト前の 1 フレーム）ではパドルを飛ばさず中央に置く。
        #expect(
            BlocksField.Metrics.fieldX(viewX: 123, viewWidth: 0) == BlocksField.Metrics.width / 2
        )
    }

    /// #597 以前の盤の値。難度を比べる基準として残す。
    private enum Legacy {
        static let height: Double = 150
        static let topMargin: Double = 14
        static let baseSpeed: Double = 70
        static let speedStep: Double = 4
    }

    /// 盤を低くすると、ブロックの最下段からパドルまでの距離＝**落球までの猶予**が縮む。
    /// 速さを据え置くとここだけが静かに厳しくなるので、**全ステージぶん**時間で固定する。
    ///
    /// ステージごとに段数も速さも違うため、代表 1 面だけを見てはいけない。可動域の縮み方は
    /// 段数によって違い（3 段で 0.61 倍・7 段で 0.52 倍）、速さは終盤ほど上がるので、
    /// **段数が多く速さも上がる終盤ステージがいちばん厳しくなる**。ここを見落とすと
    /// 「難度は変えていない」という説明が終盤だけ成り立たなくなる。
    @Test("どのステージでも落球までの猶予が #597 以前と変わらない")
    func fallingGraceMatchesTheOldBoard() {
        for stage in BlocksStage.all {
            let rows = Double(stage.rows.count)
            let ballTop = BlocksField.Metrics.restingBallY

            let travel = BlocksField.blockRect(row: stage.rows.count - 1, column: 0).minY - ballTop
            let grace = travel / stage.ballSpeed

            let legacyTravel = Legacy.height - Legacy.topMargin
                - rows * BlocksField.Metrics.blockHeight - ballTop
            let legacySpeed = Legacy.baseSpeed + Double(stage.number - 1) * Legacy.speedStep
            let legacyGrace = legacyTravel / legacySpeed

            let ratio = grace / legacyGrace
            #expect(
                ratio >= 0.95 && ratio <= 1.15,
                """
                ステージ\(stage.number)（\(stage.rows.count)段・速さ \(stage.ballSpeed)）の猶予が \
                \(grace) 秒。#597 以前は \(legacyGrace) 秒だったので \(ratio) 倍になっている
                """
            )
        }
    }

    /// 天井とブロックのあいだは、球が回り込めるだけ空けておく（ブロック崩しの定石ルート）。
    @Test("最上段の上に球が入る隙間がある")
    func ballFitsAboveTheTopRow() {
        #expect(BlocksField.Metrics.topMargin > BlocksField.Metrics.ballRadius * 2)
    }

    /// 「タップで発射」の札は、盤の大きさによらず発射前の球とパドルより上に出す。
    /// pt の固定値に戻すと、盤が大きい機種で札がパドルに重なる（#597 で iPad で実測）。
    @Test("発射前の札がパドルと球に重ならない")
    func readyHintClearsThePaddle() {
        let ballTop = BlocksField.Metrics.restingBallY + BlocksField.Metrics.ballRadius
        #expect(BlocksField.Metrics.readyHintClearance > ballTop)
        // 札はブロックの下端より下に居る（盤の中身を隠さない）。
        let deepest = BlocksStage.all.max { $0.rows.count < $1.rows.count }!
        let lowest = BlocksField.blockRect(row: deepest.rows.count - 1, column: 0).minY
        #expect(BlocksField.Metrics.readyHintClearance < lowest)
    }

    /// 盤の外へ出した一時停止ボタンの寸法（#600）。
    ///
    /// 下限は HIG のタップ標的（44pt）。上限はレコメンド枠の高さで、**こちらが盤の大きさを守る**:
    /// ボタンが枠より高くなると操作の行がそのぶん伸び、盤が縦を削られて横幅まで縮む
    /// （盤は正方形なので縦の不足がそのまま幅に出る。#597 の受け入れ条件が後退する）。
    /// 専用の行に戻したときも同じことが起きるため、上限を外すなら盤幅を実機で測り直すこと。
    @Test("一時停止ボタンは 44pt 以上で、レコメンド枠に収まる")
    func pauseButtonFitsTheControlRow() {
        #expect(BlocksView.pauseButtonSide >= 44)
        #expect(BlocksView.pauseButtonSide <= RecommendationCard.placeholderMinimumHeight)
    }
}
