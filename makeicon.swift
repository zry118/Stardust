// makeicon — 生成「星砂 Stardust」的应用图标
//
// 设计意图：俯视一个旋涡星系。中心是炽白的核，
// 四条旋臂由细密的光点组成，从白 → 青 → 蓝 → 紫向外衰减。
// 一眼就知道这是粒子引力沙盘。
//
// 编译运行：
//   swiftc -O makeicon.swift -o makeicon && ./makeicon && iconutil -c icns Stardust.iconset -o Stardust.icns

import AppKit
import CoreGraphics
import Foundation

let S: CGFloat = 1024
let outDir = "Stardust.iconset"

// 按 macOS 规范：824pt 居中，圆角 185
let INSET: CGFloat = 100
let SIDE: CGFloat = 824
let RADIUS: CGFloat = 185

func lerp(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> (Double, Double, Double) {
    (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
}

/// 沿半径取色：白 → 薄荷 → 青 → 蓝 → 紫
func armColor(_ t: Double) -> (Double, Double, Double) {
    let stops: [(Double, (Double, Double, Double))] = [
        (0.00, (1.00, 1.00, 1.00)),
        (0.16, (0.80, 1.00, 0.94)),
        (0.34, (0.42, 0.96, 0.84)),
        (0.54, (0.28, 0.72, 1.00)),
        (0.76, (0.42, 0.40, 0.98)),
        (1.00, (0.55, 0.24, 0.80)),
    ]
    let x = min(max(t, 0), 1)
    for i in 1..<stops.count {
        if x <= stops[i].0 {
            let a = stops[i - 1], b = stops[i]
            let u = (x - a.0) / (b.0 - a.0)
            return lerp(a.1, b.1, u)
        }
    }
    return stops[stops.count - 1].1
}

func render(_ px: Int) -> Data {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: px, height: px,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("no ctx")
    }
    let k = CGFloat(px) / S
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: k, y: k)

    // 圆角方底
    let body = CGRect(x: INSET, y: INSET, width: SIDE, height: SIDE)
    let shape = CGPath(roundedRect: body, cornerWidth: RADIUS, cornerHeight: RADIUS, transform: nil)
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // 背景：中心偏紫，向外沉到近黑
    let bg = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.105, green: 0.072, blue: 0.225, alpha: 1),
        CGColor(red: 0.038, green: 0.028, blue: 0.090, alpha: 1),
        CGColor(red: 0.016, green: 0.012, blue: 0.038, alpha: 1),
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawRadialGradient(bg,
                           startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 512), endRadius: 640,
                           options: [.drawsAfterEndLocation])

    let cx: CGFloat = 512, cy: CGFloat = 512

    // 外围星尘（稀疏背景点）
    var rng = SystemRandomNumberGenerator()
    for _ in 0..<260 {
        let a = Double.random(in: 0...(2 * .pi), using: &rng)
        let r = Double.random(in: 0...410, using: &rng)
        let x = cx + CGFloat(cos(a) * r)
        let y = cy + CGFloat(sin(a) * r)
        let sz = CGFloat(Double.random(in: 0.9...2.6, using: &rng))
        let al = Double.random(in: 0.06...0.30, using: &rng) * (1 - r / 480)
        ctx.setFillColor(CGColor(red: 0.85, green: 0.92, blue: 1.0, alpha: al))
        ctx.fillEllipse(in: CGRect(x: x - sz, y: y - sz, width: sz * 2, height: sz * 2))
    }

    // 盘面弥散光：让旋臂底下有一层雾，不至于悬在纯黑上
    let disc = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.45, green: 0.62, blue: 1.00, alpha: 0.16),
        CGColor(red: 0.36, green: 0.34, blue: 0.86, alpha: 0.09),
        CGColor(red: 0.24, green: 0.16, blue: 0.55, alpha: 0.0),
    ] as CFArray, locations: [0, 0.45, 1])!
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)
    ctx.scaleBy(x: 1.0, y: 0.62)
    ctx.drawRadialGradient(disc,
                           startCenter: .zero, startRadius: 0,
                           endCenter: .zero, endRadius: 430,
                           options: [])
    ctx.restoreGState()

    // 旋臂：两条主臂 + 两条副臂，副臂更暗更细
    struct Arm { let base: Double; let weight: Double }
    let arms = [
        Arm(base: 0.55, weight: 1.00),
        Arm(base: 0.55 + .pi, weight: 1.00),
        Arm(base: 0.55 + .pi / 2, weight: 0.42),
        Arm(base: 0.55 + .pi * 1.5, weight: 0.42),
    ]

    for arm in arms {
        let steps = 620
        for i in 0..<steps {
            let t = Double(i) / Double(steps - 1)
            let r = 44 + pow(t, 0.88) * 372
            let ang = arm.base + t * 1.62 * .pi
            let spread = 17 + t * 56
            let rr = r + Double.random(in: -spread...spread, using: &rng)
            let aa = ang + Double.random(in: -0.10...0.10, using: &rng)

            let x = cx + CGFloat(cos(aa) * rr)
            let y = cy + CGFloat(sin(aa) * rr)

            let col = armColor(t)
            // 中心附近点会大量重叠，先把亮度压下去，免得糊成一团白
            let coreFade = 0.42 + 0.58 * min(t / 0.20, 1.0)
            let fade = (1 - t * 0.34) * coreFade * arm.weight
                     * Double.random(in: 0.72...1.0, using: &rng)
            let sz = CGFloat((3.6 - t * 1.7) * Double.random(in: 0.55...1.35, using: &rng))

            // 外晕
            ctx.setFillColor(CGColor(red: col.0, green: col.1, blue: col.2, alpha: fade * 0.16))
            ctx.fillEllipse(in: CGRect(x: x - sz * 2.6, y: y - sz * 2.6,
                                       width: sz * 5.2, height: sz * 5.2))
            // 亮芯
            ctx.setFillColor(CGColor(red: col.0, green: col.1, blue: col.2, alpha: fade))
            ctx.fillEllipse(in: CGRect(x: x - sz, y: y - sz, width: sz * 2, height: sz * 2))
        }
    }

    // 核心光晕
    let core = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.92),
        CGColor(red: 0.78, green: 1.0, blue: 0.99, alpha: 0.50),
        CGColor(red: 0.42, green: 0.82, blue: 1.0, alpha: 0.14),
        CGColor(red: 0.34, green: 0.52, blue: 1.0, alpha: 0.0),
    ] as CFArray, locations: [0, 0.12, 0.38, 1])!
    ctx.drawRadialGradient(core,
                           startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cy), endRadius: 132,
                           options: [])

    // 核点
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: cx - 11, y: cy - 11, width: 22, height: 22))

    ctx.restoreGState()

    // 一圈极淡的内描边，让边缘从纯黑背景里浮起来
    ctx.addPath(shape)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.setLineWidth(2.5)
    ctx.strokePath()

    guard let img = ctx.makeImage() else { fatalError("no image") }
    let rep = NSBitmapImageRep(cgImage: img)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
    return data
}

// MARK: - 输出

let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try! fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for s in sizes {
    let data = render(s)
    let name = "\(outDir)/icon_\(s)x\(s).png"
    try! data.write(to: URL(fileURLWithPath: name))
    // Retina 变体
    if s <= 512 {
        let data2 = render(s * 2)
        let name2 = "\(outDir)/icon_\(s)x\(s)@2x.png"
        try! data2.write(to: URL(fileURLWithPath: name2))
    }
    print("  \(name)")
}
print("完成：\(outDir)")
