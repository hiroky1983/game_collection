import Testing
import Core
import HomerunCore
@testable import GameHomerun

@MainActor
@Suite("柵越えおじさんの場面ごとの触覚（#1949）")
struct HomerunFeedbackCueTests {
    @Test("受け入れ条件の場面（空振り・ジャストミート・場外・ファウルポール・月が割れる・たんこぶ）に触覚がある")
    func acceptanceScenes() {
        #expect(HomerunFeedbackCue.cue(for: .mitt) == .impact(.light))
        #expect(HomerunFeedbackCue.cue(for: .justMeet) == .impact(.rigid))
        #expect(HomerunFeedbackCue.cue(for: .outOfPark) == .notice(.success))
        #expect(HomerunFeedbackCue.cue(for: .foulPole) == .notice(.warning))
        #expect(HomerunFeedbackCue.cue(for: .moonCrack) == .notice(.success))
        #expect(HomerunFeedbackCue.cue(for: .tankobu) == .notice(.error))
    }

    @Test("当たりは詰まり < 普通 < ジャストミートの順に強くなる")
    func hitStrengthOrder() {
        #expect(HomerunFeedbackCue.cue(for: .hitWeak) == .impact(.light))
        #expect(HomerunFeedbackCue.cue(for: .hitGood) == .impact(.medium))
        #expect(HomerunFeedbackCue.cue(for: .justMeet) == .impact(.rigid))
    }

    @Test("打ち出し・素振り・上昇音・尻もち・怒り・実績は触覚を持たない（演出の合間にうるさくしない）")
    func silentScenes() {
        for sound in [HomerunSound.machine, .swing, .moonRise, .fall, .angry, .achievement] {
            #expect(HomerunFeedbackCue.cue(for: sound) == nil, "\(sound)")
        }
    }

    @Test("play は cue を impact / notify に振り分ける")
    func playRoutes() {
        let spy = SpyFeedback()
        spy.play(HomerunFeedbackCue.impact(.rigid))
        spy.play(HomerunFeedbackCue.notice(.error))
        #expect(spy.impacts == [.rigid])
        #expect(spy.notices == [.error])
    }
}

@MainActor
private final class SpyFeedback: FeedbackService {
    var impacts: [FeedbackImpact] = []
    var notices: [FeedbackNotice] = []
    func impact(_ style: FeedbackImpact) { impacts.append(style) }
    func notify(_ type: FeedbackNotice) { notices.append(type) }
}
