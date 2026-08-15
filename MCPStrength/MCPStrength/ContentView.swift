//
//  ContentView.swift
//  MCPStrength
//
//  Created by Drake Scifers on 8/14/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var exercises: [Exercise]

    var body: some View {
        NavigationStack {
            List(exercises) { exercise in
                Text(exercise.name)
            }
            .navigationTitle("Exercises")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Exercise.self, inMemory: true)
}
