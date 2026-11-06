import AppKit

final class StatusItemController {
    let item: NSStatusItem
    var onLeftClick: (() -> Void)?
    var onRightClick: ((NSStatusBarButton) -> Void)?

    private(set) var percent: Int = 0
    private var display = "percent"
    private var placeholder = true

    // 环形图动画（需求：菜单栏圆环要跟 5 小时额度平滑过渡）
    private var displayed: CGFloat = 0
    private var target: CGFloat = 0
    private var animationFrom: CGFloat = 0
    private var animationStart: CFTimeInterval = 0
    private var timer: Timer?
    private let animationDuration: CFTimeInterval = 0.45

    init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "Margin · OpenDesign 用量"
        }
        apply(percent: nil, display: "percent", placeholder: true)
    }

    func apply(percent: Int?, display: String, placeholder: Bool = false) {
        self.display = display
        self.placeholder = placeholder

        if placeholder || percent == nil {
            stopAnimation()
            displayed = 0
            target = 0
            render(ringPercent: 0, titlePercent: nil)
            return
        }

        let next = CGFloat(max(0, min(100, percent!)))
        self.percent = Int(next.rounded())

        if abs(next - displayed) < 0.5 || animationDuration <= 0 {
            stopAnimation()
            displayed = next
            target = next
            render(ringPercent: next, titlePercent: self.percent)
            return
        }

        animationFrom = displayed
        target = next
        animationStart = CACurrentMediaTime()
        startAnimation()
        render(ringPercent: displayed, titlePercent: self.percent)
    }

    // MARK: 动画

    private func startAnimation() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let progress = min(1, (CACurrentMediaTime() - animationStart) / animationDuration)
        let eased = 1 - pow(1 - progress, 3)
        displayed = animationFrom + (target - animationFrom) * CGFloat(eased)
        render(ringPercent: displayed, titlePercent: percent)
        if progress >= 1 {
            stopAnimation()
            displayed = target
            render(ringPercent: target, titlePercent: percent)
        }
    }

    // MARK: 渲染

    private func render(ringPercent: CGFloat, titlePercent: Int?) {
        guard let button = item.button else { return }
        button.image = Self.ringImage(percent: ringPercent)

        if display == "icon" || placeholder || titlePercent == nil {
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel(placeholder ? "Margin，正在同步用量" : "Margin，点击查看订阅用量")
            return
        }

        button.imagePosition = .imageLeading
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        button.attributedTitle = NSAttributedString(string: "\u{2009}\(titlePercent!)%", attributes: [
            .font: font,
            .baselineOffset: 0.5
        ])
        button.setAccessibilityLabel("Margin，额度剩余 \(titlePercent!)%，点击查看订阅用量")
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp, let button = item.button {
            onRightClick?(button)
        } else {
            onLeftClick?()
        }
    }

    /// 菜单栏环形图：照原型 18×18（r 6.3 / 线宽 2.1 / 中心点 1.25）用陶土色画，不做模板图，
    /// 这样和面板里的品牌色一致；代价是不随菜单栏明暗自动反色。
    static func ringImage(percent: CGFloat, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }
        let scale = size / 18
        let lineWidth: CGFloat = 2.1 * scale
        let radius: CGFloat = 6.3 * scale
        let center = NSPoint(x: size / 2, y: size / 2)
        let accent = NSColor(srgbRed: 0xE0 / 255, green: 0x8A / 255, blue: 0x6D / 255, alpha: 1)

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        accent.withAlphaComponent(0.30).setStroke()
        track.stroke()

        let clamped = max(0, min(100, percent)) / 100
        if clamped > 0 {
            // 圆头端帽会各多画半个线宽，按角度扣掉，弧长才等于百分比
            let capDegrees = (lineWidth / 2) / radius * 180 / .pi * 2
            let sweep = max(2, min(360, 360 * clamped - capDegrees))
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius,
                          startAngle: 90, endAngle: 90 - sweep, clockwise: true)
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            accent.setStroke()
            arc.stroke()
        }

        let dotRadius = 1.25 * scale
        let dot = NSBezierPath(ovalIn: NSRect(x: center.x - dotRadius, y: center.y - dotRadius,
                                              width: dotRadius * 2, height: dotRadius * 2))
        accent.setFill()
        dot.fill()
        image.isTemplate = false
        return image
    }
}
