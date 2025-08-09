//
//  ContentView.swift
//  codecontext
//
//  Created by Tarek Alexander on 08-08-2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        ZStack {
            MainWindow()
            NotificationOverlay()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(DataController.shared.container)
}
