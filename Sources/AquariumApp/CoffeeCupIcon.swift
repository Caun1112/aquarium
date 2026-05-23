import AppKit

enum CoffeeCupIcon {
    static func statusImage(isFull: Bool) -> NSImage {
        let image = makeImage(isFull: isFull, size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }

    static func settingsImage(isFull: Bool) -> NSImage {
        let image = makeImage(isFull: isFull, size: NSSize(width: 20, height: 20))
        image.isTemplate = true
        return image
    }

    private static func makeImage(isFull: Bool, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            drawCup(in: rect, isFull: isFull)
            return true
        }
    }

    private static func drawCup(in rect: NSRect, isFull: Bool) {
        let scale = min(rect.width, rect.height) / 20
        let originX = rect.midX - 10 * scale
        let originY = rect.midY - 10 * scale
        func x(_ value: CGFloat) -> CGFloat { originX + value * scale }
        func y(_ value: CGFloat) -> CGFloat { originY + value * scale }

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let lineWidth = 1.35 * scale

        let handlePath = NSBezierPath()
        handlePath.move(to: NSPoint(x: x(15.2), y: y(12.1)))
        handlePath.curve(
            to: NSPoint(x: x(15.0), y: y(6.8)),
            controlPoint1: NSPoint(x: x(19.0), y: y(12.0)),
            controlPoint2: NSPoint(x: x(19.3), y: y(7.1))
        )
        handlePath.curve(
            to: NSPoint(x: x(15.5), y: y(10.2)),
            controlPoint1: NSPoint(x: x(17.5), y: y(6.8)),
            controlPoint2: NSPoint(x: x(17.8), y: y(10.0))
        )
        handlePath.lineWidth = lineWidth
        handlePath.lineCapStyle = .round
        handlePath.lineJoinStyle = .round
        handlePath.stroke()

        let bodyPath = NSBezierPath()
        bodyPath.move(to: NSPoint(x: x(3.0), y: y(12.0)))
        bodyPath.curve(
            to: NSPoint(x: x(5.1), y: y(4.3)),
            controlPoint1: NSPoint(x: x(3.1), y: y(9.0)),
            controlPoint2: NSPoint(x: x(3.6), y: y(6.1))
        )
        bodyPath.curve(
            to: NSPoint(x: x(9.9), y: y(2.6)),
            controlPoint1: NSPoint(x: x(6.2), y: y(3.0)),
            controlPoint2: NSPoint(x: x(7.8), y: y(2.6))
        )
        bodyPath.curve(
            to: NSPoint(x: x(14.6), y: y(4.3)),
            controlPoint1: NSPoint(x: x(12.0), y: y(2.6)),
            controlPoint2: NSPoint(x: x(13.6), y: y(3.0))
        )
        bodyPath.curve(
            to: NSPoint(x: x(16.0), y: y(12.0)),
            controlPoint1: NSPoint(x: x(15.8), y: y(6.0)),
            controlPoint2: NSPoint(x: x(16.0), y: y(9.0))
        )
        bodyPath.lineWidth = lineWidth
        bodyPath.lineCapStyle = .round
        bodyPath.lineJoinStyle = .round
        bodyPath.stroke()

        let rimRect = NSRect(x: x(2.5), y: y(11.0), width: 14.2 * scale, height: 5.5 * scale)
        let rimPath = NSBezierPath(ovalIn: rimRect)
        rimPath.lineWidth = lineWidth

        if isFull {
            let coffeeRect = NSRect(x: x(3.6), y: y(11.7), width: 12.0 * scale, height: 3.7 * scale)
            NSBezierPath(ovalIn: coffeeRect).fill()
        }

        rimPath.stroke()
    }
}
