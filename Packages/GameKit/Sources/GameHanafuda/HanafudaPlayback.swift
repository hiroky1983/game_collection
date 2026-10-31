import Foundation
import SwiftUI
import Core

/// 画面上の位置を測る目印（#3138）。札の移動の出発点・到着点を引くのに使う。
enum HanafudaAnchor: Hashable {
    case card(Int)
    case deck
    /// 人間がめくり札を選ぶあいだ、見出しの行に出す札。
    case reveal
    case cpuHand
    case captured(HanafudaPlayer, HanafudaKind)
}

/// 1 手番の動きの台本の 1 手（手札から出す / 山札をめくる）。
struct HanafudaPlaybackMove: Equatable {
    enum Source: Equatable {
        case hand
        /// 山札の一番上から。裏から表へめくる。
        case deck
        /// すでに見出しの行で表になっているめくり札（人間が合わせ先を選び終えたあと）。
        case reveal
    }

    let card: HanafudaCard
    let source: Source
    /// 取った場札（出した札を含まない）。空なら場に置かれる。
    let matched: [HanafudaCard]
    /// 場に同じ月が 2 枚あり、人間が合わせ先を選ぶのを待つ（めくり札だけ）。
    let awaitsChoice: Bool
}

struct HanafudaPlaybackScript: Equatable {
    let player: HanafudaPlayer
    let moves: [HanafudaPlaybackMove]
    /// 台本が終わった時点で場に残っている札の id。置いた札が最後まで場にいるかを決める。
    let finalFieldIDs: Set<Int>
}

/// 札の移動の秒数。CPU の手番の待ちを今より大きく延ばさないよう短く保つ。
enum HanafudaPlaybackTiming {
    /// 着地先の場所をあけるのを待つ。
    static let settle = 0.05
    static let playFlight = 0.25
    static let drawFlight = 0.35
    /// 2 枚が重なって見える間。
    static let pairHold = 0.10
    static let captureFlight = 0.25
    static let betweenMoves = 0.05
    /// Reduce Motion のときの 1 手ぶんのフェード。
    static let fade = 0.15
}

/// 1 手番の札の動きを、モデルが確定させた状態の上に重ねて見せる層（#3138）。
///
/// モデルは 1 手番を一気に確定させる（中断データも確定後の状態）。ここでは確定済みの状態から
/// 「まだ着いていない札」を隠し、飛ぶ札を重ねて順に着地させる。動きの途中で中断しても、
/// 表示は常にモデルの状態に戻る（`finish`）。
@MainActor
@Observable
final class HanafudaPlayback {
    static let space = "hanafudaBoard"

    struct Flying: Identifiable, Equatable {
        let id: Int
        let card: HanafudaCard
        let baseWidth: CGFloat
        var rect: CGRect
        /// 0 = 表、180 = 裏。
        var flip: Double
        var opacity: Double
    }

    /// 画面に出ていてよいときだけ台本を受け取る（画面が無い単体テストでは動かさない）。
    var isEnabled = false
    private(set) var serial = 0
    private(set) var script: HanafudaPlaybackScript?
    /// まだ着いていない札。場・取り札のどちらにも出さない。
    private(set) var hidden: Set<Int> = []
    /// 場の席だけ取って見えなくしている札（着地先の場所をあける）。
    private(set) var ghost: Set<Int> = []
    /// 取り札側の状態では場にいない（もう取られている）が、まだ場に見せておく札。
    private(set) var extraField: [HanafudaCard] = []
    private(set) var flying: [Flying] = []
    /// 山札の表示枚数に足す数（まだめくっていない札）。
    private(set) var deckBonus = 0

    /// 動いているあいだは盤の操作を受けない。台本を持つ間は true。
    var isBusy: Bool { script != nil }

    @ObservationIgnored var frames: [HanafudaAnchor: CGRect] = [:]

    // MARK: 受け取り・片付け

    func begin(_ new: HanafudaPlaybackScript) {
        guard isEnabled, !new.moves.isEmpty else { return }
        serial += 1
        script = new
        var hide = Set<Int>()
        var extra: [HanafudaCard] = []
        var played = Set<Int>()
        for move in new.moves {
            hide.insert(move.card.id)
            for target in move.matched {
                hide.insert(target.id)
                // この台本で先に置かれた札は、置いた時点で場に出る。もとから場にいた札だけここで見せておく。
                if !played.contains(target.id) { extra.append(target) }
            }
            played.insert(move.card.id)
        }
        hidden = hide
        ghost = []
        extraField = extra
        flying = []
        deckBonus = new.moves.filter { $0.source == .deck }.count
    }

    /// 動きを捨てて、表示をモデルの状態に戻す。
    func reset() {
        serial += 1
        clear()
    }

    private func clear() {
        script = nil
        hidden = []
        ghost = []
        extraField = []
        flying = []
        deckBonus = 0
    }

    // MARK: 再生

    /// 台本を最後まで動かす。`.task(id: serial)` から呼ぶ。キャンセルされても表示は元に戻す。
    func run() async {
        guard let script else { return }
        let mine = serial
        defer { if serial == mine { clear() } }
        let reduce = Motion.isReduceMotionEnabled
        for (index, move) in script.moves.enumerated() {
            guard !Task.isCancelled, serial == mine else { return }
            if index > 0 { await wait(reduce ? 0 : HanafudaPlaybackTiming.betweenMoves) }
            await perform(move, in: script, reduceMotion: reduce)
        }
    }

    private func wait(_ seconds: Double) async {
        guard seconds > 0 else { return }
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func animate(_ seconds: Double, _ body: () -> Void) async {
        if seconds > 0 {
            withAnimation(.easeInOut(duration: seconds), body)
        } else {
            body()
        }
        await wait(seconds)
    }

    private func perform(_ move: HanafudaPlaybackMove, in script: HanafudaPlaybackScript, reduceMotion: Bool) async {
        let card = move.card
        let sourceRect = sourceRect(for: move, player: script.player)
        let width = (sourceRect?.width ?? 0)

        // 着地先: 取るなら合わせる札の上、置くなら場の席（先に席をあけて位置を測る）。
        var landing: CGRect?
        if let target = move.matched.first {
            landing = frames[.card(target.id)]
        } else if move.awaitsChoice {
            landing = frames[.reveal]
        } else {
            reserveFieldSlot(for: card, finalFieldIDs: script.finalFieldIDs)
            await wait(HanafudaPlaybackTiming.settle)
            landing = frames[.card(card.id)]
        }
        guard let sourceRect, let landing, width > 0 else {
            // 位置が測れていない（画面に出る前など）。動かさず、状態だけ最後に合わせる。
            land(move, script: script)
            return
        }

        if move.source == .deck { deckBonus = max(0, deckBonus - 1) }
        let base = max(sourceRect.width, landing.width)
        let startsFaceDown = move.source == .deck
        let flightTime = reduceMotion ? 0 : (startsFaceDown ? HanafudaPlaybackTiming.drawFlight : HanafudaPlaybackTiming.playFlight)

        if reduceMotion {
            // フェードだけ: 着地先に現れる。
            flying = [Flying(id: card.id, card: card, baseWidth: base, rect: landing, flip: 0, opacity: 0)]
            await animate(HanafudaPlaybackTiming.fade) { flying[0].opacity = 1 }
        } else {
            flying = [Flying(id: card.id, card: card, baseWidth: base, rect: sourceRect,
                             flip: startsFaceDown ? 180 : 0, opacity: 1)]
            await animate(flightTime) {
                // 取るときは相手の札に少しずらして重ねる。
                flying[0].rect = move.matched.isEmpty ? landing : landing.offsetBy(dx: landing.width * 0.22, dy: landing.height * 0.12)
                flying[0].flip = 0
            }
        }

        guard !move.matched.isEmpty else {
            flying = []
            land(move, script: script)
            return
        }

        // 2 枚（以上）が重なって見えたあと、取った人の取り札の列へ。
        await wait(reduceMotion ? 0 : HanafudaPlaybackTiming.pairHold)
        var group: [Flying] = flying
        for target in move.matched {
            if let rect = frames[.card(target.id)] {
                group.append(Flying(id: target.id, card: target, baseWidth: rect.width, rect: rect, flip: 0, opacity: 1))
            }
        }
        extraField.removeAll { move.matched.contains($0) }
        flying = group
        let player = script.player
        await animate(reduceMotion ? HanafudaPlaybackTiming.fade : HanafudaPlaybackTiming.captureFlight) {
            for index in flying.indices {
                if reduceMotion {
                    flying[index].opacity = 0
                } else if let rect = capturedRect(for: flying[index].card, player: player) {
                    flying[index].rect = rect
                    flying[index].opacity = 0.9
                } else {
                    flying[index].opacity = 0
                }
            }
        }
        flying = []
        land(move, script: script)
    }

    /// 出発点。手札は札のあった位置、CPU は相手の取り札の見出しのあたり、山札は束。
    private func sourceRect(for move: HanafudaPlaybackMove, player: HanafudaPlayer) -> CGRect? {
        switch move.source {
        case .deck:
            return frames[.deck]
        case .reveal:
            return frames[.reveal]
        case .hand:
            if player == .human { return frames[.card(move.card.id)] }
            guard let origin = frames[.cpuHand], let sample = frames[.deck] else { return nil }
            // 手札は見えないので、相手の取り札の枠の上端から出る。大きさは山札の札と同じ。
            return CGRect(x: origin.midX - sample.width / 2, y: origin.minY, width: sample.width, height: sample.height)
        }
    }

    private func capturedRect(for card: HanafudaCard, player: HanafudaPlayer) -> CGRect? {
        guard let column = frames[.captured(player, card.kind)] else { return nil }
        let height = column.height
        let width = height / HanafudaCardArt.aspectRatio
        return CGRect(x: column.midX - width / 2, y: column.minY, width: width, height: height)
    }

    /// 場に置く札の席をあける。最後に場に残らない札（あとで同じ台本の中で取られる）も、置いている間は場に出す。
    private func reserveFieldSlot(for card: HanafudaCard, finalFieldIDs: Set<Int>) {
        ghost.insert(card.id)
        if finalFieldIDs.contains(card.id) {
            hidden.remove(card.id)
        } else {
            extraField.append(card)
        }
    }

    /// 1 手の着地。置いた札は場に現れ、取った札は取り札の列に現れる。
    private func land(_ move: HanafudaPlaybackMove, script: HanafudaPlaybackScript) {
        ghost.remove(move.card.id)
        if move.matched.isEmpty {
            if move.awaitsChoice { hidden.remove(move.card.id) }
            return
        }
        hidden.remove(move.card.id)
        for target in move.matched { hidden.remove(target.id) }
    }
}

// MARK: - 計測と描画

private struct HanafudaFrameKey: PreferenceKey {
    static let defaultValue: [HanafudaAnchor: CGRect] = [:]
    static func reduce(value: inout [HanafudaAnchor: CGRect], nextValue: () -> [HanafudaAnchor: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// この View の位置を `HanafudaPlayback.space` の座標で測る（配置には干渉しない）。
    func hanafudaAnchor(_ anchor: HanafudaAnchor) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: HanafudaFrameKey.self,
                    value: [anchor: geo.frame(in: .named(HanafudaPlayback.space))]
                )
            }
        )
    }

    /// 測った位置を再生層へ渡す。座標空間の持ち主（盤全体）に付ける。
    @MainActor
    func hanafudaTrackFrames(_ playback: HanafudaPlayback) -> some View {
        coordinateSpace(name: HanafudaPlayback.space)
            .onPreferenceChange(HanafudaFrameKey.self) { playback.frames.merge($0) { $1 } }
    }
}

/// 札の裏面。花札らしく無地の濃色に赤い枠（山札・めくる前の札）。
struct HanafudaCardBack: View {
    let width: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
            .fill(Color(hex: HanafudaCardArt.inkHex))
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.07, style: .continuous)
                    .strokeBorder(Color(hex: 0xB33A3A), lineWidth: max(1, width * 0.05))
                    .padding(width * 0.1)
            )
            .frame(width: width, height: width * HanafudaCardArt.aspectRatio)
            .accessibilityHidden(true)
    }
}

/// 裏から表へ回って見える札。回転の途中（90 度）で面を替える。
private struct HanafudaFlipCard: View, Animatable {
    let card: HanafudaCard
    let width: CGFloat
    var flip: Double

    nonisolated var animatableData: Double {
        get { flip }
        set { flip = newValue }
    }

    var body: some View {
        ZStack {
            if flip < 90 {
                HanafudaCardFace(card: card, fixedWidth: width)
            } else {
                // 裏返ったぶん左右が反転して見えるので、もう一度回して戻す。
                HanafudaCardBack(width: width)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0))
    }
}

/// 飛んでいる札を盤の上に重ねる層。タップは受けない。
struct HanafudaFlyingLayer: View {
    let flying: [HanafudaPlayback.Flying]

    var body: some View {
        ZStack {
            ForEach(flying) { item in
                let scale = item.baseWidth > 0 ? item.rect.width / item.baseWidth : 1
                HanafudaFlipCard(card: item.card, width: item.baseWidth, flip: item.flip)
                    .scaleEffect(scale)
                    .opacity(item.opacity)
                    .position(x: item.rect.midX, y: item.rect.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
