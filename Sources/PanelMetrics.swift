import CoreGraphics

/// 面板的固定尺寸与时间常量，避免同一个数字散落在多个文件里
enum PanelMetrics {
    static let width: CGFloat = 392
    static let minHeight: CGFloat = 220
    static let maxHeight: CGFloat = 760
    static let initialHeight: CGFloat = 703
    static let contentInset: CGFloat = 12      // 接近上限时要多留这么多才算溢出
    static let cornerRadius: CGFloat = 26
}
