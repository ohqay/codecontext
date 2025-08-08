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
        MainWindow()
            .sheet(isPresented: $showingWelcome) {
                WelcomeView(showingWelcome: $showingWelcome)
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(DataController.shared.container)
}
