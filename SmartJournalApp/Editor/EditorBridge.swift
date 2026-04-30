//
//  EditorBridge.swift
//  SmartJournalApp
//

import AppKit
import Observation

@Observable
final class EditorBridge {
    private static let spreadKey = "editor.spread"
    private static let backgroundKey = "editor.background"

    @ObservationIgnored weak var textView: NSTextView? {
        didSet {
            (textView as? JournalTextView)?.spread = spread
            textView?.backgroundColor = background.color
        }
    }
    var fontFamily: EditorFontFamily = EditorFont.currentFamily
    var spread: EditorSpread = {
        UserDefaults.standard.string(forKey: EditorBridge.spreadKey)
            .flatMap(EditorSpread.init(rawValue:)) ?? .full
    }()
    var background: EditorBackground = {
        UserDefaults.standard.string(forKey: EditorBridge.backgroundKey)
            .flatMap(EditorBackground.init(rawValue:)) ?? .default
    }()

    func setFontFamily(_ family: EditorFontFamily) {
        guard family != fontFamily else { return }
        fontFamily = family
        EditorFont.currentFamily = family
        if let tv = textView {
            EditorFont.applyFamily(family, to: tv)
        }
    }

    func setBackground(_ value: EditorBackground) {
        guard value != background else { return }
        background = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.backgroundKey)
        textView?.backgroundColor = value.color
        textView?.needsDisplay = true
    }

    func setSpread(_ value: EditorSpread) {
        guard value != spread else { return }
        spread = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.spreadKey)
        (textView as? JournalTextView)?.spread = value
    }
}
