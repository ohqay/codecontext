//
//  codecontextApp.swift
//  codecontext
//
//  Created by Tarek Alexander on 08-08-2025.
//

import SwiftUI
import SwiftData

@main
struct codecontextApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(DataController.shared.container)
        .commands {
            AppCommands()
        }
    }
}
