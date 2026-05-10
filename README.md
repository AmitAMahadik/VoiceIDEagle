# VoiceID Eagle

On-device speaker enrollment, identification, and diarization for iOS, built with **SwiftUI**, **AVAudioEngine**, and the Picovoice **Eagle** + **Falcon** iOS SDKs.

- iOS 17+ · Swift 5.9+ · SwiftUI · MVVM
- 100% on-device. No backend. No raw audio is uploaded or stored.
- Local-only persistence of Eagle profiles in the app's Application Support directory.
- Eagle for speaker enrollment + live identification, Falcon for diarization with optional Eagle name-tagging on top.

## Project layout

```
VoiceIDEagle/
├── VoiceIDEagle/
│   ├── App/
│   │   └── VoiceIDEagleApp.swift
│   ├── Configuration/
│   │   ├── AppConfig.swift
│   │   └── EnvironmentLoader.swift
│   ├── Models/
│   │   ├── SpeakerProfile.swift
│   │   ├── SpeakerScore.swift
│   │   ├── RecognitionState.swift
│   │   ├── EnrollmentState.swift
│   │   └── DiarizedSegment.swift
│   ├── Services/
│   │   ├── EagleEnrollmentService.swift
│   │   ├── EagleRecognitionService.swift
│   │   ├── EagleSegmentClassifier.swift
│   │   ├── EagleProfileBytesAdapter.swift
│   │   ├── FalconDiarizationService.swift
│   │   ├── AudioCaptureService.swift
│   │   ├── SpeakerProfileStore.swift
│   │   └── MicrophonePermissionService.swift
│   ├── ViewModels/
│   │   ├── DashboardViewModel.swift
│   │   ├── EnrollmentViewModel.swift
│   │   ├── RecognitionViewModel.swift
│   │   ├── DiarizationViewModel.swift
│   │   └── ProfileManagementViewModel.swift
│   ├── Views/
│   │   ├── DashboardView.swift
│   │   ├── EnrollmentView.swift
│   │   ├── RecognitionView.swift
│   │   ├── DiarizationView.swift
│   │   ├── ProfileManagementView.swift
│   │   └── Components/
│   │       ├── StatusCardView.swift
│   │       ├── ScoreBarView.swift
│   │       ├── PrimaryButton.swift
│   │       └── EmptyStateView.swift
│   ├── Utilities/
│   │   ├── PCMConverter.swift
│   │   └── AppError.swift
│   └── Resources/
│       └── .env.example
├── .gitignore
└── README.md
```

## Setup

### 1. Create the Xcode project

1. Open Xcode → **File → New → Project → iOS → App**.
2. Product name: **VoiceIDEagle**, interface: **SwiftUI**, language: **Swift**, minimum deployment: **iOS 17.0**.
3. Save the project at the repository root so the `VoiceIDEagle/VoiceIDEagle/` source folder lines up with the new target's group.
4. Delete the auto-generated `ContentView.swift` and `VoiceIDEagleApp.swift` (we provide our own).
5. **File → Add Files to "VoiceIDEagle"** and add every folder from `VoiceIDEagle/VoiceIDEagle/`. Use **"Create folder references"** (or groups) — make sure "Copy items if needed" is **off** if your Xcode project shares the directory with the source files, otherwise on.

### 2. Add the Picovoice SDKs (Swift Package Manager)

The app links two Picovoice products. Both ship as Swift Packages and share a single AccessKey.

1. In Xcode: **File → Add Packages…**
2. Add each repository, selecting the named product when prompted:

   | Repository | Product | Used for |
   | --- | --- | --- |
   | `https://github.com/Picovoice/eagle.git` | `Eagle` | enrollment, identification, segment classification |
   | `https://github.com/Picovoice/falcon.git` | `Falcon` | speaker diarization |

3. Both packages must be added to the **VoiceIDEagle** target.

### 3. Configure the Picovoice AccessKey

You need a Picovoice AccessKey from the [Picovoice Console](https://console.picovoice.ai/).

1. In `VoiceIDEagle/Resources/`, copy `.env.example` to `.env`:

   ```bash
   cp VoiceIDEagle/Resources/.env.example VoiceIDEagle/Resources/.env
   ```

2. Edit `VoiceIDEagle/Resources/.env`:

   ```
   PICOVOICE_ACCESS_KEY=your_real_picovoice_access_key
   ```

3. **Add `.env` to the Xcode target**:
   - Select the project in the navigator → the **VoiceIDEagle** target.
   - **Build Phases → Copy Bundle Resources → +**.
   - Pick `Resources/.env`.
   - The `.env` file is already excluded from git via `.gitignore`. Only the `.env.example` template is committed.

> ⚠️ **Never hardcode the AccessKey in source code.** The app reads it exclusively from the bundled `.env`, the process environment (`PICOVOICE_ACCESS_KEY`), or — for local development — a `.env` file in the current working directory.

### 4. Add the microphone usage description

In the target's **Info** tab (or `Info.plist`) add:

| Key | Value |
| --- | --- |
| `NSMicrophoneUsageDescription` (Privacy – Microphone Usage Description) | `VoiceID Eagle uses the microphone to enroll and identify speakers entirely on-device.` |

Without this key, the OS will terminate the app on first microphone access.

### 5. Build and run

Build and run on a real device. The simulator can run the app, but speaker recognition quality on simulator audio paths is not representative of real device behavior.

## How enrollment works

1. The user enters a display name.
2. `EagleProfiler` is initialized with the AccessKey from `.env`.
3. `AudioCaptureService` taps the microphone via `AVAudioEngine` and resamples to `Eagle.sampleRate` mono 16-bit PCM.
4. Frames of length `EagleProfiler.frameLength` are fed to `enroll(pcm:)` until the percentage reaches 100.
5. `EagleProfiler.export()` returns an `EagleProfile`. We serialize the bytes via `EagleProfileBytesAdapter` and persist them, with the speaker's name and creation date, to a JSON file in the Application Support directory.
6. The profiler is destroyed (`delete()`), the audio engine is stopped, and resources are released.

## How recognition works

1. All saved `SpeakerProfile` records are loaded from disk and reconstituted into `EagleProfile` instances.
2. `Eagle` is initialized with the array of profiles plus the configured `voiceThreshold` (0.3 by default — Eagle's internal voice activity threshold, distinct from the app-level identification threshold).
3. Microphone audio is captured and converted to mono Int16 PCM at `Eagle.sampleRate`.
4. Frames of length `Eagle.minProcessSamples()` (`Eagle.frameLength` in current SDKs) are fed to `eagle.process(pcm:)`. The returned scores are aligned to the order of the input profiles.
5. Recognition smooths the last 3–5 score frames with a moving average to avoid jitter.
6. The highest-scoring speaker becomes the **best match** if their score is at or above the user-configurable identification threshold (default `0.65`, stored in `UserDefaults`); otherwise the UI shows **Unknown Speaker**.
7. `eagle.reset()` is called when the user taps **Reset Session**. `eagle.delete()` is called when listening stops.

## How diarization works

Falcon is **batch** — its iOS API consumes a complete PCM buffer in one call and returns all detected segments at once. So the diarization screen records first, then analyzes:

1. The user taps **Start Recording**. `FalconDiarizationService.start()` initializes Falcon (catches activation errors before recording starts).
2. The shared `AudioCaptureService` taps the microphone at `Falcon.sampleRate` (16 kHz mono Int16). Every frame is appended to a thread-safe `CaptureBuffer` inside the view model.
3. The user taps **Stop & Analyze** (or the 5-minute auto-stop fires). The buffer is drained.
4. Falcon's `process(_:)` returns `[FalconSegment]` — each with a `startSec`, `endSec`, and an anonymous integer `speakerTag`.
5. The view model groups the captured PCM by `speakerTag`. For each tag's PCM, `EagleSegmentClassifier.classify(pcm:)` spins up a fresh `Eagle` instance, walks the buffer in `minProcessSamples()`-sized chunks, and averages the score frames it gets back. A fresh `Eagle` per tag prevents the SDK's accumulated voice context from one tag leaking into the next.
6. Per-tag averaged score vectors are kept in the view model. Each segment's display name is resolved live from those scores against the identification threshold:
   - Score ≥ threshold → matched profile's name + confidence badge.
   - Otherwise → fall back to **Speaker N** (where `N = speakerTag + 1`).
7. The threshold slider re-labels segments instantly without re-running the pipeline.

If there are no enrolled profiles, the Eagle stage is skipped entirely and every turn shows as Speaker 1, 2, ….

## Architecture

- **MVVM**. View models are `@MainActor`-isolated and publish state via Combine `@Published` properties.
- **Services** (`Eagle*Service`, `AudioCaptureService`, `SpeakerProfileStore`, `MicrophonePermissionService`) own all I/O, audio, and SDK lifecycles.
- **Eagle work runs off the main thread.** `Task.detached(priority: .userInitiated)` hands every frame to a serial dispatch queue inside the Eagle services, then jumps back to the main actor only for state mutation.
- **Profile bytes serialization** is isolated in `EagleProfileBytesAdapter`. If a future Eagle SDK version renames `getBytes()` / `init(bytes:)`, that file is the only place to update.
- **Maximum reuse across SDKs.** `AudioCaptureService`, `PCMConverter`, `MicrophonePermissionService`, `EnvironmentLoader`/`AppConfig`, and the SwiftUI components all serve Eagle and Falcon equally. The diarization stack adds one new SDK service (`FalconDiarizationService`), one batch Eagle adapter (`EagleSegmentClassifier`), one model (`DiarizedSegment`), one view model, and one view.

## Privacy

- Voice profiles never leave the device.
- Raw audio is never persisted to disk and never uploaded.
- Only Eagle's compact profile bytes plus the user-supplied display name and creation date are stored, in `~/Library/Application Support/VoiceIDEagle/profiles.json` (sandboxed to the app).
- Voice identification is **not foolproof**. Do **not** use it as the sole factor for high-security authentication.

## Troubleshooting

| Symptom | Likely cause / fix |
| --- | --- |
| App crashes immediately with `Missing PICOVOICE_ACCESS_KEY in .env` | The `.env` file is missing, the key is empty, or the file was not added to **Copy Bundle Resources**. |
| Status card shows **Eagle SDK · Not configured** | Same as above. The `EnvironmentLoader` could not find a non-empty `PICOVOICE_ACCESS_KEY`. |
| `Microphone · Denied` | The user denied permission. Send them to **Settings → VoiceID Eagle → Microphone**. |
| `Picovoice activation limit reached` | Your AccessKey has exceeded its allowed devices. Generate a new key or upgrade in the Picovoice Console. |
| Enrollment never reaches 100% | Speak more, in a quieter room. Eagle requires several seconds of clean speech. |
| Recognition scores stay near zero | Confirm the input format conversion is producing audio (check the device's microphone permissions and that another app isn't holding the audio session). |
| Build error: `cannot find 'Eagle' in scope` | The `Eagle` Swift Package was not added to the target. Re-do **File → Add Packages…**. |
| Build error: `value of type 'EagleProfile' has no member 'getBytes'` | Your installed Eagle SDK version uses a different serialization API. Update `EagleProfileBytesAdapter.swift` — only that file needs to change. |
| Build error: `extra argument 'speakerProfiles' in call` (against `Eagle.init`) | Older SDK shape. Move the profiles into `Eagle.init(...)` and remove `speakerProfiles:` from the `process(pcm:)` call inside `EagleRecognitionService.swift`. |
| Build error: `cannot find 'Falcon' in scope` | The `Falcon` Swift Package was not added to the target. Re-do **File → Add Packages…** with `https://github.com/Picovoice/falcon.git`. |
| Diarization "found no speaker segments" | Falcon needs a few seconds of clearly-voiced audio. Try a longer recording in a quieter room. |
| Every diarized segment is "Speaker N" even though voices are enrolled | Lower the identification threshold from the Diarize screen, or re-enroll the speaker — Falcon segments are short and may not score as high as long live audio. |

## Configuration reference

| Setting | Where | Default |
| --- | --- | --- |
| `PICOVOICE_ACCESS_KEY` | `.env` (or process environment) | required |
| Identification threshold | `UserDefaults` key `identificationThreshold`, exposed in the Identify screen slider | `0.65` |
| Eagle voice threshold | `AppConfig.voiceThreshold` | `0.3` |
| Smoothing window | `RecognitionViewModel.smoothingWindow` | `5` frames |
| Max diarization recording length | `DiarizationViewModel.maxRecordingSec` | `300` s (5 min) |

## License

This sample app code is provided under the MIT license. The Picovoice Eagle SDK is licensed separately by Picovoice — see the [Picovoice license](https://github.com/Picovoice/eagle).
