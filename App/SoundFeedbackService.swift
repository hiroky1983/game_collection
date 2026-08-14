import AVFoundation
import Core

/// 効果音による `FeedbackService` の実装。
///
/// - オン / オフ判定は持たない（Core の `GatedFeedbackService` が受け持つ）。触覚と同じ構造。
/// - 音源ファイルは同梱せず、`SoundEffect` の波形定義から起動後に合成する
///   （素材のライセンスとアプリサイズの問題を避けるため）。
/// - `AVAudioSession` のカテゴリは `.ambient`。この設定は
///   「消音（サイレント）スイッチと画面ロックで無音になる」「他アプリの音を止めない」ことが
///   ドキュメントで保証されている組み合わせで、ゲーム音として求められる挙動そのもの。
@MainActor
final class SoundFeedbackService: FeedbackService {
    /// 種類ごとに 1 つだけ使い回す。連打されても同じ音は重ならず鳴り直すため、
    /// 音が積み重なって割れることがない。
    private var players: [SoundEffect: AVAudioPlayer] = [:]
    /// 直前にその音を鳴らした時刻。連打の間引きに使う。
    private var lastPlayedAt: [SoundEffect: TimeInterval] = [:]
    private var didActivateSession = false

    /// この間隔より短い連打では鳴らし直さない（マシンガンのように鳴るのを防ぐ）。
    private let minimumInterval: TimeInterval = 0.04
    /// 触覚に添える音なので控えめに。
    private let volume: Float = 0.6

    func impact(_ style: FeedbackImpact) {
        play(SoundEffect(style))
    }

    func notify(_ type: FeedbackNotice) {
        play(SoundEffect(type))
    }

    private func play(_ effect: SoundEffect) {
        let now = Date().timeIntervalSinceReferenceDate
        if let last = lastPlayedAt[effect], now - last < minimumInterval { return }
        lastPlayedAt[effect] = now

        activateSessionIfNeeded()
        guard let player = player(for: effect) else { return }
        // 鳴っている途中なら頭から鳴らし直す（重ねない）。
        player.stop()
        player.currentTime = 0
        player.play()
    }

    /// 初回の発音まで音声セッションに触らない。効果音がオフのままなら一度も有効化されない。
    private func activateSessionIfNeeded() {
        guard !didActivateSession else { return }
        didActivateSession = true
        let session = AVAudioSession.sharedInstance()
        // .ambient は他アプリの音とミックスされ、消音スイッチで無音になる。
        try? session.setCategory(.ambient, mode: .default)
        try? session.setActive(true)
    }

    /// 波形の合成と `AVAudioPlayer` の生成は種類ごとに初回だけ行う。
    private func player(for effect: SoundEffect) -> AVAudioPlayer? {
        if let cached = players[effect] { return cached }
        guard let player = try? AVAudioPlayer(data: effect.wavData) else { return nil }
        player.volume = volume
        player.prepareToPlay()
        players[effect] = player
        return player
    }
}
