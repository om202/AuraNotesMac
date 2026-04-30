//
//  EditorToolbar.swift
//  SmartJournalApp
//

import SwiftUI
import AppKit

struct EditorToolbar: View {
    let bridge: EditorBridge

    private let iconSize: CGFloat = 16
    private let buttonSize: CGFloat = 32
    private let labelFontSize: CGFloat = 14
    private let iconWeight: Font.Weight = .bold

    var body: some View {
        // Order: widest first. ViewThatFits picks the first variant whose
        // ideal width fits the proposed horizontal space; as the window
        // narrows it falls through to progressively more compact layouts.
        ViewThatFits(in: .horizontal) {
            content(level: .full)
            content(level: .wide)
            content(level: .medium)
            content(level: .compact)
            content(level: .minimal)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .glassEffect(.regular, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.40), radius: 24, y: 10)
        .foregroundStyle(.primary)
    }

    /// Layout tiers — items drop into the overflow menu as we shrink.
    /// `full`  → everything inline.
    /// `wide`  → drops the Sans/Serif font menu (still discoverable in app menus).
    /// `medium`→ also drops underline + strikethrough + code → overflow.
    /// `compact`→ also drops numbered list, todo list, quote, table → overflow.
    /// `minimal`→ keeps only undo/redo, style, bold, italic, bullet, link;
    ///            everything else lives in the overflow.
    private enum Level { case full, wide, medium, compact, minimal }

    @ViewBuilder
    private func content(level: Level) -> some View {
        HStack(spacing: Theme.Space.m) {
            iconButton("Undo", systemImage: "arrow.uturn.backward") {
                run { RichTextCommand.performUndo($0) }
            }
            iconButton("Redo", systemImage: "arrow.uturn.forward") {
                run { RichTextCommand.performRedo($0) }
            }

            divider

            styleMenu

            if level == .full {
                fontMenu
            }

            divider

            iconButton("Bold (⌘B)", systemImage: "bold") {
                run { RichTextCommand.toggleBold($0) }
            }
            iconButton("Italic (⌘I)", systemImage: "italic") {
                run { RichTextCommand.toggleItalic($0) }
            }

            if level == .full || level == .wide {
                iconButton("Underline (⌘U)", systemImage: "underline") {
                    run { RichTextCommand.toggleUnderline($0) }
                }
                iconButton(
                    "Strikethrough (⌘⇧X)",
                    systemImage: "strikethrough",
                    shortcut: "x", modifiers: [.command, .shift]
                ) {
                    run { RichTextCommand.toggleStrikethrough($0) }
                }
                iconButton(
                    "Code (⌘E)",
                    systemImage: "curlybraces",
                    shortcut: "e", modifiers: .command
                ) {
                    run { RichTextCommand.toggleCode($0) }
                }
            }

            divider

            iconButton(
                "Bulleted List (⌘⇧8)",
                systemImage: "list.bullet",
                shortcut: "8", modifiers: [.command, .shift]
            ) {
                run { RichTextCommand.toggleBulletList($0) }
            }

            if level != .minimal {
                iconButton(
                    "Numbered List (⌘⇧7)",
                    systemImage: "list.number",
                    shortcut: "7", modifiers: [.command, .shift]
                ) {
                    run { RichTextCommand.toggleNumberedList($0) }
                }
            }

            if level == .full || level == .wide || level == .medium {
                iconButton(
                    "Todo List (⌘⇧L)",
                    systemImage: "checklist",
                    shortcut: "l", modifiers: [.command, .shift]
                ) {
                    run { RichTextCommand.toggleTodoList($0) }
                }
                iconButton(
                    "Quote (⌘⇧.)",
                    systemImage: "text.quote",
                    shortcut: ".", modifiers: [.command, .shift]
                ) {
                    run { RichTextCommand.toggleQuote($0) }
                }

                divider

                tableMenu
            }

            iconButton("Link (⌘K)", systemImage: "link") {
                run { RichTextCommand.insertLink($0) }
            }

            if level != .full {
                overflowMenu(level: level)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Inline submenus

    private var styleMenu: some View {
        Menu {
            Button("Title") { run { RichTextCommand.setHeadingLevel($0, level: 1) } }
                .keyboardShortcut("1", modifiers: .command)
            Button("Heading") { run { RichTextCommand.setHeadingLevel($0, level: 2) } }
                .keyboardShortcut("2", modifiers: .command)
            Button("Subheading") { run { RichTextCommand.setHeadingLevel($0, level: 3) } }
                .keyboardShortcut("3", modifiers: .command)
            Divider()
            Button("Body") { run { RichTextCommand.setHeadingLevel($0, level: 0) } }
                .keyboardShortcut("0", modifiers: .command)
        } label: {
            Label("Style", systemImage: "textformat.size")
                .font(.system(size: labelFontSize, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 110)
        .help("Heading style (⌘1 / ⌘2 / ⌘3 / ⌘0)")
    }

    private var fontMenu: some View {
        Menu {
            ForEach(EditorFontFamily.allCases) { family in
                Button {
                    bridge.setFontFamily(family)
                } label: {
                    if family == bridge.fontFamily {
                        Label(family.displayName, systemImage: "checkmark")
                    } else {
                        Text(family.displayName)
                    }
                }
            }
        } label: {
            Label(bridge.fontFamily.shortName, systemImage: "textformat")
                .font(.system(size: labelFontSize, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 100)
        .help("Editor font (Sans / Serif)")
    }

    private var tableMenu: some View {
        Menu {
            Button("2 × 2") { run { RichTextCommand.insertTable($0, rows: 2, columns: 2) } }
            Button("3 × 3") { run { RichTextCommand.insertTable($0, rows: 3, columns: 3) } }
            Button("4 × 4") { run { RichTextCommand.insertTable($0, rows: 4, columns: 4) } }
            Button("5 × 3") { run { RichTextCommand.insertTable($0, rows: 5, columns: 3) } }
        } label: {
            Image(systemName: "tablecells")
                .font(.system(size: iconSize, weight: iconWeight))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: buttonSize)
        .help("Insert table")
    }

    // MARK: - Overflow

    @ViewBuilder
    private func overflowMenu(level: Level) -> some View {
        Menu {
            if level != .full {
                Button("Sans") { bridge.setFontFamily(.sans) }
                Button("Serif") { bridge.setFontFamily(.serif) }
                Divider()
            }
            if level == .medium || level == .compact || level == .minimal {
                Button("Underline") { run { RichTextCommand.toggleUnderline($0) } }
                Button("Strikethrough") { run { RichTextCommand.toggleStrikethrough($0) } }
                Button("Code") { run { RichTextCommand.toggleCode($0) } }
                Divider()
            }
            if level == .compact || level == .minimal {
                Button("Numbered List") { run { RichTextCommand.toggleNumberedList($0) } }
                Button("Todo List") { run { RichTextCommand.toggleTodoList($0) } }
                Button("Quote") { run { RichTextCommand.toggleQuote($0) } }
                Divider()
                Menu("Insert Table") {
                    Button("2 × 2") { run { RichTextCommand.insertTable($0, rows: 2, columns: 2) } }
                    Button("3 × 3") { run { RichTextCommand.insertTable($0, rows: 3, columns: 3) } }
                    Button("4 × 4") { run { RichTextCommand.insertTable($0, rows: 4, columns: 4) } }
                    Button("5 × 3") { run { RichTextCommand.insertTable($0, rows: 5, columns: 3) } }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: iconSize, weight: iconWeight))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: buttonSize)
        .help("More")
    }

    private var divider: some View {
        Rectangle()
            .fill(.primary.opacity(0.25))
            .frame(width: 1, height: 18)
            .padding(.horizontal, Theme.Space.xs)
    }

    @ViewBuilder
    private func iconButton(
        _ help: String,
        systemImage: String,
        shortcut: KeyEquivalent? = nil,
        modifiers: EventModifiers = [],
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: iconWeight))
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)

        if let shortcut {
            button.keyboardShortcut(shortcut, modifiers: modifiers)
        } else {
            button
        }
    }

    private func run(_ action: (NSTextView) -> Void) {
        guard let tv = bridge.textView else { return }
        action(tv)
        tv.window?.makeFirstResponder(tv)
    }
}
