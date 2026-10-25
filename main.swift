import SwiftUI
import AppKit
import QuartzCore

// MARK: - 主题

enum Theme: Int, CaseIterable, Identifiable {
    case aurora, ember, abyss, mono

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .aurora: return "极光"
        case .ember:  return "熔岩"
        case .abyss:  return "深海"
        case .mono:   return "素白"
        }
    }

    var bg: Color {
        switch self {
        case .aurora: return Color(red: 0.020, green: 0.018, blue: 0.042)
        case .ember:  return Color(red: 0.042, green: 0.018, blue: 0.014)
        case .abyss:  return Color(red: 0.010, green: 0.022, blue: 0.048)
        case .mono:   return Color(red: 0.032, green: 0.032, blue: 0.036)
        }
    }

    /// 8 档速度色，从慢到快
    var ramp: [Color] {
        switch self {
        case .aurora:
            return [
                Color(red: 0.26, green: 0.15, blue: 0.56),
                Color(red: 0.31, green: 0.27, blue: 0.88),
                Color(red: 0.27, green: 0.51, blue: 0.99),
                Color(red: 0.22, green: 0.77, blue: 0.95),
                Color(red: 0.35, green: 0.95, blue: 0.81),
                Color(red: 0.71, green: 1.00, blue: 0.89),
                Color(red: 0.92, green: 1.00, blue: 0.98),
                Color(red: 1.00, green: 1.00, blue: 1.00),
            ]
        case .ember:
            return [
                Color(red: 0.38, green: 0.06, blue: 0.11),
                Color(red: 0.64, green: 0.11, blue: 0.13),
                Color(red: 0.86, green: 0.23, blue: 0.10),
                Color(red: 0.97, green: 0.41, blue: 0.08),
                Color(red: 1.00, green: 0.63, blue: 0.17),
                Color(red: 1.00, green: 0.81, blue: 0.43),
                Color(red: 1.00, green: 0.94, blue: 0.75),
                Color(red: 1.00, green: 1.00, blue: 0.99),
            ]
        case .abyss:
            return [
                Color(red: 0.07, green: 0.11, blue: 0.36),
                Color(red: 0.11, green: 0.23, blue: 0.64),
                Color(red: 0.15, green: 0.41, blue: 0.87),
                Color(red: 0.21, green: 0.63, blue: 0.99),
                Color(red: 0.35, green: 0.85, blue: 0.99),
                Color(red: 0.61, green: 0.96, blue: 1.00),
                Color(red: 0.85, green: 1.00, blue: 1.00),
                Color(red: 1.00, green: 1.00, blue: 1.00),
            ]
        case .mono:
            return [
                Color(white: 0.30), Color(white: 0.42), Color(white: 0.54),
                Color(white: 0.66), Color(white: 0.78), Color(white: 0.88),
                Color(white: 0.95), Color(white: 1.00),
            ]
        }
    }
}

// MARK: - 数据结构

struct Particle {
    var x = 0.0, y = 0.0
    var vx = 0.0, vy = 0.0
    /// 近锚点：滞后约 0.09s，决定尾巴的亮段
    var nx = 0.0, ny = 0.0
    /// 远锚点：滞后约 0.38s，让尾巴弯出弧线
    var fx = 0.0, fy = 0.0
}

struct Star {
    var bx = 0.5, by = 0.5
    var ax = 0.0, ay = 0.0
    var sp = 0.2, ph = 0.0
    var mass = 1.0
    var x = 0.5, y = 0.5
    /// 大于 0 时绕主星公转，否则原地微摆
    var orbitR = 0.0
    var orbitW = 0.0
}

struct Grab {
    var x: Double
    var y: Double
    var start: Double
    var push: Bool
}

// MARK: - 模拟

final class Sim: ObservableObject {
    static let G = 0.010
    static let SOFT = 0.0016
    static let VMAX = 0.52

    @Published var tick = 0
    @Published var paused = false
    @Published var theme: Theme = .aurora
    @Published var count = 3000
    @Published var gravity: Double = 1.0

    var particles: [Particle] = []
    var stars: [Star] = []
    var bgStars: [(x: Double, y: Double, s: Double, a: Double)] = []
    var grab: Grab?
    var shake: Double = 0

    private var timer: Timer?
    private var time: Double = 0
    private var last: CFTimeInterval = 0

    init() {
        makeStars()
        makeBgStars()
        spawn(count)
        startTimer()
    }

    // MARK: 初始化

    private func makeStars() {
        stars = [
            Star(bx: 0.50, by: 0.50, ax: 0.0, ay: 0.0, sp: 0.0, ph: 0.0, mass: 1.00,
                 x: 0.50, y: 0.50),
            Star(bx: 0.50, by: 0.50, ax: 0.0, ay: 0.0, sp: 0.0, ph: 1.1, mass: 0.016,
                 x: 0.74, y: 0.50, orbitR: 0.190, orbitW: 0.230),
        ]
    }

    private func makeBgStars() {
        var rng = SystemRandomNumberGenerator()
        bgStars = (0..<300).map { _ in
            (
                x: Double.random(in: -0.02...1.02, using: &rng),
                y: Double.random(in: -0.02...1.02, using: &rng),
                s: Double.random(in: 0.4...1.5, using: &rng),
                a: Double.random(in: 0.06...0.42, using: &rng)
            )
        }
    }

    private func spawn(_ n: Int) {
        guard n > particles.count else {
            particles.removeLast(particles.count - n)
            return
        }
        let host = stars[0]
        for _ in particles.count..<n {
            let r = 0.095 + pow(Double.random(in: 0...1), 1.15) * 0.330
            // 六成粒子贴在两条对数螺旋上，其余散布成盘面
            let spiral = r * 8.6
            let arm = Double.random(in: 0...1) < 0.60 ? 0.0 : .pi
            let jitter = Double.random(in: -0.62...0.62)
            let a = spiral + arm + jitter
            let v = (Self.G / r).squareRoot() * Double.random(in: 0.955...1.045)
            var p = Particle()
            p.x = host.x + cos(a) * r
            p.y = host.y + sin(a) * r
            p.nx = p.x; p.ny = p.y
            p.fx = p.x; p.fy = p.y
            p.vx = -sin(a) * v
            p.vy = cos(a) * v
            particles.append(p)
        }
    }

    func setCount(_ n: Int) {
        let target = max(200, min(4000, n))
        if target < particles.count {
            particles.removeLast(particles.count - target)
        } else if target > particles.count {
            spawn(target)
        }
        count = target
    }

    func reset() {
        particles.removeAll(keepingCapacity: true)
        makeStars()
        spawn(count)
        grab = nil
        shake = 0
        time = 0
    }

    // MARK: 定时器

    func startTimer() {
        stopTimer()
        last = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = CACurrentMediaTime()
            var dt = now - self.last
            self.last = now
            dt = min(max(dt, 1.0 / 240.0), 1.0 / 30.0)
            if !self.paused { self.step(dt) }
            self.tick &+= 1
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: 交互

    func beginGrab(_ x: Double, _ y: Double, push: Bool) {
        grab = Grab(x: x, y: y, start: time, push: push)
    }

    func updateGrab(_ x: Double, _ y: Double) {
        guard var g = grab else { return }
        g.x = x; g.y = y
        grab = g
    }

    func endGrab() {
        grab = nil
    }

    func explode(at x: Double, at y: Double) {
        for i in particles.indices {
            let dx = particles[i].x - x
            let dy = particles[i].y - y
            let d = (dx * dx + dy * dy).squareRoot() + 0.012
            let f = 0.85 / (1 + d * 11)
            particles[i].vx += dx / d * f
            particles[i].vy += dy / d * f
        }
        shake = 9
    }

    // MARK: 物理

    func step(_ dt: Double) {
        time += dt

        for i in stars.indices {
            if stars[i].orbitR > 0 {
                let a = time * stars[i].orbitW + stars[i].ph
                stars[i].x = stars[0].x + cos(a) * stars[i].orbitR
                stars[i].y = stars[0].y + sin(a) * stars[i].orbitR
            } else {
                stars[i].x = stars[i].bx + sin(time * stars[i].sp + stars[i].ph) * stars[i].ax
                stars[i].y = stars[i].by + cos(time * stars[i].sp * 0.71 + stars[i].ph * 1.7) * stars[i].ay
            }
        }

        var sx: [Double] = []
        var sy: [Double] = []
        var sm: [Double] = []
        sx.reserveCapacity(4); sy.reserveCapacity(4); sm.reserveCapacity(4)
        for s in stars { sx.append(s.x); sy.append(s.y); sm.append(s.mass) }
        if let g = grab {
            let grow = min(time - g.start, 2.0)
            let m = (0.7 + grow * 1.7) * (g.push ? -1 : 1)
            sx.append(g.x); sy.append(g.y); sm.append(m)
        }

        let n = sx.count
        let g = Self.G * gravity
        let soft = Self.SOFT
        let vmax2 = Self.VMAX * Self.VMAX
        let host = stars[0]

        particles.withUnsafeMutableBufferPointer { buf in
            for i in 0..<buf.count {
                var p = buf[i]

                var ax = 0.0, ay = 0.0
                var coreR2 = 1.0
                for k in 0..<n {
                    let dx = sx[k] - p.x
                    let dy = sy[k] - p.y
                    let r2 = dx * dx + dy * dy
                    if k == 0 { coreR2 = r2 }
                    let rr = r2 + soft
                    let inv = g * sm[k] / (rr * rr.squareRoot())
                    ax += dx * inv
                    ay += dy * inv
                }

                p.vx += ax * dt
                p.vy += ay * dt

                let v2 = p.vx * p.vx + p.vy * p.vy
                if v2 > vmax2 {
                    let s = Self.VMAX / v2.squareRoot()
                    p.vx *= s; p.vy *= s
                }

                p.x += p.vx * dt
                p.y += p.vy * dt

                // 环绕边界：飞出左边从右边回来
                if p.x < -0.05 { p.x += 1.10; p.nx = p.x; p.fx = p.x }
                else if p.x > 1.05 { p.x -= 1.10; p.nx = p.x; p.fx = p.x }
                if p.y < -0.05 { p.y += 1.10; p.ny = p.y; p.fy = p.y }
                else if p.y > 1.05 { p.y -= 1.10; p.ny = p.y; p.fy = p.y }

                // 拖尾：时间常数与速度成反比，让每颗粒子的尾巴长度大致相同
                // （否则中心高速粒子会叠成一团白）。速度 0.2 时约 0.115 单位。
                let spd = (p.vx * p.vx + p.vy * p.vy).squareRoot()
                let kNear = 1 - exp(-dt * spd / 0.035)
                let kFar  = 1 - exp(-dt * spd / 0.115)
                p.nx += (p.x - p.nx) * kNear
                p.ny += (p.y - p.ny) * kNear
                p.fx += (p.x - p.fx) * kFar
                p.fy += (p.y - p.fy) * kFar

                // 落进核心 → 在外圈重生，形成持续的吸积
                if coreR2 < 0.00130 {
                    let a = Double.random(in: 0...(2 * .pi))
                    let r = 0.36 + Double.random(in: 0...0.06)
                    p.x = host.x + cos(a) * r
                    p.y = host.y + sin(a) * r
                    let v = (Self.G / r).squareRoot() * Double.random(in: 0.90...1.06)
                    p.vx = -sin(a) * v
                    p.vy = cos(a) * v
                    p.nx = p.x; p.ny = p.y
                    p.fx = p.x; p.fy = p.y
                }

                buf[i] = p
            }
        }

        if shake > 0.05 { shake *= pow(0.03, dt) } else { shake = 0 }
    }

    // MARK: 绘制

    func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let side = min(size.width, size.height) * 0.96
        let ox = (size.width - side) / 2
        let oy = (size.height - side) / 2
        let ramp = theme.ramp

        // 背景星点铺满整个窗口
        for s in bgStars {
            let p = CGPoint(x: s.x * size.width, y: s.y * size.height)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - s.s, y: p.y - s.s,
                                            width: s.s * 2, height: s.s * 2)),
                     with: .color(.white.opacity(s.a)))
        }

        // 盘面弥散光：让旋臂底下有雾，不至于浮在纯黑上
        let cp = CGPoint(x: ox + stars[0].x * side, y: oy + stars[0].y * side)
        let discR = side * 0.47
        ctx.fill(Path(ellipseIn: CGRect(x: cp.x - discR, y: cp.y - discR,
                                        width: discR * 2, height: discR * 2)),
                 with: .radialGradient(
                    Gradient(stops: [
                        .init(color: ramp[3].opacity(0.085), location: 0),
                        .init(color: ramp[2].opacity(0.048), location: 0.42),
                        .init(color: ramp[1].opacity(0.016), location: 0.72),
                        .init(color: ramp[0].opacity(0), location: 1),
                    ]),
                    center: cp, startRadius: 0, endRadius: discR))

        // 粒子：按速度分 8 档，每档一条路径，共 16 次描边
        let nearPaths: [CGMutablePath] = (0..<8).map { _ in CGMutablePath() }
        let farPaths:  [CGMutablePath] = (0..<8).map { _ in CGMutablePath() }
        let vRef = 0.44

        for p in particles {
            let hx = ox + p.fx * side
            let hy = oy + p.fy * side
            let mx = ox + p.nx * side
            let my = oy + p.ny * side
            let cx2 = ox + p.x * side
            let cy2 = oy + p.y * side

            // 跨边界的那一帧会拉出长线，跳过
            if abs(cx2 - hx) > side * 0.28 || abs(cy2 - hy) > side * 0.28 { continue }

            let v = (p.vx * p.vx + p.vy * p.vy).squareRoot()
            var b = Int(v / vRef * 8)
            if b > 7 { b = 7 }
            if b < 0 { b = 0 }

            farPaths[b].move(to: CGPoint(x: hx, y: hy))
            farPaths[b].addLine(to: CGPoint(x: mx, y: my))
            nearPaths[b].move(to: CGPoint(x: mx, y: my))
            nearPaths[b].addLine(to: CGPoint(x: cx2, y: cy2))
        }

        for i in 0..<8 {
            let c = ramp[i]
            let w = 1.75 - Double(i) * 0.11
            let glow = 0.20 + Double(i) * 0.018
            let core = 0.40 + Double(i) * 0.048

            // 远段：暗而细，只做余晖
            let far = Path(farPaths[i])
            ctx.stroke(far, with: .color(c.opacity(glow * 0.55)),
                       style: StrokeStyle(lineWidth: w * 2.6, lineCap: .round))
            ctx.stroke(far, with: .color(c.opacity(core * 0.40)),
                       style: StrokeStyle(lineWidth: w * 0.85, lineCap: .round))

            // 近段：亮，是粒子本体
            let near = Path(nearPaths[i])
            ctx.stroke(near, with: .color(c.opacity(glow)),
                       style: StrokeStyle(lineWidth: w * 3.0, lineCap: .round))
            ctx.stroke(near, with: .color(c.opacity(core)),
                       style: StrokeStyle(lineWidth: w, lineCap: .round))
        }

        // 恒星
        for (i, s) in stars.enumerated() {
            let p = CGPoint(x: ox + s.x * side, y: oy + s.y * side)
            let R = side * (i == 0 ? 0.205 : 0.090)
            let c = ramp[i == 0 ? 7 : 5]
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - R, y: p.y - R, width: R * 2, height: R * 2)),
                     with: .radialGradient(
                        Gradient(stops: [
                            .init(color: c.opacity(0.58), location: 0),
                            .init(color: c.opacity(0.18), location: 0.30),
                            .init(color: c.opacity(0), location: 1),
                        ]),
                        center: p, startRadius: 0, endRadius: R))
            let core = side * (i == 0 ? 0.0090 : 0.0055)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - core, y: p.y - core,
                                            width: core * 2, height: core * 2)),
                     with: .color(.white.opacity(0.95)))
        }

        // 鼠标引力源
        if let g = grab {
            let p = CGPoint(x: ox + g.x * side, y: oy + g.y * side)
            let grow = min(time - g.start, 2.0)
            let R = side * (0.030 + grow * 0.048)
            let c = g.push ? Color(red: 1.00, green: 0.44, blue: 0.46)
                           : Color(red: 0.52, green: 0.94, blue: 1.00)
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - R, y: p.y - R, width: R * 2, height: R * 2)),
                       with: .color(c.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 1.2))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.4, y: p.y - 2.4, width: 4.8, height: 4.8)),
                     with: .color(c))
        }
    }
}

// MARK: - 界面

/// Command Line Tools 没带 SwiftUIMacros 插件，@State 用不了，
/// 所以把 UI 的零碎状态也塞进一个 ObservableObject 里。
final class UIState: ObservableObject {
    @Published var showUI = true
    @Published var geo = CGSize(width: 1000, height: 760)

    private var hideWork: DispatchWorkItem?
    private var monitor: Any?

    /// 动一下鼠标就把控制条叫出来，停手 2.4 秒自动淡出
    func poke(_ delay: Double = 2.4) {
        if !showUI { showUI = true }
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.showUI = false }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .scrollWheel]
        ) { [weak self] e in
            self?.poke()
            return e
        }
    }

    func removeMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        hideWork?.cancel()
    }
}

struct ContentView: View {
    @StateObject private var sim = Sim()
    @StateObject private var ui = UIState()

    var body: some View {
        ZStack(alignment: .top) {
            RadialGradient(colors: [sim.theme.bg, sim.theme.bg.opacity(0.92), Color.black],
                           center: .center, startRadius: 0, endRadius: 720)
                .ignoresSafeArea()

            Canvas { ctx, size in
                sim.draw(ctx, size)
            }
            .ignoresSafeArea()
            .offset(x: sim.shake > 0 ? CGFloat.random(in: -sim.shake...sim.shake) : 0,
                    y: sim.shake > 0 ? CGFloat.random(in: -sim.shake...sim.shake) : 0)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let u = unit(v.location, ui.geo)
                        if sim.grab == nil {
                            sim.beginGrab(u.0, u.1,
                                          push: NSEvent.modifierFlags.contains(.option))
                        } else {
                            sim.updateGrab(u.0, u.1)
                        }
                    }
                    .onEnded { _ in sim.endGrab() }
            )
            .simultaneousGesture(
                SpatialTapGesture(count: 2)
                    .onEnded { v in
                        let u = unit(v.location, ui.geo)
                        sim.explode(at: u.0, at: u.1)
                    }
            )
            .background(
                GeometryReader { g in
                    Color.clear.onAppear { ui.geo = g.size }
                        .onChange(of: g.size) { _, s in ui.geo = s }
                }
            )

            topBar
                .opacity(ui.showUI ? 1 : 0)
                .allowsHitTesting(ui.showUI)
                .animation(.easeInOut(duration: 0.18), value: ui.showUI)
        }
        .frame(minWidth: 720, minHeight: 560)
        .onAppear {
            sim.startTimer()
            ui.installMonitor()
            ui.poke(4.0)
        }
        .onDisappear {
            sim.stopTimer()
            ui.removeMonitor()
        }
    }

    private func unit(_ p: CGPoint, _ size: CGSize) -> (Double, Double) {
        let side = min(size.width, size.height) * 0.96
        let ox = (size.width - side) / 2
        let oy = (size.height - side) / 2
        return (Double((p.x - ox) / side), Double((p.y - oy) / side))
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 7) {
                ForEach(Theme.allCases) { t in
                    Button {
                        sim.theme = t
                    } label: {
                        Circle()
                            .fill(LinearGradient(colors: [t.ramp[3], t.ramp[6]],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 15, height: 15)
                            .overlay(
                                Circle().stroke(Color.white.opacity(sim.theme == t ? 0.85 : 0.14),
                                                lineWidth: sim.theme == t ? 1.6 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(t.name)
                }
            }

            divider

            labeled("粒子") {
                Slider(value: Binding(
                    get: { Double(sim.count) },
                    set: { sim.setCount(Int($0)) }
                ), in: 400...4000)
                .frame(width: 92)
            }

            labeled("引力") {
                Slider(value: $sim.gravity, in: 0.15...3.0)
                    .frame(width: 92)
            }

            divider

            iconButton(sim.paused ? "play.fill" : "pause.fill") {
                sim.paused.toggle()
            }

            iconButton("arrow.counterclockwise") {
                sim.reset()
            }

            Spacer()
        }
        .padding(.leading, 84)
        .padding(.trailing, 18)
        .padding(.vertical, 11)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: 15)
    }

    private func labeled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.38))
            content()
        }
    }

    private func iconButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 入口

@main
struct StardustApp: App {
    init() {
        if CommandLine.arguments.contains("--bench") {
            MainActor.assumeIsolated {
                let s = Sim()
                s.stopTimer()
                let t0 = CACurrentMediaTime()
                for _ in 0..<600 { s.step(1.0 / 60.0) }
                let el = CACurrentMediaTime() - t0
                print(String(format: "600 帧物理：%.3f s，平均 %.2f ms/帧", el, el / 600 * 1000))
                var sum = 0.0, mx = 0.0
                for p in s.particles {
                    let v = (p.vx * p.vx + p.vy * p.vy).squareRoot()
                    sum += v
                    if v > mx { mx = v }
                }
                print(String(format: "粒子 %d，平均速度 %.4f，最大 %.4f",
                             s.particles.count, sum / Double(s.particles.count), mx))
                var hist = [Int](repeating: 0, count: 8)
                var rmax = 0.0
                for p in s.particles {
                    let dx = p.x - 0.5, dy = p.y - 0.5
                    let r = (dx * dx + dy * dy).squareRoot()
                    if r > rmax { rmax = r }
                    let b = min(7, Int(r / 0.09))
                    hist[b] += 1
                }
                print("半径直方图(每 0.09):", hist.map { String(format: "%4d", $0) }.joined())
                print(String(format: "最远半径 %.3f", rmax))
            }
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("星砂") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1020, height: 780)
        .windowResizability(.contentMinSize)
    }
}
