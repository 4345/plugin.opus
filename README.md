# plugin.opus — Solar2D Opus Audio Plugin Documentation

Plugin Name: `plugin.opus`
Publisher ID: `ovh.azi`

---

## 1. Overview

The Solar2D Opus Plugin is a high-performance, lightweight native audio codec plugin for Solar2D (formerly Corona SDK). It brings the standard Opus 1.6.1 voice and audio codec to Solar2D projects, allowing developers to compress, transmit, and decompress audio streams with high fidelity and ultra-low bandwidth.

---

## 2. Design Decisions & Implementation Highlights

* **Platform-Specific Architectures & Formats**
  * **Android:** Packaged as a Java JAR wrapping a compiled JNI native dynamic library (`.so`) for `armeabi-v7a` and `arm64-v8a` architectures.
  * **iOS / iOS Simulator:** Distributed as a static library (`libplugin_opus.a`). Links statically with the target application binary during the Solar2D cloud build process.
  * **Windows Simulator:** Full native C++ implementation (`plugin_opus.dll`) compiled with the Opus 1.6.1 codec to enable full encoding/decoding capabilities on Windows desktop.
  * **macOS Simulator & Desktop:** Full native C++ implementation (`plugin_opus.dylib`) compiled with the Opus 1.6.1 codec as a universal binary (`arm64` and `x86_64`) to enable full native encoding/decoding, resampling, and volume normalization.
  * **Linux Simulator:** Pure Lua stub implementation (`plugin_opus.lua`) to prevent simulator crashes and support clean UI flow testing.

* **Statically Linked Codec**
  For Android, iOS, and Windows, instead of using a separate C/C++ library, the Opus codec is statically compiled and linked directly into the native wrapper library. This enables compiler/linker dead-code stripping, reducing the final binary footprint under 1MB (e.g. ~459KB for iOS device, ~680KB for Android arm64-v8a, and ~302KB for Windows Simulator DLL).

* **Fixed-Point Math Compilation**
  Compiled with the `OPUS_FIXED_POINT=ON` flag. This configures the entire Opus codec to use integer-based, fixed-point calculations instead of floating-point math. This is optimal for mobile processors (ARM) and desktop simulators, resulting in significantly reduced CPU overhead.

* **Native Volume Normalizer (Android, iOS, macOS & Windows Simulator)**
  On Android, iOS, macOS, and Windows Simulator, the plugin includes a built-in volume peak normalizer running directly in the native C++ layer. It scans the PCM input, calculates the peak amplitude, and applies a scaling factor up to the target ratio (e.g., 95% peak volume) in a single pass. This boosts quiet recordings from low-end microphones without digital clipping. (Bypassed on Linux as `opus.normalize` is nil).

* **Native Linear Resampler (Android, iOS, macOS & Windows Simulator)**
  On Android, iOS, macOS, and Windows Simulator, the plugin includes a native resampler written in C++. Since mobile and desktop devices might record audio at various hardware sample rates (e.g. 44100 Hz), while Opus strictly requires specific target sample rates (8000, 12000, 16000, 24000, or 48000 Hz), the resampler bridges this difference directly in C++. (Bypassed on Linux as `opus.resample` is nil).

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
* **application:** Number (2048 = VOIP, 2049 = Audio/Music, 2051 = Low Delay)
* **Returns:** Encoder object, or `(nil, error_message)`

#### Encoder Methods:
* **`encoder:encode(pcmBytesString, frameSize)`**
  Compresses a frame of 16-bit PCM samples.
  * `pcmBytesString`: String containing raw 16-bit PCM bytes (Little-Endian).
  * `frameSize`: Number of samples per channel (e.g., `sampleRate * 0.02` for 20ms).
  * **Returns:** Compressed Opus packet (binary string), or `nil`.
* **`encoder:set_dtx(useDtx)`**
  Enables/disables Discontinuous Transmission (VAD/DTX codec-level silence).
  * `useDtx`: Boolean
  * **Returns:** Status code (0 on success).
* **`encoder:destroy()`**
  Destroys the encoder and frees its native memory pool.
  * *Note:* Optional on iOS (cleanup is handled automatically by Lua's Garbage Collector). Explicitly releases resources on Android and Windows.

### `opus.decoder_create(sampleRate, channels)`
Creates and returns a native Opus decoder instance.
* **sampleRate:** Number (Supported: 8000, 12000, 16000, 24000, 48000 Hz)
* **channels:** Number (1 = Mono, 2 = Stereo)
* **Returns:** Decoder object, or `(nil, error_message)`

#### Decoder Methods:
* **`decoder:decode(packetBytesString, frameSize)`**
  Decompresses an Opus packet back to raw 16-bit PCM bytes.
  * `packetBytesString`: String containing the compressed Opus packet.
  * `frameSize`: Number of samples per channel to decode.
  * **Returns:** Decoded raw PCM bytes (binary string), or `nil`.
* **`decoder:destroy()`**
  Destroys the decoder and frees its native memory pool.
  * *Note:* Optional on iOS (cleanup is handled automatically by Lua's Garbage Collector). Explicitly releases resources on Android and Windows.

### `opus.resample(pcmBytesString, fromRate, toRate, channels)` [Android, iOS, macOS & Windows Simulator]
Natively resamples raw PCM bytes from one sample rate to another.
* **pcmBytesString:** Raw 16-bit PCM bytes.
* **fromRate:** Source frequency in Hz.
* **toRate:** Target frequency in Hz.
* **channels:** Number of channels.
* **Returns:** Resampled PCM bytes (binary string).
* *Note:* This function is `nil` on Linux simulator.

### `opus.normalize(pcmBytesString, targetRatio)` [Android, iOS, macOS & Windows Simulator]
Natively boosts the peak volume level of the audio.
* **pcmBytesString:** Raw 16-bit PCM bytes.
* **targetRatio:** Target peak amplitude ratio (e.g., 0.95 for 95% maximum volume).
* **Returns:** Normalized PCM bytes (binary string).
* *Note:* This function is `nil` on Linux simulator.

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

*(See `pub/SimpleAudioRecorder` for a fully implemented Lua file-based helper class wrapping this logic).*

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
                macosx = { url = "https://raw.githubusercontent.com/4345/plugin.opus/main/plugins_tgz/macosx.tgz" },
                ["win32-sim"] = { url = "https://raw.githubusercontent.com/4345/plugin.opus/main/plugins_tgz/win32-sim.tgz" }
            }
        },
    },
}
```

### Windows C++ Redistributable Dependency

The Windows Simulator plugin (`plugin_opus.dll`) has an implicit dependency on the Microsoft Visual C++ Runtime libraries. Without these libraries installed in the host OS, Solar2D Simulator will fail to load the plugin at runtime, causing build/simulation errors.

To check and automatically install the required C++ dependencies on Windows, run the provided setup scripts:
* PowerShell Script: [setup_dependencies.ps1](setup_dependencies.ps1)
* Batch Script: [setup_dependencies.bat](setup_dependencies.bat)

Simply run `setup_dependencies.bat` to ensure your system has all required C++ runtime libraries.
