//
//  TagCreateView.swift
//  Framwise
//
//  Dialog for creating a new clip tag
//

import SwiftUI

struct TagCreateView: View {
    @Environment(\.dismiss) var dismiss
    let existingNames: Set<String>
    let onCreate: (ClipTag) -> Bool

    @State private var tagName = ""
    @State private var selectedColor: ClipTag.TagColor = .red
    @State private var validationMessage: String?

    private var trimmedName: String {
        tagName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedExistingNames: Set<String> {
        Set(existingNames.map { normalizeName($0) })
    }

    private var hasDuplicate: Bool {
        normalizedExistingNames.contains(normalizeName(tagName))
    }

    private var canCreate: Bool {
        !trimmedName.isEmpty && !hasDuplicate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TAG CREATION")
                    .font(.framwiseMono(10))
                    .foregroundStyle(FramwiseTheme.warm)
                Text("New Tag")
                    .font(.framwiseDisplay(24, weight: .semibold))
                    .foregroundStyle(FramwiseTheme.textPrimary)
                Text("Create a new sorting lane for the current working session.")
                    .font(.framwiseUI(13))
                    .foregroundStyle(FramwiseTheme.textMuted)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("NAME")
                    .font(.framwiseMono(10))
                    .foregroundStyle(FramwiseTheme.textMuted)
                TextField("Hero shot, vows, reactions...", text: $tagName)
                    .textFieldStyle(.plain)
                    .font(.framwiseUI(14))
                    .foregroundStyle(FramwiseTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .framwisePanel(background: FramwiseTheme.surfaceRaised, radius: 16)

                Text(hasDuplicate ? "A tag with this name already exists." : "Use short labels that help you sort fast.")
                    .font(.framwiseUI(12))
                    .foregroundStyle(hasDuplicate ? FramwiseTheme.warning : FramwiseTheme.textMuted)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("COLOR")
                    .font(.framwiseMono(10))
                    .foregroundStyle(FramwiseTheme.textMuted)

                HStack(spacing: 10) {
                    ForEach(ClipTag.TagColor.allCases, id: \.self) { color in
                        Button(action: {
                            selectedColor = color
                        }) {
                            ZStack {
                                Circle()
                                    .fill(color.systemColor)
                                if selectedColor == color {
                                    Circle()
                                        .stroke(FramwiseTheme.textPrimary, lineWidth: 2)
                                        .padding(2)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(FramwiseGhostButtonStyle())

                Spacer()

                Button("Create") {
                    let tag = ClipTag(name: trimmedName, color: selectedColor)
                    if onCreate(tag) {
                        dismiss()
                    } else {
                        validationMessage = "Unable to create tag. Try a different name."
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(FramwisePrimaryButtonStyle())
                .disabled(!canCreate)
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.framwiseUI(12))
                    .foregroundStyle(FramwiseTheme.warning)
            }
        }
        .padding(22)
        .frame(width: 360)
        .background(FramwiseTheme.background)
        .onChange(of: tagName) { _, _ in
            validationMessage = nil
        }
    }

    private func normalizeName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct TagRenameView: View {
    @Environment(\.dismiss) var dismiss
    let initialName: String
    let existingNames: Set<String>
    let onRename: (String) -> Bool

    @State private var tagName: String
    @State private var validationMessage: String?

    init(initialName: String, existingNames: Set<String>, onRename: @escaping (String) -> Bool) {
        self.initialName = initialName
        self.existingNames = existingNames
        self.onRename = onRename
        _tagName = State(initialValue: initialName)
    }

    private var trimmedName: String {
        tagName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedExistingNames: Set<String> {
        Set(existingNames.map { normalizeName($0) })
    }

    private var hasDuplicate: Bool {
        let normalized = normalizeName(tagName)
        return normalized != normalizeName(initialName) && normalizedExistingNames.contains(normalized)
    }

    private var canRename: Bool {
        !trimmedName.isEmpty && !hasDuplicate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TAG EDIT")
                    .font(.framwiseMono(10))
                    .foregroundStyle(FramwiseTheme.warm)
                Text("Rename Tag")
                    .font(.framwiseDisplay(24, weight: .semibold))
                    .foregroundStyle(FramwiseTheme.textPrimary)
                Text("Update the tag label without changing clip assignments.")
                    .font(.framwiseUI(13))
                    .foregroundStyle(FramwiseTheme.textMuted)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("NAME")
                    .font(.framwiseMono(10))
                    .foregroundStyle(FramwiseTheme.textMuted)
                TextField("Tag name", text: $tagName)
                    .textFieldStyle(.plain)
                    .font(.framwiseUI(14))
                    .foregroundStyle(FramwiseTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .framwisePanel(background: FramwiseTheme.surfaceRaised, radius: 16)

                Text(hasDuplicate ? "A tag with this name already exists." : "Keep names concise and action-oriented.")
                    .font(.framwiseUI(12))
                    .foregroundStyle(hasDuplicate ? FramwiseTheme.warning : FramwiseTheme.textMuted)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(FramwiseGhostButtonStyle())

                Spacer()

                Button("Rename") {
                    if onRename(trimmedName) {
                        dismiss()
                    } else {
                        validationMessage = "Unable to rename tag. Try a different name."
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(FramwisePrimaryButtonStyle())
                .disabled(!canRename)
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.framwiseUI(12))
                    .foregroundStyle(FramwiseTheme.warning)
            }
        }
        .padding(22)
        .frame(width: 360)
        .background(FramwiseTheme.background)
        .onChange(of: tagName) { _, _ in
            validationMessage = nil
        }
    }

    private func normalizeName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
