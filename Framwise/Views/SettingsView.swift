//
//  SettingsView.swift
//  Framwise
//
//  Workspace tuning settings
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("segmentCount") private var segmentCount = SceneDetectionSettings.defaultTileCount

    private static let sliderRange = Double(SceneDetectionSettings.minTileCount)...Double(SceneDetectionSettings.maxTileCount)
    private static let sliderStep = Double(SceneDetectionSettings.tileCountStep)

    private var densityLabel: String {
        switch segmentCount {
        case ...18: return "Broad overview"
        case 19...48: return "Balanced"
        case 49...84: return "Detailed"
        default: return "Fine detail"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PREFERENCES")
                    .font(.framwiseMono(10))
                    .foregroundStyle(FramwiseTheme.warm)
                Text("Settings")
                    .font(.framwiseDisplay(24, weight: .semibold))
                    .foregroundStyle(FramwiseTheme.textPrimary)
                Text("Configure how videos are split into preview tiles.")
                    .font(.framwiseUI(13))
                    .foregroundStyle(FramwiseTheme.textMuted)
            }

            settingsCard(
                title: "Preview Tiles",
                value: "\(segmentCount)"
            ) {
                Slider(value: Binding(
                    get: { Double(segmentCount) },
                    set: { segmentCount = Int($0) }
                ), in: Self.sliderRange, step: Self.sliderStep) {
                    Text("Target Tile Count")
                }
                .tint(FramwiseTheme.warm)

                HStack(spacing: 8) {
                    Text(densityLabel)
                        .font(.framwiseMono(11))
                        .foregroundStyle(FramwiseTheme.warm)

                    Text("—")
                        .foregroundStyle(FramwiseTheme.textMuted.opacity(0.4))

                    Text("More tiles = finer detail. Scene detection sensitivity adjusts automatically.")
                        .font(.framwiseUI(12))
                        .foregroundStyle(FramwiseTheme.textMuted)
                }

                Text("Changes apply to next import.")
                    .font(.framwiseUI(11))
                    .foregroundStyle(FramwiseTheme.textMuted.opacity(0.5))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FramwiseTheme.background)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(title: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.framwiseDisplay(18, weight: .semibold))
                    .foregroundStyle(FramwiseTheme.textPrimary)
                Spacer()
                Text(value)
                    .font(.framwiseMono(11))
                    .foregroundStyle(FramwiseTheme.textMuted)
            }
            content()
        }
        .padding(16)
        .framwisePanel(background: FramwiseTheme.surface, radius: 18)
    }
}
