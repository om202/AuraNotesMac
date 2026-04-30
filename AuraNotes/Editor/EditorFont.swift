//
//  EditorFont.swift
//  AuraNotes
//

import AppKit
import CoreText

enum EditorFontFamily: String, CaseIterable, Identifiable {
    case sans
    case serif

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .sans: return "Sans"
        case .serif: return "Serif"
        }
    }

    var displayName: String {
        switch self {
        case .sans: return "Source Sans 3"
        case .serif: return "Source Serif 4"
        }
    }

    var familyName: String {
        switch self {
        case .sans: return "Source Sans 3"
        case .serif: return "Source Serif 4"
        }
    }

    /// Optical-size compensation. Both families have similar x-heights,
    /// so no scaling is needed.
    var sizeScale: CGFloat {
        switch self {
        case .sans: return 1.0
        case .serif: return 1.0
        }
    }

    static func family(of font: NSFont) -> EditorFontFamily? {
        guard let name = font.familyName else { return nil }
        return allCases.first { $0.familyName == name }
    }

    /// `logicalSize` is the design-system size (e.g. `Theme.FontSize.body`).
    /// The actual rendered size is `logicalSize * sizeScale`.
    func font(size logicalSize: CGFloat,
              weight: NSFont.Weight = .regular,
              italic: Bool = false) -> NSFont {
        let renderedSize = logicalSize * sizeScale
        var descriptor = NSFontDescriptor()
            .withFamily(familyName)
            .addingAttributes([
                .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]
            ])
        if italic {
            descriptor = descriptor.withSymbolicTraits(.italic)
        }
        return NSFont(descriptor: descriptor, size: renderedSize)
            ?? NSFont.systemFont(ofSize: renderedSize, weight: weight)
    }

    func font(matching old: NSFont) -> NSFont {
        let traits = old.fontDescriptor.symbolicTraits
        let oldScale = EditorFontFamily.family(of: old)?.sizeScale ?? 1
        let logicalSize = old.pointSize / oldScale
        return font(
            size: logicalSize,
            weight: old.editorWeight,
            italic: traits.contains(.italic)
        )
    }
}

enum EditorFont {
    private static let storageKey = "editor.fontFamily"

    static var currentFamily: EditorFontFamily {
        get {
            UserDefaults.standard.string(forKey: storageKey)
                .flatMap(EditorFontFamily.init(rawValue:)) ?? .sans
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }

    static let registerBundledFonts: Void = {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf",
                                          subdirectory: nil) else { return }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    /// Replace every `.font` run in the storage with the equivalent variant in `family`.
    static func applyFamily(_ family: EditorFontFamily,
                            to storage: NSMutableAttributedString) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        storage.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
            let old = (value as? NSFont) ?? NSFont.systemFont(ofSize: Theme.FontSize.body)
            storage.addAttribute(.font, value: family.font(matching: old), range: range)
        }
    }

    /// Apply `family` to the current text view content and typing attributes.
    static func applyFamily(_ family: EditorFontFamily, to tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)

        if full.length > 0,
           tv.shouldChangeText(in: full, replacementString: nil) {
            storage.beginEditing()
            applyFamily(family, to: storage)
            storage.endEditing()
            tv.didChangeText()
        }

        var typing = tv.typingAttributes
        let old = (typing[.font] as? NSFont) ?? NSFont.systemFont(ofSize: Theme.FontSize.body)
        typing[.font] = family.font(matching: old)
        tv.typingAttributes = typing
    }
}

extension NSFont {
    /// The numeric weight stored in the font descriptor's traits dictionary,
    /// converted to an `NSFont.Weight`. Falls back to `.regular`.
    var editorWeight: NSFont.Weight {
        let traits = fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        if let raw = traits?[.weight] as? CGFloat {
            return NSFont.Weight(raw)
        }
        if let raw = traits?[.weight] as? Double {
            return NSFont.Weight(CGFloat(raw))
        }
        return .regular
    }
}
