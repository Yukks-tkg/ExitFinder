#!/usr/bin/env swift
// generate_icon.swift
// プロジェクトルートで実行: swift generate_icon.swift
// → ExitFinder/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png を生成します

import AppKit
import CoreGraphics

// ─────────────────────────────────────────────
// MARK: - 描画設定
// ─────────────────────────────────────────────

let size: CGFloat = 1024

// ─────────────────────────────────────────────
// MARK: - ヘルパー
// ─────────────────────────────────────────────

extension CGContext {
    func setFillGradient(colors: [(CGFloat, CGFloat, CGFloat, CGFloat)],
                         locations: [CGFloat],
                         start: CGPoint,
                         end: CGPoint) {
        let cgColors = colors.map {
            CGColor(red: $0.0, green: $0.1, blue: $0.2, alpha: $0.3)
        }
        let space = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: space,
                                        colors: cgColors as CFArray,
                                        locations: locations) else { return }
        drawLinearGradient(gradient, start: start, end: end, options: [])
    }
}

// ─────────────────────────────────────────────
// MARK: - アイコン描画
// ─────────────────────────────────────────────

func drawIcon(ctx: CGContext, s: CGFloat) {
    let cx = s / 2
    let cy = s / 2

    // ── 背景グラデーション ──
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    ctx.addRect(bgRect)
    ctx.clip()
    ctx.setFillGradient(
        colors: [
            (0.09, 0.10, 0.24, 1),
            (0.04, 0.12, 0.28, 1)
        ],
        locations: [0, 1],
        start: CGPoint(x: 0, y: s),
        end:   CGPoint(x: s, y: 0)
    )
    ctx.resetClip()

    // ── 外周リング ──
    let ringR1 = s * 0.365
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
    ctx.setLineWidth(s * 0.007)
    ctx.addEllipse(in: CGRect(x: cx - ringR1, y: cy - ringR1,
                              width: ringR1 * 2, height: ringR1 * 2))
    ctx.strokePath()

    // ── 内周リング ──
    let ringR2 = s * 0.275
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.07))
    ctx.setLineWidth(s * 0.003)
    ctx.addEllipse(in: CGRect(x: cx - ringR2, y: cy - ringR2,
                              width: ringR2 * 2, height: ringR2 * 2))
    ctx.strokePath()

    // ── 目盛り（16 方位） ──
    for i in 0..<16 {
        let isCardinal = i % 4 == 0
        let isNorth    = i == 0
        let angleDeg   = Double(i) * 22.5 - 90   // 0° = 上
        let angleRad   = angleDeg * .pi / 180

        let tickH: CGFloat = isCardinal ? s * 0.054 : s * 0.027
        let tickW: CGFloat = isCardinal ? s * 0.009 : s * 0.005
        let alpha: CGFloat = isNorth ? 1.0 : (isCardinal ? 0.55 : 0.22)

        let color: CGColor = isNorth
            ? CGColor(red: 1.00, green: 0.88, blue: 0.00, alpha: 1.00)
            : CGColor(red: 1, green: 1, blue: 1, alpha: alpha)

        let dist = ringR1 - tickH / 2

        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: CGFloat(angleRad))
        ctx.translateBy(x: 0, y: -dist)

        let tickRect = CGRect(x: -tickW / 2, y: -tickH / 2,
                              width: tickW, height: tickH)
        let tickPath = CGPath(roundedRect: tickRect,
                              cornerWidth: tickW / 2,
                              cornerHeight: tickW / 2,
                              transform: nil)
        ctx.setFillColor(color)
        ctx.addPath(tickPath)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // ── 出口矢印（黄色グラデーション）──
    let arrowW = s * 0.22
    let arrowH = s * 0.36
    let arrowX = cx - arrowW / 2
    let arrowY = cy - arrowH / 2

    let headH  = arrowH * 0.42
    let stemW  = arrowW * 0.37
    let stemX  = arrowX + (arrowW - stemW) / 2

    // CoreGraphics の Y 軸は下向きなので、矢印の向きを上に合わせるため反転座標で描く
    let arrowPath = CGMutablePath()
    arrowPath.move(to:      .init(x: cx,              y: arrowY))            // 先端（上）
    arrowPath.addLine(to:   .init(x: arrowX + arrowW, y: arrowY + headH))   // 右肩
    arrowPath.addLine(to:   .init(x: stemX + stemW,   y: arrowY + headH))   // 右内
    arrowPath.addLine(to:   .init(x: stemX + stemW,   y: arrowY + arrowH))  // 右下
    arrowPath.addLine(to:   .init(x: stemX,            y: arrowY + arrowH)) // 左下
    arrowPath.addLine(to:   .init(x: stemX,            y: arrowY + headH))  // 左内
    arrowPath.addLine(to:   .init(x: arrowX,           y: arrowY + headH))  // 左肩
    arrowPath.closeSubpath()

    // 矢印グロー（影）
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.05,
                  color: CGColor(red: 1, green: 0.85, blue: 0, alpha: 0.50))
    ctx.addPath(arrowPath)
    ctx.setFillColor(CGColor(red: 1, green: 0.88, blue: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // 矢印本体グラデーション
    ctx.saveGState()
    ctx.addPath(arrowPath)
    ctx.clip()
    ctx.setFillGradient(
        colors: [
            (1.00, 0.88, 0.00, 1),
            (1.00, 0.68, 0.00, 1)
        ],
        locations: [0, 1],
        start: CGPoint(x: cx, y: arrowY),
        end:   CGPoint(x: cx, y: arrowY + arrowH)
    )
    ctx.resetClip()
    ctx.restoreGState()

    // ── 中心点 ──
    let dotR = s * 0.013
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.012,
                  color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.70))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.90))
    ctx.addEllipse(in: CGRect(x: cx - dotR, y: cy - dotR,
                              width: dotR * 2, height: dotR * 2))
    ctx.fillPath()
    ctx.restoreGState()
}

// ─────────────────────────────────────────────
// MARK: - PNG 生成 & 保存
// ─────────────────────────────────────────────

let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
guard let ctx = CGContext(
    data: nil,
    width:  Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: bitmapInfo.rawValue
) else {
    print("❌ CGContext の作成に失敗")
    exit(1)
}

drawIcon(ctx: ctx, s: size)

guard let cgImage = ctx.makeImage() else {
    print("❌ CGImage の生成に失敗")
    exit(1)
}

let nsImage = NSImage(cgImage: cgImage,
                      size: NSSize(width: size, height: size))
guard let tiff   = nsImage.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png    = bitmap.representation(using: .png, properties: [:]) else {
    print("❌ PNG データの生成に失敗")
    exit(1)
}

let outputPath = "ExitFinder/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
let outputURL  = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent(outputPath)

do {
    try png.write(to: outputURL)
    print("✅ 保存完了: \(outputURL.path)")
} catch {
    print("❌ 保存失敗: \(error)")
    exit(1)
}
