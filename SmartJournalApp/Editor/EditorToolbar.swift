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

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            iconButton("Undo", systemImage: "arrow.uturn.backward") {
                run { RichTextCommand.performUndo($0) }
            }
            iconButton("Redo", systemImage: "arrow.uturn.forward") {
                run { RichTextCommand.performRedo($0) }
            }

            divider

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
                    .font(.system(size: 13))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 86)
            .help("Heading style (⌘1 / ⌘2 / ⌘3 / ⌘0)")

            divider

            iconButton("Bold (⌘B)", systemImage: "bold") {
                run { RichTextCommand.toggleBold($0) }
            }
            iconButton("Italic (⌘I)", systemImage: "italic") {
                run { RichTextCommand.toggleItalic($0) }
            }
            iconButton("Underline (⌘U)", systemImage: "underline") {
                run { RichTextCommand.toggleUnderline($0) }
            }
            iconButton("Strikethrough", systemImage: "strikethrough") {
                run { RichTextCommand.toggleStrikethrough($0) }
            }

            divider

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
                    .font(.system(size: 13))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 78)
            .help("Editor font (Sans / Serif)")

            divider

            iconButton("Bulleted List", systemImage: "list.bullet") {
                run { RichTextCommand.toggleBulletList($0) }
            }
            iconButton("Numbered List", systemImage: "list.number") {
                run { RichTextCommand.toggleNumberedList($0) }
            }
            iconButton("Todo List", systemImage: "checklist") {
                run { RichTextCommand.toggleTodoList($0) }
            }
            iconButton("Quote", systemImage: "text.quote") {
                run { RichTextCommand.toggleQuote($0) }
            }

            divider

            Menu {
                Button("2 × 2") { run { RichTextCommand.insertTable($0, rows: 2, columns: 2) } }
                Button("3 × 3") { run { RichTextCommand.insertTable($0, rows: 3, columns: 3) } }
                Button("4 × 4") { run { RichTextCommand.insertTable($0, rows: 4, columns: 4) } }
                Button("5 × 3") { run { RichTextCommand.insertTable($0, rows: 5, columns: 3) } }
            } label: {
                Image(systemName: "tablecells")
                    .font(.system(size: iconSize, weight: .regular))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: buttonSize)
            .help("Insert table")

            iconButton("Link (⌘K)", systemImage: "link") {
                run { RichTextCommand.insertLink($0) }
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(
            Capsule(style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
    }

    private var divider: some View {
        Divider()
            .frame(height: 18)
            .padding(.horizontal, Theme.Space.s)
    }

    private func iconButton(_ help: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .regular))
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func run(_ action: (NSTextView) -> Void) {
        guard let tv = bridge.textView else { return }
        action(tv)
        tv.window?.makeFirstResponder(tv)
    }
}
