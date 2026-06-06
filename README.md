# plugin.opus
==============================================================================
                    Solar2D Opus Audio Plugin Documentation
==============================================================================
Plugin Name:  plugin.opus
Codec Version: Opus 1.6.1
------------------------------------------------------------------------------

1. Overview
===========
The Solar2D Opus Plugin is a high-performance, lightweight native audio codec 
plugin for Solar2D (Corona SDK). It brings the standard Opus 1.6.1 voice and 
audio codec to Solar2D projects, allowing developers to compress, transmit, 
and decompress audio streams with high fidelity and ultra-low bandwidth.

2. Design Decisions & Implementation Highlights
===============================================
* Platform-Specific Architectures & Formats
  - Android: Packaged as a Java JAR wrapping a compiled JNI native dynamic library (.so)
    for armeabi-v7a and arm64-v8a architectures.
  - iOS / iOS Simulator: Distributed as a static library (libplugin_opus.a). Links statically
    with the target application binary during the Solar2D cloud build process.
  - Desktop Simulator (macOS, Windows, Linux): Pure Lua stub implementation (plugin_opus.lua)
    to prevent simulator crashes and support clean UI flow testing.

* Statically Linked Codec
  For both Android and iOS, instead of using a separate dynamic shared C/C++ library, 
  the Opus codec is statically compiled and linked directly into the native wrapper 
  library. This enables compiler/linker dead-code stripping, reducing the final 
  binary footprint under 1MB (e.g. ~459KB for iOS device and ~680KB for Android arm64-v8a).

* Fixed-Point Math Compilation
  Compiled with the `OPUS_FIXED_POINT=ON` flag. This configures the entire Opus 
  codec to use integer-based, fixed-point calculations instead of floating-point 
  math. This is optimal for mobile processors (ARM) and embedded systems, resulting 
  in significantly reduced battery usage and CPU overhead.

* Native Volume Normalizer (Android Only)
  On Android, the plugin includes a built-in volume peak normalizer running directly
  in the native C++ layer. It scans the PCM input, calculates the peak amplitude, 
  and applies a scaling factor up to the target ratio (e.g., 95% peak volume) in a 
  single pass. This boosts quiet recordings from low-end microphones without digital 
  clipping. (Bypassed on iOS as `opus.normalize` is nil).

* Native Linear Resampler (Android Only)
  On Android, the plugin includes a native resampler written in C++. Since Android 
  devices typically record audio at a fixed hardware sample rate of 44100 Hz, while 
  Opus strictly requires specific target sample rates (8000, 12000, 16000, 24000, or 
  48000 Hz), the resampler bridges this difference directly in C++ before JNI boundaries.
  On iOS, Solar2D records audio natively at the target rate specified in Lua (e.g. 16000 Hz),
  which is directly supported by the Opus codec. Thus, native resampling is bypassed 
  on iOS (the native `opus.resample` is nil).

3. Plugin API Reference
=======================
The plugin exposes native functions to Lua in an object-oriented wrapper table.

-- Importing the plugin:
local opus = require "plugin.opus"

* opus.encoder_create(sampleRate, channels, application)
  Creates and returns a native Opus encoder instance.
  - sampleRate: Number (Supported: 8000, 12000, 16000, 24000, 48000 Hz)
  - channels: Number (1 = Mono, 2 = Stereo)
  - application: Number (2048 = VOIP, 2049 = Audio/Music, 2051 = Low Delay)
  - Returns: Encoder object, or (nil, error_message)

  Encoder Methods:
  - encoder:encode(pcmBytesString, frameSize)
    Compresses a frame of 16-bit PCM samples.
    * pcmBytesString: String containing raw 16-bit PCM bytes (Little-Endian).
    * frameSize: Number of samples per channel (e.g., sampleRate * 0.02 for 20ms).
    * Returns: Compressed Opus packet (binary string), or nil.
  - encoder:set_dtx(useDtx)
    Enables/disables Discontinuous Transmission (VAD/DTX codec-level silence).
    * useDtx: Boolean
    * Returns: Status code (0 on success).
  - encoder:destroy()
    Destroys the encoder and frees its native memory pool.
    * Note: Optional on iOS (cleanup is handled automatically by Lua's
      Garbage Collector). Explicitly releases resources on Android.

* opus.decoder_create(sampleRate, channels)
  Creates and returns a native Opus decoder instance.
  - sampleRate: Number (Supported: 8000, 12000, 16000, 24000, 48000 Hz)
  - channels: Number (1 = Mono, 2 = Stereo)
  - Returns: Decoder object, or (nil, error_message)

  Decoder Methods:
  - decoder:decode(packetBytesString, frameSize)
    Decompresses an Opus packet back to raw 16-bit PCM bytes.
    * packetBytesString: String containing the compressed Opus packet.
    * frameSize: Number of samples per channel to decode.
    * Returns: Decoded raw PCM bytes (binary string), or nil.
  - decoder:destroy()
    Destroys the decoder and frees its native memory pool.
    * Note: Optional on iOS (cleanup is handled automatically by Lua's
      Garbage Collector). Explicitly releases resources on Android.

* opus.resample(pcmBytesString, fromRate, toRate, channels) [Android Only]
  Natively resamples raw PCM bytes from one sample rate to another.
  - pcmBytesString: Raw 16-bit PCM bytes.
  - fromRate: Source frequency in Hz.
  - toRate: Target frequency in Hz.
  - channels: Number of channels.
  - Returns: Resampled PCM bytes (binary string).
  - Note: This function is nil on iOS and Desktop Simulators.

* opus.normalize(pcmBytesString, targetRatio) [Android Only]
  Natively boosts the peak volume level of the audio.
  - pcmBytesString: Raw 16-bit PCM bytes.
  - targetRatio: Target peak amplitude ratio (e.g., 0.95 for 95% maximum volume).
  - Returns: Normalized PCM bytes (binary string).
  - Note: This function is nil on iOS and Desktop Simulators.

4. Typical Audio Transcoding Flow
=================================
For a standard voice message recording/playback feature:
1. Record audio:
   - On Android: WAV format at 44100 Hz (fixed rate).
   - On iOS: AIFF format at 16000 Hz (configurable native rate).
2. Read the audio file, extract the raw PCM chunk.
3. Handle resampling (Android Only):
   - On Android, resample the PCM to 16000 Hz natively using `opus.resample`.
   - On iOS, the PCM is already at 16000 Hz, so resampling is skipped.
4. Boost volume to comfortable listening level:
   - On Android, use `opus.normalize` (target peak 95%).
   - On iOS, normalization is skipped or handled in Lua.
5. Instantiate an encoder using `opus.encoder_create(16000, 1, 2048)`.
6. Loop through the PCM by 20ms frames (640 bytes for Mono 16kHz) and call `encoder:encode`.
7. Package the resulting packets together with the WAV/AIFF metadata.
8. To play back: Instantiate a decoder, decode the packets frame-by-frame, resample back to original rate if needed, rebuild the audio file header, and write back.

(See pub/SimpleAudioRecorder for a fully implemented Lua file-based helper class wrapping this logic).
==============================================================================
