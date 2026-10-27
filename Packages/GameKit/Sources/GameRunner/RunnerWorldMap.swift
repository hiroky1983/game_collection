import Core
import SwiftUI

// MARK: - ステージセレクト（#798 → #2730 で C 案に作り直し）

/// 開始シートに載せるステージセレクト。**横スクロールの「世界の帯」＋世界のつまみ＋その世界の 6 面**
/// （会長決裁 2026-10-24・C 案。モックは `docs/design/runner-60-stages/select-ui/`）。
///
/// 旧 #798 は 9 世界 × 6 面の格子を縦に積んでいたので、面が増えるたびにシートが長くなり、
/// 開いた直後はマップが 1 画面ぶん下に隠れていた。帯は 1 枚に 1 世界で、**面が増えても高さが変わらず**
/// iPhone SE でも 1 画面に収まる。開いたときは選んでいる面（＝今いる面）の世界の帯を出す。
///
/// 見せ方（モックの共通の約束）: 今いる面＝珊瑚色＋「▶ 今ここ」／クリア済み＝薄い世界の色＋✓／
/// まだ遊べない面＝灰＋鍵。ノーミスの★は入れない（決裁が出たら別に足す）。
///
/// 世界の数は `RunnerWorld.allCases` から取り、直書きしない。最後の世界の次は「？？？ つづく…」の
/// ティザー（#1185 の考え方を引き継ぐ）で、帯・つまみに 1 枚ぶん足す（`pageCount`）——**ただし物語が 60 面（10 世界）で
/// 完結した #2729 からは出さない**（`showsTeaser`。設計書 §2.3「10 世界で消す。将来 11 以降を作るなら復活させる」）。
/// **`RunnerWorld` には実在しない世界を足さない**（`world(forStage:)` 等に混入するため）。
///
/// 世界の色（`RunnerWorld.mapColor`）は見出しの丸・マスの上端の帯・マスの薄い色味にだけ使い、
/// 文字はその上に載せない（文字と面の組み合わせは `Theme` のまま）。選択中は他の設定シート
/// （`GameSetupChooser`）と同じ「差し色で塗って `onAccent` の文字」。
struct RunnerWorldMap: View {
    @Binding var selectedStage: Int
    let reachedStage: Int

    /// 見ている帯（0 始まり。ティザーを出すときは `RunnerWorld.allCases.count` がティザー）。
    @State private var page: Int?

    init(selectedStage: Binding<Int>, reachedStage: Int) {
        _selectedStage = selectedStage
        self.reachedStage = reachedStage
        var initial = Self.page(forStage: selectedStage.wrappedValue)
        #if DEBUG
        // 撮影用: `-runnerSelectPage N` で N 番目の帯（0 始まり）を開く（ティザーの帯を撮るため・#2730）。
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-runnerSelectPage"), i + 1 < args.count,
           let forced = Int(args[i + 1]), (0..<Self.pageCount).contains(forced) {
            initial = forced
        }
        #endif
        _page = State(initialValue: initial)
    }

    /// 最後の世界の次に「？？？ つづく…」のティザーを出すか（#1185）。物語は富士山（60 面）で完結した（#2729）ので
    /// 出さない。11 番目の世界を足すときは true に戻す（ティザーの帯・札の絵はそのために残してある）。
    static let showsTeaser = false

    /// 帯の枚数（実在の世界。ティザーを出すときはさらに 1 枚）。
    static var pageCount: Int { RunnerWorld.allCases.count + (showsTeaser ? 1 : 0) }

    /// 面の属する帯。範囲外は最初の世界。
    static func page(forStage number: Int) -> Int {
        RunnerWorld.contains(stage: number) ? RunnerWorld.world(forStage: number).number - 1 : 0
    }

    /// 帯の世界。ティザーは nil。
    static func world(at page: Int) -> RunnerWorld? {
        RunnerWorld.allCases.indices.contains(page) ? RunnerWorld.allCases[page] : nil
    }

    private var currentPage: Int { page ?? 0 }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    /// つまみ（高さ 22pt）の角丸。マスの角丸（`Theme.cornerSmall`）をそのまま使うと丸薬になるので半分。
    private static let knobCorner = Theme.cornerSmall / 2

    var body: some View {
        // 間隔・マスの高さは iPhone SE（縦 667pt）でモードの節の下に 6 面と 1 行の記録まで収まる寸法。
        VStack(alignment: .leading, spacing: 8) {
            band
            knobs
            if let world = Self.world(at: currentPage) {
                stageGrid(world)
                worldSummary(world)
            } else {
                teaserCard
            }
        }
    }

    // MARK: 世界の帯

    /// 横に 1 枚ずつ送る帯。各ページは帯の幅いっぱい（`containerRelativeFrame`）で、`.paging` で 1 枚ずつ止まる。
    /// 帯の高さは幅から決まる（`RunnerWorldBandArt.aspectRatio`）ので、面の数にも世界の数にもよらない。
    private var band: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(0..<Self.pageCount, id: \.self) { index in
                    bandPage(index)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                        // 読み上げは見えている帯だけ（隣の帯は VoiceOver に出さない）。
                        .accessibilityHidden(index != currentPage)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $page)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
        .overlay { bandArrows }
    }

    @ViewBuilder
    private func bandPage(_ index: Int) -> some View {
        if let world = Self.world(at: index) {
            RunnerWorldBandView(world: world)
                .overlay {
                    bandCaption(
                        title: tr("ワールド %1$lld / %2$lld", world.number, Self.pageCount),
                        name: world.displayName
                    )
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(RunnerAccessibility.worldBandLabel(world: world, total: Self.pageCount))
        } else {
            teaserBand
        }
    }

    /// 帯の中央に置く「ワールド n / 10」と世界の名前の札。
    private func bandCaption(title: String, name: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .scaledFont(11, weight: .bold, design: .rounded).monospacedDigit()
                .foregroundStyle(Theme.inkSubText)
            Text(name)
                .scaledFont(16, weight: .heavy, design: .rounded)
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .fill(Theme.surface.opacity(0.92))
        )
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 10)
    }

    /// 最後の世界の次の帯（#1185 のティザー）。タップしても何も起きず、VoiceOver にも「押せる世界」だと読ませない。
    private var teaserBand: some View {
        ZStack {
            Theme.ink.opacity(0.2)
            VStack(spacing: 4) {
                Text(tr("？？？"))
                    .scaledFont(12, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.inkSubText)
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .scaledFont(13, weight: .bold)
                    Text(tr("つづく…"))
                        .scaledFont(16, weight: .heavy, design: .rounded)
                }
                .foregroundStyle(Theme.ink)
            }
        }
        .aspectRatio(RunnerWorldBandArt.aspectRatio, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("まだ見ぬ世界が続く予定です"))
    }

    /// 帯の両端の ‹ ›。スワイプに気づかない人のため（モックどおり）。端では出さない。
    private var bandArrows: some View {
        HStack {
            arrowButton(systemImage: "chevron.left", label: tr("前の世界"), enabled: currentPage > 0) {
                show(page: currentPage - 1)
            }
            Spacer(minLength: 0)
            arrowButton(systemImage: "chevron.right", label: tr("次の世界"), enabled: currentPage < Self.pageCount - 1) {
                show(page: currentPage + 1)
            }
        }
        .padding(.horizontal, 8)
    }

    private func arrowButton(systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .scaledFont(14, weight: .heavy)
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.surface.opacity(0.92)))
                // 丸は 36pt だが、当たりは 44pt（iOS の最小のタップ寸）。
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pop)
        .opacity(enabled ? 1 : 0)
        .disabled(!enabled)
        // 見えない端の矢印を VoiceOver に読ませない。
        .accessibilityHidden(!enabled)
        .accessibilityLabel(label)
    }

    private func show(page next: Int) {
        guard (0..<Self.pageCount).contains(next) else { return }
        withGameAnimation(.easeInOut(duration: 0.25)) { page = next }
    }

    // MARK: 世界のつまみ

    /// 10 世界のつまみ。今どの帯を見ているかの印で、押せばその帯へ飛ぶ。絵は帯と同じ（縮めるだけ）。
    private var knobs: some View {
        HStack(spacing: 4) {
            ForEach(0..<Self.pageCount, id: \.self) { index in
                knob(index)
            }
        }
    }

    private func knob(_ index: Int) -> some View {
        let world = Self.world(at: index)
        let selected = index == currentPage
        return Button {
            show(page: index)
        } label: {
            knobLabel(world, index: index, selected: selected)
        }
        .buttonStyle(.pop)
        .accessibilityLabel(
            world.map { tr("ワールド %lld、%@", $0.number, $0.displayName) } ?? tr("まだ見ぬ世界が続く予定です")
        )
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func knobLabel(_ world: RunnerWorld?, index: Int, selected: Bool) -> some View {
        VStack(spacing: 3) {
            Group {
                if let world {
                    // つまみは幅が狭い（SE で 31pt）ので、帯の縦横比は保たず枠いっぱいに伸ばして切る。
                    RunnerWorldBandView(world: world, keepsAspectRatio: false)
                } else {
                    Theme.ink.opacity(0.2)
                }
            }
            .frame(height: 22)
            .clipShape(RoundedRectangle(cornerRadius: Self.knobCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.knobCorner, style: .continuous)
                    .strokeBorder(selected ? Theme.Fill.coral : Theme.inkSub.opacity(0.3), lineWidth: selected ? 2 : 1)
            )
            Text(verbatim: "\(index + 1)")
                .scaledFont(11, weight: selected ? .heavy : .bold, design: .rounded).monospacedDigit()
                .foregroundStyle(selected ? Theme.ink : Theme.inkSubText)
        }
        // 絵と番号で 40pt ほどしかないので、当たりは縦に 44pt（iOS の最小のタップ寸）まで広げる。
        .frame(maxWidth: .infinity, minHeight: GameButtonMetrics.minTapTarget)
        .contentShape(Rectangle())
    }

    // MARK: その世界の 6 面

    private func stageGrid(_ world: RunnerWorld) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(world.stageRange, id: \.self) { number in
                stageCell(number, world: world)
            }
        }
    }

    private func stageCell(_ number: Int, world: RunnerWorld) -> some View {
        let state = RunnerStageSelectState.state(of: number, reachedStage: reachedStage)
        let reached = state != .locked
        let selected = reached && number == selectedStage
        let tint = Color(hex: world.mapColor)
        return Button {
            selectedStage = number
        } label: {
            VStack(spacing: 2) {
                // 数値の桁区切りが入らないよう verbatim で出す。
                Text(verbatim: RunnerWorld.code(forStage: number))
                    .scaledFont(16, weight: .heavy, design: .rounded).monospacedDigit()
                    .foregroundStyle(selected ? Theme.onAccent : (reached ? Theme.ink : Theme.inkSubText))
                stageStatus(state, selected: selected)
            }
            // 上下の余白 6pt と合わせて 46pt（iOS の最小のタップ寸 44pt 以上）。
            .frame(maxWidth: .infinity, minHeight: 34)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                        .fill(selected ? Theme.Fill.coral : (reached ? tint.opacity(0.16) : Theme.surface))
                    // 世界の色の帯。未到達は薄くして「まだ塗られていない」ことを見せる。
                    Capsule()
                        .fill(tint.opacity(reached ? 1 : 0.35))
                        .frame(height: 4)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                    if !reached {
                        // 未到達はさらに幕をかけてグレーに沈める（麻雀牌の `isBlocked` と同じ濃さ）。
                        // 面色の帯だけでは薄く、シートの地（`Theme.surface`）と同化して押せない
                        // マスだと分かりにくかった（会長指摘「アンロックなステージは背景グレーに」・2026-09-16）。
                        RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                            .fill(Theme.ink.opacity(0.16))
                    }
                }
                .shadow(color: .black.opacity(selected ? 0.15 : 0.06), radius: 6, y: 3)
            )
        }
        .buttonStyle(.pop)
        .disabled(!reached)
        .accessibilityLabel(RunnerAccessibility.stageSelectLabel(number: number, state: state))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// マスの下段: クリア済み＝✓ クリア／今いる面＝▶ 今ここ／まだ遊べない面＝鍵。
    /// 選んでいるマス（珊瑚色）では文字も `onAccent`。
    private func stageStatus(_ state: RunnerStageSelectState, selected: Bool) -> some View {
        HStack(spacing: 3) {
            switch state {
            case .cleared:
                Image(systemName: "checkmark").scaledFont(10, weight: .heavy)
                Text(tr("クリア")).scaledFont(11, weight: .bold, design: .rounded)
            case .current:
                Image(systemName: "play.fill").scaledFont(9, weight: .heavy)
                Text(tr("今ここ")).scaledFont(11, weight: .bold, design: .rounded)
            case .locked:
                Image(systemName: "lock.fill").scaledFont(11, weight: .bold)
            }
        }
        .foregroundStyle(selected ? Theme.onAccent : (state == .locked ? Theme.inkSubText : Theme.ink.opacity(0.7)))
        .frame(height: 14)
    }

    /// 帯の下の 1 行。「この世界: n / 6 クリア」。
    private func worldSummary(_ world: RunnerWorld) -> some View {
        let cleared = RunnerStageSelectState.clearedCount(in: world, reachedStage: reachedStage)
        return Text(tr("この世界: %1$lld / %2$lld クリア", cleared, RunnerWorld.stagesPerWorld))
            .scaledFont(12, weight: .medium, design: .rounded).monospacedDigit()
            .foregroundStyle(Theme.inkSubText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// ティザーの帯のとき、6 面の格子の代わりに置く札（#1185）。格子とほぼ同じ高さにして、
    /// 帯の下の見た目が世界をまたいで跳ねないようにする。
    private var teaserCard: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .scaledFont(12, weight: .bold)
            Text(tr("つづく…"))
                .scaledFont(13, weight: .bold, design: .rounded)
        }
        .foregroundStyle(Theme.inkSubText)
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .fill(Theme.surface)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("まだ見ぬ世界が続く予定です"))
    }
}

// MARK: - 面の見え方（#2730）

/// ステージセレクトの 1 面の状態。到達した最大の面（`RunnerModel.reachedStage`）だけから決まる。
///
/// 到達点より手前はクリア済み、到達点が「今ここ」、その先はまだ遊べない。最終面をクリアしても
/// 到達点は最終面で頭打ち（`RunnerModel`）なので、最終面は「今ここ」のまま。
public enum RunnerStageSelectState: Equatable, Sendable {
    case cleared
    case current
    case locked

    public static func state(of number: Int, reachedStage: Int) -> RunnerStageSelectState {
        if number < reachedStage { return .cleared }
        if number == reachedStage { return .current }
        return .locked
    }

    /// 世界の中でクリア済みの面の数（0…`stagesPerWorld`）。
    static func clearedCount(in world: RunnerWorld, reachedStage: Int) -> Int {
        world.stageRange.filter { state(of: $0, reachedStage: reachedStage) == .cleared }.count
    }
}

// MARK: - 帯の絵

/// 世界の帯の背景（`RunnerWorldBandArt`）を敷く面。絵が描けるまで（初回の 1 フレーム）はその世界の空の色。
/// 帯もつまみも同じ部品で、枠の大きさに合わせて絵を伸ばして切る（縦横比は `RunnerWorldBandArt.aspectRatio`）。
private struct RunnerWorldBandView: View {
    let world: RunnerWorld
    /// 真なら帯の縦横比で高さを決める（帯）。偽なら枠の大きさに任せる（つまみ）。
    var keepsAspectRatio = true
    @State private var image: CGImage?

    var body: some View {
        Color(hex: world.palette.sky)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .aspectRatio(keepsAspectRatio ? RunnerWorldBandArt.aspectRatio : nil, contentMode: .fit)
            .clipped()
            // 絵を起こすのは画面に出たときだけ。帯（いま見ている 1 枚）はすぐ描き、つまみ（最大 10 枚）は
            // 1 枚ずつ間を空けて描く（シートを開いた瞬間にメインアクターへ 9 枚ぶんの描画を詰めない）。
            .task(id: world) {
                image = keepsAspectRatio
                    ? RunnerWorldBandArt.image(for: world)
                    : await RunnerWorldBandArt.staggeredImage(for: world)
            }
    }
}
