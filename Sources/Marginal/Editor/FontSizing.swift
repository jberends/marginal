import CoreGraphics

struct FontSizing {
    static let minimumPointSize: CGFloat = 10
    static let maximumPointSize: CGFloat = 36
    static let step: CGFloat = 1
    /// The body size the editor starts at, and the size `Actual Size` returns to. 16px is the
    /// design system's base (headings scale 1.25/1.5/1.875 from it).
    static let defaultPointSize: CGFloat = 16

    static func increased(from size: CGFloat) -> CGFloat {
        min(size + step, maximumPointSize)
    }

    static func decreased(from size: CGFloat) -> CGFloat {
        max(size - step, minimumPointSize)
    }
}
