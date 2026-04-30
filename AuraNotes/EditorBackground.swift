//
//  EditorBackground.swift
//  AuraNotes
//

import AppKit

enum EditorBackground: String, CaseIterable, Identifiable {
    case `default`
    case paper
    case sepia
    case mint
    case lavender
    case rose
    case ocean
    case sand
    case slate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default:  return "Default"
        case .paper:    return "Paper"
        case .sepia:    return "Sepia"
        case .mint:     return "Mint"
        case .lavender: return "Lavender"
        case .rose:     return "Rose"
        case .ocean:    return "Ocean"
        case .sand:     return "Sand"
        case .slate:    return "Slate"
        }
    }

    /// Swatch tint matching the resolved appearance — light shade in light
    /// mode, dark shade in dark mode.
    func swatch(for appearance: NSAppearance? = nil) -> NSColor {
        guard let pair = palette else { return .controlAccentColor }
        let resolved = appearance ?? NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
        let isDark = resolved.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return isDark ? pair.dark : pair.light
    }

    /// A small rounded-square NSImage swatch suitable for inline use in menus
    /// and toolbar labels. Resolves the fill against the current appearance so
    /// dark-mode users see the dark variant.
    func swatchImage(size: CGFloat = 14) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                    xRadius: 3, yRadius: 3)
            let appearance = NSAppearance.currentDrawing()
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            if self == .default {
                NSColor.windowBackgroundColor.setFill()
                path.fill()
                let stroke = isDark
                    ? NSColor.white.withAlphaComponent(0.65)
                    : NSColor.black.withAlphaComponent(0.55)
                stroke.setStroke()
                path.lineWidth = 1.25
                path.stroke()
            } else {
                self.swatch(for: appearance).setFill()
                path.fill()
                let stroke = isDark
                    ? NSColor.white.withAlphaComponent(0.55)
                    : NSColor.black.withAlphaComponent(0.55)
                stroke.setStroke()
                path.lineWidth = 1.25
                path.stroke()
            }
            return true
        }
        image.isTemplate = false
        image.cacheMode = .never
        return image
    }

    /// Resolved dynamic background color. `nil` means "use the system default".
    var color: NSColor {
        guard let pair = palette else { return .textBackgroundColor }
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            return isDark ? pair.dark : pair.light
        }
    }

    private typealias Pair = (light: NSColor, dark: NSColor)

    /// Carefully picked light/dark shades. Lights are soft, low-chroma tints
    /// that stay readable against black text; darks are deep, slightly desaturated
    /// so syntax-colored text in `Theme.EditorColor` keeps ≥ 7:1 contrast.
    private var palette: Pair? {
        switch self {
        case .default:
            return nil
        case .paper:
            return (rgb(0xFA, 0xF7, 0xF2), rgb(0x1C, 0x1B, 0x19))
        case .sepia:
            return (rgb(0xF6, 0xEC, 0xD8), rgb(0x2A, 0x22, 0x18))
        case .mint:
            return (rgb(0xE6, 0xF3, 0xEB), rgb(0x16, 0x26, 0x21))
        case .lavender:
            return (rgb(0xEF, 0xEA, 0xF7), rgb(0x21, 0x1C, 0x2E))
        case .rose:
            return (rgb(0xF8, 0xE9, 0xEC), rgb(0x2A, 0x1A, 0x21))
        case .ocean:
            return (rgb(0xE5, 0xEE, 0xF7), rgb(0x16, 0x1F, 0x2E))
        case .sand:
            return (rgb(0xF3, 0xEA, 0xD8), rgb(0x26, 0x20, 0x18))
        case .slate:
            return (rgb(0xEA, 0xED, 0xF1), rgb(0x1B, 0x1E, 0x24))
        }
    }

    private func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}
