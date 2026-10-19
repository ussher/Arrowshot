import AppKit
import XCTest
@testable import Arrowshot

@MainActor
final class ArrowLabelTypingTests: XCTestCase {
    private var window: NSWindow!
    private var canvas: CanvasView!

    override func setUp() {
        super.setUp()
        NSApp.setActivationPolicy(.accessory)
        let frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        window = NSWindow(
            contentRect: frame.offsetBy(dx: -4000, dy: -4000),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        canvas = CanvasView(frame: frame)
        window.contentView = canvas
        window.makeKeyAndOrderFront(nil)
        canvas.loadImage(Self.fixtureImage(size: NSSize(width: 400, height: 300)))
    }

    override func tearDown() {
        window?.close()
        window = nil
        canvas = nil
        super.tearDown()
    }

    func testTypingAfterDrawingAnArrowOpensALabelAtItsTail() throws {
        drawArrow()
        closeUndoGroup()
        XCTAssertEqual(canvas.annotations.count, 1)
        let arrow = try XCTUnwrap(canvas.annotations.first)
        XCTAssertEqual(arrow.kind, .arrow)
        XCTAssertEqual(canvas.selectedAnnotationID, arrow.id)

        type("H", keyCode: 4)

        let editor = try XCTUnwrap(inlineText())
        XCTAssertEqual(editor.string, "H")
        type("i", keyCode: 34)
        XCTAssertEqual(editor.string, "Hi")
        commitInlineText()

        XCTAssertEqual(canvas.annotations.count, 2)
        let committedArrow = canvas.annotations[0]
        let label = canvas.annotations[1]
        XCTAssertEqual(label.kind, .text)
        XCTAssertEqual(label.text, "Hi")
        XCTAssertTrue(label.color.isEqual(committedArrow.color))
        XCTAssertEqual(label.textSize, 16 + committedArrow.lineWidth * 3, accuracy: 0.001)
        XCTAssertEqual(label.rect.origin.x, committedArrow.displayedStart.x, accuracy: 0.001)
        XCTAssertEqual(label.rect.origin.y, committedArrow.displayedStart.y, accuracy: 0.001)
        XCTAssertGreaterThan(
            hypot(
                label.rect.origin.x - committedArrow.displayedEnd.x,
                label.rect.origin.y - committedArrow.displayedEnd.y
            ),
            20
        )
        XCTAssertEqual(canvas.selectedAnnotationID, label.id)

        canvas.undoEdit()
        XCTAssertEqual(canvas.annotations.count, 1)
        XCTAssertEqual(canvas.annotations[0].kind, .arrow)
        XCTAssertEqual(canvas.selectedAnnotationID, canvas.annotations[0].id)
        canvas.redoEdit()
        XCTAssertEqual(canvas.annotations.count, 2)
        XCTAssertEqual(canvas.annotations[1].text, "Hi")
    }

    func testTypingAfterSelectingAnExistingArrowOpensALabel() throws {
        drawArrow()
        let arrowID = try XCTUnwrap(canvas.annotations.first?.id)
        click(at: CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY - 50))
        XCTAssertNil(canvas.selectedAnnotationID)
        click(at: CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY))
        XCTAssertEqual(canvas.selectedAnnotationID, arrowID)

        type("t", keyCode: 17)
        let editor = try XCTUnwrap(inlineText())
        XCTAssertEqual(editor.string, "t")
        commitInlineText()
        let label = try XCTUnwrap(canvas.annotations.last)
        let arrow = try XCTUnwrap(canvas.annotations.first { $0.id == arrowID })
        XCTAssertEqual(label.rect.origin.x, arrow.displayedStart.x, accuracy: 0.001)
        XCTAssertEqual(label.rect.origin.y, arrow.displayedStart.y, accuracy: 0.001)
    }

    func testTypingAfterDrawingARectanglePlacesTextAtTheReleasePoint() throws {
        canvas.tool = .rectangle
        drag(
            from: CGPoint(x: canvas.bounds.midX - 40, y: canvas.bounds.midY - 30),
            to: CGPoint(x: canvas.bounds.midX + 50, y: canvas.bounds.midY + 30)
        )
        let box = try XCTUnwrap(canvas.annotations.first)
        XCTAssertEqual(box.kind, .rectangle)
        XCTAssertEqual(canvas.tool, .rectangle)

        type("t", keyCode: 17)
        let editor = try XCTUnwrap(inlineText())
        XCTAssertEqual(editor.string, "t")
        commitInlineText()

        let label = try XCTUnwrap(canvas.annotations.last)
        XCTAssertEqual(label.kind, .text)
        XCTAssertEqual(label.text, "t")
        XCTAssertEqual(label.rect.origin.x, box.rect.maxX, accuracy: 0.001)
        XCTAssertEqual(label.rect.origin.y, box.rect.maxY, accuracy: 0.001)
        XCTAssertEqual(canvas.tool, .rectangle)
    }

    func testTextToolStillPlacesAFreeLabel() throws {
        drawArrow()
        click(at: CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY - 50))
        canvas.tool = .text
        let point = CGPoint(x: canvas.bounds.midX - 30, y: canvas.bounds.midY + 40)
        click(at: point)
        let editor = try XCTUnwrap(inlineText())
        XCTAssertEqual(editor.string, "")
        XCTAssertEqual(canvas.annotations.count, 1)
        let host = editor.superview ?? editor
        XCTAssertLessThan(hypot(host.frame.midX - point.x, host.frame.midY - point.y), 48)
    }

    func testDeleteAndNudgeStillApplyToTheSelectedArrow() throws {
        drawArrow()
        let start = try XCTUnwrap(canvas.annotations.first).start
        type(String(UnicodeScalar(NSLeftArrowFunctionKey)!), keyCode: 123)
        XCTAssertNil(inlineText())
        XCTAssertEqual(canvas.annotations[0].start.x, start.x - 1, accuracy: 0.001)
        type("\u{7F}", keyCode: 51)
        XCTAssertTrue(canvas.annotations.isEmpty)
    }

    func testCommandKeyDoesNotStartAnArrowLabel() throws {
        drawArrow()
        type("t", keyCode: 17, modifiers: .command)
        XCTAssertNil(inlineText())
        XCTAssertEqual(canvas.annotations.count, 1)
    }

    private func drawArrow() {
        drag(
            from: CGPoint(x: canvas.bounds.midX - 70, y: canvas.bounds.midY),
            to: CGPoint(x: canvas.bounds.midX + 40, y: canvas.bounds.midY)
        )
    }

    private func drag(from start: CGPoint, to end: CGPoint) {
        canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: start))
        canvas.mouseDragged(with: mouseEvent(.leftMouseDragged, at: end))
        canvas.mouseUp(with: mouseEvent(.leftMouseUp, at: end))
    }

    private func click(at viewPoint: CGPoint) {
        canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: viewPoint))
        canvas.mouseUp(with: mouseEvent(.leftMouseUp, at: viewPoint))
    }

    private func type(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters.lowercased(),
            isARepeat: false,
            keyCode: keyCode
        )!
        canvas.keyDown(with: event)
    }

    private func mouseEvent(_ type: NSEvent.EventType, at viewPoint: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: canvas.convert(viewPoint, to: nil),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    private func inlineText() -> NSTextView? {
        func walk(_ view: NSView) -> NSTextView? {
            if let textView = view as? NSTextView { return textView }
            for subview in view.subviews {
                if let textView = walk(subview) { return textView }
            }
            return nil
        }
        return walk(canvas)
    }

    /// Drawing and typing share one test turn. Close the open undo group so the
    /// label is its own step, matching separate mouse and key events in the app.
    private func closeUndoGroup() {
        let manager = canvas.editingUndoManager
        while manager.groupingLevel > 0 {
            manager.endUndoGrouping()
        }
    }

    private func commitInlineText() {
        guard let textView = inlineText() else {
            XCTFail("Expected the inline editor")
            return
        }
        if canvas.editingUndoManager.groupingLevel == 0 {
            canvas.editingUndoManager.beginUndoGrouping()
        }
        canvas.textDidEndEditing(
            Notification(name: NSText.didEndEditingNotification, object: textView)
        )
        closeUndoGroup()
    }

    private static func fixtureImage(size: NSSize) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        return NSImage(cgImage: rep.cgImage!, size: size)
    }
}
