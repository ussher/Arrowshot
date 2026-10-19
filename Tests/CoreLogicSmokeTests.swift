import AppKit
import Foundation

@main
struct CoreLogicSmokeTests {
    @MainActor
    static func main() {
        precondition(EditorTool.allCases.first == .arrow)
        precondition(!EditorTool.allCases.map(\.title).contains("選択"))
        for symbolName in [
            "arrow.down.left",
            "rectangle",
            "circle",
            "line.diagonal",
            "crop",
            "arrow.uturn.backward",
            "arrow.uturn.forward",
            "doc.on.doc",
            "square.and.arrow.down"
        ] {
            precondition(NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil)
        }

        let reverseDrag = Geometry.normalizedRect(
            from: CGPoint(x: 90, y: 80),
            to: CGPoint(x: 20, y: 10)
        )
        precondition(reverseDrag == CGRect(x: 20, y: 10, width: 70, height: 70))

        let rotated = Geometry.rotate(
            CGPoint(x: 20, y: 10),
            around: CGPoint(x: 10, y: 10),
            by: .pi / 2
        )
        precondition(abs(rotated.x - 10) < 0.0001)
        precondition(abs(rotated.y - 20) < 0.0001)

        let original = CGRect(x: -500, y: 120, width: 320, height: 240)
        let quartz = ScreenCoordinates.cocoaRectToQuartz(original, primaryScreenHeight: 982)
        let roundTrip = ScreenCoordinates.quartzRectToCocoa(quartz, primaryScreenHeight: 982)
        precondition(roundTrip == original)

        let secondaryScreen = CGRect(x: 1920, y: -240, width: 2560, height: 1440)
        let overlayContent = OverlayWindowGeometry.contentRect(forScreenFrame: secondaryScreen)
        precondition(overlayContent == CGRect(x: 0, y: 0, width: 2560, height: 1440))

        let outputSize = CaptureOutputSizing.pixels(
            forLogicalSize: CGSize(width: 1475, height: 1007)
        )
        precondition(outputSize.width == 1475)
        precondition(outputSize.height == 1007)

        let nativeSize = CaptureOutputSizing.nativePixels(
            forLogicalSize: CGSize(width: 1022, height: 659),
            pointPixelScale: 2
        )
        precondition(nativeSize.width == 2044)
        precondition(nativeSize.height == 1318)

        let referenceColor = ArrowshotStyle.defaultAnnotationColor.usingColorSpace(.sRGB)!
        precondition(abs(referenceColor.redComponent - 1) < 0.0001)
        precondition(abs(referenceColor.greenComponent - 59 / 255) < 0.0001)
        precondition(abs(referenceColor.blueComponent - 48 / 255) < 0.0001)
        let outlineColor = ArrowshotStyle.textOutlineColor.usingColorSpace(.sRGB)!
        precondition(outlineColor.redComponent == 1)
        precondition(outlineColor.greenComponent == 1)
        precondition(outlineColor.blueComponent == 1)
        precondition(ArrowshotStyle.textOutlineWidth > 0)

        var arrow = Annotation(
            kind: .arrow,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 10, y: 0),
            rotation: .pi / 2,
            color: referenceColor,
            lineWidth: 4
        )
        let fixedEndpoint = arrow.displayedEnd
        arrow.moveEndpoint(.start, to: CGPoint(x: 2, y: 8))
        precondition(hypot(arrow.end.x - fixedEndpoint.x, arrow.end.y - fixedEndpoint.y) < 0.0001)
        precondition(arrow.rotation == 0)

        let arrowPoints = ArrowGeometry.points(
            from: CGPoint(x: 10, y: 30),
            to: CGPoint(x: 110, y: 30),
            lineWidth: 6
        )
        precondition(ArrowGeometry.boundingRect(for: arrowPoints).maxX == 110)
        // Skitch-style silhouette: widest at the head, tapering to a thin tail.
        let arrowBounds = ArrowGeometry.boundingRect(for: arrowPoints)
        let tailHalfWidth = arrowPoints.map { abs($0.y - 30) }.min()!
        let headHalfWidth = arrowBounds.height / 2
        precondition(headHalfWidth > tailHalfWidth * 6)
        precondition(abs(headHalfWidth - 0.49 * max(18, 6 * 5)) < 0.5)

        var rectangle = Annotation(
            kind: .rectangle,
            rect: CGRect(x: 20, y: 30, width: 100, height: 60),
            rotation: .pi / 4,
            color: referenceColor,
            lineWidth: 4
        )
        let fixedCorner = rectangle.displayedCorner(.bottomRight)
        rectangle.resize(from: .topLeft, to: CGPoint(x: 5, y: 10))
        let resizedFixedCorner = rectangle.displayedCorner(.bottomRight)
        precondition(hypot(resizedFixedCorner.x - fixedCorner.x, resizedFixedCorner.y - fixedCorner.y) < 0.0001)

        var text = Annotation(
            kind: .text,
            rect: CGRect(x: 40, y: 50, width: 120, height: 48),
            rotation: .pi / 3,
            color: referenceColor,
            lineWidth: 6,
            text: "PictoJot",
            textSize: 34
        )
        text.resizeText(to: CGPoint(x: 280, y: 146))
        precondition(text.rect.origin == CGPoint(x: 40, y: 50))
        precondition(abs(text.rect.width - 240) < 0.0001)
        precondition(abs(text.rect.height - 96) < 0.0001)
        precondition(abs(text.textSize - 68) < 0.0001)
        precondition(text.rotation == 0)

        let textLeadingConstraint = text.constrainedTranslation(
            CGPoint(x: -100, y: -100),
            within: CGSize(width: 200, height: 100)
        )
        let constrainedTextBounds = text.displayedVisualBounds.offsetBy(
            dx: textLeadingConstraint.x,
            dy: textLeadingConstraint.y
        )
        precondition(constrainedTextBounds.minX >= 0)
        precondition(constrainedTextBounds.minY >= 0)
        let textTrailingOverflow = text.constrainedTranslation(
            CGPoint(x: 300, y: 300),
            within: CGSize(width: 200, height: 100)
        )
        precondition(textTrailingOverflow == CGPoint(x: 300, y: 300))

        let rectangleTranslation = rectangle.constrainedTranslation(
            CGPoint(x: 500, y: 500),
            within: CGSize(width: 300, height: 240)
        )
        let constrainedRectangleBounds = rectangle.displayedVisualBounds.offsetBy(
            dx: rectangleTranslation.x,
            dy: rectangleTranslation.y
        )
        precondition(constrainedRectangleBounds.maxX <= 300.0001)
        precondition(constrainedRectangleBounds.maxY <= 240.0001)

        precondition(EditorCursors.fourWayResize.image.size == CGSize(width: 28, height: 28))
        precondition(EditorCursors.rotation(angle: .pi / 3).image.size == CGSize(width: 28, height: 28))

        let highResolutionRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 20,
            pixelsHigh: 12,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        // A 2x capture keeps all of its pixels while reporting a logical size.
        let retinaCapture = NSImage(cgImage: highResolutionRep.cgImage!, size: CGSize(width: 10, height: 6))
        let normalizedRetina = retinaCapture.normalizedForEditing()
        precondition(normalizedRetina.size == CGSize(width: 10, height: 6))
        // Check the backing bitmap that export uses; representation pixel metadata
        // is reported differently on macOS 14.
        let normalizedBitmap = normalizedRetina.cgImageValue
        precondition(normalizedBitmap?.width == 20, "width: \(String(describing: normalizedBitmap?.width))")
        precondition(normalizedBitmap?.height == 12, "height: \(String(describing: normalizedBitmap?.height))")

        // An image with no meaningful point size falls back to its pixel size.
        let oddScaleImage = NSImage(cgImage: highResolutionRep.cgImage!, size: CGSize(width: 13, height: 7))
        precondition(oddScaleImage.normalizedForEditing().size == CGSize(width: 20, height: 12))

        let expectedExportSize = CGSize(width: 1022, height: 659)
        guard let rendered = PixelExactImageRenderer.render(size: expectedExportSize, drawing: { bounds in
            NSColor.systemBlue.setFill()
            bounds.fill()
        }), let pngData = rendered.pngData(), let representation = NSBitmapImageRep(data: pngData) else {
            preconditionFailure("Could not render the export regression fixture")
        }
        precondition(representation.pixelsWide == 1022)
        precondition(representation.pixelsHigh == 659)

        // JPEG keeps the pixel size and flattens transparency onto white.
        guard let transparent = PixelExactImageRenderer.render(size: CGSize(width: 40, height: 30), drawing: { _ in }),
              let jpegData = ImageFormat.jpeg.data(for: transparent),
              let jpegRep = NSBitmapImageRep(data: jpegData),
              let corner = jpegRep.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else {
            preconditionFailure("Could not encode the JPEG fixture")
        }
        precondition(jpegData.starts(with: [0xFF, 0xD8]), "not a JPEG")
        precondition(jpegRep.pixelsWide == 40 && jpegRep.pixelsHigh == 30)
        precondition(corner.redComponent > 0.95 && corner.greenComponent > 0.95 && corner.blueComponent > 0.95,
                     "transparent pixels should become white: \(corner)")

        checkArrowLabelTyping()

        print("Core logic smoke tests passed")
    }

    @MainActor
    private static func checkArrowLabelTyping() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        let window = NSWindow(
            contentRect: frame.offsetBy(dx: -4000, dy: -4000),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let canvas = CanvasView(frame: frame)
        window.contentView = canvas
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 400,
            pixelsHigh: 300,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        canvas.loadImage(NSImage(cgImage: rep.cgImage!, size: NSSize(width: 400, height: 300)))

        func mouse(_ type: NSEvent.EventType, at viewPoint: CGPoint) -> NSEvent {
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
        func drag(from start: CGPoint, to end: CGPoint) {
            canvas.mouseDown(with: mouse(.leftMouseDown, at: start))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, at: end))
            canvas.mouseUp(with: mouse(.leftMouseUp, at: end))
        }
        func type(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) {
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
        func closeUndoGroup() {
            let manager = canvas.editingUndoManager
            while manager.groupingLevel > 0 {
                manager.endUndoGrouping()
            }
        }
        func commit(_ textView: NSTextView) {
            if canvas.editingUndoManager.groupingLevel == 0 {
                canvas.editingUndoManager.beginUndoGrouping()
            }
            canvas.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: textView))
            closeUndoGroup()
        }
        func inlineText() -> NSTextView? {
            func walk(_ view: NSView) -> NSTextView? {
                if let textView = view as? NSTextView { return textView }
                for subview in view.subviews {
                    if let textView = walk(subview) { return textView }
                }
                return nil
            }
            return walk(canvas)
        }

        let bounds = canvas.bounds
        precondition(bounds.width > 100 && bounds.height > 100, "canvas bounds \(bounds)")
        drag(
            from: CGPoint(x: bounds.midX - 70, y: bounds.midY),
            to: CGPoint(x: bounds.midX + 40, y: bounds.midY)
        )
        closeUndoGroup()
        precondition(canvas.annotations.count == 1, "arrow count \(canvas.annotations.count)")
        precondition(canvas.annotations[0].kind == .arrow)
        let arrowID = canvas.annotations[0].id
        precondition(canvas.selectedAnnotationID == arrowID)

        type("H", keyCode: 4)
        guard let editor = inlineText() else {
            preconditionFailure("typing after an arrow did not open the inline editor")
        }
        precondition(editor.string == "H", "editor text \(editor.string.debugDescription)")
        type("i", keyCode: 34)
        precondition(editor.string == "Hi", "second key produced \(editor.string.debugDescription)")

        commit(editor)
        precondition(canvas.annotations.count == 2)
        precondition(canvas.annotations[1].kind == .text)
        precondition(canvas.annotations[1].text == "Hi")
        let committedArrow = canvas.annotations[0]
        let label = canvas.annotations[1]
        precondition(label.color.isEqual(committedArrow.color))
        precondition(abs(label.rect.origin.x - committedArrow.displayedStart.x) < 0.001)
        precondition(abs(label.rect.origin.y - committedArrow.displayedStart.y) < 0.001)
        precondition(
            hypot(
                label.rect.origin.x - committedArrow.displayedEnd.x,
                label.rect.origin.y - committedArrow.displayedEnd.y
            ) > 20
        )

        canvas.undoEdit()
        precondition(
            canvas.annotations.count == 1,
            "undo left \(canvas.annotations.count) annotations, canUndo \(canvas.editingUndoManager.canUndo)"
        )
        precondition(canvas.selectedAnnotationID == canvas.annotations[0].id)
        canvas.redoEdit()
        precondition(canvas.annotations.count == 2)
        precondition(canvas.annotations[1].text == "Hi")

        // Deselect, select the arrow again, and type. The label stays on the tail.
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: bounds.midX, y: bounds.midY - 50)))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: bounds.midX, y: bounds.midY - 50)))
        precondition(canvas.selectedAnnotationID == nil, "click away should deselect")
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: bounds.midX, y: bounds.midY)))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: bounds.midX, y: bounds.midY)))
        precondition(canvas.selectedAnnotationID == committedArrow.id)
        type("t", keyCode: 17)
        guard let selectedEditor = inlineText() else {
            preconditionFailure("typing after selecting an arrow did not open the inline editor")
        }
        precondition(selectedEditor.string == "t", "editor text \(selectedEditor.string.debugDescription)")
        commit(selectedEditor)
        let tailLabel = canvas.annotations.last!
        precondition(abs(tailLabel.rect.origin.x - committedArrow.displayedStart.x) < 0.001)
        precondition(abs(tailLabel.rect.origin.y - committedArrow.displayedStart.y) < 0.001)

        // Drawing a box with the rectangle tool, then typing, drops text at the release point.
        canvas.loadImage(NSImage(cgImage: rep.cgImage!, size: NSSize(width: 400, height: 300)))
        canvas.tool = .rectangle
        drag(
            from: CGPoint(x: bounds.midX - 40, y: bounds.midY - 30),
            to: CGPoint(x: bounds.midX + 50, y: bounds.midY + 30)
        )
        precondition(canvas.annotations.first?.kind == .rectangle)
        precondition(canvas.tool == .rectangle)
        let box = canvas.annotations[0]
        type("t", keyCode: 17)
        guard let boxEditor = inlineText() else {
            preconditionFailure("typing after a box did not open the inline editor")
        }
        precondition(boxEditor.string == "t")
        commit(boxEditor)
        let boxLabel = canvas.annotations.last!
        precondition(boxLabel.kind == .text)
        precondition(abs(boxLabel.rect.origin.x - box.rect.maxX) < 0.001)
        precondition(abs(boxLabel.rect.origin.y - box.rect.maxY) < 0.001)
        precondition(canvas.tool == .rectangle)

        canvas.loadImage(NSImage(cgImage: rep.cgImage!, size: NSSize(width: 400, height: 300)))
        canvas.tool = .arrow
        drag(
            from: CGPoint(x: bounds.midX - 70, y: bounds.midY),
            to: CGPoint(x: bounds.midX + 40, y: bounds.midY)
        )
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: bounds.midX, y: bounds.midY - 50)))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: bounds.midX, y: bounds.midY - 50)))
        canvas.tool = .text
        let freePoint = CGPoint(x: bounds.midX - 30, y: bounds.midY + 40)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: freePoint))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: freePoint))
        guard let freeEditor = inlineText() else {
            preconditionFailure("text tool did not open a free label")
        }
        precondition(freeEditor.string.isEmpty)
        let freeHost = freeEditor.superview ?? freeEditor
        precondition(
            hypot(freeHost.frame.midX - freePoint.x, freeHost.frame.midY - freePoint.y) < 48,
            "editor \(freeHost.frame) point \(freePoint) bounds \(canvas.bounds)"
        )

        canvas.loadImage(NSImage(cgImage: rep.cgImage!, size: NSSize(width: 400, height: 300)))
        canvas.tool = .arrow
        drag(
            from: CGPoint(x: bounds.midX - 70, y: bounds.midY),
            to: CGPoint(x: bounds.midX + 40, y: bounds.midY)
        )
        let nudgedStart = canvas.annotations[0].start
        type(String(UnicodeScalar(NSLeftArrowFunctionKey)!), keyCode: 123)
        precondition(inlineText() == nil)
        precondition(abs(canvas.annotations[0].start.x - (nudgedStart.x - 1)) < 0.001)
        type("t", keyCode: 17, modifiers: .command)
        precondition(inlineText() == nil)
        type("\u{7F}", keyCode: 51)
        precondition(canvas.annotations.isEmpty)

        checkEditorPreferences()
        checkSettingsLayout()
    }

    private static func checkEditorPreferences() {
        let red = ArrowshotStyle.defaultAnnotationColor
        precondition(AnnotationColorSettings.hexString(for: red) == "#FF3B30")
        let blue = NSColor(srgbRed: 0, green: 0.5, blue: 1, alpha: 1)
        precondition(AnnotationColorSettings.hexString(for: blue) == "#0080FF")
        let parsed = AnnotationColorSettings.color(fromHex: "#0080FF")!
        let parsedRGB = parsed.usingColorSpace(.sRGB)!
        precondition(abs(parsedRGB.redComponent - 0) < 0.001)
        precondition(abs(parsedRGB.greenComponent - 128 / 255) < 0.001)
        precondition(abs(parsedRGB.blueComponent - 1) < 0.001)
        precondition(AnnotationColorSettings.color(fromHex: "nope") == nil)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let date = Date(timeIntervalSince1970: 1_760_832_645)
        let stamp = formatter.string(from: date)
        let dated = ExportFileName.fileName(format: .png, pattern: "Arrowshot {datetime}", date: date)
        precondition(dated == "Arrowshot \(stamp).png", dated)
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        formatter.dateFormat = "HH.mm.ss"
        let time = formatter.string(from: date)
        let mixed = ExportFileName.fileName(format: .jpeg, pattern: "Shot {DATE} at {Time}", date: date)
        precondition(mixed == "Shot \(day) at \(time).jpg", mixed)
        let fallback = ExportFileName.fileName(format: .png, pattern: "   ", date: date)
        precondition(fallback == "Arrowshot \(stamp).png", fallback)
        let cleaned = ExportFileName.fileName(format: .png, pattern: "A/B:C {date}.png", date: date)
        precondition(cleaned == "A-B-C \(day).png", cleaned)
        let blank = ExportFileName.fileName(format: .png, pattern: "/", date: date)
        precondition(blank == "Arrowshot \(stamp).png", blank)

        let defaults = UserDefaults.standard
        let colorKey = "annotationColorHex"
        let nameKey = "exportFileNamePattern"
        let oldColor = defaults.string(forKey: colorKey)
        let oldName = defaults.string(forKey: nameKey)
        defer {
            if let oldColor {
                defaults.set(oldColor, forKey: colorKey)
            } else {
                defaults.removeObject(forKey: colorKey)
            }
            if let oldName {
                defaults.set(oldName, forKey: nameKey)
            } else {
                defaults.removeObject(forKey: nameKey)
            }
        }
        AnnotationColorSettings.set(blue)
        let stored = AnnotationColorSettings.color.usingColorSpace(.sRGB)!
        precondition(abs(stored.blueComponent - 1) < 0.001)
        AnnotationColorSettings.set(blue)
        ExportFileName.setPattern("Notes {date}")
        precondition(ExportFileName.pattern == "Notes {date}")
        precondition(ExportFileName.fileName(format: .png, date: date) == "Notes \(day).png")
        ExportFileName.setPattern("  ")
        precondition(ExportFileName.pattern == ExportFileName.defaultPattern)
    }

    @MainActor
    private static func checkSettingsLayout() {
        let settings = SettingsWindowController()
        guard let window = settings.window, let content = window.contentView else {
            preconditionFailure("settings window missing")
        }
        window.setFrame(NSRect(x: -4000, y: -4000, width: 480, height: 640), display: false)
        content.layoutSubtreeIfNeeded()

        guard let nameField = find(in: content, where: { ($0 as? NSTextField)?.isEditable == true && ($0 as? NSTextField)?.stringValue.contains("{datetime}") == true }) as? NSTextField else {
            preconditionFailure("file name field missing")
        }
        precondition(nameField.bounds.width > 200, "file name field width \(nameField.bounds.width)")
        precondition(nameField.bounds.height > 10, "file name field height \(nameField.bounds.height)")

        guard let colorWell = find(in: content, where: { $0 is NSColorWell }) as? NSColorWell else {
            preconditionFailure("default color well missing")
        }
        precondition(colorWell.bounds.width > 20 && colorWell.bounds.height > 20)

        guard let scrollView = find(in: content, where: { $0 is NSScrollView }) as? NSScrollView,
              let document = scrollView.documentView else {
            preconditionFailure("settings did not scroll")
        }
        document.layoutSubtreeIfNeeded()
        let documentHeight = document.bounds.height
        precondition(documentHeight > scrollView.contentView.bounds.height, "document \(documentHeight) clip \(scrollView.contentView.bounds.height)")
        let fieldInClip = nameField.convert(nameField.bounds, to: scrollView.contentView)
        precondition(
            scrollView.contentView.bounds.intersects(fieldInClip),
            "file name field \(fieldInClip) starts off screen in \(scrollView.contentView.bounds)"
        )
        let fieldBottom = nameField.convert(nameField.bounds, to: document).maxY
        precondition(fieldBottom > 0 && fieldBottom <= documentHeight + 1, "file name field bottom \(fieldBottom) document \(documentHeight)")
        let wellFrame = colorWell.convert(colorWell.bounds, to: document)
        precondition(wellFrame.minY >= 0 && wellFrame.maxY <= documentHeight + 1, "color well \(wellFrame) document \(documentHeight)")

        guard let shortcuts = find(in: document, where: { ($0 as? NSTextField)?.stringValue == "Editor Shortcuts" }) else {
            preconditionFailure("editor shortcuts heading missing")
        }
        let clip = scrollView.contentView
        let maxOffset = documentHeight - clip.bounds.height
        clip.scroll(to: NSPoint(x: 0, y: maxOffset))
        scrollView.reflectScrolledClipView(clip)
        let visible = clip.bounds
        let heading = shortcuts.convert(shortcuts.bounds, to: clip)
        precondition(visible.intersects(heading), "shortcuts \(heading) not visible in \(visible)")
    }

    private static func find(in view: NSView, where matches: (NSView) -> Bool) -> NSView? {
        if matches(view) { return view }
        for subview in view.subviews {
            if let found = find(in: subview, where: matches) { return found }
        }
        return nil
    }
}
