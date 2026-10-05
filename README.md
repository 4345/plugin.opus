# plugin.opus — Solar2D Opus Audio Plugin Documentation

Plugin Name: `plugin.opus`
Publisher ID: `ovh.azi`

---

## 1. Overview

The Solar2D Opus Plugin is a high-performance, lightweight native audio codec plugin for Solar2D (formerly Corona SDK). It brings the standard Opus 1.6.1 voice and audio codec to Solar2D projects, allowing developers to compress, transmit, and decompress audio streams with high fidelity and ultra-low bandwidth.

---

## 2. Design Decisions & Implementation Highlights

* **Platform-Specific Architectures & Formats**
  * **Android:** Packaged as a Java JAR wrapping a compiled JNI native dynamic library (`.so`) for `armeabi-v7a`, `arm64-v8a`, `x86` and `x86_64` architectures.
  * **iOS / iOS Simulator:** Distributed as a static library (`libplugin_opus.a`), linked statically into the application when Solar2D builds it.
  * **Windows Simulator:** Full native C++ implementation (`plugin_opus.dll`, 32-bit) compiled with the Opus 1.6.1 codec to enable full encoding/decoding capabilities on Windows desktop.
  * **macOS Simulator:** Full native C++ implementation (`plugin_opus.dylib`) compiled with the Opus 1.6.1 codec as a universal binary (`arm64` and `x86_64`) to enable full native encoding/decoding, resampling, and volume normalization.
  * **Linux Simulator:** Pure Lua stub (`plugin_opus.lua`) that keeps projects running and lets the UI flow be tested: every function exists and prints a warning, but nothing is encoded — `encode` and `decode` return empty strings, `resample` and `normalize` return the input unchanged.

* **Statically Linked Codec**
  On Android, iOS, macOS and Windows, instead of using a separate C/C++ library, the Opus codec is statically compiled and linked directly into the native wrapper library. This enables compiler/linker dead-code stripping, keeping each binary under 1MB (e.g. ~478KB for iOS device, ~674KB for Android arm64-v8a, ~302KB for the Windows Simulator DLL).

* **Fixed-Point Math on Android and Windows**
  On Android (`OPUS_FIXED_POINT=ON`) and in the Windows Simulator (`FIXED_POINT`), the Opus codec is compiled with integer-based, fixed-point calculations instead of floating-point math, which keeps the CPU cost low on any device. The iOS and macOS builds use Opus' default floating-point configuration (`opus_config/config.h`).

* **Native Volume Normalizer (Android, iOS, macOS & Windows Simulator)**
  The plugin includes a peak normalizer running directly in the native C++ layer. It scans the PCM input for the peak amplitude and scales all samples so that the peak becomes the target ratio of full scale (e.g., 95%): quiet recordings from low-end microphones are boosted without digital clipping, louder ones are brought down to the same level. Silent input is returned unchanged. (On Linux the stub returns the input unchanged.)

* **Native Linear Resampler (Android, iOS, macOS & Windows Simulator)**
  The plugin includes a native linear-interpolation resampler written in C++. Since mobile and desktop devices might record audio at various hardware sample rates (e.g. 44100 Hz), while Opus strictly requires specific sample rates (8000, 12000, 16000, 24000, or 48000 Hz), the resampler bridges this difference directly in C++. (On Linux the stub returns the input unchanged.)

---

## 3. Plugin API Reference

The plugin exposes native functions to Lua in an object-oriented wrapper table.

```lua
-- Importing the plugin:
local opus = require "plugin.opus"
```

### `opus.encoder_create(sampleRate, channels, application)`
Creates and returns a native Opus encoder instance.
* **sampleRate:** Number (Supported: 8000, 12000, 16000, 24000, 48000 Hz)
* **channels:** Number (1 = Mono, 2 = Stereo)
* **application:** Number (2048 = VOIP, 2049 = Audio/Music, 2051 = Low Delay). Required on Android; on iOS, macOS and Windows it defaults to 2049 when omitted.
* **Returns:** Encoder object, or `(nil, error_message)`. On iOS and macOS an unsupported sample rate or channel count raises a Lua error instead.

#### Encoder Methods:
* **`encoder:encode(pcmBytesString, frameSize)`**
  Compresses a frame of 16-bit PCM samples.
  * `pcmBytesString`: String containing raw 16-bit PCM bytes (Little-Endian).
  * `frameSize`: Number of samples per channel — a valid Opus frame duration: 2.5, 5, 10, 20, 40 or 60 ms (e.g., `sampleRate * 0.02` for 20ms).
  * **Returns:** Compressed Opus packet (binary string). On failure: `nil` (with an error message on iOS, macOS and Windows).
* **`encoder:set_dtx(useDtx)`**
  Enables/disables Discontinuous Transmission (VAD/DTX codec-level silence).
  * `useDtx`: Boolean
  * **Returns:** Status code (0 on success) on Android and Windows; nothing on iOS and macOS.
* **`encoder:set_bitrate(bitsPerSecond)`**, **`encoder:set_complexity(0..10)`**, **`encoder:set_vbr(useVbr)`** — iOS, macOS & Windows Simulator only (not available on Android).
  Set the target bitrate, the encoder complexity and variable bitrate. Windows returns the Opus status code; iOS and macOS return nothing.
* **`encoder:destroy()`** — Android, Windows Simulator (and the Linux stub).
  Destroys the encoder and frees its native memory.
  * *Note:* On Android the encoder is a Lua table, and Solar2D's Lua 5.1 does not run `__gc` for tables, so native memory is freed **only** by `destroy()`. On iOS and macOS the encoder is userdata freed by the garbage collector, and there is no `destroy` method. Portable code: `if encoder.destroy then encoder:destroy() end`.

### `opus.decoder_create(sampleRate, channels)`
Creates and returns a native Opus decoder instance.
* **sampleRate:** Number (Supported: 8000, 12000, 16000, 24000, 48000 Hz)
* **channels:** Number (1 = Mono, 2 = Stereo)
* **Returns:** Decoder object, or `(nil, error_message)`

#### Decoder Methods:
* **`decoder:decode(packetBytesString, frameSize)`**
  Decompresses an Opus packet back to raw 16-bit PCM bytes.
  * `packetBytesString`: String containing the compressed Opus packet.
  * `frameSize`: Maximum number of samples per channel to decode.
  * **Returns:** Decoded raw PCM bytes (binary string). On failure: `nil` (with an error message on iOS, macOS and Windows).
* **`decoder:destroy()`** — Android, Windows Simulator (and the Linux stub).
  Destroys the decoder and frees its native memory. Same rules as `encoder:destroy()`: required on Android, absent on iOS and macOS (garbage-collected).

### `opus.resample(pcmBytesString, fromRate, toRate, channels)` [Android, iOS, macOS & Windows Simulator]
Natively resamples raw PCM bytes from one sample rate to another.
* **pcmBytesString:** Raw 16-bit PCM bytes.
* **fromRate:** Source frequency in Hz.
* **toRate:** Target frequency in Hz.
* **channels:** Number of channels.
* **Returns:** Resampled PCM bytes (binary string), linearly interpolated.
* *Note:* On the Linux simulator the stub returns the input unchanged.

### `opus.normalize(pcmBytesString, targetRatio)` [Android, iOS, macOS & Windows Simulator]
Natively scales the audio so that its peak reaches the target level.
* **pcmBytesString:** Raw 16-bit PCM bytes.
* **targetRatio:** Target peak amplitude ratio (e.g., 0.95 for 95% maximum volume). Quiet audio is boosted, louder audio is attenuated.
* **Returns:** Normalized PCM bytes (binary string); silent input is returned unchanged.
* *Note:* On the Linux simulator the stub returns the input unchanged.

---

## 4. Typical Audio Transcoding Flow

For a standard voice message recording/playback feature:
1. **Record audio:**
   * On Android and Windows: WAV format at 44100 Hz (fixed rate).
   * On iOS and macOS: AIFF format at 16000 Hz (configurable native rate).
2. Read the audio file, extract the raw PCM chunk.
3. **Handle resampling:**
   * On Android, iOS, macOS, and Windows, resample the PCM to 16000 Hz natively using `opus.resample` (or skip if already recorded at target rate).
4. **Boost volume to comfortable listening level:**
   * Use `opus.normalize` (target peak 95%) on Android, iOS, macOS, and Windows.
5. Instantiate an encoder using `opus.encoder_create(16000, 1, 2048)`.
6. Loop through the PCM by 20ms frames (640 bytes for Mono 16kHz) and call `encoder:encode`.
7. Package the resulting packets together with the WAV/AIFF metadata.
8. **To play back:** Instantiate a decoder, decode the packets frame-by-frame (always to WAV format for cross-platform compatibility), resample back to original rate if needed, rebuild the audio file header, and write back.

*(See `SimpleAudioRecorder` for a fully implemented Lua file-based helper class wrapping this logic).*

---

## 5. Integration & Installation

To integrate the plugin into your Solar2D project, configure your `build.settings` to download the precompiled platform archives directly from this repository:

```lua
settings =
{
    plugins =
    {
        ["plugin.opus"] =
        {
            publisherId = "ovh.azi",
            supportedPlatforms = {
                android = { url = "https://raw.githubusercontent.com/4345/plugin.opus/main/plugins_tgz/android.tgz" },
                iphone = { url = "https://raw.githubusercontent.com/4345/plugin.opus/main/plugins_tgz/iphone.tgz" },
                ["iphone-sim"] = { url = "https://raw.githubusercontent.com/4345/plugin.opus/main/plugins_tgz/iphone-sim.tgz" },
                ["mac-sim"] = { url = "https://raw.githubusercontent.com/4345/plugin.opus/main/plugins_tgz/macosx.tgz" },
                ["win32-sim"] = { url = "https://raw.githubusercontent.com/4345/plugin.opus/main/plugins_tgz/win32-sim.tgz" }
            }
        },
    },
}
```

The macOS archive is named `macosx.tgz`, but the Solar2D Simulator on a Mac only picks it up under the `["mac-sim"]` key — with a `macosx` key nothing is downloaded and `require "plugin.opus"` fails.

### Windows C++ Redistributable Dependency

The Windows Simulator plugin (`plugin_opus.dll`) is linked against the Microsoft Visual C++ Runtime DLLs (`VCRUNTIME140.dll`, `MSVCP140.dll`). Without these libraries installed in the host OS, Solar2D Simulator will fail to load the plugin at runtime, causing build/simulation errors.

To check and automatically install the required C++ dependencies on Windows, run the provided setup scripts:
* PowerShell Script: [setup_dependencies.ps1](setup_dependencies.ps1)
* Batch Script: [setup_dependencies.bat](setup_dependencies.bat)

Simply run `setup_dependencies.bat` to ensure your system has all required C++ runtime libraries.

---

## 6. Source Code & Building

The precompiled archives in `plugins_tgz/` (and the older directory layout in `plugin.opus/`) are built from the sources in this repository:

| Directory | Contents |
| :--- | :--- |
| `android/` | Solar2D Native Android project. The plugin module is `android/plugin`: Java loader `src/main/java/plugin/opus/LuaLoader.java`, JNI wrapper `src/main/cpp/plugin_opus.cpp` and `CMakeLists.txt` that builds Opus (fixed-point, no intrinsics) for all four ABIs. `android/app` is the test application: by default it packs the `SimpleAudioRecorder` demo (`coronaSrcDir` in `android/gradle.properties`); `./gradlew :app:assembleDebug -PcoronaSrcDir=../../Corona` packs the test suite instead. |
| `ios/` | Xcode projects for iOS: `Plugin/PluginLibrary.mm` (the plugin), `build_opus.sh` (static Opus for device and simulator), `build.sh` (produces `BuiltPlugin/iphone` and `BuiltPlugin/iphone-sim`; it also runs `build_mac.sh`, an older standalone macOS build — the published macOS plugin comes from `mac/`), `App.xcodeproj` (test application with the `Corona/` test suite). |
| `mac/` | Xcode project for the macOS Simulator plugin (`plugin_opus.dylib`, universal `arm64` + `x86_64`), built from `shared/SimulatorPluginLibrary.cpp`; `build_opus_mac.sh` builds Opus for macOS. |
| `shared/` | C++ implementation shared by the macOS Simulator build. |
| `win32/` | Visual Studio project for the Windows Simulator plugin (`plugin_opus.dll`, 32-bit): `plugin_opus.cpp`, with Opus compiled in. |
| `Corona/` | Cross-platform test suite: `main.lua` encodes and decodes 200 ms of a sine wave, checks the level after the codec, the resampler and the normalizer, and prints PASS/FAIL. Used by the iOS test application and, with `-PcoronaSrcDir`, by the Android one. |
| `SimpleAudioRecorder/` | Demo application: records a voice message, encodes it to Opus and plays it back (`opus.lua` — a reusable file-based helper). |
| `opus_config/` | `config.h` for the iOS/macOS builds of Opus (produced by Opus' `./configure`; they compile Opus with `-DHAVE_CONFIG_H`) and `COPYING` — the Opus license. |
| `tools/` | `poluchit_opus.py` downloads the Opus sources; `sobrat_android_tgz.py` packs `plugins_tgz/android.tgz`. |

### Opus sources

The Opus codec itself is not stored in this repository. All builds expect the **Opus 1.6.1** sources in `opus-1.6.1/` at the repository root:

* Project and repository: [opus-codec.org](https://opus-codec.org), [github.com/xiph/opus](https://github.com/xiph/opus) (tag `v1.6.1`).
* Release archive used for the published binaries: [opus-1.6.1.tar.gz](https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz), SHA-256 `6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1` (see [SHA256SUMS.txt](https://downloads.xiph.org/releases/opus/SHA256SUMS.txt)).

To download, verify and unpack it:

```
python tools/poluchit_opus.py
```

Only `src/`, `celt/` and `silk/` are compiled — the neural (`dnn/`) features are not used. Every build stops with a message pointing to the script if `opus-1.6.1/` is missing.

### Android

Requirements: JDK 17, Android SDK with NDK, Solar2D Native (`CORONA_ROOT`).

```
cd android
./gradlew :plugin:assembleRelease
cd ..
python tools/sobrat_android_tgz.py
```

`assembleRelease` produces `android/plugin/build/outputs/aar/plugin-release.aar`. `sobrat_android_tgz.py` turns it into `plugins_tgz/android.tgz`: `plugin.opus.jar` (the classes plus `lib/<abi>/libplugin_opus.so` for all four ABIs), `metadata.lua` and `resources/package.txt` from `plugin.opus/android/`. For testing with a local Solar2D build, `./gradlew :plugin:deployToLocalSolar2DRepo` puts the AAR into the local `Solar2DPlugins` directory.

### iOS and iOS Simulator

Requirements: macOS with Xcode and Solar2D Native (`~/Library/Application Support/Corona/Native`). Verified with Xcode 27, which accepts deployment targets from iOS 15.0 and macOS 12.0 — the projects use exactly these minimums.

```
ios/build.sh
```

The result is `ios/BuiltPlugin/iphone` and `ios/BuiltPlugin/iphone-sim` (`libplugin_opus.a` with Opus merged in, and `metadata.lua`). `ios/deployLocal.sh` packs them into the local `Solar2DPlugins` directory.

The test application `ios/App.xcodeproj` links the plugin target (`libplugin_library.a`, without Opus) and the Opus library from `ios/build/opus_build/`, so run `ios/build.sh` (or `ios/build_opus.sh`) before building `App`. Build the `Download Plugins` target first, then `App`.

### macOS Simulator

```
mac/build.sh
```

Builds Opus (`build_opus_mac.sh`), then the Xcode project, strips local symbols and re-signs `plugin_opus.dylib`.

### Windows Simulator

Requirements: Visual Studio 2022 with C++ desktop tools, Solar2D for Windows; the environment variable `CORONA_ROOT` points to its `Native` directory (for example `C:\Program Files (x86)\Corona Labs\Corona\Native`).

```
msbuild win32\Plugin.vcxproj /p:Configuration=Release /p:Platform=Win32
```

The result is `win32\Release\plugin_opus.dll`; a post-build step copies it into the Solar2D Simulator plugin directory.

---

## 7. License

The plugin code is released under the MIT License — see [LICENSE](LICENSE).

The Opus codec, statically linked into all plugin binaries (and the generated `opus_config/config.h`), is © the Xiph.Org Foundation and contributors and is distributed under the BSD 3-Clause license — see [opus_config/COPYING](opus_config/COPYING).
