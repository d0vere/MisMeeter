# MisMeeter

Prototype iOS app to validate:

- Live Activity on Lock Screen
- Dynamic Island presentation
- interactive Mute / Unmute button
- unsigned IPA build on GitHub Actions

This first milestone **does not stream microphone audio yet**. It only validates the iOS/ActivityKit/sideload path.

## Build on GitHub

Push this repository to GitHub. Then:

1. Open **Actions**
2. Select **Build unsigned iOS IPA**
3. Run the workflow (or push a commit)
4. When it finishes, download the `MisMeeter-unsigned` artifact
5. Extract it to obtain `MisMeeter.ipa`
6. Resign/sideload the IPA with your usual tool

The GitHub runner does not need your Apple ID or signing certificate.

## Test on iPhone

1. Launch MisMeeter
2. Tap **Start Live Activity**
3. Lock the phone and check the Lock Screen
4. On a Dynamic Island iPhone, check the Island
5. Expand the Live Activity and try **Mute / Unmute**

The button changes only the prototype `muted` state. Microphone capture and Windows streaming come later.

## Notes

- Deployment target: iOS 17.0
- The Xcode project is generated during CI with XcodeGen from `project.yml`.
- Bundle IDs are deliberately generic and may be rewritten by your sideloading tool:
  - `dev.mismeeter.app`
  - `dev.mismeeter.app.widget`
