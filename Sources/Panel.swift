import AppKit

/// 面板形状：26pt 圆角主体 + 顶部箭头（原型 14×14 菱形，可见底宽 19.8、高 9.9）。
enum PanelShape {
    // 不再画顶部箭头：面板就是一个 26pt 圆角矩形
    static let cornerRadius: CGFloat = 26

    static func path(size: NSSize, caretX: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                     xRadius: cornerRadius, yRadius: cornerRadius)
    }

    static func maskImage(size: NSSize, caretX: CGFloat) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        path(size: size, caretX: caretX).fill()
        image.unlockFocus()
        return image
    }
}

/// 压在系统材质上的品牌底色（maskImage 不裁剪子视图，所以这层必须自己按形状画）。
final class TintView: NSView {
    var fillColor: NSColor = .clear
    var borderColor: NSColor = .clear
    var caretX: CGFloat = 0

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let path = PanelShape.path(size: bounds.size, caretX: caretX)
        fillColor.setFill()
        path.fill()
        if borderColor.alphaComponent > 0 {
            borderColor.setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class MarginPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
