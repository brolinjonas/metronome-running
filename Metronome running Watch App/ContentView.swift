//
//  ContentView.swift
//  Metronome running Watch App
//
//  Created by Jonas Brolin on 2026-07-19.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MetronomeViewModel()

    var body: some View {
        VStack(spacing: 8) {
            Text("\(viewModel.bpm)")
                .font(.system(size: 40, weight: .bold))
            Text("BPM")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("-1") { viewModel.decrement() }
                Button("+1") { viewModel.increment() }
            }

            Button(playButtonTitle) {
                viewModel.togglePlayback()
            }
            .tint(playButtonTint)
        }
        .padding()
    }

    private var playButtonTitle: String {
        if viewModel.isPlaying { return "Stop" }
        if viewModel.isStarting { return "Starting…" }
        return "Play"
    }

    private var playButtonTint: Color {
        if viewModel.isPlaying { return .red }
        if viewModel.isStarting { return .orange }
        return .green
    }
}

#Preview {
    ContentView()
}
