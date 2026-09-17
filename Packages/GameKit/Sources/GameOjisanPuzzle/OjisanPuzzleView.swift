import SwiftUI
import Core

/// 腰痛おじさんパズル（プロトタイプ）のプレイ画面。
///
/// 盤の描画は `OjisanPuzzleModel.displayBoard`（盤 + 落下中の組）をそのまま並べるだけで、
/// 判定は一切持たない。操作は下のボタン列から Model の受け口を叩く。
public struct OjisanPuzzleView: View {
    private let services: GameServices
    @State private var model: OjisanPuzzleModel
    @Environment(\.scenePhase) private var scenePhase
    /// いま触っているドラッグで、すでに何マスぶん左右へ動かしたか（右が +）。
    @State private var appliedColumns = 0
    /// 同じく、すでに何マスぶん落としたか。
    @State private var appliedRows = 0

    /// 盤の内側の余白。
    private static let boardInset: CGFloat = 6

    public init(services: GameServices) {
        self.services = services
        #if DEBUG
        // 動作確認用: 腰痛ゲージを最初から高くして始める（`-simulateOjisanPain 85`）。
        // 高いゲージの手触り（落下が速い・操作が遅れる）と顔は、実際に十数個積まないと出せないため。
        // 他ゲームの `-simulateBlocks` / `-simulateRunner` と同じ作法で、製品には入らない。
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-simulateOjisanPain"),
           index + 1 < args.count, let pain = Int(args[index + 1]) {
            _model = State(initialValue: OjisanPuzzleModel(
                services: services,
                board: OjisanPuzzleBoard.emptyBoard(),
                current: OjisanPuzzleBoard.spawn(axisKind: 1, childKind: 2),
                pain: pain
            ))
            return
        }
        #endif
        _model = State(initialValue: OjisanPuzzleModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 12) {
            header
            HStack(alignment: .top, spacing: 12) {
                boardView
                sidePanel
            }
            controlHint
            // 終局したら次に遊ぶゲームを勧める枠（#52・#722）。全ゲーム共通の部品をそのまま置く。
            RecommendationArea(services: services, isFinished: model.outcome != nil)
            Spacer(minLength: 0)
        }
        .padding()
        // リザルトは盤の上ではなく画面全体に重ねる（盤は 6×12 で細長く、中に置くと文字が折り返す）。
        .overlay { if model.outcome != nil { resultOverlay } }
        .gameChrome(title: "腰痛おじさんパズル", review: services.review) {
            ToolbarItem(placement: .primaryAction) {
                Button { withGameAnimation { model.newGame() } } label: {
                    Label("リセット", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { model.resume() }
        .onDisappear { model.pause() }
        .onChange(of: scenePhase) { _, phase in
            // 裏に回っているあいだに荷物が落ち続けないようにする。
            if phase == .active { model.resume() } else { model.pause() }
        }
    }

    // MARK: - 見出し（スコア・連鎖・腰痛ゲージ）

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("スコア")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                Text("\(model.score)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            if model.lastChain > 1 {
                Text("\(model.lastChain)連鎖")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.coral)
                    // 同じ連鎖数が続くと値が変わらずトランジションが再生されないので、
                    // 連鎖のたびに増える通し番号を `.id` にする（ブロックならべと同じ手）。
                    .id(model.chainEventID)
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer(minLength: 0)
            painGauge
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
        .gameAnimation(.easeOut(duration: 0.2), value: model.chainEventID)
    }

    private var painGauge: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("腰痛 \(model.pain)　\(model.painStage.caption)")
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(model.painStage == .easy ? Theme.inkSub : Theme.coral)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fillMuted.opacity(0.22))
                GeometryReader { geo in
                    Capsule()
                        .fill(Self.painColor(model.painStage))
                        .frame(width: max(0, geo.size.width) * painRatio)
                }
            }
            .frame(width: 128, height: 8)
        }
        .gameAnimation(.easeInOut(duration: 0.2), value: model.pain)
    }

    private var painRatio: CGFloat {
        CGFloat(model.pain) / CGFloat(OjisanPuzzlePain.limit)
    }

    private static func painColor(_ stage: OjisanPuzzlePain.Stage) -> Color {
        switch stage {
        case .easy: Theme.Fill.teal
        case .aching: Theme.Fill.yellow
        case .severe: Theme.Fill.coral
        }
    }

    // MARK: - おじさん

    /// 腰の痛みを顔に出す（会長指示 2026-09-17）。数字のバーより顔が歪むほうが伝わる。
    /// 絵は `OjisanPixel` の 3 表情をそのまま使い、新しく描き起こさない。
    /// ドット絵なので枠は `faceDotSize` × scale で切る（scale は 1 ドットが Retina の整数ピクセルになる
    /// 1・1.5・2 に限る。32×30 ドットなので 1.5 倍で 48×45pt）。
    private func ojisanFace(scale: CGFloat) -> some View {
        OjisanPixel.faceImage(Self.face(for: model.painStage))
            .frame(
                width: CGFloat(OjisanPixel.faceDotSize.width) * scale,
                height: CGFloat(OjisanPixel.faceDotSize.height) * scale
            )
            // 限界のときだけ少し傾ける（腰をかばっている姿）。
            .rotationEffect(.degrees(model.painStage == .severe ? -8 : 0))
            .gameAnimation(.easeInOut(duration: 0.2), value: model.painStage)
    }

    /// 元気 → 普通 → しかめ面、と一方向に下がるように割り当てる
    /// （`cheer` が一番元気、`smile` が基本、`frown` がしかめ面）。
    private static func face(for stage: OjisanPuzzlePain.Stage) -> OjisanPixel.Face {
        switch stage {
        case .easy: .cheer
        case .aching: .smile
        case .severe: .frown
        }
    }

    // MARK: - 盤

    private var boardView: some View {
        GeometryReader { geo in
            // GeometryReader は最初に 0 を渡してくるので、0 でも割らない・負にしない（#874 と同じ守り）。
            let cell = max(0, min(
                (geo.size.width - Self.boardInset * 2) / CGFloat(OjisanPuzzleBoard.columns),
                (geo.size.height - Self.boardInset * 2) / CGFloat(OjisanPuzzleBoard.rows)
            ))
            let board = model.displayBoard
            VStack(spacing: 1) {
                ForEach(0..<OjisanPuzzleBoard.rows, id: \.self) { row in
                    HStack(spacing: 1) {
                        ForEach(0..<OjisanPuzzleBoard.columns, id: \.self) { col in
                            luggage(board[row][col], side: max(0, cell - 1))
                        }
                    }
                }
            }
            .padding(Self.boardInset)
            .frame(width: geo.size.width, height: geo.size.height)
            .background {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.fillMuted.opacity(0.18))
            }
            // 操作は盤の上で受ける（ボタンを置かないぶん盤を大きく取れる）。
            // 指の移動量を 1 マスぶん（`cell`）で割って刻むので、盤の大きさが変わっても手触りが変わらない。
            .overlay { gestureLayer(step: max(24, cell)) }
        }
        .aspectRatio(CGFloat(OjisanPuzzleBoard.columns) / CGFloat(OjisanPuzzleBoard.rows), contentMode: .fit)
        .gameAnimation(.easeInOut(duration: 0.12), value: model.displayBoard)
    }

    /// 荷物 1 個。**何を運んでいるかが分かる絵**にする（会長指摘 2026-09-17）。
    ///
    /// ドット絵の描き起こしは試作の範囲外なので、色 + SF Symbol で 4 種を見分けられるようにした。
    /// 重いものほど色を濃くする（重さはまだルールには効かない。`OjisanPuzzleLuggage` の doc 参照）。
    private func luggage(_ value: Int, side: CGFloat) -> some View {
        let kind = OjisanPuzzleLuggage.kind(value)
        return RoundedRectangle(cornerRadius: max(1, side * 0.24), style: .continuous)
            .fill(kind == nil ? Theme.fillMuted.opacity(0.14) : Self.color(value))
            // 重いものほど一段沈んだ色にする（1 = そのまま 〜 4 = いちばん濃い）。
            .brightness(-0.045 * Double((kind?.weight ?? 1) - 1))
            .overlay {
                if let kind {
                    Image(systemName: kind.symbol)
                        .font(.system(size: max(1, side * 0.52), weight: .black))
                        .foregroundStyle(Theme.onAccent)
                }
            }
            .frame(width: side, height: side)
    }

    /// 荷物の色。プロトタイプなので差し色をそのまま 4 種に割り当てる（濃さは `luggage` 側で足す）。
    static func color(_ value: Int) -> Color {
        switch value {
        case 1: Theme.Fill.yellow   // 段ボール箱（軽い）
        case 2: Theme.Fill.teal     // 座布団
        case 3: Theme.Fill.coral    // 米袋
        case 4: Theme.Fill.purple   // タンス（重い）
        default: Theme.fillMuted
        }
    }

    // MARK: - 操作（スワイプ・タップ）

    /// 盤の上に敷く透明な操作層（会長指示 2026-09-17: 左右ボタンは置かない）。
    ///
    /// - 横スワイプ … 1 マスずつ左右へ動かす
    /// - 下スワイプ … 1 マスずつ落とす（ソフトドロップ）
    /// - タップ … 回す
    ///
    /// 指に張り付かせず `step`（1 マスぶん）で刻むのは、落ちものの標準的な手触りに合わせるため。
    /// 「これまでに何マスぶん適用したか」を持ち、指の総移動量との差だけを追いかける
    /// （毎フレームの差分を足すと、ゆっくり動かしたときに取りこぼす）。
    private func gestureLayer(step: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard model.outcome == nil else { return }
                        let columns = OjisanPuzzleDrag.steps(value.translation.width, step: step)
                        while appliedColumns < columns { appliedColumns += 1; model.move(by: 1) }
                        while appliedColumns > columns { appliedColumns -= 1; model.move(by: -1) }

                        // 下方向だけ拾う（上スワイプには何も割り当てない）。
                        let rows = OjisanPuzzleDrag.downSteps(value.translation.height, step: step)
                        while appliedRows < rows { appliedRows += 1; model.softDrop() }
                    }
                    .onEnded { value in
                        if OjisanPuzzleDrag.isTap(
                            translation: value.translation,
                            movedColumns: appliedColumns,
                            movedRows: appliedRows
                        ) {
                            withGameAnimation(.easeOut(duration: 0.1)) { model.rotate(clockwise: true) }
                        }
                        appliedColumns = 0
                        appliedRows = 0
                    }
            )
    }

    // MARK: - 次の荷物

    private var sidePanel: some View {
        VStack(spacing: 10) {
            // おじさん本人。盤の横でずっと腰の具合を訴えている。
            VStack(spacing: 4) {
                ojisanFace(scale: 1.5)
                Text(model.painStage.caption)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(model.painStage == .easy ? Theme.inkSub : Theme.coral)
            }
            .frame(width: 64)
            .padding(.vertical, 10)
            // 限界のときは面そのものを痛い色にして、目の端でも分かるようにする。
            .popCard(fill: model.painStage == .severe ? Theme.Fill.coral.opacity(0.28) : Theme.surface,
                     corner: Theme.cornerSmall)

            VStack(spacing: 6) {
                Text("つぎ")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                VStack(spacing: 2) {
                    luggage(model.next.childKind, side: 26)
                    luggage(model.next.axisKind, side: 26)
                }
            }
            .frame(width: 64)
            .padding(.vertical, 12)
            .popCard(corner: Theme.cornerSmall)

            // 盤と同じ高さまで白い面を伸ばさない（カードは中身ぶんだけ）。
            Spacer(minLength: 0)
        }
    }

    // MARK: - 操作の説明

    /// 操作はすべて盤の上のスワイプ・タップなので、代わりに 1 行だけ遊び方を出す。
    private var controlHint: some View {
        HStack(spacing: 14) {
            hintItem("よこにスワイプ", systemImage: "arrow.left.and.right")
            hintItem("タップで回す", systemImage: "arrow.clockwise")
            hintItem("下スワイプ", systemImage: "arrow.down")
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(Theme.inkSub)
    }

    private func hintItem(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
    }

    // MARK: - 決着

    private var resultOverlay: some View {
        VStack(spacing: 10) {
            OjisanPixel.faceImage(.frown)
                .frame(width: 64, height: 60)
            Text(model.outcome == .hospitalized ? "入院！" : "積みあがった！")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(model.outcome == .hospitalized
                 ? "腰が限界です。おだいじに。"
                 : "荷物が天井まで届きました。")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
                .multilineTextAlignment(.center)
            Text("スコア \(model.score)")
                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.ink)
            Button {
                withGameAnimation { model.newGame() }
            } label: {
                Text("もう一度")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                            .fill(Theme.Fill.coral)
                    )
            }
            .buttonStyle(.pop)
        }
        .padding(22)
        .popCard()
        .padding(12)
    }
}
