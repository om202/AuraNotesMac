//
//  Theme.swift
//  AuraNotes
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

    /// All structural text — titles, headings, code, list markers, quote bars —
    /// renders in the body color. The only special color is `link`, applied
    /// via `linkTextAttributes` so it's strictly bound to link runs and never
    /// inherits into surrounding typing attributes.
    enum EditorColor {
        static let background = dynamic(
            dark:  NSColor(srgbRed: 41/255, green: 42/255, blue: 47/255, alpha: 1),
            light: .textBackgroundColor
        )
        static let body = dynamic(
            dark:  NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
            light: .labelColor
        )
        static let title      = body
        static let heading    = body
        static let subheading = body
        static let code       = body
        static let quote      = body
        static let listMarker = body
        static let link = dynamic(
            dark:  NSColor(srgbRed: 0x9E/255, green: 0xD1/255, blue: 0xFF/255, alpha: 1),
            light: .linkColor
        )

        private static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
            NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                return isDark ? dark : light
            }
        }
    }
}
