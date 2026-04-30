//
//  AuraNotesApp.swift
//  AuraNotes
//

import SwiftUI
import SwiftData

@main
struct AuraNotesApp: App {
    init() {
        _ = EditorFont.registerBundledFonts
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Entry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(
                    minWidth: 880, idealWidth: 1200,
                    minHeight: 600, idealHeight: 820
                )
        }
        .modelContainer(sharedModelContainer)
        .windowResizability(.contentMinSize)
    }
}
