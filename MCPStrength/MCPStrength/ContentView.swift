//
//  ContentView.swift
//  MCPStrength
//
//  Created by Drake Scifers on 8/14/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        ExercisesScreen()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Exercise.self, inMemory: true)
}
