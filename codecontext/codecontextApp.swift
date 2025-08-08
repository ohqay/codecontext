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
    @State private var notificationSystem = NotificationSystem()
    
    var body: some Scene {
        WindowGroup {
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
