import AVFoundation
import QuartzCore
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
    /// 連打の間引き。判定は Core 側に置いてテストできるようにしてある。
    private var throttle = SoundThrottle()
    /// 触覚に添える音なので控えめに。
    private let volume: Float = 0.6
    /// 柵越えおじさんの場面の音（`HomerunSoundService`）。`players` とは別に持ち、**互いを止めない**
    /// （カキーンの余韻が月への上昇音で切れない）。`SoundEffect` を鳴らしたときの「他の音を止める」も、こちらには掛けない。
    private var homerunPlayers: [HomerunSound: AVAudioPlayer] = [:]
    /// 合成を裏で進めている間か（`prepare` の二重起動を防ぐ）。
    private var isPreparingHomerun = false

    func impact(_ style: FeedbackImpact) {
        play(SoundEffect(style))
    }

    func notify(_ type: FeedbackNotice) {
        play(SoundEffect(type))
    }

    private func play(_ effect: SoundEffect) {
        // 壁時計だと時刻が過去へ飛んだときに鳴らなくなるため、単調増加する時計を使う。
        guard throttle.shouldPlay(effect, now: CACurrentMediaTime()) else { return }

        configureSessionIfNeeded()
        guard let player = player(for: effect) else { return }

        // 種類の違う音が同時に鳴らないよう、鳴っている他の音は止める。
        // 着手の直後に決着が来る（`impact(.medium)` → `notify(.success)`）ような場面で
        // 2 つ同時に鳴るのを防ぐ。`stop()` ではなく `pause()` を使うのは、
        // `prepareToPlay()` で温めたバッファを捨てないため（次の発音が遅れない）。
        for (kind, other) in players where kind != effect && other.isPlaying {
            other.pause()
        }

        // 鳴っている途中なら頭へ巻き戻して鳴らし直す（重ねない）。
        // `stop()` は `prepareToPlay()` のバッファまで捨ててしまい 2 回目以降の発音が遅れるので使わない。
        player.currentTime = 0
        if !player.play() {
            // 通話・Siri などの割り込みでセッションが非アクティブになっていると play() が false を返す。
            // その場合だけ張り直して 1 度やり直す（割り込み通知の購読より単純で、取りこぼしも無い）。
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
        }
    }

    /// カテゴリが `.ambient` でなければ張り直す。
    ///
    /// 一度きりの設定では不十分。**AdMob のリワード動画は再生時に自前でアプリの音声セッションを操作する**
    /// （SDK 側の `audioSessionIsApplicationManaged` が既定で false）ため、広告のあとカテゴリが
    /// `.ambient` 以外へ変わっていることがある。そのまま鳴らすと消音スイッチを無視したり
    /// 他アプリの音楽を止めたりする側の挙動になり、本機能の前提が崩れる。
    /// 発音のたびに呼ばれるが、`category` の読み取りは安価で、変化が無ければ何もしない。
    private func configureSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .ambient else { return }
        // .ambient は他アプリの音とミックスされ、消音スイッチで無音になる。
        try? session.setCategory(.ambient, mode: .default)
        try? session.setActive(true)
        #if DEBUG
        // シミュレータで「実際に .ambient が適用されたか」を確認するための診断出力。
        print("[SoundFeedback] AVAudioSession.category=\(session.category.rawValue)")
        #endif
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

// MARK: - 柵越えおじさんの場面の音

extension SoundFeedbackService: HomerunSoundService {
    /// 重ねて鳴らす。同じ音が鳴っている途中なら頭から鳴らし直す（同じ音は重ねない）。他の音は止めない。
    func play(_ sound: HomerunSound) {
        configureSessionIfNeeded()
        let player: AVAudioPlayer
        if let cached = homerunPlayers[sound] {
            player = cached
        } else {
            // 準備（`prepare`）が間に合わなかったときだけ、その場で合成する。
            guard let made = makeHomerunPlayer(sound.wavData) else { return }
            homerunPlayers[sound] = made
            player = made
        }
        player.currentTime = 0
        if !player.play() {
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
        }
    }

    /// 16 音の合成（場外の歓声など長いもので数十 ms）を画面を開いたときに裏で済ませ、初めて鳴らす瞬間に詰まらないようにする。
    func prepare() {
        guard !isPreparingHomerun, homerunPlayers.count < HomerunSound.allCases.count else { return }
        isPreparingHomerun = true
        Task.detached(priority: .utility) { [weak self] in
            let data = HomerunSound.allCases.map { ($0, $0.wavData) }
            await self?.installHomerunPlayers(data)
        }
    }

    private func installHomerunPlayers(_ data: [(HomerunSound, Data)]) {
        for (sound, wav) in data where homerunPlayers[sound] == nil {
            homerunPlayers[sound] = makeHomerunPlayer(wav)
        }
        isPreparingHomerun = false
    }

    private func makeHomerunPlayer(_ wav: Data) -> AVAudioPlayer? {
        guard let player = try? AVAudioPlayer(data: wav) else { return nil }
        player.volume = volume
        player.prepareToPlay()
        return player
    }
}
