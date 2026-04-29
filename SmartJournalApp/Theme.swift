//
//  Theme.swift
//  SmartJournalApp
//

import SwiftUI
import AppKit

enum Theme {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    enum Size {
        static let editorMaxWidth: CGFloat = 720
        static let sidebarMin: CGFloat = 240
        static let sidebarIdeal: CGFloat = 280
        static let rowMinHeight: CGFloat = 44
    }

    enum Radius {
        static let s: CGFloat = 6
        static let m: CGFloat = 10
    }

    enum FontSize {
        static let body: CGFloat = 18
        static let title: CGFloat = 34
        static let heading: CGFloat = 26
        static let subheading: CGFloat = 21
        static let bodyLineHeightMultiple: CGFloat = 1.5
    }

    /// In dark mode, an Xcode-inspired palette tuned for ≥ 7:1 contrast on
    /// the 41/42/47 editor canvas. In light mode, defers to system colors so
    /// the editor looks native on a white page.
    enum EditorColor {
        static let background = dynamic(
            dark:  NSColor(srgbRed: 41/255, green: 42/255, blue: 47/255, alpha: 1),
            light: .textBackgroundColor
        )
        static let body = dynamic(
            dark:  NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
            light: .labelColor
        )
        static let title = dynamic(
            dark:  NSColor(srgbRed: 0xFF/255, green: 0xA8/255, blue: 0xCB/255, alpha: 1),
            light: .labelColor
        )
        static let heading = dynamic(
            dark:  NSColor(srgbRed: 0xE5/255, green: 0xC9/255, blue: 0xFF/255, alpha: 1),
            light: .labelColor
        )
        static let subheading = dynamic(
            dark:  NSColor(srgbRed: 0x9C/255, green: 0xEC/255, blue: 0xFF/255, alpha: 1),
            light: .labelColor
        )
        static let code = dynamic(
            dark:  NSColor(srgbRed: 0xFF/255, green: 0xB1/255, blue: 0x99/255, alpha: 1),
            light: .labelColor
        )
        static let link = dynamic(
            dark:  NSColor(srgbRed: 0x9E/255, green: 0xD1/255, blue: 0xFF/255, alpha: 1),
            light: .linkColor
        )
        static let quote = dynamic(
            dark:  NSColor(srgbRed: 0xB8/255, green: 0xBE/255, blue: 0xC4/255, alpha: 1),
            light: .tertiaryLabelColor
        )
        static let listMarker = dynamic(
            dark:  NSColor(srgbRed: 0x9B/255, green: 0xE0/255, blue: 0xCC/255, alpha: 1),
            light: .labelColor
        )

        private static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
            NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                return isDark ? dark : light
            }
        }
    }
}
