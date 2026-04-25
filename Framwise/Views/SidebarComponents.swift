//
//  SidebarComponents.swift
//  Framwise
//
//  Reusable sidebar rows and tag hints
//

import SwiftUI

struct SidebarRow: View {
    let title: String
    let icon: String
    let value: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isActive ? FramwiseTheme.accentSoft : FramwiseTheme.surfaceRaised)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isActive ? FramwiseTheme.accent : FramwiseTheme.textMuted)
                }
                .frame(width: 28, height: 28)

                Text(title)
                    .font(.framwiseUI(13, weight: .medium))
                    .foregroundStyle(FramwiseTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(value)
                    .font(.framwiseMono(11))
                    .foregroundStyle(isActive ? FramwiseTheme.textPrimary : FramwiseTheme.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? FramwiseTheme.accentSoft : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isActive ? FramwiseTheme.accent.opacity(0.3) : FramwiseTheme.line.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct SidebarTagRow: View {
    let tag: ClipTag
    let count: Int
    let isActive: Bool
    var shortcutNumber: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(tag.color.systemColor)
                    .frame(width: 10, height: 10)

                Text(tag.name)
                    .font(.framwiseUI(13, weight: .medium))
                    .foregroundStyle(FramwiseTheme.textPrimary)

                Spacer()

                if let num = shortcutNumber {
                    Text("\(num)")
                        .font(.framwiseMono(10))
                        .foregroundStyle(FramwiseTheme.textMuted.opacity(0.6))
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(FramwiseTheme.surfaceRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(FramwiseTheme.line.opacity(0.5), lineWidth: 0.5)
                        )
                }

                Text("\(count)")
                    .font(.framwiseMono(11))
                    .foregroundStyle(isActive ? FramwiseTheme.textPrimary : FramwiseTheme.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? tag.color.systemColor.opacity(0.16) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isActive ? tag.color.systemColor.opacity(0.35) : FramwiseTheme.line.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tags Empty State

struct TagsEmptyStateView: View {
    let onLoadPreset: () -> Void
    let onCreateTag: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: "tag.slash")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(FramwiseTheme.textMuted.opacity(0.5))

                Text("No sorting tags yet")
                    .font(.framwiseUI(13, weight: .medium))
                    .foregroundStyle(FramwiseTheme.textMuted)
            }
            .padding(.top, 4)

            Button(action: onLoadPreset) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                    Text("Load Wedding Preset")
                        .font(.framwiseUI(13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(FramwiseTheme.warm.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(FramwiseTheme.warm.opacity(0.3), lineWidth: 1)
                )
                .foregroundStyle(FramwiseTheme.warm)
            }
            .buttonStyle(.plain)

            Text("Pre-built tags for ceremony, reception, first dance & more. Press 1–6 to tag clips instantly.")
                .font(.framwiseUI(11))
                .foregroundStyle(FramwiseTheme.textMuted.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            Button(action: onCreateTag) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Create custom tag")
                        .font(.framwiseUI(12))
                }
                .foregroundStyle(FramwiseTheme.textMuted)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tags Keyboard Hint

struct TagsKeyboardHint: View {
    let tagCount: Int

    private var hintText: Text {
        let maxKey = min(tagCount, 9)
        let muted = FramwiseTheme.textMuted.opacity(0.6)
        let warm = FramwiseTheme.warm.opacity(0.8)
        let prefix = Text("Focus or hover a clip, press ").font(.framwiseUI(11)).foregroundStyle(muted)
        let one = Text("1").font(.framwiseMono(11)).foregroundStyle(warm)
        let dash = Text("–").font(.framwiseUI(11)).foregroundStyle(muted)
        let end = Text("\(maxKey)").font(.framwiseMono(11)).foregroundStyle(warm)
        let suffix = Text(" to tag").font(.framwiseUI(11)).foregroundStyle(muted)
        return prefix + one + dash + end + suffix
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(FramwiseTheme.textMuted.opacity(0.5))

            hintText
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(FramwiseTheme.warm.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FramwiseTheme.warm.opacity(0.1), lineWidth: 0.5)
        )
    }
}

struct SidebarMetricRow: View {
    let label: String
    let value: String
    var tone: Color = FramwiseTheme.textPrimary

    var body: some View {
        HStack {
            Text(label)
                .font(.framwiseUI(13))
                .foregroundStyle(FramwiseTheme.textMuted)
            Spacer()
            Text(value)
                .font(.framwiseMono(11))
                .foregroundStyle(tone)
        }
        .padding(.vertical, 2)
    }
}
