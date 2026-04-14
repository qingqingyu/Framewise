//
//  TagCreateView.swift
//  Framwise
//
//  Dialog for creating a new clip tag
//

import SwiftUI

struct TagCreateView: View {
    @Environment(\.dismiss) var dismiss
    let onCreate: (ClipTag) -> Void

    @State private var tagName = ""
    @State private var selectedColor: ClipTag.TagColor = .red

    var body: some View {
        VStack(spacing: 16) {
            Text("New Tag")
                .font(.headline)

            TextField("Tag name", text: $tagName)
                .textFieldStyle(.roundedBorder)

            // Color picker
            HStack(spacing: 10) {
                ForEach(ClipTag.TagColor.allCases, id: \.self) { color in
                    Circle()
                        .fill(color.systemColor)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color.primary, lineWidth: selectedColor == color ? 2 : 0)
                        )
                        .onTapGesture {
                            selectedColor = color
                        }
                }
            }
            .padding(.vertical, 4)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    let trimmed = tagName.trimmingCharacters(in: .whitespaces)
                    let tag = ClipTag(name: trimmed, color: selectedColor)
                    onCreate(tag)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}
