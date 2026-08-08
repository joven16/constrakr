//
//  SettingsScannerView.swift
//  ConsTrakr
//

import SwiftUI

struct SettingsScannerView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Engine", value: MatchThresholdSettings.engineName)
                LabeledContent("Anti-Spoof") {
                    Text(CoreMLAntiSpoof.shared.isReady ? "MiniFASNetV2 (Core ML)" : "Heuristics only")
                        .foregroundStyle(CoreMLAntiSpoof.shared.isReady ? .green : .orange)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Match Threshold: \(viewModel.matchThreshold, format: .number.precision(.fractionLength(2)))")
                    Slider(
                        value: $viewModel.matchThreshold,
                        in: viewModel.matchThresholdRange,
                        step: 0.01
                    )
                }
            } header: {
                Text("Face Match")
            } footer: {
                Text("Default threshold is 0.45. Lower if valid faces show “Not recognized”; raise to reduce lookalike matches.")
            }

            Section {
                ForEach(FaceScanSettings.Level.allCases) { level in
                    Button {
                        Task { await viewModel.selectFaceScanLevel(level) }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(level.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(level.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 8)
                            if viewModel.faceScanLevel == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSavingFaceScanSettings)
                }

                if FaceScanSettings.isCustomConfiguration {
                    LabeledContent("Custom") {
                        Text("Manual angles below")
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(FaceScanSettings.settingsLabel(for: .closeUp), isOn: $viewModel.faceScanCenterEnabled)
                    .disabled(viewModel.isSavingFaceScanSettings)
                Toggle(FaceScanSettings.settingsLabel(for: .lookLeft), isOn: $viewModel.faceScanLeftEnabled)
                    .disabled(viewModel.isSavingFaceScanSettings)
                Toggle(FaceScanSettings.settingsLabel(for: .lookRight), isOn: $viewModel.faceScanRightEnabled)
                    .disabled(viewModel.isSavingFaceScanSettings)
                Toggle(FaceScanSettings.settingsLabel(for: .lookUp), isOn: $viewModel.faceScanUpEnabled)
                    .disabled(viewModel.isSavingFaceScanSettings)
                Toggle(FaceScanSettings.settingsLabel(for: .lookDown), isOn: $viewModel.faceScanDownEnabled)
                    .disabled(viewModel.isSavingFaceScanSettings)

                if viewModel.isSavingFaceScanSettings {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Saving…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Time In / Out Checks")
            } footer: {
                if let note = viewModel.faceScanSettingsMessage {
                    Text(note)
                        .foregroundStyle(.orange)
                } else {
                    Text("Blink always runs first, then enabled steps, then 3D depth when available. Registration always captures all five angles.")
                }
            }
        }
        .navigationTitle("Scanner")
        .navigationBarTitleDisplayMode(.inline)
    }
}
