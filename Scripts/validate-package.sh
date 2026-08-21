#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

for file in $(find MisMeeter MisMeeterWidget Shared -type f -name '*.swift' | sort); do
  swiftc -parse "$file" >/dev/null
done

python3 - <<'PY'
from pathlib import Path
import json, plistlib, yaml
root = Path('.')
yaml.safe_load((root / 'project.yml').read_text())
yaml.safe_load((root / '.github/workflows/build-ios.yml').read_text())
for path in root.rglob('*.json'):
    json.loads(path.read_text())
for path in (root/'MisMeeter/MisMeeter.entitlements', root/'MisMeeterWidget/MisMeeterWidget.entitlements'):
    plistlib.loads(path.read_bytes())

project = yaml.safe_load((root/'project.yml').read_text())
all_swift = {str(p) for p in root.rglob('*.swift')}
listed = set()
for target in project['targets'].values():
    for source in target.get('sources', []):
        path = source['path'] if isinstance(source, dict) else source
        if path.endswith('.swift'):
            listed.add(path)
if all_swift != listed:
    raise SystemExit(f'Source membership mismatch. Unlisted={sorted(all_swift-listed)}, missing={sorted(listed-all_swift)}')
PY

# Control architecture invariants.
grep -Fq 'ControlWidgetToggle(' MisMeeterWidget/MisMeeterSystemControls.swift
grep -Fq 'ControlValueProvider' MisMeeterWidget/MisMeeterSystemControls.swift
grep -Fq 'provider: Provider()' MisMeeterWidget/MisMeeterSystemControls.swift
grep -Fq 'func currentValue() async throws -> MisMeeterControlValue' MisMeeterWidget/MisMeeterSystemControls.swift
grep -Fq 'SharedAppState.readSnapshot()' MisMeeterWidget/MisMeeterSystemControls.swift
grep -Fq '.disabled(!value.isActive)' MisMeeterWidget/MisMeeterSystemControls.swift
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
! grep -Fq 'struct SharedControlState:' Shared/SharedControlState.swift
! grep -Fq 'control-state-' Shared/SharedControlState.swift
grep -Fq 'publishControlState(reloadControls: true)' Shared/MisMeeterRuntime.swift
grep -Fq 'publishSharedState(status: currentStatusText)' Shared/MisMeeterRuntime.swift
grep -Fq 'onTransportSnapshotChange' Shared/MisMeeterRuntime.swift
grep -Fq 'runtimeSnapshot()' Shared/MisMeeterRuntime.swift
grep -Fq 'statePublicationLock' Shared/MisMeeterRuntime.swift
grep -Fq 'value.normalized()' Shared/SharedAppState.swift
grep -Fq 'prepareForProcessTermination()' Shared/MisMeeterRuntime.swift
grep -Fq 'didFinishLaunchingWithOptions' MisMeeter/MisMeeterApp.swift
grep -Fq 'applicationWillTerminate' MisMeeter/MisMeeterApp.swift
# Removed architectures must remain absent from source membership.
if grep -Eq 'NowPlayingRemoteController|MediaPlayer|MPNowPlayingSession|MPRemoteCommandCenter|mismeeter-silence|TXPacketQueue|CaptureRingBuffer|AudioClockEstimator|MonotonicPacer|SampleFIFO' project.yml; then
  echo 'Legacy architecture found in project.yml' >&2
  exit 1
fi


# App and widget must share exactly the same App Group.
grep -Fq 'group.dev.mismeeter.app' MisMeeter/MisMeeter.entitlements
grep -Fq 'group.dev.mismeeter.app' MisMeeterWidget/MisMeeterWidget.entitlements
grep -Fq 'static let appGroup = "group.dev.mismeeter.app"' Shared/SharedAppState.swift
grep -Fq 'CFBundleShortVersionString: "4.0.3"' project.yml
grep -Fq 'CFBundleVersion: "103"' project.yml

echo 'MisMeeter package validation passed.'
