//
//  ClipTag.swift
//  Framwise
//
//  Represents a tag that can be assigned to clips for categorization
//

import SwiftUI

struct ClipTag: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var color: TagColor

    init(id: UUID = UUID(), name: String, color: TagColor) {
        self.id = id
        self.name = name
        self.color = color
    }

    enum TagColor: String, CaseIterable, Codable {
        case red, orange, yellow, green, blue, purple, pink, gray

        var systemColor: Color {
            switch self {
            case .red: return FramwiseTheme.danger
            case .orange: return FramwiseTheme.warning
            case .yellow: return FramwiseTheme.warm
            case .green: return FramwiseTheme.success
            case .blue: return FramwiseTheme.info
            case .purple: return FramwiseTheme.accent
            case .pink: return Color(hex: "E58ACF")
            case .gray: return Color(hex: "6E778A")
            }
        }

        var localizedName: String { rawValue }
    }
}
