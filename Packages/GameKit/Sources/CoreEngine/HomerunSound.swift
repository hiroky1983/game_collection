import Foundation

/// 柵越えおじさんの場面ごとの効果音（会長指示 2026-10-04「ゲームに組み込むか動画作って」）。
///
/// `SoundEffect` は触覚と 1 対 1 の短い操作音で、どのゲームにも相乗りする。こちらは柵越えおじさんの演出に合わせて
/// 鳴らす**場面の音**で、触覚とは対応しない（打球の着弾・月が割れる等、触覚を鳴らさない瞬間にも鳴る）。
/// そのため `FeedbackService` には混ぜず、専用の入口（`HomerunSoundService`）から鳴らす。
///
/// 音源ファイルは同梱せず、`SoundSynth` で起動後に合成する（`SoundEffect` と同じ方針）。
/// 中身は試作の 16 場面 × A/B 案のうち、**ひとまず全部 A 案**。差し替えは `samples` の switch（場面 → 合成の式の対応）
/// 1 か所を書き換えるだけで済むようにしてある。
public enum HomerunSound: String, CaseIterable, Sendable {
    /// 01 バッティングマシンの打ち出し（シュポン）。
    case machine
    /// 02 振った（風切り・ブンッ）。空振り・当たり・素振りのどれでも振った瞬間に鳴らす。
    case swing
    /// 03a 当たり: 芯（木のバットのカーン）。
    case hitJust
    /// 03b 当たり: 普通（木のバットのコーン・少しこもる）。
    case hitGood
    /// 03c 当たり: 詰まり・擦り（ゴッ／バキッ）。
    case hitWeak
    /// 04 ジャストミートの止め（J4・ドンッ+木のカーン）。
    case justMeet
    /// 05a 柵越え確定（合成の「ワッ」・歓声の代用）。
    case homerun
    /// 05b 場外（長い「ワッ」+抜けていく笛）。
    case outOfPark
    /// 06 ファウルポール直撃（金属の柱のカーン）。
    case foulPole
    /// 07 ミットに収まる（バスッ）。
    case mitt
    /// 08a 月まで飛ぶ（上がり続ける音程+噴射）。
    case moonRise
    /// 08b 月が割れる（パキーン）。
    case moonCrack
    /// 09a たんこぶ（ゴツン）。
    case tankobu
    /// 09b 空振りで回って倒れる（ドテッ）。
    case fall
    /// 09c 怒りマーク（プンッ）。
    case angry
    /// 10 実績解禁（キラーン）。
    case achievement

    /// 0.3 秒を超えてよい音（`SoundEffect` の「`fanfare` 以外は 0.3 秒未満」の例外）。
    /// 操作のたびに鳴る音ではなく、1 球の演出の見せ場に 1 回だけ鳴る余韻・歓声・上昇音なので長くてよい。
    /// 操作に直結する音（マシン・風切り・普通と詰まりの当たり・ミット・たんこぶ・倒れる・怒り）は短いまま。
    public static let longSounds: Set<HomerunSound> = [
        .hitJust, .justMeet, .homerun, .outOfPark, .foulPole, .moonRise, .moonCrack, .achievement,
    ]

    /// そのまま `AVAudioPlayer(data:)` に渡せる WAV バイト列。
    public var wavData: Data { ToneGenerator.wavData(samples: samples) }

    /// 長さ（秒）。
    public var duration: Double { Double(samples.count) / SoundSynth.sampleRate }

    /// 波形（-1〜1）。**場面 → 合成の式の対応はここ 1 か所**。B 案へ差し替えるときは右辺の式を入れ替える。
    /// 種は場面ごとに固定（同じ音は毎回同じ波形）。
    public var samples: [Double] {
        var s = SoundSynth(seed: seed)
        switch self {
        case .machine: return Recipe.machineA(&s)
        case .swing: return Recipe.swingA(&s)
        case .hitJust: return Recipe.hitJustA(&s)
        case .hitGood: return Recipe.hitGoodA(&s)
        case .hitWeak: return Recipe.hitWeakA(&s)
        case .justMeet: return Recipe.justMeetA(&s)
        case .homerun: return Recipe.homerunA(&s)
        case .outOfPark: return Recipe.outOfParkA(&s)
        case .foulPole: return Recipe.foulPoleA(&s)
        case .mitt: return Recipe.mittA(&s)
        case .moonRise: return Recipe.moonRiseA(&s)
        case .moonCrack: return Recipe.moonCrackA(&s)
        case .tankobu: return Recipe.tankobuA(&s)
        case .fall: return Recipe.fallA(&s)
        case .angry: return Recipe.angryA(&s)
        case .achievement: return Recipe.achievementA(&s)
        }
    }

    private var seed: UInt64 {
        UInt64(Self.allCases.firstIndex(of: self) ?? 0) &+ 7
    }
}

/// 試作（`homerun-sfx/work/synth.py`）の A 案の式。音量の基準: 操作音 0.30 前後 / 当たり 0.40 前後 / 最大でも 0.50（-6dBFS）。
private enum Recipe {
    typealias S = SoundSynth

    /// シュポン: 空気が抜けるノイズ（高→低）+ 低い「ポン」。
    static func machineA(_ s: inout S) -> [Double] {
        var out = s.noise(0.16, .bandPass, from: 2500, to: 700, q: 1.2, attack: 0.002, decay: 0.045)
        S.mix(&out, S.tone(0.14, from: 260, to: 110, amplitude: 0.9, attack: 0.002, decay: 0.04), at: 0.012)
        return S.normalize(out, peak: 0.30)
    }

    /// ブンッ: 中域の風切り（中心周波数が上がって下がる）。
    static func swingA(_ s: inout S) -> [Double] {
        let out = s.noise(0.26, .bandPass, from: 380, to: 1400, q: 2.2,
                          envelope: S.bellEnvelope(length: S.count(0.26), peak: 0.55, power: 2.2))
        return S.normalize(out, peak: 0.32)
    }

    /// 木のバットの打撃音（会長指摘 2026-10-04「金属音っぽい。木のバットに当たる音に」）。金属の長い鳴り（高い倍音の持続）は
    /// 使わず、乾いた短い破裂（`woodCrack`）+ 中低域の胴鳴り（数十 ms で消える部分音）で作る。
    /// 帯域ノイズの破裂: 木が弾ける「カッ」。金属の高域（4kHz 以上）の破裂より低い 1.5〜3kHz に置く。
    static func woodCrack(_ s: inout S, center: Double, amplitude: Double, decay: Double) -> [Double] {
        s.noise(0.04, .bandPass, from: center, to: center * 0.8, q: 0.9, amplitude: amplitude, attack: 0.0005, decay: decay)
    }

    /// カーン（芯・木）: 澄んで抜ける乾いた破裂 + 中域の胴鳴り（約 0.1 秒で消える）。
    static func hitJustA(_ s: inout S) -> [Double] {
        var out = woodCrack(&s, center: 2600, amplitude: 1.0, decay: 0.006)
        S.mix(&out, S.partials(0.32, [(880, 0.55, 0.055), (1390, 0.35, 0.035), (2150, 0.18, 0.02), (520, 0.30, 0.045)]),
              at: 0.001)
        S.mix(&out, S.tone(0.12, from: 210, to: 160, amplitude: 0.35, attack: 0.001, decay: 0.03))
        return S.normalize(out, peak: 0.42)
    }

    /// コーン（普通・木）: 芯より少しこもる（破裂を低く弱く・胴鳴りを低く短く）。
    static func hitGoodA(_ s: inout S) -> [Double] {
        var out = woodCrack(&s, center: 1800, amplitude: 0.7, decay: 0.006)
        S.mix(&out, S.partials(0.25, [(690, 0.5, 0.04), (1080, 0.28, 0.025), (410, 0.32, 0.035)]), at: 0.001)
        S.mix(&out, s.noise(0.06, .lowPass, from: 900, q: 0.7, amplitude: 0.3, attack: 0.001, decay: 0.015))
        return S.normalize(out, peak: 0.36)
    }

    /// ゴッ／バキッ（詰まり・擦り・木）: 鳴らない鈍い打撃 + 木が軋む短い割れ。
    static func hitWeakA(_ s: inout S) -> [Double] {
        var out = s.noise(0.10, .lowPass, from: 800, q: 0.8, attack: 0.001, decay: 0.022)
        S.mix(&out, S.tone(0.10, from: 220, to: 140, amplitude: 0.8, attack: 0.001, decay: 0.028))
        S.mix(&out, s.noise(0.05, .bandPass, from: 1300, to: 900, q: 1.6, amplitude: 0.45, attack: 0.0005, decay: 0.009),
              at: 0.006)
        return S.normalize(out, peak: 0.32)
    }

    /// ジャストミートの止め（会長指示 2026-10-05: 参考音に寄せる・高音は気持ち抑える。参考音の波形は使わず、
    /// 分析した特徴から合成）: 1.37kHz 付近が主役の「カーン」。当たりの破裂と速く消える鳴り（約 20ms）のあと、
    /// 70ms 遅れて同じ帯域の球場の響きが立ち上がり、約 0.7 秒かけて消える。1.5kHz より上は参考音より数 dB 弱い。
    static func justMeetA(_ s: inout S) -> [Double] {
        var out = s.noise(0.05, .bandPass, from: 1500, to: 1200, q: 0.9, amplitude: 1.0, attack: 0.0003, decay: 0.012)
        S.mix(&out, s.crack(0.004, amplitude: 0.56))
        S.mix(&out, s.noise(0.03, .bandPass, from: 3600, to: 3000, q: 0.8, amplitude: 1.6, attack: 0.0003, decay: 0.006))
        S.mix(&out, S.partials(0.12, [(1370, 0.9, 0.02), (1290, 0.45, 0.016), (1430, 0.4, 0.016), (1110, 0.35, 0.014),
                                      (1214, 0.3, 0.014), (800, 0.25, 0.014), (640, 0.2, 0.012), (2014, 0.4, 0.008)],
                               attack: 0.0005))
        S.mix(&out, S.tone(0.12, from: 120, to: 70, amplitude: 0.04, attack: 0.001, decay: 0.03))
        // 球場の響き（鳴りと帯域ノイズ）。
        let tail = 0.7
        S.mix(&out, S.partials(tail, [(1370, 0.12, 0.085), (1330, 0.07, 0.08), (1094, 0.05, 0.07), (824, 0.04, 0.07)],
                               attack: 0.012), at: 0.07)
        S.mix(&out, s.noise(tail, .bandPass, from: 1380, to: 1340, q: 3, amplitude: 0.38, attack: 0.012, decay: 0.075), at: 0.07)
        S.mix(&out, s.noise(tail, .bandPass, from: 900, to: 800, q: 2, amplitude: 0.15, attack: 0.012, decay: 0.07), at: 0.07)
        return S.normalize(out, peak: 0.50)
    }

    /// 合成の「ワッ」: 母音「あ」の帯域（第 1 フォルマント 750Hz / 第 2 フォルマント 1200Hz 付近）を持つノイズを、
    /// 少しずつずらして何人分も重ねる。本物の歓声には遠く、あくまで代用（本物らしくするなら素材が要る）。
    static func crowd(_ s: inout S, duration: Double, swell: Double, peak: Double) -> [Double] {
        let length = S.count(duration)
        var out = [Double](repeating: 0, count: length)
        for _ in 0..<10 {
            let start = s.uniform(0, 0.12)
            let d = duration - start
            let e = S.bellEnvelope(length: S.count(d), peak: swell / d, power: 1.3)
            let f1 = s.uniform(620, 860)
            let f2 = s.uniform(1050, 1400)
            var voice = s.noise(d, .bandPass, from: f1, to: f1 * 0.9, q: 4, envelope: e)
            S.mix(&voice, s.noise(d, .bandPass, from: f2, to: f2 * 0.92, q: 5, amplitude: 0.6, envelope: e))
            S.mix(&out, voice, at: start)
        }
        S.mix(&out, s.noise(duration, .lowPass, from: 500, q: 0.7, amplitude: 0.4,
                            envelope: S.bellEnvelope(length: length, peak: swell / duration, power: 1.5)))
        return S.normalize(Array(out.prefix(length)), peak: peak)
    }

    /// 柵越え: 合成「ワッ」（代用）。
    static func homerunA(_ s: inout S) -> [Double] {
        crowd(&s, duration: 1.6, swell: 0.35, peak: 0.36)
    }

    /// 場外: ワッ を長く大きく + 遠くへ抜ける高い笛。
    static func outOfParkA(_ s: inout S) -> [Double] {
        var out = crowd(&s, duration: 2.2, swell: 0.5, peak: 1.0)
        S.mix(&out, S.tone(1.0, from: 900, to: 1900, amplitude: 0.25, attack: 0.2, decay: 0.5, vibrato: 0.01, vibratoRate: 6),
              at: 0.1)
        return S.normalize(out, peak: 0.40)
    }

    /// ファウルポール直撃 カーン: 金属の柱。低めの基音 + 高い倍音、わずかなうなりで長く残る。
    static func foulPoleA(_ s: inout S) -> [Double] {
        var out = s.crack(0.01, amplitude: 0.9)
        S.mix(&out, S.partials(1.2, [(523, 0.5, 0.45), (529, 0.35, 0.45), (1440, 0.35, 0.25), (2820, 0.2, 0.12),
                                     (4650, 0.1, 0.05)]))
        return S.normalize(out, peak: 0.40)
    }

    /// バスッ: こもったノイズ + 低い打撃。
    static func mittA(_ s: inout S) -> [Double] {
        var out = s.noise(0.09, .lowPass, from: 1600, to: 700, q: 0.8, attack: 0.001, decay: 0.02)
        S.mix(&out, S.tone(0.09, from: 160, to: 100, amplitude: 0.9, attack: 0.001, decay: 0.03))
        return S.normalize(out, peak: 0.32)
    }

    /// 月へ: 上がり続ける音程（ゆるいビブラート）+ 噴射のノイズ。
    static func moonRiseA(_ s: inout S) -> [Double] {
        let duration = 3.0
        let length = S.count(duration)
        let bell = S.bellEnvelope(length: length, peak: 0.85, power: 1.2)
        var out = zip(S.tone(duration, from: 220, to: 1300, amplitude: 0.6, attack: 0.3, decay: 0, vibrato: 0.015,
                             vibratoRate: 8, shape: .triangle), bell).map { $0 * $1 }
        S.mix(&out, s.noise(duration, .bandPass, from: 600, to: 2000, q: 0.8, amplitude: 0.5,
                            envelope: S.bellEnvelope(length: length, peak: 0.8, power: 1.0)))
        return S.normalize(out, peak: 0.22)
    }

    /// パキーン: ひびの細かい破裂（ランダムなクリック列）+ 高い鳴り + 低い衝撃。
    static func moonCrackA(_ s: inout S) -> [Double] {
        var out = [Double]()
        var t = 0.0
        for _ in 0..<14 {
            let amp = s.uniform(0.4, 1.0)
            S.mix(&out, s.crack(0.004, amplitude: amp), at: t)
            t += s.uniform(0.006, 0.025)
        }
        S.mix(&out, S.partials(0.9, [(2637, 0.4, 0.3), (3951, 0.25, 0.2), (5274, 0.12, 0.1)]), at: 0.01)
        S.mix(&out, S.tone(0.5, from: 120, to: 60, amplitude: 0.6, attack: 0.002, decay: 0.12))
        return S.normalize(out, peak: 0.40)
    }

    /// ゴツン: 硬い物が頭に当たる木琴のような短い鳴り。
    static func tankobuA(_ s: inout S) -> [Double] {
        var out = s.crack(0.004, amplitude: 0.6)
        S.mix(&out, S.partials(0.25, [(392, 0.8, 0.06), (1090, 0.35, 0.03), (2040, 0.12, 0.015)]))
        return S.normalize(out, peak: 0.36)
    }

    /// ドテッ: 低い打撃 1 発 + 小さな跳ね返り。
    static func fallA(_ s: inout S) -> [Double] {
        var out = S.tone(0.22, from: 130, to: 60, attack: 0.002, decay: 0.06)
        S.mix(&out, s.noise(0.1, .lowPass, from: 700, q: 0.7, amplitude: 0.6, attack: 0.001, decay: 0.03))
        S.mix(&out, S.tone(0.1, from: 120, to: 80, amplitude: 0.3, attack: 0.002, decay: 0.03), at: 0.13)
        return S.normalize(out, peak: 0.36)
    }

    /// プンッ: 短く跳ね上がる。
    static func angryA(_ s: inout S) -> [Double] {
        S.normalize(S.tone(0.12, from: 330, to: 760, attack: 0.004, decay: 0.05, shape: .triangle), peak: 0.28)
    }

    /// キラーン: 速いベルのアルペジオ（G6→C7→E7）+ 余韻。
    static func achievementA(_ s: inout S) -> [Double] {
        var out = [Double]()
        for (f, at) in [(1568.0, 0.0), (2093, 0.06), (2637, 0.12)] {
            S.mix(&out, S.partials(0.8, [(f, 0.6, 0.3), (f * 2.76, 0.12, 0.08)], attack: 0.002), at: at)
        }
        return S.normalize(out, peak: 0.30)
    }
}

/// 柵越えおじさんの場面の音を鳴らす入口（`GameServices.homerunSound`）。App 層が `AVAudioPlayer` の実装を注入し、
/// テスト・プレビューでは `NoopHomerunSoundService` を使う。
///
/// `FeedbackService`（触覚と 1 対 1）とは別にしてある: 場面の音は触覚の無い瞬間（着弾・月が割れる等）にも鳴り、
/// 演出の音は互いを止めずに重ねて鳴らす（カキーンの余韻が上昇音で切れない）ため、止め方の規則が違う。
public protocol HomerunSoundService {
    @MainActor func play(_ sound: HomerunSound)
    /// 波形の合成を先に済ませておく（画面を開いたときに呼ぶ。初めて鳴らす瞬間に合成で詰まらない）。
    @MainActor func prepare()
}

public extension HomerunSoundService {
    @MainActor func prepare() {}
}

/// 何もしない実装。テスト・プレビュー用。
public struct NoopHomerunSoundService: HomerunSoundService {
    public init() {}
    @MainActor public func play(_ sound: HomerunSound) {}
}

/// 設定の「効果音」がオフのときは鳴らさないラッパー（`GatedFeedbackService` と同じ役割）。
/// 合成の準備（`prepare`）はオフでも済ませる（ゲームの途中でオンにしてもすぐ鳴る）。
public struct GatedHomerunSoundService: HomerunSoundService {
    private let base: HomerunSoundService
    private let isEnabled: @MainActor () -> Bool

    public init(base: HomerunSoundService, isEnabled: @escaping @MainActor () -> Bool) {
        self.base = base
        self.isEnabled = isEnabled
    }

    @MainActor public func play(_ sound: HomerunSound) {
        guard isEnabled() else { return }
        base.play(sound)
    }

    @MainActor public func prepare() {
        base.prepare()
    }
}
