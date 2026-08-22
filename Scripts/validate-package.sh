#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Parse every Swift source independently. This catches syntax regressions even on
# non-macOS review hosts where Apple SDK type-checking is unavailable.
while IFS= read -r file; do
  swiftc -parse "$file" >/dev/null
done < <(find MisMeeter MisMeeterWidget Shared -type f -name '*.swift' | sort)

python3 - <<'PY'
from pathlib import Path
import json, plistlib, re
root = Path('.')

# XcodeGen owns YAML semantic validation in CI. Here we use a stdlib-only parser
# for the one invariant we need locally: every Swift file has explicit membership.
project_text = (root / 'project.yml').read_text()
listed = set(re.findall(r'^\s*-\s+path:\s+([^\s#]+\.swift)\s*$', project_text, re.MULTILINE))
all_swift = {str(p) for base in ('MisMeeter', 'MisMeeterWidget', 'Shared') for p in (root/base).rglob('*.swift')}
if all_swift != listed:
    raise SystemExit(f'Source membership mismatch. Unlisted={sorted(all_swift-listed)}, missing={sorted(listed-all_swift)}')

for path in root.rglob('*.json'):
    json.loads(path.read_text())
for path in (root/'MisMeeter/MisMeeter.entitlements', root/'MisMeeterWidget/MisMeeterWidget.entitlements'):
    plistlib.loads(path.read_bytes())
PY

# Control architecture invariants.
grep -Fq 'ControlWidgetToggle(' MisMeeterWidget/MisMeeterSystemControls.swift
grep -Fq 'ControlValueProvider' MisMeeterWidget/MisMeeterSystemControls.swift
grep -Fq 'provider: Provider()' MisMeeterWidget/MisMeeterSystemControls.swift
grep -Fq 'func currentValue() async throws -> MisMeeterControlValue' MisMeeterWidget/MisMeeterSystemControls.swift
grep -Fq 'SharedAppState.readSnapshot()' MisMeeterWidget/MisMeeterSystemControls.swift
! grep -Fq '.disabled(' MisMeeterWidget/MisMeeterSystemControls.swift
grep -Fq '.tint(.red)' MisMeeterWidget/MisMeeterSystemControls.swift
grep -Fq 'TX IDLE' MisMeeterWidget/MisMeeterSystemControls.swift
grep -Fq 'RX IDLE' MisMeeterWidget/MisMeeterSystemControls.swift
! grep -Fq 'Activity<' MisMeeterWidget/MisMeeterSystemControls.swift
grep -Fq 'SetValueIntent, LiveActivityIntent' Shared/SetMicrophoneMuteControlIntent.swift
grep -Fq 'SetValueIntent, LiveActivityIntent' Shared/SetReceiveMuteControlIntent.swift
! grep -Fq 'reloadControls' Shared/SetMicrophoneMuteControlIntent.swift
! grep -Fq 'reloadControls' Shared/SetReceiveMuteControlIntent.swift
! grep -Fq 'ControlCenter' Shared/SharedAppState.swift
grep -Fq 'ControlCenter.shared.reloadControls(ofKind: Kinds.receive)' Shared/SharedControlState.swift
grep -Fq 'ControlCenter.shared.reloadControls(ofKind: Kinds.microphone)' Shared/SharedControlState.swift
grep -Fq 'ControlCenter.shared.reloadAllControls()' Shared/SharedControlState.swift
! grep -Fq 'struct SharedControlState:' Shared/SharedControlState.swift
! grep -Fq 'control-state-' Shared/SharedControlState.swift

# Runtime/state reliability invariants.
grep -Fq 'MisMeeterLiveActivityCoordinator' Shared/MisMeeterRuntime.swift
grep -Fq 'publishControlState(reloadControls: true)' Shared/MisMeeterRuntime.swift
grep -Fq 'publishSharedState(status: currentStatusText)' Shared/MisMeeterRuntime.swift
grep -Fq 'onTransportSnapshotChange' Shared/MisMeeterRuntime.swift
grep -Fq 'runtimeSnapshot()' Shared/MisMeeterRuntime.swift
grep -Fq 'statePublicationLock' Shared/MisMeeterRuntime.swift
grep -Fq 'value.normalized()' Shared/SharedAppState.swift
grep -Fq 'prepareForProcessTermination()' Shared/MisMeeterRuntime.swift
grep -Fq 'didFinishLaunchingWithOptions' MisMeeter/MisMeeterApp.swift
grep -Fq 'applicationWillTerminate' MisMeeter/MisMeeterApp.swift

# Audio/network safety regressions fixed by the senior review.
grep -Fq 'AVAudioApplication.requestRecordPermission()' MisMeeter/ContentView.swift
grep -Fq 'kAudioUnitProperty_MaximumFramesPerSlice' Shared/MicrophoneEngine.swift
grep -Fq 'func acceptFrame(_ frame: UInt32) -> Bool' Shared/VBANReceiver.swift
grep -Fq 'syncOnNetworkQueue' Shared/VBANReceiver.swift
grep -Fq 'maxPacketsPerWake = 256' Shared/VBANReceiver.swift
! grep -Fq 'UInt16(Int(' MisMeeter/ContentView.swift
! grep -Fq 'transmissionModeV08' MisMeeter/ContentView.swift
! test -e Shared/VBANTransmissionMode.swift
! test -e Shared/TransportState.swift
! grep -Fq '3.2.3' MisMeeter/ContentView.swift

# Removed architectures must remain absent from source membership.
if grep -Eq 'NowPlayingRemoteController|MediaPlayer|MPNowPlayingSession|MPRemoteCommandCenter|mismeeter-silence|TXPacketQueue|CaptureRingBuffer|AudioClockEstimator|MonotonicPacer|SampleFIFO|VBANTransmissionMode|TransportState' project.yml; then
  echo 'Legacy architecture found in project.yml' >&2
  exit 1
fi

# App and widget must share exactly the same App Group and release identity.
grep -Fq 'group.dev.mismeeter.app' MisMeeter/MisMeeter.entitlements
grep -Fq 'group.dev.mismeeter.app' MisMeeterWidget/MisMeeterWidget.entitlements
grep -Fq 'static let appGroup = "group.dev.mismeeter.app"' Shared/SharedAppState.swift
grep -Fq 'CFBundleShortVersionString: "4.0.4"' project.yml
grep -Fq 'CFBundleVersion: "104"' project.yml


echo 'MisMeeter package validation passed.'
