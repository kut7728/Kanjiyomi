//
//  KanjiyomiApp.swift
//  Kanjiyomi
//

import SwiftData
import SwiftUI

@main
struct KanjiyomiApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([VocabWord.self, WordCache.self, ScanRecord.self])
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
        }
        .modelContainer(sharedModelContainer)
    }
}
