//
//  ClipTag.swift
//  Framwise
//
//  Represents a tag that can be assigned to clips for categorization
//

import SwiftUI

struct ClipTag: Identifiable, Hashable {
    let id: UUID
    var name: String
    var color: TagColor

    init(id: UUID = UUID(), name: String, color: TagColor) {
        self.id = id
        self.name = name
        self.color = color
    }

    enum TagColor: String, CaseIterable {
        case red, orange, yellow, green, blue, purple, pink, gray

        var systemColor: Color {
            switch self {
            case .red: return .red
            case .orange: return .orange
            case .yellow: return .yellow
            case .green: return .green
            case .blue: return .blue
            case .purple: return .purple
            case .pink: return .pink
            case .gray: return .gray
            }
        }

        var localizedName: String {
            switch self {
            case .red: return "Red"
            case .orange: return "Orange"
            case .yellow: return "Yellow"
            case .green: return "Green"
            case .blue: return "Blue"
            case .purple: return "Purple"
            case .pink: return "Pink"
            case .gray: return "Gray"
            }
        }
    }
}
