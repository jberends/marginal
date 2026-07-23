import CoreGraphics

struct FontSizing {
    static let minimumPointSize: CGFloat = 10
    static let maximumPointSize: CGFloat = 36
    static let step: CGFloat = 1

    static func increased(from size: CGFloat) -> CGFloat {
        min(size + step, maximumPointSize)
    }

    static func decreased(from size: CGFloat) -> CGFloat {
        max(size - step, minimumPointSize)
    }
}
