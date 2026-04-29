//
//  EditorToolbar.swift
//  SmartJournalApp
//

import SwiftUI
import AppKit

struct EditorToolbar: View {
    let bridge: EditorBridge

    var body: some View {
        HStack(spacing: 2) {
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
            }
            .menuStyle(.borderlessButton)
            .frame(width: 70)
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
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 30)
            .help("Insert table")

            iconButton("Link (⌘K)", systemImage: "link") {
                run { RichTextCommand.insertLink($0) }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .controlSize(.small)
    }

    private var divider: some View {
        Divider().frame(height: 14).padding(.horizontal, 4)
    }

    private func iconButton(_ help: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 22, height: 22)
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
