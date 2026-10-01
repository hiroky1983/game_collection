// #1690 対局中の条件表示の置き場所モック（五目並べを代表に、3案 × SE / Pro Max）。
// swiftc -O mock.swift -o mockbin_1690 && ./mockbin_1690 <出力ディレクトリ>
import SwiftUI
import AppKit

let bg = Color(red: 1, green: 0.965, blue: 0.925)
let ink = Color(red: 0.29, green: 0.23, blue: 0.2)
let inkSub = Color(red: 0.604, green: 0.541, blue: 0.502)
let teal = Color(red: 0.133, green: 0.765, blue: 0.745)
let coral = Color(red: 1, green: 0.435, blue: 0.38)

func f(_ s: CGFloat, _ w: Font.Weight = .semibold) -> Font { .system(size: s, weight: w, design: .rounded) }

struct Card<C: View>: View {
    let c: C
    init(@ViewBuilder _ c: () -> C) { self.c = c() }
    var body: some View {
        c.background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white)
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2))
    }
}

struct Chip: View {
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Text(text).font(f(12, .bold)).lineLimit(1)
            Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(Color(red: 0.93, green: 0.9, blue: 0.87)))
    }
}

enum Variant { case a, b, c }

struct Screen: View {
    let w: CGFloat, h: CGFloat, v: Variant
    let cond = "ふつう・先手"
    var body: some View {
        let safeTop: CGFloat = h > 800 ? 62 : 20
        let navH: CGFloat = v == .a ? 44 + 16 : 44
        VStack(spacing: 0) {
            Color.clear.frame(height: safeTop)
            // ナビバー
            ZStack {
                HStack {
                    Image(systemName: "chevron.left").foregroundStyle(coral).font(.system(size: 17, weight: .semibold))
                    Spacer()
                    HStack(spacing: 14) {
                        Image(systemName: "questionmark.circle"); Image(systemName: "plus.circle")
                    }.foregroundStyle(coral).font(.system(size: 18))
                }.padding(.horizontal, 16)
                VStack(spacing: 1) {
                    Text("五目並べ").font(f(20, .bold)).foregroundStyle(ink)
                    if v == .a { Chip(text: cond).scaleEffect(0.95) }
                }
            }.frame(height: navH)
            VStack(spacing: 8) {
                // ステータス帯
                Card {
                    HStack(spacing: 8) {
                        Text("あなたの番").font(f(14, .bold)).foregroundStyle(ink)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(Color(red: 0.2, green: 0.78, blue: 0.75)))
                        Spacer()
                        if v == .b { Chip(text: cond) }
                        Text("12手").font(f(13)).foregroundStyle(inkSub)
                    }.padding(.horizontal, 12).frame(height: 44)
                }
                stoneRow("CPU", white: true)
                GeometryReader { g in
                    let side = min(g.size.width, g.size.height)
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(red: 0.871, green: 0.71, blue: 0.408))
                        Canvas { ctx, size in
                            let pad: CGFloat = 14, n = 15
                            let sp = (size.width - pad * 2) / CGFloat(n - 1)
                            var p = Path()
                            for i in 0..<n {
                                let x = pad + sp * CGFloat(i)
                                p.move(to: CGPoint(x: x, y: pad)); p.addLine(to: CGPoint(x: x, y: size.height - pad))
                                p.move(to: CGPoint(x: pad, y: x)); p.addLine(to: CGPoint(x: size.width - pad, y: x))
                            }
                            ctx.stroke(p, with: .color(.black.opacity(0.55)), lineWidth: 0.7)
                            let stones: [(Int, Int, Bool)] = [(7,7,false),(7,8,true),(8,8,false),(6,6,true),(8,6,false),(9,9,true),(6,8,false),(8,7,true),(9,7,false),(10,7,true),(5,9,false),(6,7,true)]
                            for (r, c, white) in stones {
                                let d = sp * 0.86
                                let rect = CGRect(x: pad + sp * CGFloat(c) - d / 2, y: pad + sp * CGFloat(r) - d / 2, width: d, height: d)
                                ctx.fill(Path(ellipseIn: rect), with: .color(white ? .white : .black))
                                if white { ctx.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.4)), lineWidth: 0.6) }
                            }
                        }
                    }
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }.layoutPriority(1)
                stoneRow("あなた", white: false)
                // 「⋯」行
                HStack {
                    if v == .c { Chip(text: cond) }
                    Spacer()
                    Text("⋯").font(.system(size: 22, weight: .bold)).foregroundStyle(ink)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.white).shadow(color: .black.opacity(0.08), radius: 3, y: 1))
                }.frame(height: 46)
                Text("遊び方：先に5つ並べたら勝ち").font(f(12)).foregroundStyle(inkSub)
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.25)).frame(height: 50)
                    .overlay(Text("広告").font(f(11)).foregroundStyle(inkSub))
            }.padding(16)
        }
        .frame(width: w, height: h, alignment: .top)
        .background(bg)
    }
    func stoneRow(_ name: String, white: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(white ? .white : .black).overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 0.6)).frame(width: 14, height: 14)
            Text(name).font(f(12)).foregroundStyle(inkSub)
            Spacer()
        }.padding(.horizontal, 4)
    }
}

@MainActor func render(_ v: Variant, w: CGFloat, h: CGFloat, to path: String) {
    let r = ImageRenderer(content: Screen(w: w, h: h, v: v))
    r.scale = 2
    guard let cg = r.cgImage else { print("fail", path); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

MainActor.assumeIsolated {
    let out = CommandLine.arguments.dropFirst().first ?? "."
    for (name, v) in [("A", Variant.a), ("B", .b), ("C", .c)] {
        render(v, w: 375, h: 667, to: "\(out)/1690-mock-\(name)-se.png")
        render(v, w: 440, h: 956, to: "\(out)/1690-mock-\(name)-promax.png")
    }
}
