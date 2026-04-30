//
//  EditorBridge.swift
//  AuraNotes
//

import AppKit
import Observation

@Observable
final class EditorBridge {
    private static let spreadKey = "editor.spread"
    private static let backgroundKey = "editor.background"
    private static let assistsKey = "editor.assists"

    @ObservationIgnored weak var textView: NSTextView? {
        didSet {
            (textView as? JournalTextView)?.spread = spread
            textView?.backgroundColor = background.color
            applyAssists(to: textView)
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
    var assistsEnabled: Bool = {
        if UserDefaults.standard.object(forKey: EditorBridge.assistsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: EditorBridge.assistsKey)
    }()

    let dictation = DictationController()

    init() {
        dictation.bridge = self
    }

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

    func setAssistsEnabled(_ enabled: Bool) {
        assistsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.assistsKey)
        applyAssists(to: textView)
    }

    func toggleAssists() {
        setAssistsEnabled(!assistsEnabled)
    }

    private func applyAssists(to tv: NSTextView?) {
        guard let tv else { return }
        let on = assistsEnabled
        tv.isAutomaticQuoteSubstitutionEnabled = on
        tv.isAutomaticDashSubstitutionEnabled = on
        tv.isAutomaticTextReplacementEnabled = on
        tv.isAutomaticSpellingCorrectionEnabled = on
        tv.isContinuousSpellCheckingEnabled = on
        tv.isGrammarCheckingEnabled = on
        tv.isAutomaticLinkDetectionEnabled = on
        tv.smartInsertDeleteEnabled = on
        tv.isAutomaticDataDetectionEnabled = on
    }
}
