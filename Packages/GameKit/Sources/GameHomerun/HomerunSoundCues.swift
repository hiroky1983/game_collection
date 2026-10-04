import Core
import Foundation
import HomerunCore
import SwiftUI

/// 鳴らす予定の 1 つ（いつ・どの音）。
struct HomerunSoundCue: Hashable {
    var at: Date
    var sound: HomerunSound
    /// 「同じ予定か」を見分ける時刻（出し直しで 2 回鳴らさない鍵）。nil なら `at`。鳴らす時刻が出し直すたびに変わる予定
    /// （10 球の結果に入ったときの実績解禁）だけ、変わらない時刻を入れる。
    var identity: Date? = nil

    var key: Key { Key(sound: sound, at: identity ?? at) }

    struct Key: Hashable {
        var sound: HomerunSound
        var at: Date
    }
}

/// 柵越えおじさんの効果音を**いつ鳴らすか**（純粋な値）。音そのものは `HomerunSound`（CoreEngine）。
///
/// Model は時計を持たないので、演出の時刻を決めているのと同じ式（`HomerunSwingPlan` の打点・打球の道・月・たんこぶ・
/// 空振りの演出の時刻）から、1 つの進行（`HomerunModel.step`）の間に鳴らす音と時刻の一覧を出す。待って鳴らすのは
/// `HomerunSoundPlayer`（View の `.task`）。演出の時間を詰め直したら音も自動で付いてくる。
enum HomerunSoundCues {
    /// 空振りの演出（`HomerunWhiffGag`）で尻もちをつくコマ（クリップの 1 始まり）。シミュレータの録画で、回り終えて地面に
    /// 尻が着くコマを測った値（座り込みきるのは 92 コマ目ごろ・`HomerunWhiffGag.cardDelay`）。
    static let fallFrame: Double = 85
    /// 月まで飛ぶ打球で、当たってから上昇音を鳴らし始めるまで（秒）。カキーンの頭と重ならないよう少し空ける。
    static let moonRiseDelay: TimeInterval = 0.25

    /// いまの進行の間に鳴らす音。
    /// - `bannerShownAt`: 「実績解禁」を出した時刻（出していなければ nil）。
    /// - `unlockedAtFinish`: 挑戦の最後の球で実績を解除した（10 球の結果に出る）。
    /// - `now`: 10 球の結果に入った時刻（実績解禁の音をそこで鳴らす）。
    static func cues(plan: HomerunSwingPlan, bannerShownAt: Date?, unlockedAtFinish: Bool, now: Date) -> [HomerunSoundCue] {
        var cues: [HomerunSoundCue] = []
        switch plan.phase {
        case .idle:
            return []
        case .finished:
            // 鳴らすのは結果に入った時刻（`now`）。同じ挑戦の結果で遊び方を開閉する・バックグラウンドから戻るたびに
            // 出し直されるので、鍵は最後の球の時刻にする（1 挑戦に 1 回だけ鳴る）。
            guard unlockedAtFinish else { return [] }
            return [HomerunSoundCue(at: now, sound: .achievement, identity: plan.clock?.pitchStart ?? .distantPast)]
        case .pitching:
            guard let clock = plan.clock else { return [] }
            // 怒りマークは構えに入った瞬間（マシンが込め始める時刻）から出ている。
            if plan.faceMark.showsAngryMark {
                cues.append(HomerunSoundCue(at: clock.pitchStart.addingTimeInterval(-HomerunModel.windup), sound: .angry))
            }
            if let bannerShownAt { cues.append(HomerunSoundCue(at: bannerShownAt, sound: .achievement)) }
            cues.append(HomerunSoundCue(at: clock.pitchStart, sound: .machine))
            if let practice = clock.practiceSwingAt { cues.append(HomerunSoundCue(at: practice, sound: .swing)) }
            // 見送り: 振らずに締め切り（輪が重なって 0.3 秒後）を待つ間に、球はミットに入る。
            cues.append(HomerunSoundCue(at: mittTime(clock), sound: .mitt))
        case .ballResult:
            guard let clock = plan.clock else { return [] }
            if let release = clock.releasedAt { cues.append(HomerunSoundCue(at: release, sound: .swing)) }
            if let practice = clock.practiceSwingAt, practice > (clock.releasedAt ?? .distantPast) {
                cues.append(HomerunSoundCue(at: practice, sound: .swing))
            }
            guard let ball = plan.lastBall else { break }
            if ball.kind == .miss {
                cues.append(HomerunSoundCue(at: mittTime(clock), sound: .mitt))
                if plan.whiffGag, let release = clock.releasedAt {
                    let start = HomerunSwingContact.swingStart(release: release, offsetMilliseconds: clock.timingOffset ?? 0,
                                                               column: plan.column)
                    let sinceStart = (fallFrame - 1) / HomerunWhiffGag.frameRate - HomerunBatterMotion.loadDuration
                    cues.append(HomerunSoundCue(at: start.addingTimeInterval(sinceStart), sound: .fall))
                }
                break
            }
            guard let contact = plan.contactAt else { break }
            cues.append(HomerunSoundCue(at: contact, sound: hitSound(for: ball)))
            if ball.isTankobu {
                if let start = plan.tankobuStart {
                    cues.append(HomerunSoundCue(at: start.addingTimeInterval(HomerunTankobuGag.impactDelay), sound: .tankobu))
                }
            } else if ball.isMoon {
                cues.append(HomerunSoundCue(at: contact.addingTimeInterval(moonRiseDelay), sound: .moonRise))
                cues.append(HomerunSoundCue(at: contact.addingTimeInterval(HomerunMoonShot.impact), sound: .moonCrack))
            } else if ball.kind == .homer, let track = plan.chaseTrack {
                // ジャストミートのヒットストップ（#1775）のぶん、打球の時間は実時刻より遅れて進む。
                let held = HomerunJustMeet.applies(to: ball) ? HomerunJustMeet.extraDuration : 0
                if ball.isPoleHit {
                    // ポール直撃の道は、最初の区間がポールに当たる所で終わる。
                    cues.append(HomerunSoundCue(at: contact.addingTimeInterval(held + track.flightDuration), sound: .foulPole))
                } else if ball.isOutOfPark {
                    // 場外はスタンドに落ちないので、柵を越える瞬間に沸かせる。
                    cues.append(HomerunSoundCue(at: contact.addingTimeInterval(held + fenceCrossing(track, fence: ball.fence)),
                                                sound: .outOfPark))
                } else {
                    cues.append(HomerunSoundCue(at: contact.addingTimeInterval(held + track.flightDuration), sound: .homerun))
                }
            }
        }
        return cues
    }

    /// 当たりの音。ジャストミート（J4 の止め）> 芯（柵越え・月・ジャスト）> 詰まり（ファウル・たんこぶ・端で当てたゴロ / ポップ）> 普通。
    static func hitSound(for ball: HomerunBattedBall) -> HomerunSound {
        if HomerunJustMeet.applies(to: ball) { return .justMeet }
        if ball.isTankobu || ball.kind == .foul { return .hitWeak }
        if ball.isMoon || ball.kind == .homer || ball.timing == .just { return .hitJust }
        if ball.timing == .hit, ball.launch == .grounder || ball.launch == .pop { return .hitWeak }
        return .hitGood
    }

    /// 投球がミットに収まる時刻（打たなかった球）。3D の球と同じ式（`HomerunBallFlight.pitchPosition`・輪が重なって約 0.07 秒後）。
    /// ただし当たり窓の終わり（輪が重なって `HomerunTiming.hitWindow` 後）より前には鳴らさない: 投球中に予定した音なので、
    /// 窓の終わり際に振って当てた球で「バスッ」の後に「カーン」が鳴ってしまう（差は約 0.04 秒で聞き分けられない）。
    static func mittTime(_ clock: HomerunModel.BallClock) -> Date {
        let column = HomerunSwingContact.column(zone: clock.zone)
        let travel = clock.arrival.timeIntervalSince(clock.pitchStart)
        let reach = HomerunBallFlight.mittReach(target: HomerunSwingContact.approachTarget(column: column),
                                                mitt: HomerunBallFlight.mittPoint(), travel: travel)
        return clock.arrival.addingTimeInterval(max(reach, HomerunTiming.hitWindow / 1000 + 0.01))
    }

    /// 打球が柵の上を越える（本塁からの水平距離が柵に達する）までの時間（打球の道の時刻・秒）。届かなければ飛んでいる時間。
    static func fenceCrossing(_ track: HomerunBallChase.Track, fence: Double) -> TimeInterval {
        let step = 1.0 / 120
        var t = 0.0
        while t < track.flightDuration {
            if track.point(at: t).s >= fence { return t }
            t += step
        }
        return track.flightDuration
    }
}

/// 鳴らす予定（`HomerunSoundCues`）を時刻まで待って鳴らす。進行（`step`）が変わる・素振りが入るたびに予定を出し直す。
/// 止めている間（一時停止・バックグラウンド・遊び方のシート）は鳴らさない。
struct HomerunSoundPlayer: ViewModifier {
    let model: HomerunModel
    let service: HomerunSoundService

    /// 予定を出し直した時点で少し過ぎていても鳴らす幅（秒）。離した瞬間の風切りは `step` が進んだ直後に出し直すため。
    static let lateTolerance: TimeInterval = 0.25

    /// 鳴らした予定（出し直しで同じ音を 2 回鳴らさない）。描画とは無関係なので観測しない入れ物にする。
    @State private var played = Played()

    final class Played {
        var keys: [HomerunSoundCue.Key: Date] = [:]

        /// 初めてなら記録して true。古い記録（鳴らしてから 10 分）は捨てる。
        func insert(_ cue: HomerunSoundCue, now: Date) -> Bool {
            keys = keys.filter { now.timeIntervalSince($0.value) < 600 }
            guard keys[cue.key] == nil else { return false }
            keys[cue.key] = now
            return true
        }
    }

    private struct Key: Hashable {
        var step: Int
        var practice: Date?
    }

    func body(content: Content) -> some View {
        content
            .onAppear { service.prepare() }
            .task(id: Key(step: model.step, practice: model.ballClock?.practiceSwingAt)) { await run() }
    }

    private func run() async {
        guard !model.isHeld else { return }
        let start = Date()
        let shownAt = model.unlockBanner.isEmpty ? nil : model.unlockBannerUntil?.addingTimeInterval(-HomerunModel.unlockBannerDuration)
        let cues = HomerunSoundCues.cues(plan: HomerunSwingPlan(model: model), bannerShownAt: shownAt,
                                         unlockedAtFinish: model.unlockedAtFinish, now: start)
            .filter { start.timeIntervalSince($0.at) <= Self.lateTolerance }
            .sorted { $0.at < $1.at }
        for cue in cues {
            let wait = cue.at.timeIntervalSinceNow
            if wait > 0 {
                do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            }
            guard !Task.isCancelled, !model.isHeld else { return }
            guard played.insert(cue, now: Date()) else { continue }
            service.play(cue.sound)
            // 録画に音を重ねるための記録（どの音をいつ鳴らしたか・壁時計の秒）。DEBUG ビルドだけ（判定は `HomerunDebugOverrides`）。
            if HomerunDebugOverrides.isDebugBuild {
                print(String(format: "[HomerunSFX] %.3f %@", Date().timeIntervalSince1970, cue.sound.rawValue))
            }
        }
    }
}
