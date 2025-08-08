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

    var body: some View {
        ZStack {
            MainWindow()
                .sheet(isPresented: $showingWelcome) {
                    WelcomeView(showingWelcome: $showingWelcome)
                }
            
            NotificationOverlay()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(DataController.shared.container)
}
