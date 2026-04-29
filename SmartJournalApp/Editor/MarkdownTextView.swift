//
//  MarkdownTextView.swift
//  SmartJournalApp
//

import AppKit

final class MarkdownTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.option),
           !event.modifierFlags.contains(.control),
           let chars = event.charactersIgnoringModifiers
        {
            switch chars {
            case "b":
                MarkdownCommand.toggleWrap(self, marker: "**"); return
            case "i":
                MarkdownCommand.toggleWrap(self, marker: "*"); return
            case "`":
                MarkdownCommand.toggleWrap(self, marker: "`"); return
            case "k":
                MarkdownCommand.insertLink(self); return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        if MarkdownCommand.continueListIfNeeded(self) { return }
        super.insertNewline(sender)
    }
}
