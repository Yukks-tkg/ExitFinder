import SwiftUI

// MARK: - App Icon Design（コンパス × 出口矢印）

struct AppIconView: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {

                // ── 背景グラデーション（ダークネイビー）──
                LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.10, blue: 0.24),
                        Color(red: 0.04, green: 0.12, blue: 0.28)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // ── コンパス 外周リング ──
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: s * 0.007)
                    .frame(width: s * 0.73, height: s * 0.73)

                // ── コンパス 内周リング（淡い） ──
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: s * 0.003)
                    .frame(width: s * 0.55, height: s * 0.55)

                // ── 目盛り（16 方位） ──
                ForEach(0..<16) { i in
                    let isCardinal = i % 4 == 0     // N / S / E / W
                    let isNorth    = i == 0
                    let tickH: CGFloat = isCardinal ? s * 0.054 : s * 0.027
                    let tickW: CGFloat = isCardinal ? s * 0.009 : s * 0.005
                    let ringR = s * 0.365
                    let offset = ringR - tickH / 2

                    Capsule()
                        .fill(
                            isNorth    ? Color.yellow :
                            isCardinal ? Color.white.opacity(0.55) :
                                         Color.white.opacity(0.22)
                        )
                        .frame(width: tickW, height: tickH)
                        .offset(y: -offset)
                        .rotationEffect(.degrees(Double(i) * 22.5))
                }

                // ── 出口矢印（黄色グラデーション）──
                ExitArrowShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.00, green: 0.88, blue: 0.00),
                                Color(red: 1.00, green: 0.68, blue: 0.00)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: s * 0.22, height: s * 0.36)
                    .shadow(color: Color.yellow.opacity(0.50), radius: s * 0.05)

                // ── 中心点 ──
                Circle()
                    .fill(Color.white.opacity(0.90))
                    .frame(width: s * 0.026, height: s * 0.026)
                    .shadow(color: Color.white.opacity(0.70), radius: s * 0.012)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - 上向き矢印シェイプ

struct ExitArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w      = rect.width
        let h      = rect.height
        let headH  = h * 0.42
        let stemW  = w * 0.37
        let stemX  = (w - stemW) / 2

        var p = Path()
        p.move(to:    .init(x: w / 2,          y: 0))       // 先端
        p.addLine(to: .init(x: w,              y: headH))   // 右肩
        p.addLine(to: .init(x: stemX + stemW,  y: headH))   // 右内
        p.addLine(to: .init(x: stemX + stemW,  y: h))       // 右下
        p.addLine(to: .init(x: stemX,          y: h))       // 左下
        p.addLine(to: .init(x: stemX,          y: headH))   // 左内
        p.addLine(to: .init(x: 0,              y: headH))   // 左肩
        p.closeSubpath()
        return p
    }
}

// MARK: - Xcode プレビュー

#Preview("400pt（角丸あり）") {
    AppIconView()
        .frame(width: 400, height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 88, style: .continuous))
        .padding(24)
        .background(Color.black)
}

#Preview("1024pt（等倍）") {
    AppIconView()
        .frame(width: 1024, height: 1024)
        .clipShape(RoundedRectangle(cornerRadius: 224, style: .continuous))
}
