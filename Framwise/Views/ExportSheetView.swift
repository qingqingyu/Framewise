//
//  ExportSheetView.swift
//  Framwise
//
//  Export delivery sheet
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExportSheetView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var exportViewModel: ExportViewModel
    @Environment(\.dismiss) var dismiss

    @State private var exportedFileURL: URL?
    @State private var saveError: String?

    private var clipsToExport: [VideoClip] {
        appState.selectedClips.filter { $0.effectiveWasteType == .none }
    }

    private var excludedWasteCount: Int {
        appState.selectedClips.count - clipsToExport.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Export Delivery")
                    .font(.framwiseDisplay(28, weight: .semibold))
                    .foregroundStyle(FramwiseTheme.textPrimary)
                Text("Choose a handoff format, confirm how many clips are leaving the workspace, and deliver only what survives the cut.")
                    .font(.framwiseUI(14))
                    .foregroundStyle(FramwiseTheme.textMuted)
            }

            HStack(spacing: 12) {
                FramwiseMetricBadge(title: "Selected", value: "\(appState.selectedClips.count)")
                FramwiseMetricBadge(title: "Exportable", value: "\(clipsToExport.count)", color: FramwiseTheme.textPrimary)
                FramwiseMetricBadge(title: "Waste Excluded", value: "\(max(excludedWasteCount, 0))", color: excludedWasteCount > 0 ? FramwiseTheme.warning : FramwiseTheme.textMuted)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("FORMAT")
                    .font(.framwiseMono(10))
                    .foregroundStyle(FramwiseTheme.textMuted)

                ForEach(ExportViewModel.ExportFormat.allCases, id: \.self) { format in
                    Button(action: {
                        exportViewModel.exportFormat = format
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: exportViewModel.exportFormat == format ? "record.circle.fill" : "circle")
                                .foregroundStyle(exportViewModel.exportFormat == format ? FramwiseTheme.accent : FramwiseTheme.textMuted)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(format.displayName)
                                    .font(.framwiseUI(14, weight: .semibold))
                                    .foregroundStyle(FramwiseTheme.textPrimary)
                                Text(formatDescription(for: format))
                                    .font(.framwiseUI(12))
                                    .foregroundStyle(FramwiseTheme.textMuted)
                            }
                            Spacer()
                            Text(format.fileExtension.uppercased())
                                .font(.framwiseMono(11))
                                .foregroundStyle(FramwiseTheme.textMuted)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(exportViewModel.exportFormat == format ? FramwiseTheme.accentSoft : FramwiseTheme.surfaceRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(exportViewModel.exportFormat == format ? FramwiseTheme.accent.opacity(0.35) : FramwiseTheme.line.opacity(0.85), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .framwisePanel(background: FramwiseTheme.surface, radius: 22)

            VStack(alignment: .leading, spacing: 10) {
                if clipsToExport.isEmpty && excludedWasteCount > 0 {
                    statusCallout(
                        title: "Nothing exportable yet",
                        body: "All \(appState.selectedClips.count) selected clips are currently marked as waste.",
                        color: FramwiseTheme.warning
                    )
                } else if excludedWasteCount > 0 {
                    statusCallout(
                        title: "Waste clips excluded",
                        body: "\(appState.selectedClips.count) selected, \(excludedWasteCount) marked as waste and removed from delivery.",
                        color: FramwiseTheme.warning
                    )
                } else {
                    statusCallout(
                        title: "Ready to export",
                        body: "\(clipsToExport.count) approved clips will be written to the delivery file.",
                        color: FramwiseTheme.success
                    )
                }

                if let warning = exportViewModel.warning {
                    statusCallout(
                        title: "Export warning",
                        body: warning,
                        color: FramwiseTheme.warning
                    )
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(FramwiseGhostButtonStyle())

                Spacer()

                Button(action: startExport) {
                    Label(exportViewModel.isExporting ? "Exporting..." : "Export", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(FramwisePrimaryButtonStyle())
                .disabled(clipsToExport.isEmpty || exportViewModel.isExporting)
            }
        }
        .padding(28)
        .frame(width: 560)
        .background(FramwiseTheme.background)
        .alert("Export Error", isPresented: Binding(
            get: { exportViewModel.error != nil },
            set: { if !$0 { exportViewModel.error = nil } }
        ), presenting: exportViewModel.error) { _ in
            Button("OK") { exportViewModel.error = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
        .alert("Save Error", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        ), presenting: saveError) { _ in
            Button("OK") { saveError = nil }
        } message: { message in
            Text(message)
        }
    }

    private func formatDescription(for format: ExportViewModel.ExportFormat) -> String {
        switch format {
        case .edl:
            return "最轻量的时间线交换格式，适合兼容交接。"
        case .fcpxml:
            return "适合 Final Cut / DaVinci 等继续整理与重建时间线。"
        }
    }

    @ViewBuilder
    private func statusCallout(title: String, body: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.framwiseUI(13, weight: .semibold))
                .foregroundStyle(FramwiseTheme.textPrimary)
            Text(body)
                .font(.framwiseUI(12))
                .foregroundStyle(FramwiseTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.24), lineWidth: 1)
        )
    }

    private func startExport() {
        Task {
            if let url = await exportViewModel.export(
                clips: clipsToExport,
                format: exportViewModel.exportFormat
            ) {
                exportedFileURL = url
                let panel = NSSavePanel()
                panel.nameFieldStringValue = url.lastPathComponent
                panel.allowedContentTypes = [.init(filenameExtension: exportViewModel.exportFormat.fileExtension) ?? .data]
                panel.begin { response in
                    defer {
                        try? FileManager.default.removeItem(at: url)
                        exportViewModel.isExporting = false
                    }
                    if response == .OK, let destURL = panel.url {
                        do {
                            if FileManager.default.fileExists(atPath: destURL.path) {
                                try FileManager.default.removeItem(at: destURL)
                            }
                            try FileManager.default.copyItem(at: url, to: destURL)
                            dismiss()
                        } catch {
                            saveError = "Failed to save file: \(error.localizedDescription)"
                        }
                    }
                }
            } else {
                exportViewModel.isExporting = false
            }
        }
    }
}
