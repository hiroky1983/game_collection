import SwiftUI

// MARK: - 未サインイン

/// Game Center にサインインしていない人のランキングページ（会長決定 2026-10-08: 「登録すると見られます」の案内だけ）。
struct SignedOutRankingPage: View {
    var onNext: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 12) {
                    OjisanImage().frame(width: 120, height: 120)
                    Text("ランキングは Game Center に登録すると見られます")
                        .themeBody(17, weight: .heavy).foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    Text("週間ランキングは Game Center の仕組みを使っています。設定アプリで Game Center にサインインすると、次の挑戦から今週の順位が出ます。")
                        .themeBody(13).foregroundStyle(Theme.inkSub)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {} label: {
                        Label("Game Center の設定を開く", systemImage: "gearshape.fill")
                            .themeBody(15).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).controlSize(.large).tint(Theme.coral)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .popCard()

                VStack(spacing: 4) {
                    Text("毎週月曜 0:00 に切り替わります。1 人 1 件（その週の自己ベスト）")
                        .themeCaption(11).foregroundStyle(Theme.inkSub)
                    Text("ランキングは予告なく終了する場合があります")
                        .themeCaption(11).foregroundStyle(Theme.inkSub)
                }
                .multilineTextAlignment(.center)

                Button(action: onNext) {
                    HStack(spacing: 8) {
                        Text("結果を見る").themeBody(18)
                        Image(systemName: "chevron.right").scaledFont(15, weight: .bold)
                    }
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(Theme.Fill.coral)
                .padding(.top, 6)
            }
            .padding(Theme.pad)
        }
        .popBackground()
    }
}

// MARK: - リザルト（演出）の写し

/// 10 球が終わった直後の演出（`HomerunFinaleView` の「グッド！」）の見た目だけの写し。タップで次へ。
struct FinaleMockPage: View {
    let homers: Int
    let total: Int
    var onTap: () -> Void = {}

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let side = min(size.width * 0.58, 250.0) * 1.15
            ZStack {
                Color.black
                LinearGradient(colors: [Color(red: 0.45, green: 0.8, blue: 1.0), Color(red: 0.2, green: 0.5, blue: 0.9)],
                               startPoint: .top, endPoint: .bottom).opacity(0.92)
                TimelineView(.animation) { ctx in
                    Rays(rays: 16)
                        .fill(.white.opacity(0.14))
                        .frame(width: size.height * 1.4, height: size.height * 1.4)
                        .rotationEffect(.degrees(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 20) * 18))
                        .position(x: size.width / 2, y: size.height * 0.47)
                }
                VStack(spacing: 0) {
                    Spacer().frame(height: size.height * 0.15)
                    Text("グッド！")
                        .font(.system(size: 58, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: Color(red: 0.05, green: 0.25, blue: 0.6), radius: 0, x: 0, y: 5)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 6)
                    Image(uiImage: bundleImage("HomerunFinaleGood")).resizable().scaledToFit()
                        .frame(width: side, height: side)
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                        .padding(.top, 10)
                    HStack(spacing: 10) {
                        statChip("柵越え", "\(homers) 本")
                        statChip("合計", "\(RankText.group(total)) m")
                    }
                    .padding(.top, 14)
                    Text("ニューレコード！")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .frame(width: size.width)
                        .background(LinearGradient(colors: [Color(red: 0.95, green: 0.15, blue: 0.35), Color(red: 1, green: 0.4, blue: 0.2)],
                                                   startPoint: .leading, endPoint: .trailing))
                        .overlay(Rectangle().stroke(.yellow, lineWidth: 3).padding(.vertical, 3))
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
                        .padding(.top, 18)
                    Spacer()
                    Text("タップで次へ")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.bottom, size.height * 0.06)
                }
                .frame(width: size.width, height: size.height)
            }
            .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func statChip(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: label).font(.system(size: 12, weight: .bold)).foregroundStyle(Color(white: 0.35))
            Text(verbatim: value).font(.system(size: 22, weight: .black, design: .rounded)).monospacedDigit()
                .foregroundStyle(Color(white: 0.2))
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.92)))
    }
}

struct Rays: Shape {
    let rays: Int
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = max(rect.width, rect.height)
        for i in 0..<rays {
            let a0 = Double(i) / Double(rays) * 2 * .pi
            let a1 = a0 + .pi / Double(rays)
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x + r * cos(a0), y: c.y + r * sin(a0)))
            p.addLine(to: CGPoint(x: c.x + r * cos(a1), y: c.y + r * sin(a1)))
            p.closeSubpath()
        }
        return p
    }
}

// MARK: - 結果ページの写し

/// 結果ページ（`HomerunResultView`）の見た目だけの写し。ランキングから戻って来る先。
struct ResultMockPage: View {
    let homers: Int
    let total: Int
    let rank: Int
    let rankDelta: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    OjisanImage().frame(width: 80, height: 80)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("10 球の結果").themeCaption(13).foregroundStyle(Theme.inkSub)
                        Text(verbatim: "\(RankText.group(total)) m")
                            .scaledFont(44, weight: .black, design: .rounded).monospacedDigit()
                            .foregroundStyle(Theme.ink)
                        HStack(spacing: 6) {
                            Chip(text: "柵越え \(homers) 本", systemImage: "flag.checkered", fill: Theme.Fill.yellow)
                            Chip(text: "ベスト更新！", fill: Theme.Fill.pink)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .popCard()

                // ランキングへ戻る 1 行（提案: 結果ページからも今週の順位を見返せるように）。
                HStack {
                    Label("今週のランキング", systemImage: "trophy.fill").themeBody(16).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(verbatim: "\(rank)位").themeBody(16, weight: .heavy).foregroundStyle(Theme.ink)
                    if rankDelta > 0 { Chip(text: "↑ \(rankDelta)", fill: Theme.Fill.pink) }
                    Image(systemName: "chevron.right").scaledFont(13, weight: .bold).foregroundStyle(Theme.inkSub)
                }
                .padding(14)
                .popCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("1 球ずつ").themeBody(16).foregroundStyle(Theme.ink)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                        ForEach(0..<10, id: \.self) { i in
                            let homer = [0, 2, 3, 5, 6, 9].contains(i)
                            let miss = i == 7
                            VStack(spacing: 2) {
                                Image(systemName: homer ? "flag.checkered" : miss ? "xmark" : "baseball.fill")
                                    .scaledFont(16, weight: .bold)
                                    .foregroundStyle(homer ? Theme.yellow : miss ? Theme.inkSub : Theme.teal)
                                Text(verbatim: miss ? "空振り" : "\([152, 98, 141, 138, 101, 160, 133, 0, 118, 165][i]) m")
                                    .themeCaption(11).foregroundStyle(Theme.ink)
                                Text(verbatim: "\(i + 1) 球目").themeCaption(9).foregroundStyle(Theme.inkSub)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: Theme.cornerSmall)
                                .fill(homer ? Theme.Fill.yellow.opacity(0.25) : Theme.fillMuted.opacity(0.12)))
                        }
                    }
                }
                .padding(14)
                .popCard()

                Button {} label: {
                    HStack(spacing: 12) {
                        Label("もう一回", systemImage: "figure.baseball").themeBody(18).foregroundStyle(Theme.onAccent)
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                Image(systemName: "baseball.fill").scaledFont(20)
                                    .foregroundStyle(i < 1 ? .white : Theme.onAccent.opacity(0.25))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
                .padding(.top, 6)
                Button {} label: {
                    Text("打席前へ").themeBody(16).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large).tint(Theme.coral)
            }
            .padding(Theme.pad)
        }
        .popBackground()
    }
}
