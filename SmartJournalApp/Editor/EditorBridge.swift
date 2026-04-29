//
//  EditorBridge.swift
//  SmartJournalApp
//

import AppKit
import Observation

@Observable
final class EditorBridge {
    @ObservationIgnored weak var textView: NSTextView?
    var fontFamily: EditorFontFamily = EditorFont.currentFamily

    func setFontFamily(_ family: EditorFontFamily) {
        guard family != fontFamily else { return }
        fontFamily = family
        EditorFont.currentFamily = family
        if let tv = textView {
            EditorFont.applyFamily(family, to: tv)
        }
    }
}
