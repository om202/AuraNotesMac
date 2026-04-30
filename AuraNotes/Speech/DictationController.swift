//
//  DictationController.swift
//  AuraNotes
//
//  Bridges DictationService to the active NSTextView. Manages a
//  "volatile range" — the slice of text currently being refined by
//  the recognizer — so the editor shows live updates that solidify
//  into final text without ever leaving the cursor in a weird spot.
//

import AppKit
import Observation

@Observable
@MainActor
final class DictationController {
    private(set) var isRecording = false
    var lastError: String?

    @ObservationIgnored private let service = DictationService()
    @ObservationIgnored weak var bridge: EditorBridge?
    @ObservationIgnored private var volatileRange: NSRange?
    @ObservationIgnored private var liveTask: Task<Void, Never>?

    func toggle() {
        if isRecording {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard !isRecording, let tv = bridge?.textView else { return }

        // Replace any current selection so dictation overwrites it,
        // matching how typing behaves.
        let selection = tv.selectedRange()
        if selection.length > 0,
           tv.shouldChangeText(in: selection, replacementString: "") {
            tv.textStorage?.deleteCharacters(in: selection)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: selection.location, length: 0))
        }

        volatileRange = NSRange(location: tv.selectedRange().location, length: 0)
        isRecording = true
        lastError = nil

        liveTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.service.start { [weak self] update in
                    self?.apply(update)
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                self.lastError = message
                self.isRecording = false
                self.volatileRange = nil
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        volatileRange = nil
        let svc = service
        Task { try? await svc.stop() }
        liveTask?.cancel()
        liveTask = nil
    }

    // MARK: - Apply transcript updates

    private func apply(_ update: DictationUpdate) {
        guard isRecording,
              let tv = bridge?.textView,
              let storage = tv.textStorage,
              var range = volatileRange else { return }

        // Defensively clamp the range against the current storage length
        // — the user may have edited elsewhere while we were transcribing.
        let len = storage.length
        if range.location > len { range.location = len }
        if range.location + range.length > len {
            range.length = len - range.location
        }

        let text = update.text
        guard tv.shouldChangeText(in: range, replacementString: text) else { return }

        let baseAttrs = tv.typingAttributes
        var insertAttrs = baseAttrs
        insertAttrs[.foregroundColor] = (baseAttrs[.foregroundColor] as? NSColor) ?? Theme.EditorColor.body
        storage.replaceCharacters(
            in: range,
            with: NSAttributedString(string: text, attributes: insertAttrs)
        )
        tv.didChangeText()

        let insertedLength = (text as NSString).length
        let cursor = range.location + insertedLength

        if update.isFinal {
            // Final text is committed — next volatile preview starts after it.
            volatileRange = NSRange(location: cursor, length: 0)
        } else {
            // Volatile preview spans the just-inserted text; next refinement
            // will overwrite it in place.
            volatileRange = NSRange(location: range.location, length: insertedLength)
        }
        tv.setSelectedRange(NSRange(location: cursor, length: 0))
        tv.scrollRangeToVisible(NSRange(location: cursor, length: 0))
    }
}
