-- main.lua
-- Test suite for the plugin.opus Solar2D native plugin
-- (Android, iOS, macOS and Windows Simulator)

local opus = require "plugin.opus"

print("========================================")
print("     Testing plugin.opus Native SDK    ")
print("========================================")

local sampleRate = 48000
local channels = 1
local frequency = 440   -- 440 Hz (A4 note)
local frameSize = 960   -- 20ms at 48000Hz (960 samples)
local frameCount = 10   -- 200ms of audio
local amplitude = 20000

local results = {}
local function check(name, ok, details)
    results[#results + 1] = ok
    print(string.format("    %s  %s%s", ok and "ok  " or "FAIL", name, details and (" — " .. details) or ""))
end

-- Helper: Convert Lua array of 16-bit signed PCM samples to a binary string (little-endian)
local function pcmToString(samples, first, last)
    local chars = {}
    for i = first or 1, last or #samples do
        local v = samples[i]
        -- Clamp to 16-bit range just in case
        if v > 32767 then v = 32767 elseif v < -32768 then v = -32768 end
        if v < 0 then v = v + 65536 end
        chars[#chars + 1] = string.char(v % 256, math.floor(v / 256))
    end
    return table.concat(chars)
end

-- Helper: Convert binary string of 16-bit signed PCM samples to a Lua array
local function stringToPcm(str)
    local samples = {}
    for i = 1, string.len(str) - 1, 2 do
        local v = string.byte(str, i) + string.byte(str, i + 1) * 256
        if v >= 32768 then v = v - 65536 end
        samples[#samples + 1] = v
    end
    return samples
end

-- Root mean square of samples [first, last]
local function rms(samples, first, last)
    local sum, n = 0, 0
    for i = first, last do
        sum = sum + samples[i] * samples[i]
        n = n + 1
    end
    return n > 0 and math.sqrt(sum / n) or 0
end

-- 1. Generate a continuous sine wave
print("[1] Generating " .. frequency .. " Hz sine wave: " .. frameCount .. " frames of 20 ms...")
local original = {}
for i = 1, frameSize * frameCount do
    original[i] = math.floor(math.sin(2 * math.pi * frequency * (i - 1) / sampleRate) * amplitude)
end

-- 2. Create Opus Encoder
print("[2] Creating Opus Encoder (48000 Hz, 1 channel, Audio)...")
-- application: 2049 = Audio/Music (required on Android)
local encoder, err = opus.encoder_create(sampleRate, channels, 2049)
check("encoder_create", encoder ~= nil, err)
if not encoder then error("Failed to create encoder: " .. tostring(err)) end

-- Configure encoder parameters (iOS, macOS and Windows only)
if encoder.set_bitrate then
    encoder:set_bitrate(24000) -- 24kbps
    encoder:set_complexity(8)  -- high complexity/quality
    encoder:set_vbr(true)      -- variable bitrate
    print("    configured: bitrate=24000, complexity=8, vbr=true")
else
    print("    set_bitrate/set_complexity/set_vbr are not available on this platform - defaults are used")
end

-- 3. Create Opus Decoder
print("[3] Creating Opus Decoder (48000 Hz, 1 channel)...")
local decoder, decErr = opus.decoder_create(sampleRate, channels)
check("decoder_create", decoder ~= nil, decErr)
if not decoder then error("Failed to create decoder: " .. tostring(decErr)) end

-- 4. Encode and decode frame by frame
print("[4] Encoding and decoding " .. frameCount .. " frames...")
local decoded = {}
local packetBytes = 0
local allEncoded, allDecoded = true, true
for f = 0, frameCount - 1 do
    local pcm = pcmToString(original, f * frameSize + 1, (f + 1) * frameSize)
    local packet, encodeErr = encoder:encode(pcm, frameSize)
    if not packet or packet == "" then
        allEncoded = false
        print("    frame " .. (f + 1) .. ": encoding failed: " .. tostring(encodeErr))
        break
    end
    packetBytes = packetBytes + string.len(packet)
    local out, decodeErr = decoder:decode(packet, frameSize)
    if not out or string.len(out) ~= frameSize * 2 then
        allDecoded = false
        print("    frame " .. (f + 1) .. ": decoding failed: " .. tostring(decodeErr))
        break
    end
    for _, v in ipairs(stringToPcm(out)) do decoded[#decoded + 1] = v end
end
check("encode " .. frameCount .. " frames", allEncoded,
    allEncoded and string.format("%d bytes of Opus for %d bytes of PCM (%.1fx)",
        packetBytes, frameSize * frameCount * 2, frameSize * frameCount * 2 / math.max(packetBytes, 1)))
check("decode " .. frameCount .. " frames", allDecoded and #decoded == #original,
    #decoded .. " samples")

-- 5. Signal level after the codec. Opus is lossy and delays the signal by a few
--    milliseconds, so samples are not compared one by one: the level (RMS) of the
--    decoded sine, without the first two frames, must match the original.
if allDecoded and #decoded == #original then
    local first, last = 2 * frameSize + 1, #original
    local ratio = rms(decoded, first, last) / rms(original, first, last)
    check("decoded level matches the original", ratio > 0.8 and ratio < 1.2,
        string.format("RMS ratio %.2f", ratio))
end

-- 6. Native resampler: 20 ms at 48000 Hz -> 16000 Hz
print("[5] Resampling 48000 Hz -> 16000 Hz...")
local resampled = opus.resample(pcmToString(original, 1, frameSize), sampleRate, 16000, channels)
check("resample", string.len(resampled) / 2 == frameSize / 3,
    (string.len(resampled) / 2) .. " samples, expected " .. (frameSize / 3))

-- 7. Native normalizer: peak 20000 -> 95% of full scale
print("[6] Normalizing to 95% peak...")
local normalized = stringToPcm(opus.normalize(pcmToString(original, 1, frameSize), 0.95))
local peak = 0
for i = 1, #normalized do
    local a = math.abs(normalized[i])
    if a > peak then peak = a end
end
check("normalize", math.abs(peak - 32767 * 0.95) < 100,
    "peak " .. peak .. ", expected about " .. math.floor(32767 * 0.95))

-- 8. Release native objects: destroy exists on Android and Windows (on Android it
--    is the only way to free native memory); on iOS and macOS the garbage collector
--    frees them
if encoder.destroy then encoder:destroy() end
if decoder.destroy then decoder:destroy() end

local failed = 0
for _, ok in ipairs(results) do
    if not ok then failed = failed + 1 end
end
print("========================================")
if failed == 0 then
    print("      STATUS: SUCCESS (PASS)            ")
    print("  Opus codec is operating perfectly!    ")
else
    print("      STATUS: FAILED (" .. failed .. " checks)")
end
print("========================================")
