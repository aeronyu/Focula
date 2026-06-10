import Foundation
import SwiftUI
import FoculaCore

enum DisplayFormatters {
    static func minutes(_ seconds: TimeInterval) -> String {
        "\(Int(seconds / 60))m"
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

extension FoculaCore.FocusState {
    var label: String {
        switch self {
        case .onGoal: "On goal"
        case .maybe: "Maybe"
        case .offGoal: "Off goal"
        case .unknown: "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .onGoal: "checkmark.seal.fill"
        case .maybe: "questionmark.circle.fill"
        case .offGoal: "exclamationmark.triangle.fill"
        case .unknown: "eye.slash.fill"
        }
    }

    var tint: Color {
        switch self {
        case .onGoal: .green
        case .maybe: .orange
        case .offGoal: .pink
        case .unknown: .secondary
        }
    }
}
