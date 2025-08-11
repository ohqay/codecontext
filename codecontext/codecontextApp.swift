//
//  codecontextApp.swift
//  codecontext
//
//  Created by Tarek Alexander on 08-08-2025.
//

import SwiftData
import SwiftUI

@main
struct codecontextApp: App {
    @State private var notificationSystem = NotificationSystem()
    @State private var tokenizerInitialized = false

    init() {
        // Enable native window tabbing for macOS
        #if os(macOS)
            NSWindow.allowsAutomaticWindowTabbing = true
        #endif

        // Initialize tokenizer immediately at app startup
        // This ensures tokenization is always available and accurate
        Task {
            do {
                try await TokenizerService.shared.initialize()
                print("[App] Tokenizer initialized successfully")
            } catch {
                // This should never happen with bundled tokenizer data
                // In debug builds, we want to catch this immediately
                #if DEBUG
                    fatalError("[App] CRITICAL: Failed to initialize tokenizer: \(error)")
                #else
                    print("[App] ERROR: Failed to initialize tokenizer: \(error)")
                #endif
            }
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(notificationSystem)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .modelContainer(DataController.shared.container)
        .commands {
            AppCommands()
        }
    }
}
