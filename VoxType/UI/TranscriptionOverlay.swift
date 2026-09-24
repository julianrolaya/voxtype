import Cocoa
import SwiftUI

enum OverlayState: Equatable {
    case idle
    case recording
    case transcribing
    case llmProcessing
    case showing(text: String)
    case pasted(text: String)

    static func == (lhs: OverlayState, rhs: OverlayState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording), (.transcribing, .transcribing): return true
        case (.showing(let a), .showing(let b)): return a == b
        case (.pasted(let a), .pasted(let b)): return a == b
        default: return false
        }
    }
}

enum Halo {
    static let inset: CGFloat = 30
}

class OverlayPanel: NSPanel {
    weak var overlayModel: OverlayModel?
    var onDrop: (() -> Void)?

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        var newFrame = frameRect
        guard let screen = screen ?? NSScreen.main else { return newFrame }

        let paddingX = Halo.inset
        let paddingY = Halo.inset
        let gap: CGFloat = 24.0

        let visibleFrame = screen.visibleFrame
        let minSafeX = visibleFrame.minX + gap
        let maxSafeX = visibleFrame.maxX - gap
        let minSafeY = visibleFrame.minY + gap
        let maxSafeY = visibleFrame.maxY - gap

        let pillMinX = newFrame.minX + paddingX
        let pillMaxX = newFrame.maxX - paddingX
        let pillMinY = newFrame.minY + paddingY
        let pillMaxY = newFrame.maxY - paddingY

        let screens = NSScreen.screens

        let canMoveDown = screens.contains { $0.frame.minY < screen.frame.minY }
        let canMoveUp = screens.contains { $0.frame.maxY > screen.frame.maxY }
        let canMoveLeft = screens.contains { $0.frame.minX < screen.frame.minX }
        let canMoveRight = screens.contains { $0.frame.maxX > screen.frame.maxX }

        if !canMoveDown && pillMinY < minSafeY { newFrame.origin.y = minSafeY - paddingY }
        if !canMoveUp && pillMaxY > maxSafeY { newFrame.origin.y = maxSafeY - newFrame.height + paddingY }
        if !canMoveLeft && pillMinX < minSafeX { newFrame.origin.x = minSafeX - paddingX }
        if !canMoveRight && pillMaxX > maxSafeX { newFrame.origin.x = maxSafeX - newFrame.width + paddingX }

        return newFrame
    }

    private var dragAnchor: NSPoint?
    private var dragWindowOrigin: NSPoint?
    private var didDrag = false

    private let dragSlop: CGFloat = 3

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragAnchor = NSEvent.mouseLocation
            dragWindowOrigin = frame.origin
            didDrag = false
            super.sendEvent(event)

        case .leftMouseDragged:
            guard let anchor = dragAnchor, let origin = dragWindowOrigin else {
                super.sendEvent(event)
                return
            }
            let now = NSEvent.mouseLocation
            let dx = now.x - anchor.x
            let dy = now.y - anchor.y
            if !didDrag && hypot(dx, dy) < dragSlop {
                super.sendEvent(event)
                return
            }
            didDrag = true
            setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))

        case .leftMouseUp:
            let moved = didDrag
            if !moved { super.sendEvent(event) }
            dragAnchor = nil
            dragWindowOrigin = nil
            didDrag = false
            guard moved else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onDrop?()
            }

        default:
            super.sendEvent(event)
        }
    }

    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

class TranscriptionOverlay {
    var panel: NSPanel?
    private var hostingView: NSHostingView<OverlayView>?
    private var dismissTimer: Timer?
    private let overlayModel = OverlayModel()

    private(set) var expectedSize: NSSize = .zero
    private var isReasserting = false
    private var isSyncing = false

    init() {
        DispatchQueue.main.async { self.createPanel() }
    }

    private func measuredPanelSize() -> NSSize? {
        guard let hosting = hostingView else { return nil }
        hosting.layoutSubtreeIfNeeded()
        let s = hosting.fittingSize
        guard s.width > 1, s.height > 1 else { return nil }
        return NSSize(width: ceil(s.width), height: ceil(s.height))
    }

    func syncWindowFrame(usingFloor: Bool = false) {
        guard let p = panel else { return }
        isSyncing = true
        defer { isSyncing = false }

        let floor = NSSize(width: overlayModel.sizeFloor.width + Halo.inset * 2,
                           height: overlayModel.sizeFloor.height + Halo.inset * 2)
        var newSize = measuredPanelSize() ?? floor
        if usingFloor {
            newSize.width  = max(newSize.width,  floor.width)
            newSize.height = max(newSize.height, floor.height)
            DispatchQueue.main.async { [weak self] in self?.syncWindowFrame() }
        }

        expectedSize = newSize

        let frame = p.frame
        guard abs(newSize.width - frame.width) > 0.5 || abs(newSize.height - frame.height) > 0.5
        else { return }

        let center = NSPoint(x: frame.midX, y: frame.midY)
        p.setFrame(NSRect(x: center.x - (newSize.width / 2),
                          y: center.y - (newSize.height / 2),
                          width: newSize.width,
                          height: newSize.height),
                   display: true)
    }

    func reassertFrameIfNeeded() {
        guard let p = panel, !isReasserting, !isSyncing, expectedSize.width > 0 else { return }
        let actual = p.frame.size
        guard abs(actual.width - expectedSize.width) > 1
           || abs(actual.height - expectedSize.height) > 1 else { return }

        Log.ui.debug("Overlay frame changed externally: \(actual.width, format: .fixed(precision: 0))x\(actual.height, format: .fixed(precision: 0)) -> restoring \(self.expectedSize.width, format: .fixed(precision: 0))x\(self.expectedSize.height, format: .fixed(precision: 0))")
        isReasserting = true
        p.setFrame(NSRect(origin: p.frame.origin, size: expectedSize), display: true)
        isReasserting = false
    }

    func setOnCancel(_ handler: @escaping () -> Void) {
        overlayModel.onCancel = handler
    }

    func setIdle() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        overlayModel.state = .idle
        syncWindowFrame(usingFloor: true)
    }

    func startRecording() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        overlayModel.state = .recording
        syncWindowFrame(usingFloor: true)
    }

    func showTranscribing() {
        overlayModel.state = .transcribing
        syncWindowFrame(usingFloor: true)
    }

    func showLLMProcessing() {
        overlayModel.state = .llmProcessing
        syncWindowFrame(usingFloor: true)
    }

    enum Reading {
        static let maxWords = 32
        static let wordsPerSecond = 4.0

        static func truncated(_ text: String) -> String {
            let words = text.split(separator: " ", omittingEmptySubsequences: true)
            guard words.count > maxWords else { return text }
            return words.prefix(maxWords).joined(separator: " ") + "…"
        }

        static func dwell(for text: String) -> TimeInterval {
            let words = Double(text.split(separator: " ", omittingEmptySubsequences: true).count)
            return min(10, max(4, 2 + words / wordsPerSecond))
        }
    }

    func showText(_ text: String, uncertain: [String] = []) {
        overlayModel.uncertainWords = Set(uncertain.map(OverlayModel.matchKey))
        overlayModel.state = .showing(text: Reading.truncated(text))
        syncWindowFrame(usingFloor: true)
    }

    func showNotice(_ text: String) {
        overlayModel.state = .showing(text: text)
        syncWindowFrame(usingFloor: true)
        scheduleDismiss(after: 2.5)
    }

    func showPasted(_ text: String) {
        let shown = Reading.truncated(text)
        overlayModel.state = .pasted(text: shown)
        syncWindowFrame(usingFloor: true)
        scheduleDismiss(after: Reading.dwell(for: shown))
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
        }
    }

    private func createPanel() {
        overlayModel.onPanelInvalidated = { [weak self] in
            DispatchQueue.main.async { self?.syncWindowFrame() }
        }

        let view = OverlayView(model: overlayModel)
        let hosting = NSHostingView(rootView: view)
        self.hostingView = hosting

        let floor = overlayModel.sizeFloor
        let initialFrame = NSRect(x: 0, y: 0,
                                  width: floor.width + Halo.inset * 2,
                                  height: floor.height + Halo.inset * 2)
        hosting.frame = initialFrame

        let p = OverlayPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.overlayModel = overlayModel
        p.onDrop = { [weak self] in
            self?.windowDelegate?.handleDrop()
        }
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = false
        p.isMovable = false
        let container = NSView(frame: initialFrame)
        container.autoresizesSubviews = true
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        p.contentView = container
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        self.windowDelegate = OverlayWindowDelegate(overlay: self)
        p.delegate = self.windowDelegate

        positionPanel(p)
        p.orderFront(nil)

        self.panel = p
        syncWindowFrame()
    }

    private var hasBeenPositioned = false
    private var windowDelegate: OverlayWindowDelegate?

    private func bottomCenterOrigin(for p: NSPanel) -> NSPoint {
        guard let screen = NSScreen.main else { return p.frame.origin }
        let gap: CGFloat = 24.0
        let visible = screen.visibleFrame
        return NSPoint(x: visible.minX + (visible.width - p.frame.width) / 2,
                       y: visible.minY + gap - Halo.inset)
    }

    func resetPosition() {
        guard panel != nil else { return }
        updateOrientation(isVertical: false)
        hasBeenPositioned = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let p = self.panel else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.5
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                p.animator().setFrameOrigin(self.bottomCenterOrigin(for: p))
            }
        }
    }

    private func positionPanel(_ p: NSPanel) {
        guard !hasBeenPositioned else { return }
        p.setFrameOrigin(bottomCenterOrigin(for: p))
        hasBeenPositioned = true
    }

    private func scheduleDismiss(after delay: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.setIdle()
        }
    }
    func updateOrientation(isVertical: Bool) {
        if overlayModel.isVertical != isVertical {
            overlayModel.isVertical = isVertical
            syncWindowFrame(usingFloor: true)
        }
    }
}

class OverlayWindowDelegate: NSObject, NSWindowDelegate {
    weak var overlay: TranscriptionOverlay?

    private let snapThreshold: CGFloat = 36.0
    private let gap: CGFloat = 24.0

    private enum Edge { case left, right, none }

    init(overlay: TranscriptionOverlay) {
        self.overlay = overlay
        super.init()
    }

    func handleDrop() {
        guard let overlay = overlay, let window = overlay.panel,
              let screen = window.screen ?? NSScreen.main else { return }

        let screenRect = screen.visibleFrame
        let frame = window.frame
        let pillMinX = frame.minX + Halo.inset
        let pillMaxX = frame.maxX - Halo.inset

        let edge: Edge
        if abs(pillMinX - screenRect.minX) < snapThreshold { edge = .left }
        else if abs(pillMaxX - screenRect.maxX) < snapThreshold { edge = .right }
        else { edge = .none }

        overlay.updateOrientation(isVertical: edge != .none)

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let overlay = self.overlay, let window = overlay.panel,
                  let screen = window.screen ?? NSScreen.main else { return }
            self.place(window: window, screen: screen, edge: edge, size: overlay.expectedSize)
        }
    }

    private func place(window: NSWindow, screen: NSScreen, edge: Edge, size: NSSize) {
        let screenRect = screen.visibleFrame
        let size = size.width > 0 ? size : window.frame.size
        var origin = window.frame.origin

        let minSafeX = screenRect.minX + gap - Halo.inset
        let maxSafeX = screenRect.maxX - gap + Halo.inset - size.width
        let minSafeY = screenRect.minY + gap - Halo.inset
        let maxSafeY = screenRect.maxY - gap + Halo.inset - size.height

        switch edge {
        case .left:  origin.x = minSafeX
        case .right: origin.x = maxSafeX
        case .none:  break
        }
        origin.x = max(minSafeX, min(origin.x, maxSafeX))
        origin.y = max(minSafeY, min(origin.y, maxSafeY))

        guard !NSEqualPoints(origin, window.frame.origin) else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrameOrigin(origin)
        }
    }

    func windowDidResize(_ notification: Notification) {
        overlay?.reassertFrameIfNeeded()
    }
}

class OverlayModel: ObservableObject {
    @Published var state: OverlayState = .idle
    @Published var isVertical: Bool = false

    var onPanelInvalidated: (() -> Void)?

    var onCancel: (() -> Void)?

    @Published var uncertainWords: Set<String> = []

    static func matchKey(_ s: String) -> String {
        s.lowercased().trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "'-")))
    }

    func styled(_ text: String, base: Color) -> AttributedString {
        var out = AttributedString()
        let parts = text.split(separator: " ", omittingEmptySubsequences: false)
        for (i, part) in parts.enumerated() {
            if i > 0 { out += AttributedString(" ") }
            var piece = AttributedString(String(part))
            let key = OverlayModel.matchKey(String(part))
            if !key.isEmpty && uncertainWords.contains(key) {
                piece.foregroundColor = Color(red: 1.0, green: 0.72, blue: 0.24)
                piece.underlineStyle = .single
            } else {
                piece.foregroundColor = base
            }
            out += piece
        }
        return out
    }

    var sizeFloor: CGSize {
        let isText: Bool
        switch state {
        case .showing, .pasted: isText = true
        default: isText = false
        }
        if isVertical {
            return isText ? CGSize(width: 200, height: 320) : CGSize(width: 90, height: 300)
        }
        return isText ? CGSize(width: 540, height: 160) : CGSize(width: 300, height: 90)
    }

    var minimumPillSize: CGSize {
        let thickness: CGFloat
        switch AppSettings.shared.widgetSize {
        case .small:  thickness = isVertical ? 38 : 32
        case .medium: thickness = 44
        case .large:  thickness = 56
        }
        return isVertical ? CGSize(width: thickness, height: thickness * 2)
                          : CGSize(width: thickness * 2, height: thickness)
    }
}

struct GlowOrb: View {
    let color1: Color
    let color2: Color
    let size: CGFloat
    let isPulsing: Bool
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [color1, color2],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .shadow(color: color1.opacity(0.6), radius: size * 0.5)
            .shadow(color: color2.opacity(0.3), radius: size * 0.9)
            .scaleEffect(scale)
            .onAppear {
                if isPulsing {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        scale = 1.18
                    }
                }
            }
            .onChange(of: isPulsing) { _, pulsing in
                if !pulsing {
                    withAnimation(.easeOut(duration: 0.3)) { scale = 1.0 }
                } else {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        scale = 1.18
                    }
                }
            }
    }
}

struct WaveformBars: View {
    let isAnimating: Bool
    let barColor: Color
    let barCount: Int
    let isVertical: Bool

    @State private var heights: [CGFloat] = []
    @State private var timer: Timer? = nil

    var body: some View {
        if isVertical {
            VStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor.opacity(0.5 + safeHeight(i) * 0.5))
                        .frame(width: 3 + safeHeight(i) * 16, height: 2)
                }
            }
            .frame(width: 22)
            .onAppear { setup() }
            .onChange(of: isAnimating) { _, animating in handleAnim(animating) }
        } else {
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor.opacity(0.5 + safeHeight(i) * 0.5))
                        .frame(width: 2, height: 3 + safeHeight(i) * 16)
                }
            }
            .frame(height: 22)
            .onAppear { setup() }
            .onChange(of: isAnimating) { _, animating in handleAnim(animating) }
        }
    }

    private func setup() {
        heights = (0..<barCount).map { i in
            let center = Double(barCount) / 2.0
            let dist = abs(Double(i) - center) / center
            return CGFloat(max(0.1, 1.0 - dist * dist))
        }
        if isAnimating { startAnimation() }
    }

    private func handleAnim(_ animating: Bool) {
        if animating {
            startAnimation()
        } else {
            timer?.invalidate()
            timer = nil
            withAnimation(.easeOut(duration: 0.6)) {
                heights = heights.map { $0 * 0.3 }
            }
        }
    }

    private func safeHeight(_ index: Int) -> CGFloat {
        guard index < heights.count else { return 0.3 }
        return heights[index]
    }

    private func startAnimation() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.09)) {
                let center = Double(barCount) / 2.0
                heights = (0..<barCount).map { i in
                    let dist = abs(Double(i) - center) / center
                    let base = max(0.08, 1.0 - dist * 0.6)
                    return CGFloat(base * Double.random(in: 0.2...1.0))
                }
            }
        }
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject private var history = TranscriptionHistory.shared

    @State private var justCopied = false

    @State private var now = Date()
    private let ticker = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    private let copyWindow: TimeInterval = 120

    private var recentTranscription: String? {
        guard let entry = history.entries.first else { return nil }
        return now.timeIntervalSince(entry.timestamp) <= copyWindow ? entry.text : nil
    }

    private var pillOpacity: Double {
        model.state == .idle ? 0.6 : 1.0
    }

    private var isIdle: Bool { model.state == .idle }

    var body: some View {
        let thickness = model.isVertical ? model.minimumPillSize.width
                                         : model.minimumPillSize.height
        let insetAcross: CGFloat = 6
        let insetAlong: CGFloat = thickness / 2 + 4

        return content
            .padding(.horizontal, model.isVertical ? insetAcross : insetAlong)
            .padding(.vertical, model.isVertical ? insetAlong : insetAcross)
            .frame(minWidth: model.minimumPillSize.width,
                   minHeight: model.minimumPillSize.height)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(isIdle ? AnyShapeStyle(.ultraThinMaterial)
                                 : AnyShapeStyle(Color.black.opacity(0.88)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Color.white.opacity(isIdle ? 0.15 : 0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(isIdle ? 0.15 : 0),
                            radius: isIdle ? 8 : 0, x: 0, y: isIdle ? 2 : 0)
                    .opacity(pillOpacity)
            )
            .fixedSize()
            .padding(Halo.inset)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { model.onPanelInvalidated?() }
                        .onChange(of: geo.size) { model.onPanelInvalidated?() }
                }
            )
            .animation(.easeInOut(duration: 0.25), value: pillOpacity)
            .onReceive(ticker) { now = $0 }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if model.isVertical {
                VStack(spacing: 12) {
                    innerContent
                }
            } else {
                HStack(spacing: 12) {
                    innerContent
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if case .showing = model.state { model.state = .idle }
            if case .pasted = model.state { model.state = .idle }
        }
    }

    private var sizeMultiplier: CGFloat {
        switch settings.widgetSize {
        case .small: return 1.0
        case .medium: return 1.25
        case .large: return 1.5
        }
    }

    private var orbSize: CGFloat {
        let baseSize: CGFloat = model.state == .idle ? 8.0 : 12.0
        return baseSize * sizeMultiplier
    }

    private var barsCount: Int {
        switch settings.widgetSize {
        case .small: return 7
        case .medium: return 11
        case .large: return 15
        }
    }

    private var toggleIconSize: CGFloat {
        switch settings.widgetSize {
        case .small: return 11
        case .medium: return 14
        case .large: return 18
        }
    }

    private var textMaxWidth: CGFloat {
        if model.isVertical { return settings.widgetSize == .large ? 150 : 110 }
        return settings.widgetSize == .large ? 372 : 312
    }

    private var toggleButtonFrame: CGSize {
        switch settings.widgetSize {
        case .small: return model.isVertical ? CGSize(width: 20, height: 28) : CGSize(width: 28, height: 20)
        case .medium: return model.isVertical ? CGSize(width: 26, height: 38) : CGSize(width: 38, height: 26)
        case .large: return model.isVertical ? CGSize(width: 36, height: 48) : CGSize(width: 48, height: 36)
        }
    }

    @ViewBuilder
    private var innerContent: some View {
        switch model.state {
        case .idle:
            GlowOrb(color1: Color(white: 0.45), color2: Color(white: 0.35), size: orbSize, isPulsing: false)

            if settings.ollamaEnabled {
                if model.isVertical {
                    VStack(spacing: 0) { idleButtons }
                        .background(Color.black.opacity(0.45))
                        .cornerRadius(4)
                } else {
                    HStack(spacing: 0) { idleButtons }
                        .background(Color.black.opacity(0.45))
                        .cornerRadius(4)
                }
            }

            if let recent = recentTranscription {
                copyButton(recent)
            }

        case .recording:
            let colors = settings.llmMode == .formatter ? (settings.formatterTheme.color1, settings.formatterTheme.color2) : (settings.assistantTheme.color1, settings.assistantTheme.color2)
            GlowOrb(color1: colors.0, color2: colors.1, size: orbSize, isPulsing: true)
            WaveformBars(isAnimating: true, barColor: Color(white: 0.85), barCount: barsCount, isVertical: model.isVertical)
            cancelButton

        case .transcribing:
            let colors = settings.llmMode == .formatter ? (settings.formatterTheme.color1, settings.formatterTheme.color2) : (settings.assistantTheme.color1, settings.assistantTheme.color2)
            GlowOrb(color1: colors.0, color2: colors.1, size: orbSize, isPulsing: true)
            WaveformBars(isAnimating: false, barColor: Color(white: 0.5), barCount: barsCount, isVertical: model.isVertical)
            cancelButton

        case .llmProcessing:
            let colors = settings.llmMode == .formatter ? (settings.formatterTheme.color1, settings.formatterTheme.color2) : (settings.assistantTheme.color1, settings.assistantTheme.color2)
            GlowOrb(color1: colors.0, color2: colors.1, size: orbSize, isPulsing: true)
            WaveformBars(isAnimating: true, barColor: Color(white: 0.6), barCount: barsCount, isVertical: model.isVertical)
            cancelButton

        case .showing(let text):
            GlowOrb(color1: .green, color2: Color(red: 0.0, green: 0.7, blue: 0.2), size: 11, isPulsing: false)
            Text(model.styled(text, base: Color(white: 0.92)))
                .font(.system(size: 12, weight: .regular))
                .lineLimit(model.isVertical ? 10 : 5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: textMaxWidth, alignment: model.isVertical ? .center : .leading)
                .multilineTextAlignment(model.isVertical ? .center : .leading)

        case .pasted(let text):
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 14, weight: .medium))
            Text(model.styled(text, base: Color(white: 0.55)))
                .font(.system(size: 12, weight: .regular))
                .lineLimit(model.isVertical ? 10 : 5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: textMaxWidth, alignment: model.isVertical ? .center : .leading)
                .multilineTextAlignment(model.isVertical ? .center : .leading)
        }
    }

    private var cancelButton: some View {
        Button(action: { model.onCancel?() }) {
            Image(systemName: "xmark")
                .font(.system(size: toggleIconSize, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: toggleButtonFrame.width, height: toggleButtonFrame.height)
                .background(Color.black.opacity(0.45))
                .cornerRadius(4)
                .padding(6)
                .contentShape(Rectangle())
                .padding(-6)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Cancel")
        .accessibilityLabel("Cancel dictation")
    }

    private func copyButton(_ text: String) -> some View {
        Button(action: {
            history.copyToClipboard(text)
            justCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { justCopied = false }
        }) {
            Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: toggleIconSize, weight: .bold))
                .foregroundColor(justCopied ? .green : .white.opacity(0.9))
                .frame(width: toggleButtonFrame.width, height: toggleButtonFrame.height)
                .background(Color.black.opacity(0.45))
                .cornerRadius(4)
                .padding(6)
                .contentShape(Rectangle())
                .padding(-6)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Copy last transcription")
        .accessibilityLabel("Copy last transcription")
    }

    @ViewBuilder
    private var idleButtons: some View {
        Button(action: {
            settings.llmMode = .formatter
        }) {
            Image(systemName: "pencil")
                .font(.system(size: toggleIconSize, weight: .bold))
                .foregroundColor(settings.llmMode == .formatter ? .white : .white.opacity(0.9))
                .frame(width: toggleButtonFrame.width, height: toggleButtonFrame.height)
                .background(settings.llmMode == .formatter ? Color.white.opacity(0.2) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())

        Button(action: {
            settings.llmMode = .assistant
        }) {
            Image(systemName: "sparkles")
                .font(.system(size: toggleIconSize, weight: .bold))
                .foregroundColor(settings.llmMode == .assistant ? .white : .white.opacity(0.9))
                .frame(width: toggleButtonFrame.width, height: toggleButtonFrame.height)
                .background(settings.llmMode == .assistant ? Color.white.opacity(0.2) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

