//
//  SettingsScannerView.swift
//  ConsTrakr
//

import SwiftUI

private struct ScannerSettingsDraft: Equatable {
    var matchThreshold: Double
    var centerEnabled: Bool
    var leftEnabled: Bool
    var rightEnabled: Bool
    var upEnabled: Bool
    var downEnabled: Bool

    static func loaded() -> ScannerSettingsDraft {
        ScannerSettingsDraft(
            matchThreshold: Double(MatchThresholdSettings.current),
            centerEnabled: FaceScanSettings.isStepEnabled(.closeUp),
            leftEnabled: FaceScanSettings.isStepEnabled(.lookLeft),
            rightEnabled: FaceScanSettings.isStepEnabled(.lookRight),
            upEnabled: FaceScanSettings.isStepEnabled(.lookUp),
            downEnabled: FaceScanSettings.isStepEnabled(.lookDown)
        )
    }

    var matchingLevel: FaceScanSettings.Level? {
        let enabled = enabledSteps
        return FaceScanSettings.Level.allCases.first { $0.enabledSteps == enabled }
    }

    var isCustomConfiguration: Bool {
        matchingLevel == nil
    }

    private var enabledSteps: Set<FaceScanSettings.Step> {
        var steps = Set<FaceScanSettings.Step>()
        if centerEnabled { steps.insert(.closeUp) }
        if leftEnabled { steps.insert(.lookLeft) }
        if rightEnabled { steps.insert(.lookRight) }
        if upEnabled { steps.insert(.lookUp) }
        if downEnabled { steps.insert(.lookDown) }
        return steps
    }

    mutating func applyLevel(_ level: FaceScanSettings.Level) {
        centerEnabled = level.enabledSteps.contains(.closeUp)
        leftEnabled = level.enabledSteps.contains(.lookLeft)
        rightEnabled = level.enabledSteps.contains(.lookRight)
        upEnabled = level.enabledSteps.contains(.lookUp)
        downEnabled = level.enabledSteps.contains(.lookDown)
    }
}

struct SettingsScannerView: View {
    @Bindable var viewModel: SettingsViewModel

    @State private var draft = ScannerSettingsDraft.loaded()
    @State private var savedSnapshot = ScannerSettingsDraft.loaded()
    @State private var isSaving = false

    private var hasChanges: Bool {
        draft != savedSnapshot
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Engine", value: MatchThresholdSettings.engineName)
                LabeledContent("Anti-Spoof") {
                    Text(CoreMLAntiSpoof.shared.isReady ? "MiniFASNetV2 (Core ML)" : "Heuristics only")
                        .foregroundStyle(CoreMLAntiSpoof.shared.isReady ? .green : .orange)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Match Threshold: \(draft.matchThreshold, format: .number.precision(.fractionLength(2)))")
                    Slider(
                        value: $draft.matchThreshold,
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
                        draft.applyLevel(level)
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
                            if draft.matchingLevel == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }

                if draft.isCustomConfiguration {
                    LabeledContent("Custom") {
                        Text("Manual angles below")
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(FaceScanSettings.settingsLabel(for: .closeUp), isOn: $draft.centerEnabled.withToggleBusy())
                    .disabled(isSaving)
                Toggle(FaceScanSettings.settingsLabel(for: .lookLeft), isOn: $draft.leftEnabled.withToggleBusy())
                    .disabled(isSaving)
                Toggle(FaceScanSettings.settingsLabel(for: .lookRight), isOn: $draft.rightEnabled.withToggleBusy())
                    .disabled(isSaving)
                Toggle(FaceScanSettings.settingsLabel(for: .lookUp), isOn: $draft.upEnabled.withToggleBusy())
                    .disabled(isSaving)
                Toggle(FaceScanSettings.settingsLabel(for: .lookDown), isOn: $draft.downEnabled.withToggleBusy())
                    .disabled(isSaving)

                if isSaving {
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
                    Text("Blink always runs first, then enabled steps, then 3D depth when available. Registration always captures all five angles. Tap Save to apply changes.")
                }
            }
        }
        .navigationTitle("Scanner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await saveChanges() }
                }
                .disabled(!hasChanges || isSaving)
            }
        }
        .onAppear {
            reloadDraftFromSaved()
        }
    }

    private func reloadDraftFromSaved() {
        let loaded = ScannerSettingsDraft.loaded()
        draft = loaded
        savedSnapshot = loaded
    }

    private func saveChanges() async {
        isSaving = true
        defer { isSaving = false }

        await viewModel.saveScannerSettings(
            matchThreshold: draft.matchThreshold,
            centerEnabled: draft.centerEnabled,
            leftEnabled: draft.leftEnabled,
            rightEnabled: draft.rightEnabled,
            upEnabled: draft.upEnabled,
            downEnabled: draft.downEnabled
        )
        savedSnapshot = draft
    }
}
