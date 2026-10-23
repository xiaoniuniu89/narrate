// Narrate — a menu bar app for talking while you investigate.
//
//  Menu bar mic → "Start narrating" (or ⌃⌥⌘N). A red stop button appears.
//  Anything you copy lands inline, exactly where you were in the sentence.
//  Click it (or ⌃⌥⌘N) to stop → the whole narration is put on your clipboard.
//
//  Transcription uses Apple's built-in on-device speech recognition:
//  no model download, no third-party service, audio never leaves the Mac.
//  The latest session is also saved live to last.md (overwritten each time) in
//  ~/Library/Application Support/Narrate — open it from the menu.
//
//  The menu bar icon also has "Edit vocabulary…", "Open last narration", "Quit".
//  Vocabulary (vocab.txt, same folder) teaches the recogniser your jargon.

import AppKit
import AVFoundation
import Carbon.HIToolbox
import Speech

// MARK: - Transcription

final class Segment {
    let request = SFSpeechAudioBufferRecognitionRequest()
    var task: SFSpeechRecognitionTask?
    var text = ""
    var done = false
    let started = Date()
    var lastChange = Date()
}

enum Entry {
    case speech(Segment)
    case clip(String?)
}

enum NarratorState {
    case idle, recording, finishing
    case error(String)
}

final class Narrator {
    /// Out of the way, where Mac apps normally keep their data:
    /// ~/Library/Application Support/Narrate
    static let outDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Narrate")
    static let vocabURL = outDir.appendingPathComponent("vocab.txt")
    static let lastURL = outDir.appendingPathComponent("last.md")

    /// Terms the recogniser should expect, written the way you want them spelled.
    /// Edit vocab.txt via the menu (one per line) to add your own — no rebuild needed.
    static let defaultVocab = """
        # Narrate vocabulary — words the speech recogniser should expect.
        # This list is yours: add, remove or reorder anything. It only lives on this Mac.
        # One term per line, spelled how you want it to appear. Lines starting with # are ignored.
        # Changes apply the next time you start recording.

        # React / TypeScript
        React
        TypeScript
        JavaScript
        JSX
        TSX
        useEffect
        useState
        useMemo
        useCallback
        useRef
        useContext
        useReducer
        props
        prop drilling
        re-render
        hook
        component
        Redux
        Next.js
        Node.js
        npm
        Yarn
        pnpm
        Webpack
        Vite
        Babel
        ESLint
        Prettier
        Jest
        Playwright
        async
        await
        Promise
        undefined
        null
        NaN
        enum
        interface
        generic
        tsconfig
        package.json
        node_modules

        # Browser devtools
        DevTools
        network tab
        console error
        stack trace
        payload
        request headers
        response headers
        status code
        200
        401
        403
        404
        500
        CORS
        preflight
        XHR
        fetch
        JSON
        API
        REST
        GraphQL
        endpoint
        localStorage
        sessionStorage
        cookie
        DOM
        CSS
        HTML
        URL
        localhost

        # CI / Git
        TeamCity
        GitHub
        GitHub Actions
        pull request
        PR
        repo
        branch
        commit
        rebase
        merge conflict
        pipeline
        build agent
        build config
        artifact
        Claude
        Claude Code

        # Your own terms — company names, product names, internal tools
        """

    static func loadVocab() -> [String] {
        let fm = FileManager.default
        if !fm.fileExists(atPath: vocabURL.path) {
            try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)
            // Carry over a vocab list from early versions (~/narrations/vocab.txt).
            let old = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("narrations/vocab.txt")
            if (try? fm.copyItem(at: old, to: vocabURL)) == nil {
                try? defaultVocab.write(to: vocabURL, atomically: true, encoding: .utf8)
            }
        }
        let text = (try? String(contentsOf: vocabURL, encoding: .utf8)) ?? defaultVocab
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private var vocab: [String] = []

    var onState: (NarratorState) -> Void = { _ in }
    private(set) var state: NarratorState = .idle { didSet { onState(state) } }

    private let recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var current: Segment?      // segment the mic is currently feeding
    private var entries: [Entry] = []  // speech + clipboard items, in order
    private var fileURL: URL?
    private var header = ""
    private var pbCount = 0
    private var timer: Timer?

    init() {
        // First English locale that can run fully on-device.
        recognizer = ["en-IE", "en-GB", "en-US"]
            .compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
            .first { $0.supportsOnDeviceRecognition }
    }

    func toggle() {
        switch state {
        case .recording: stop()
        case .finishing: break
        default: start()
        }
    }

    // MARK: Start / stop

    func start() {
        guard let recognizer, recognizer.isAvailable else {
            NSSound(named: "Basso")?.play()
            state = .error("On-device speech recognition isn't available. "
                + "Turn on Dictation in System Settings → Keyboard, then try again.")
            return
        }

        try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        let now = Date()
        let fmt = DateFormatter()
        fileURL = Self.lastURL  // only the latest narration is kept
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        header = "# Narration \(fmt.string(from: now))\n\n"
        entries = []
        vocab = Self.loadVocab()
        pbCount = NSPasteboard.general.changeCount
        entries.append(.speech(rotate()))

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) {
            [weak self] buffer, _ in
            guard let self else { return }
            self.lock.lock()
            let request = self.current?.request
            self.lock.unlock()
            request?.append(buffer)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            current?.task?.cancel()
            current = nil
            state = .error("Couldn't start the microphone: \(error.localizedDescription)")
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
        save()
        state = .recording
        NSSound(named: "Tink")?.play()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        let last = current
        current = nil
        lock.unlock()
        last?.request.endAudio()

        state = .finishing
        NSSound(named: "Pop")?.play()
        finish(deadline: Date().addingTimeInterval(10))
    }

    /// Wait for every segment to finalise (or time out), then copy everything.
    private func finish(deadline: Date) {
        let pending = entries.contains {
            if case .speech(let s) = $0 { return !s.done }
            return false
        }
        if pending && Date() < deadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.finish(deadline: deadline)
            }
            return
        }
        for case .speech(let s) in entries where !s.done { s.task?.cancel() }
        save()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(render(), forType: .string)
        state = .idle
        NSSound(named: "Glass")?.play()
    }

    // MARK: Segments

    /// Start a fresh recognition segment and close the previous one.
    /// Closing it (endAudio) lets it finish transcribing what it already heard.
    private func rotate() -> Segment {
        let seg = Segment()
        seg.request.shouldReportPartialResults = true
        seg.request.requiresOnDeviceRecognition = true
        seg.request.addsPunctuation = true
        seg.request.contextualStrings = vocab
        seg.task = recognizer?.recognitionTask(with: seg.request) { [weak self] result, error in
            DispatchQueue.main.async {
                if let result {
                    seg.text = result.bestTranscription.formattedString
                    seg.lastChange = Date()
                    if result.isFinal { seg.done = true }
                }
                if error != nil { seg.done = true }
                if seg.done { seg.task = nil }
                self?.save()
            }
        }
        lock.lock()
        let old = current
        current = seg
        lock.unlock()
        old?.request.endAudio()
        return seg
    }

    private func tick() {
        // A copy splits the speech and drops the clipboard text in between.
        let pb = NSPasteboard.general
        if pb.changeCount != pbCount {
            pbCount = pb.changeCount
            let clip = pb.string(forType: .string)
            let next = rotate()
            entries.append(.clip(clip))
            entries.append(.speech(next))
            save()
            return
        }
        // Keep segments under about a minute, preferring to cut at a pause.
        guard let cur = current else { return }
        let now = Date()
        let age = now.timeIntervalSince(cur.started)
        let quiet = now.timeIntervalSince(cur.lastChange)
        if (age > 45 && quiet > 0.8) || age > 55 {
            entries.append(.speech(rotate()))
        }
    }

    // MARK: Output

    private func render() -> String {
        var out = header
        for entry in entries {
            switch entry {
            case .speech(let s):
                let t = s.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { out += t + "\n\n" }
            case .clip(let c):
                out += Self.formatClip(c)
            }
        }
        return out
    }

    static func formatClip(_ clip: String?) -> String {
        guard let clip else { return "[copied: non-text item]\n\n" }
        let t = clip.trimmingCharacters(in: .newlines)
        if t.contains("\n") || t.count > 120 { return "[copied]\n~~~\n\(t)\n~~~\n\n" }
        return "[copied] \(t)\n\n"
    }

    private func save() {
        guard let fileURL else { return }
        try? render().write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - Floating stop button (only shown while recording)

final class StopButton: NSView {
    var onClick: () -> Void = {}
    var color: NSColor = .systemRed { didSet { needsDisplay = true } }
    var symbol = "stop.fill" { didSet { needsDisplay = true } }
    private var dragged = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4)).fill()
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "Stop")
        else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        let img = base.withSymbolConfiguration(config) ?? base
        let s = img.size
        img.draw(in: NSRect(x: bounds.midX - s.width / 2, y: bounds.midY - s.height / 2,
                            width: s.width, height: s.height))
    }

    // Click stops; click-and-drag moves the button.
    override func mouseDown(with event: NSEvent) { dragged = false }
    override func mouseDragged(with event: NSEvent) {
        if !dragged {
            dragged = true
            window?.performDrag(with: event)
        }
    }
    override func mouseUp(with event: NSEvent) { if !dragged { onClick() } }
}

// MARK: - Global hotkey (⌃⌥⌘N) — Carbon, so no Accessibility permission needed

private var hotKeyAction: (() -> Void)?
private var hotKeyRef: EventHotKeyRef?

func registerHotKey(_ action: @escaping () -> Void) {
    hotKeyAction = action
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                             eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
        DispatchQueue.main.async { hotKeyAction?() }
        return noErr
    }, 1, &spec, nil, nil)
    let id = EventHotKeyID(signature: OSType(0x4E41_5252), id: 1)  // 'NARR'
    RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey | cmdKey),
                        id, GetApplicationEventTarget(), 0, &hotKeyRef)
}

// MARK: - App (menu bar icon + floating stop button)

final class AppDelegate: NSObject, NSApplicationDelegate {
    let narrator = Narrator()
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let toggleItem = NSMenuItem(title: "Start narrating", action: #selector(toggle),
                                keyEquivalent: "")
    let button = StopButton(frame: NSRect(x: 0, y: 0, width: 56, height: 56))
    var panel: NSPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        // Menu bar icon and its menu
        let menu = NSMenu()
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Edit vocabulary…", action: #selector(editVocab),
                     keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open last narration", action: #selector(openLast),
                     keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Narrate", action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        statusItem.menu = menu

        // Floating stop button — hidden until you start recording
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        panel = NSPanel(
            contentRect: NSRect(x: screen.maxX - 90, y: screen.minY + 90, width: 56, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],  // clicking it won't steal focus
            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = button
        button.onClick = { [weak self] in self?.toggle() }

        narrator.onState = { [weak self] state in self?.show(state) }
        show(.idle)

        registerHotKey { [weak self] in self?.toggle() }
    }

    @objc func toggle() { narrator.toggle() }

    func setIcon(_ name: String) {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Narrate")
        img?.isTemplate = true
        statusItem.button?.image = img
    }

    func show(_ state: NarratorState) {
        switch state {
        case .idle:
            setIcon("text.bubble")
            statusItem.button?.toolTip = "Narrate — ⌃⌥⌘N to start"
            toggleItem.title = "Start narrating   ⌃⌥⌘N"
            toggleItem.isEnabled = true
            panel.orderOut(nil)
        case .recording:
            setIcon("text.bubble.fill")
            statusItem.button?.toolTip = "Recording — click the red button or ⌃⌥⌘N to stop"
            toggleItem.title = "Stop & copy   ⌃⌥⌘N"
            toggleItem.isEnabled = true
            button.color = .systemRed
            button.symbol = "stop.fill"
            button.toolTip = "Stop and copy to clipboard"
            panel.orderFrontRegardless()
        case .finishing:
            setIcon("ellipsis.bubble")
            toggleItem.title = "Finishing…"
            toggleItem.isEnabled = false
            button.color = .systemOrange
            button.symbol = "ellipsis"
            button.toolTip = "Finishing transcription…"
        case .error(let message):
            setIcon("exclamationmark.bubble")
            toggleItem.title = "Start narrating   ⌃⌥⌘N"
            toggleItem.isEnabled = true
            panel.orderOut(nil)
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Narrate"
            alert.informativeText = message
            alert.runModal()
            setIcon("text.bubble")
        }
    }

    @objc func openLast() {
        if FileManager.default.fileExists(atPath: Narrator.lastURL.path) {
            NSWorkspace.shared.open(Narrator.lastURL)
        } else {
            NSSound.beep()  // nothing recorded yet
        }
    }

    @objc func editVocab() {
        _ = Narrator.loadVocab()  // creates the file with defaults if missing
        NSWorkspace.shared.open(Narrator.vocabURL)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // no Dock icon — lives in the menu bar
app.run()
