import Core
import SwiftUI

// MARK: - ワールドマップ（#798）

/// 開始シートに載せる 5 世界 × 6 面の格子（世界の数は `RunnerWorld.allCases` から作る）。到達済みの面だけ選べる。
///
/// **世界ごとに 3 列 × 2 段**にしてある。マスに出すのは「1-1」の表記だけ（面の名前は #946 で
/// 外した）。6 列 1 段だと iPhone SE（幅 375pt・シートの余白を引いて 343pt）では 1 マスが
/// 50pt 前後になり鍵の絵と並べると窮屈なので、3 列のままにしてある。
/// マスの高さは名前の行が無くなっても 44pt を割らないよう `minHeight` で担保する。
///
/// 世界の色（`RunnerWorld.mapColor`）は**見出しの丸・マスの上端の帯・マスの薄い色味**にだけ
/// 使い、文字はその上に載せない（世界の空の色は文字とのコントラストが世界ごとにばらつくため。
/// 面と文字の組み合わせは `Theme` のまま）。選択中は他の設定シート（`GameSetupChooser`）と
/// 同じ「差し色で塗って `onAccent` の文字」にして、選んでいることの見え方をアプリ全体で揃える。
/// 未到達は鍵の絵と薄い文字で、押せない（`disabled`）。
struct RunnerWorldMap: View {
    @Binding var selectedStage: Int
    let reachedStage: Int

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(RunnerWorld.allCases, id: \.self) { world in
                VStack(alignment: .leading, spacing: 8) {
                    worldHeader(world)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(world.stageRange, id: \.self) { number in
                            stageCell(number, world: world)
                        }
                    }
                }
            }
            teaserCard
        }
    }

    /// 港町（最後の世界）の下に置く、機能しないティザー（#1185）。
    ///
    /// **`RunnerWorld` には手を入れない**（実在しない世界を enum ケースとして足すと
    /// `world(forStage:)` 等の既存ロジック・テストに実在の面として混入するため、表示専用の
    /// 静的パーツとして別に置く）。タップしても何も起きないよう `Button` は使わず、
    /// VoiceOver にも「押せる面」だと読ませない（`.accessibilityElement(children: .ignore)` +
    /// 単一のラベルで上書き）。
    private var teaserCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.inkSub.opacity(0.4))
                    .frame(width: 10, height: 10)
                Text("？？？")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
            }
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                Text("つづく…")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Theme.inkSub)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(Theme.surface)
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("まだ見ぬ世界が続く予定です")
    }

    private func worldHeader(_ world: RunnerWorld) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: world.mapColor))
                .frame(width: 10, height: 10)
            Text("ワールド \(world.number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            Text(world.displayName)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func stageCell(_ number: Int, world: RunnerWorld) -> some View {
        let reached = number <= reachedStage
        let selected = reached && number == selectedStage
        let tint = Color(hex: world.mapColor)
        return Button {
            selectedStage = number
        } label: {
            HStack(spacing: 4) {
                // 数値の桁区切りが入らないよう verbatim で出す。
                Text(verbatim: RunnerWorld.code(forStage: number))
                    .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                if !reached {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(selected ? Theme.onAccent : (reached ? Theme.ink : Theme.inkSub))
            // 上下の余白 10pt と合わせて 44pt（iOS の最小のタップ寸）。
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                        .fill(selected ? Theme.Fill.coral : (reached ? tint.opacity(0.16) : Theme.surface))
                    // 世界の色の帯。未到達は薄くして「まだ塗られていない」ことを見せる。
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint.opacity(reached ? 1 : 0.35))
                        .frame(height: 4)
                        .padding(.horizontal, 10)
                        .padding(.top, 3)
                    if !reached {
                        // 未到達はさらに幕をかけてグレーに沈める（麻雀牌の `isBlocked` と同じ濃さ）。
                        // 面色の帯だけでは薄く、シートの地（`Theme.surface`）と同化して押せない
                        // マスだと分かりにくかった（会長指摘「アンロックなステージは背景グレーに」・
                        // 2026-09-16）。
                        RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                            .fill(Theme.ink.opacity(0.16))
                    }
                }
                .shadow(color: .black.opacity(selected ? 0.15 : 0.06), radius: 6, y: 3)
            )
        }
        .buttonStyle(.pop)
        .disabled(!reached)
        .accessibilityLabel(RunnerAccessibility.stageMapLabel(number: number, reached: reached))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
