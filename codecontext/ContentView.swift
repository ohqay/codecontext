//
//  ContentView.swift
//  codecontext
//
//  Created by Tarek Alexander on 08-08-2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var showingWelcome = true
    @State private var hasShownWelcome = false

    var body: some View {
        ZStack {
            MainWindow()
                .sheet(isPresented: $showingWelcome) {
                    WelcomeView(showingWelcome: $showingWelcome)
                }
                .onAppear {
                    // Only show welcome on first window
                    if !hasShownWelcome {
                        hasShownWelcome = true
                    } else {
                        showingWelcome = false
                    }
                }
            
            NotificationOverlay()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(DataController.shared.container)
}
