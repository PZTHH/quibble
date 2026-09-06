# A functional per-app microphone selector

Retrieved: 2026-09-06 · Directional after: 2026-10-06

## Answer

The previous `AVAudioRecorder` path cannot implement an independent macOS microphone selection with public API. Apple describes it as recording from the system’s active input; its channel-assignment API is unavailable on macOS in the installed SDK. The replacement uses one Audio Queue input client with `kAudioQueueProperty_CurrentDevice` set to the selected device UID. Recording, level meters, and HUD spectrum consume that same queue’s PCM, without changing the system default or opening a second microphone client. [AVAudioRecorder](https://developer.apple.com/documentation/avfaudio/avaudiorecorder), [queue device property](https://developer.apple.com/documentation/audiotoolbox/kaudioqueueproperty_currentdevice), read 2026-09-06.

A saved explicit device UID remains selected if disconnected and produces an actionable unavailable-input error. System Default resolves the current default once per utterance; a default change applies to the next recording. An ongoing utterance keeps its captured device. These are app behavior decisions, implemented in [AudioInputDevices.swift](../App/AudioInputDevices.swift) and [MicrophoneRecorder.swift](../App/MicrophoneRecorder.swift), inspected 2026-09-06.

## Primary evidence

| Claim | Source | Read on |
|---|---|---|
| AVAudioRecorder uses the active system input; it exposes no public macOS device-UID setter. | [Apple AVAudioRecorder docs](https://developer.apple.com/documentation/avfaudio/avaudiorecorder); installed Xcode MacOSX SDK `AVFAudio.framework/Headers/AVAudioRecorder.h`, whose `channelAssignments` declaration is `API_UNAVAILABLE(macos)` | 2026-09-06 |
| Audio Queue’s CurrentDevice property is read/write and contains a device UID. | [Apple Audio Queue property](https://developer.apple.com/documentation/audiotoolbox/kaudioqueueproperty_currentdevice); installed `AudioToolbox.framework/Headers/AudioQueue.h` | 2026-09-06 |
| HAL device UIDs persist across boots, unlike the transient AudioDeviceID used by a current hardware object. | Installed `CoreAudio.framework/Headers/AudioHardwareBase.h`, `kAudioDevicePropertyDeviceUID` documentation; [Apple device UID documentation](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertydeviceuid) | 2026-09-06 |
| The input-scope stream configuration exposes an AudioBufferList describing each stream’s channels, allowing output-only devices to be excluded. | Installed `CoreAudio.framework/Headers/AudioHardware.h`, `kAudioDevicePropertyStreamConfiguration`; [Apple property docs](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertystreamconfiguration) | 2026-09-06 |
| HAL listeners can observe device-list/default-input changes; their blocks must be removed with matching arguments. | [Apple AudioObjectAddPropertyListenerBlock](https://developer.apple.com/documentation/coreaudio/audioobjectaddpropertylistenerblock(_:_:_:_:)) | 2026-09-06 |
| A null input callback run loop selects an internal Audio Queue thread, so callbacks must not inherit MainActor isolation. | Installed `AudioToolbox.framework/Headers/AudioQueue.h`, `AudioQueueNewInput` documentation; [Apple queue API](https://developer.apple.com/documentation/audiotoolbox/audioqueuenewinput(_:_:_:_:_:_:_:)) | 2026-09-06 |
| Stop(true) is synchronous. Queue reset/stop can invoke final callbacks; disposal returns after releasing resources and prevents subsequent callbacks. | [Apple stop docs](https://developer.apple.com/documentation/audiotoolbox/audioqueuestop(_:_:)); [reset](https://developer.apple.com/documentation/audiotoolbox/audioqueuereset(_:)); [dispose](https://developer.apple.com/documentation/audiotoolbox/audioqueuedispose(_:_:)) | 2026-09-06 |
| For uncompressed PCM, AudioFileWritePackets treats packets as frames and reports the number actually written. | [Apple AudioFileWritePackets](https://developer.apple.com/documentation/audiotoolbox/audiofilewritepackets(_:_:_:_:_:_:_:)) | 2026-09-06 |

## Implementation and integration

- `AudioInputDevices` publishes the enumerated input devices, `selectedUID`, `systemDefaultUID`, and errors. `select(uid: nil)` selects System Default; `resolveForRecording()` returns a fresh `Device` or throws. `onDevicesChanged` is delivered on MainActor. No `AudioObjectSetPropertyData` call changes the system input. Listeners also watch hardware names, liveness, and input stream configuration.
- `MicrophoneRecorder(url:device:)`, `record() throws`, and synchronous `stop()` replace AVAudioRecorder. The recorder exposes `device`, `isRecording`, `currentTime`, `averagePower`, `peakPower`, `latestAmplitudes`, `spectrumEnabled`, and `error: RecordingError?`.
- The queue requests signed 16-bit, 16 kHz, mono PCM and writes a WAV. Three 50 ms buffers bound normal callback work. The same PCM supplies RMS/peak measurements and the optional [HUDSpectrumMonitor](../App/HUDSpectrumMonitor.swift).
- Stopping disables buffer recycling while leaving PCM writes enabled for the final callback. File closure follows synchronous queue disposal. Capture, interruption, stop, disposal, and file-close errors remain visible afterward. If native disposal fails, the callback context remains retained to prevent late native calls into freed Swift state; failure is reported rather than treated as a valid recording.
- Controller integration should compare both captured UID and HAL device ID against the current list during recording. A reconnect can preserve UID while replacing the active HAL object. Do not hot-swap input in the middle of an utterance.

These code claims were inspected on 2026-09-06 in the linked app sources; this subtask did not alter signing or entitlements.

## Verification

Both commands completed with exit 0 on 2026-09-06 using `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`:

```sh
python3 Scripts/check-audio-input-devices.py
python3 Scripts/check-hud-audio-callback.py
```

The input-device probe checks UID persistence, default following between utterances, explicit disconnect failure, reconnect with a changed AudioDeviceID, and unknown-selection rejection. It also performed read-only native enumeration, finding two inputs. It did not change any system route or request microphone access.

The callback probe invokes the actual production C input callback on a background executor with Swift 6 actor checks. Synthetic PCM passes through the production file writer, meters, and spectrum analyzer. It validates 64 finite spectrum bands, expected RMS/peak values, disabled-spectrum behavior, a 257-frame final partial buffer, a finalized 16 kHz mono 16-bit WAV header, rejection of callbacks after finalization, and interruption-error preservation. The actual source also passed an isolated Swift 6 typecheck.

## Unconfirmed and practical limits

- **Hardware routing/conversion:** no microphone capture was started by these probes. Successful native conversion from specific USB, Bluetooth, or multichannel input formats to the requested mono 16 kHz format still needs a signed-app recording check. Unsupported routes should fail explicitly; no fallback to a different device is configured.
- **Native final-buffer timing:** the synthetic probe proves that production PCM state accepts a partial buffer during stopping and rejects writes after closure. It does not simulate an actual AudioQueueStop/Dispose call or prove a particular device’s stop latency. A short real recording whose final word ends at release is the relevant integration check.
- **Physical disconnect:** preference-state behavior is covered by injected snapshots. Hardware notification and interruption behavior needs unplug/reconnect testing with an available external microphone.
- **HUD response:** the existing 4,096-sample spectrum window represents 256 ms at 16 kHz. Spectrum analysis remains capped at 20 Hz; the direct loudness meter updates per input buffer and supplies the existing fallback while the first full spectrum window fills.
- **Build/UI:** the integration task owns the full signed app build, menu interaction, and live recording validation. No app build, relaunch, or UI automation was performed by this subtask.
