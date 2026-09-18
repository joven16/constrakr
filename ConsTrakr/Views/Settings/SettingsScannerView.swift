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

    var registrationCenterEnabled: Bool
    var registrationLeftEnabled: Bool
    var registrationRightEnabled: Bool
    var registrationUpEnabled: Bool
    var registrationDownEnabled: Bool

    static func loaded() -> ScannerSettingsDraft {
        ScannerSettingsDraft(
            matchThreshold: Double(MatchThresholdSettings.current),
            centerEnabled: FaceScanSettings.isStepEnabled(.closeUp),
            leftEnabled: FaceScanSettings.isStepEnabled(.lookLeft),
            rightEnabled: FaceScanSettings.isStepEnabled(.lookRight),
            upEnabled: FaceScanSettings.isStepEnabled(.lookUp),
            downEnabled: FaceScanSettings.isStepEnabled(.lookDown),
            registrationCenterEnabled: RegistrationPoseSettings.isPoseEnabled(.center),
            registrationLeftEnabled: RegistrationPoseSettings.isPoseEnabled(.left),
            registrationRightEnabled: RegistrationPoseSettings.isPoseEnabled(.right),
            registrationUpEnabled: RegistrationPoseSettings.isPoseEnabled(.up),
            registrationDownEnabled: RegistrationPoseSettings.isPoseEnabled(.down)
        )
    }

    var matchingLevel: FaceScanSettings.Level? {
        let enabled = enabledSteps
        return FaceScanSettings.Level.allCases.first { $0.enabledSteps == enabled }
    }

    var isCustomConfiguration: Bool {
        matchingLevel == nil
    }

    var registrationMatchingLevel: RegistrationPoseSettings.Level? {
        let enabled = enabledRegistrationPoses
        return RegistrationPoseSettings.Level.allCases.first { $0.enabledPoses == enabled }
    }

    var isRegistrationCustomConfiguration: Bool {
        registrationMatchingLevel == nil
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

    private var enabledRegistrationPoses: Set<FacePose> {
        var poses = Set<FacePose>()
        if registrationCenterEnabled { poses.insert(.center) }
        if registrationLeftEnabled { poses.insert(.left) }
        if registrationRightEnabled { poses.insert(.right) }
        if registrationUpEnabled { poses.insert(.up) }
        if registrationDownEnabled { poses.insert(.down) }
        return poses
    }

    mutating func applyLevel(_ level: FaceScanSettings.Level) {
        centerEnabled = level.enabledSteps.contains(.closeUp)
        leftEnabled = level.enabledSteps.contains(.lookLeft)
        rightEnabled = level.enabledSteps.contains(.lookRight)
        upEnabled = level.enabledSteps.contains(.lookUp)
        downEnabled = level.enabledSteps.contains(.lookDown)
    }

    mutating func applyRegistrationLevel(_ level: RegistrationPoseSettings.Level) {
        registrationCenterEnabled = level.enabledPoses.contains(.center)
        registrationLeftEnabled = level.enabledPoses.contains(.left)
        registrationRightEnabled = level.enabledPoses.contains(.right)
        registrationUpEnabled = level.enabledPoses.contains(.up)
        registrationDownEnabled = level.enabledPoses.contains(.down)
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

            attendanceSection
            registrationSection
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

    private var attendanceSection: some View {
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
                savingRow
            }
        } header: {
            Text("Time In / Out Checks")
        } footer: {
            if let note = viewModel.faceScanSettingsMessage {
                Text(note)
                    .foregroundStyle(.orange)
            } else {
                Text("Blink always runs first, then enabled steps, then 3D depth when available. Tap Save to apply changes.")
            }
        }
    }

    private var registrationSection: some View {
        Section {
            ForEach(RegistrationPoseSettings.Level.allCases) { level in
                Button {
                    draft.applyRegistrationLevel(level)
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
                        if draft.registrationMatchingLevel == level {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }

            if draft.isRegistrationCustomConfiguration {
                LabeledContent("Custom") {
                    Text("Manual angles below")
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(
                RegistrationPoseSettings.settingsLabel(for: .center),
                isOn: $draft.registrationCenterEnabled.withToggleBusy()
            )
            .disabled(isSaving)
            Toggle(
                RegistrationPoseSettings.settingsLabel(for: .left),
                isOn: $draft.registrationLeftEnabled.withToggleBusy()
            )
            .disabled(isSaving)
            Toggle(
                RegistrationPoseSettings.settingsLabel(for: .right),
                isOn: $draft.registrationRightEnabled.withToggleBusy()
            )
            .disabled(isSaving)
            Toggle(
                RegistrationPoseSettings.settingsLabel(for: .up),
                isOn: $draft.registrationUpEnabled.withToggleBusy()
            )
            .disabled(isSaving)
            Toggle(
                RegistrationPoseSettings.settingsLabel(for: .down),
                isOn: $draft.registrationDownEnabled.withToggleBusy()
            )
            .disabled(isSaving)

            if isSaving {
                savingRow
            }
        } header: {
            Text("Registration")
        } footer: {
            Text("Controls which face angles are captured when registering an employee. Look Straight stays on if every angle is turned off. Blink and 3D scan still run first. Tap Save to apply changes.")
        }
    }

    private var savingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Saving…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
            downEnabled: draft.downEnabled,
            registrationCenterEnabled: draft.registrationCenterEnabled,
            registrationLeftEnabled: draft.registrationLeftEnabled,
            registrationRightEnabled: draft.registrationRightEnabled,
            registrationUpEnabled: draft.registrationUpEnabled,
            registrationDownEnabled: draft.registrationDownEnabled
        )
        // Reload so forced Look Straight (if all were off) shows in the form.
        reloadDraftFromSaved()
    }
}
