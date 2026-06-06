-- opus.lua
-- Reusable Solar2D module for Opus-1.6.1 transcoding (WAV and AIFF files)
--
-- ==============================================================================
-- PLUGIN DETAILS & PLATFORM CAPABILITIES:
-- ==============================================================================
-- * Codec version: Opus 1.6.1 (published as plugin.opus)
-- * Fixed-Point Math: Compiled with OPUS_FIXED_POINT=ON for high performance and
--   low power consumption on mobile CPUs (Android & iOS).
--
-- [Android Target]
-- * Format: Java JAR wrapping a compiled JNI native dynamic library (.so).
-- * Static Linkage: Links libopus.a statically into the JNI library to enable
--   dead-code stripping, minimizing the plugin package footprint.
-- * Native Volume Normalizer: Includes a custom JNI peak normalizer to boost
--   audio levels (target peak 95%) without introducing digital clipping.
-- * Native JNI Resampler: Fast linear resampler to bridge Android's fixed
--   44100 Hz recording rate to standard Opus-supported rates (8kHz to 48kHz).
--
-- [iOS / iOS Simulator Targets]
-- * Format: Universal static library (libplugin_opus.a) linked at cloud build time.
-- * Static Linkage: Fully statically linked with native dead-code stripping,
--   keeping the device static library size down to ~459 KB.
-- * Recording & Rates: Bypasses native resampling/normalizing. On iOS, Solar2D
--   records audio directly at the requested target rate (e.g. 16000 Hz), which
--   is natively supported by the Opus codec.
--
-- [Desktop Simulator Targets (macOS, Windows, Linux)]
-- * Format: Pure Lua stubs to prevent simulator crashes and support clean UI testing.
-- ==============================================================================
-- API USAGE EXAMPLE:
-- ==============================================================================
-- local opusModule = require("opus")
-- 
-- -- 1. Encode a recorded WAV/AIFF file into custom .opus package
-- local targetRate = 16000 -- Hz (8000, 12000, 16000, 24000, 48000 supported)
-- local encoded, encErr = opusModule.encodeFile(srcAudioPath, destOpusPath, targetRate)
-- if not encoded then
--     print("Encoding failed: " .. tostring(encErr))
-- end
-- 
-- -- 2. Decode the custom .opus package back to original WAV/AIFF format
-- local decoded, decErr = opusModule.decodeFile(destOpusPath, decodedAudioPath)
-- if not decoded then
--     print("Decoding failed: " .. tostring(decErr))
-- end
-- ==============================================================================

local M = {}

-- ==============================================================================
-- BINARY PARSING HELPERS (WAV/AIFF Support)
-- ==============================================================================

local function readBigEndianInt32(str, pos)
    local b1 = string.byte(str, pos)
    local b2 = string.byte(str, pos + 1)
    local b3 = string.byte(str, pos + 2)
    local b4 = string.byte(str, pos + 3)
    return b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
end

local function readBigEndianInt16(str, pos)
    local b1 = string.byte(str, pos)
    local b2 = string.byte(str, pos + 1)
    return b1 * 256 + b2
end

local function readLittleEndianInt32(str, pos)
    local b1 = string.byte(str, pos)
    local b2 = string.byte(str, pos + 1)
    local b3 = string.byte(str, pos + 2)
    local b4 = string.byte(str, pos + 3)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function readLittleEndianInt16(str, pos)
    local b1 = string.byte(str, pos)
    local b2 = string.byte(str, pos + 1)
    return b1 + b2 * 256
end

local function readExtendedFloat(str, pos)
    local exp = readBigEndianInt16(str, pos) % 32768
    local hiMant = readBigEndianInt32(str, pos + 2)
    local loMant = readBigEndianInt32(str, pos + 6)
    
    local exponent = exp - 16383
    local signShift = 0
    if hiMant >= 2147483648 then
        signShift = 1
    end
    local val = signShift + (hiMant % 2147483648) / 2147483648 + loMant / 9223372036854775808
    return math.floor(val * math.pow(2, exponent) + 0.5)
end

-- ==============================================================================
-- BINARY WRITING HELPERS
-- ==============================================================================

local function writeBigEndianInt32(val)
    local b1 = math.floor(val / 16777216) % 256
    local b2 = math.floor(val / 65536) % 256
    local b3 = math.floor(val / 256) % 256
    local b4 = val % 256
    return string.char(b1, b2, b3, b4)
end

local function writeLittleEndianInt32(val)
    local b1 = val % 256
    local b2 = math.floor(val / 256) % 256
    local b3 = math.floor(val / 65536) % 256
    local b4 = math.floor(val / 16777216) % 256
    return string.char(b1, b2, b3, b4)
end

local function writeLittleEndianInt16(val)
    local b1 = val % 256
    local b2 = math.floor(val / 256) % 256
    return string.char(b1, b2)
end

-- Swaps byte ordering to convert between big-endian (AIFF) and little-endian (WAV/Opus)
local function swapBytes(pcmString)
    local len = #pcmString
    local chars = {}
    for i = 1, len, 2 do
        local b1 = string.byte(pcmString, i)
        local b2 = string.byte(pcmString, i + 1)
        if not b1 or not b2 then break end
        chars[#chars + 1] = string.char(b2, b1)
    end
    return table.concat(chars)
end

-- ==============================================================================
-- ENCODE FILE API
-- ==============================================================================
-- Reads WAV/AIFF audio from inputFilePath, normalizes and resamples using the
-- native library, compresses to Opus frames, and writes to outputOpusPath in
-- a custom self-contained binary format containing all file headers and metadata.
-- ==============================================================================
function M.encodeFile(inputFilePath, outputOpusPath, targetSampleRate)
    local f = io.open(inputFilePath, "rb")
    if not f then
        print("Error: Could not open input audio file: " .. tostring(inputFilePath))
        return nil, "Could not open input file"
    end
    local content = f:read("*a")
    f:close()

    local fileType = content:sub(1, 4)
    local rawPcm, sampleRate, channels, soundDataOffset, soundDataSize
    local isBigEndian = false
    
    -- Byte offset references in headers to rewrite sizes on decoding
    local commNumFramesOffset = nil
    local ssndChunkSizeOffset = nil
    local dataChunkSizeOffset = nil

    if fileType == "FORM" then
        -- AIFF / AIFC
        local formType = content:sub(9, 12)
        if formType == "AIFF" or formType == "AIFC" then
            isBigEndian = (formType == "AIFF")
            local pos = 13
            while pos < #content do
                local chunkId = content:sub(pos, pos + 3)
                local chunkSize = readBigEndianInt32(content, pos + 4)
                if not chunkSize or chunkSize <= 0 then break end

                if chunkId == "COMM" then
                    channels = readBigEndianInt16(content, pos + 8)
                    sampleRate = readExtendedFloat(content, pos + 16)
                    commNumFramesOffset = pos + 10
                elseif chunkId == "SSND" then
                    local offsetVal = readBigEndianInt32(content, pos + 8)
                    soundDataOffset = pos + 16 + offsetVal
                    soundDataSize = chunkSize - 8
                    ssndChunkSizeOffset = pos + 4
                end

                pos = pos + 8 + chunkSize
                if chunkSize % 2 == 1 then pos = pos + 1 end
            end
        end
    elseif fileType == "RIFF" then
        -- WAV
        local formType = content:sub(9, 12)
        if formType == "WAVE" then
            isBigEndian = false
            local pos = 13
            while pos < #content do
                local chunkId = content:sub(pos, pos + 3)
                local chunkSize = readLittleEndianInt32(content, pos + 4)
                if not chunkSize or chunkSize <= 0 then break end

                if chunkId == "fmt " then
                    channels = readLittleEndianInt16(content, pos + 10)
                    sampleRate = readLittleEndianInt32(content, pos + 12)
                elseif chunkId == "data" then
                    soundDataOffset = pos + 8
                    soundDataSize = chunkSize
                    dataChunkSizeOffset = pos + 4
                end

                pos = pos + 8 + chunkSize
            end
        end
    end

    if not soundDataOffset or not soundDataSize or not sampleRate or not channels then
        return nil, "Failed to parse WAV/AIFF audio headers"
    end

    rawPcm = content:sub(soundDataOffset, soundDataOffset + soundDataSize - 1)

    print("\n==========================================")
    print("      OPUS NATIVE ENCODING PIPELINE")
    print("==========================================")
    print("Source Audio Properties:")
    print("  Format: " .. (fileType == "FORM" and "AIFF" or "WAV"))
    print("  Sample Rate: " .. sampleRate .. " Hz")
    print("  Channels: " .. channels)
    print("  Original Size: " .. #rawPcm .. " PCM bytes")

    local opus = require "plugin.opus"
    local hasResample = (opus.resample ~= nil)

    -- Determine valid target rate supported by the Opus codec
    local workingSampleRate = targetSampleRate or sampleRate
    if workingSampleRate ~= 8000 and workingSampleRate ~= 12000 and workingSampleRate ~= 16000 and workingSampleRate ~= 24000 and workingSampleRate ~= 48000 then
        -- Fallback to the closest supported codec rate
        if workingSampleRate < 10000 then workingSampleRate = 8000
        elseif workingSampleRate < 14000 then workingSampleRate = 12000
        elseif workingSampleRate < 20000 then workingSampleRate = 16000
        elseif workingSampleRate < 36000 then workingSampleRate = 24000
        else workingSampleRate = 48000 end
    end

    -- Swap endianness if file is Big-Endian (AIFF)
    local inputPcm = rawPcm
    if isBigEndian then
        inputPcm = swapBytes(rawPcm)
    end

    -- Perform native JNI resampling if rates differ
    local pcmForOpus = inputPcm
    if sampleRate ~= workingSampleRate then
        if hasResample then
            print("Resampling source PCM natively from " .. sampleRate .. " Hz to " .. workingSampleRate .. " Hz...")
            pcmForOpus = opus.resample(inputPcm, sampleRate, workingSampleRate, channels)
        else
            print("Warning: Native resampler not available, using source sample rate: " .. sampleRate .. " Hz.")
            workingSampleRate = sampleRate
        end
    end

    -- Perform native JNI volume normalization (target peak 95% volume level)
    if opus.normalize ~= nil then
        print("Normalizing peak volume level natively to 95%...")
        pcmForOpus = opus.normalize(pcmForOpus, 0.95)
    end

    -- Check if working sample rate is supported by Opus
    if workingSampleRate ~= 8000 and workingSampleRate ~= 12000 and workingSampleRate ~= 16000 and workingSampleRate ~= 24000 and workingSampleRate ~= 48000 then
        return nil, "Unsupported working sample rate: " .. workingSampleRate .. " Hz"
    end

    local frameSize = math.floor(workingSampleRate * 0.02) -- 20ms audio frame
    local bytesPerFrame = frameSize * channels * 2

    -- Create native Opus encoder (VOIP mode = 2048)
    local encoder, err = opus.encoder_create(workingSampleRate, channels, 2048)
    if not encoder then
        return nil, "Failed to create native encoder: " .. tostring(err)
    end
    
    -- Keep standard DTX disabled to ensure stable codec stream output
    encoder:set_dtx(false)

    local compressedData = {}
    local totalCompressedSize = 0

    print("Encoding PCM frames to Opus...")
    for i = 1, #pcmForOpus, bytesPerFrame do
        local chunk = pcmForOpus:sub(i, i + bytesPerFrame - 1)
        if #chunk < bytesPerFrame then
            -- Zero-pad trailing sub-frame
            chunk = chunk .. string.rep(string.char(0), bytesPerFrame - #chunk)
        end
        local packet, encErr = encoder:encode(chunk, frameSize)
        if not packet then
            if encoder.destroy then encoder:destroy() end
            return nil, "Encoding error at byte " .. i .. ": " .. tostring(encErr)
        end
        compressedData[#compressedData + 1] = packet
        totalCompressedSize = totalCompressedSize + #packet
    end

    if encoder.destroy then encoder:destroy() end

    print("  Compressed Opus Size: " .. totalCompressedSize .. " bytes")
    local compRatio = #pcmForOpus / totalCompressedSize
    print("  Compression Ratio: " .. string.format("%.2f", compRatio) .. "x")

    -- Expose original header for exact WAV/AIFF formatting preservation
    local newHeader = content:sub(1, soundDataOffset - 1)

    -- Write packaged data to the custom .opus file container
    local out, ioErr = io.open(outputOpusPath, "wb")
    if not out then
        return nil, "Failed to open Opus output file: " .. tostring(ioErr)
    end

    -- Container Header:
    -- Magic (4 bytes) | Format (4 bytes) | SrcRate (4 bytes) | Channels (2 bytes) | WorkingRate (2 bytes)
    -- CommOffset (4 bytes) | SsndOffset (4 bytes) | DataOffset (4 bytes)
    -- HeaderSize (4 bytes) | OriginalHeader (H bytes) | PacketCount (4 bytes)
    out:write("OPUS")
    out:write(fileType == "FORM" and "AIFF" or "WAVE")
    out:write(writeLittleEndianInt32(sampleRate))
    out:write(writeLittleEndianInt16(channels))
    out:write(writeLittleEndianInt16(workingSampleRate))
    
    out:write(writeLittleEndianInt32(commNumFramesOffset or 0))
    out:write(writeLittleEndianInt32(ssndChunkSizeOffset or 0))
    out:write(writeLittleEndianInt32(dataChunkSizeOffset or 0))
    
    out:write(writeLittleEndianInt32(#newHeader))
    out:write(newHeader)
    out:write(writeLittleEndianInt32(#compressedData))

    -- Packets payload
    for i = 1, #compressedData do
        local packet = compressedData[i]
        out:write(writeLittleEndianInt32(#packet))
        out:write(packet)
    end
    out:close()

    print("Audio file successfully encoded & packaged to: " .. outputOpusPath)
    print("==========================================\n")
    return true
end

-- ==============================================================================
-- DECODE FILE API
-- ==============================================================================
-- Reads custom .opus packaged file from inputOpusPath, decodes the packets back
-- to PCM, resamples back to original sampleRate, and writes updated WAV/AIFF file.
-- ==============================================================================
function M.decodeFile(inputOpusPath, outputFilePath)
    local f, ioErr = io.open(inputOpusPath, "rb")
    if not f then
        print("Error: Could not open input Opus file: " .. tostring(inputOpusPath))
        return nil, "Could not open input file: " .. tostring(ioErr)
    end

    -- Read and verify container header fields
    local magic = f:read(4)
    if magic ~= "OPUS" then
        f:close()
        return nil, "Invalid file format identifier (expected 'OPUS')"
    end

    local formatType = f:read(4) -- "AIFF" or "WAVE"
    
    local headerBytes = f:read(4)
    local sampleRate = readLittleEndianInt32(headerBytes, 1)
    
    local channelsBytes = f:read(2)
    local channels = readLittleEndianInt16(channelsBytes, 1)
    
    local workingRateBytes = f:read(2)
    local workingSampleRate = readLittleEndianInt16(workingRateBytes, 1)
    
    -- Load byte offsets for header size rewriting
    local commNumFramesOffsetVal = readLittleEndianInt32(f:read(4), 1)
    local ssndChunkSizeOffsetVal = readLittleEndianInt32(f:read(4), 1)
    local dataChunkSizeOffsetVal = readLittleEndianInt32(f:read(4), 1)
    
    local commNumFramesOffset = (commNumFramesOffsetVal > 0) and commNumFramesOffsetVal or nil
    local ssndChunkSizeOffset = (ssndChunkSizeOffsetVal > 0) and ssndChunkSizeOffsetVal or nil
    local dataChunkSizeOffset = (dataChunkSizeOffsetVal > 0) and dataChunkSizeOffsetVal or nil

    local newHeaderSizeBytes = f:read(4)
    local newHeaderSize = readLittleEndianInt32(newHeaderSizeBytes, 1)
    local newHeader = f:read(newHeaderSize)
    
    local packetCountBytes = f:read(4)
    local packetCount = readLittleEndianInt32(packetCountBytes, 1)

    -- Extract packets
    local compressedData = {}
    for i = 1, packetCount do
        local lenBytes = f:read(4)
        if not lenBytes or #lenBytes < 4 then break end
        local len = readLittleEndianInt32(lenBytes, 1)
        local packet = f:read(len)
        compressedData[#compressedData + 1] = packet
    end
    f:close()

    print("\n==========================================")
    print("      OPUS NATIVE DECODING PIPELINE")
    print("==========================================")
    print("Opus Package Properties:")
    print("  Target Format: " .. formatType)
    print("  Original Sample Rate: " .. sampleRate .. " Hz")
    print("  Working Sample Rate: " .. workingSampleRate .. " Hz")
    print("  Channels: " .. channels)
    print("  Total Packets: " .. #compressedData)

    local opus = require "plugin.opus"
    local hasResample = (opus.resample ~= nil)

    -- Create native Opus decoder
    local decoder, err = opus.decoder_create(workingSampleRate, channels)
    if not decoder then
        return nil, "Failed to create native decoder: " .. tostring(err)
    end

    local frameSize = math.floor(workingSampleRate * 0.02) -- 20ms frame size
    local decodedPcmList = {}

    print("Decoding Opus packets...")
    for i = 1, #compressedData do
        local packet = compressedData[i]
        local pcmFrame, decErr = decoder:decode(packet, frameSize)
        if not pcmFrame then
            if decoder.destroy then decoder:destroy() end
            return nil, "Decoding error at packet " .. i .. ": " .. tostring(decErr)
        end
        decodedPcmList[#decodedPcmList + 1] = pcmFrame
    end

    if decoder.destroy then decoder:destroy() end

    local decodedPcm = table.concat(decodedPcmList)
    print("  Decoded PCM Raw Size: " .. #decodedPcm .. " bytes")

    -- Resample PCM back to original sampleRate if they differed
    if sampleRate ~= workingSampleRate then
        if hasResample then
            print("Resampling decoded PCM natively from " .. workingSampleRate .. " Hz back to " .. sampleRate .. " Hz...")
            decodedPcm = opus.resample(decodedPcm, workingSampleRate, sampleRate, channels)
            print("  Resampled PCM Size: " .. #decodedPcm .. " bytes")
        end
    end

    -- Convert back to Big-Endian if target file format is AIFF
    local isBigEndian = (formatType == "AIFF")
    if isBigEndian then
        decodedPcm = swapBytes(decodedPcm)
    end

    -- Update WAV/AIFF header chunk sizes to match the decoded PCM size
    local updatedContent
    if formatType == "AIFF" then
        local totalSize = #newHeader + #decodedPcm
        
        -- 1. Update FORM chunk size (offset 5)
        local p1 = newHeader:sub(1, 4)
        local p2 = writeBigEndianInt32(totalSize - 8)
        local p3 = newHeader:sub(9)
        newHeader = p1 .. p2 .. p3
        
        -- 2. Update COMM chunk frame count
        if commNumFramesOffset then
            local numFrames = #decodedPcm / (channels * 2)
            p1 = newHeader:sub(1, commNumFramesOffset - 1)
            p2 = writeBigEndianInt32(numFrames)
            p3 = newHeader:sub(commNumFramesOffset + 4)
            newHeader = p1 .. p2 .. p3
        end
        
        -- 3. Update SSND chunk size
        if ssndChunkSizeOffset then
            p1 = newHeader:sub(1, ssndChunkSizeOffset - 1)
            p2 = writeBigEndianInt32(#decodedPcm + 8)
            p3 = newHeader:sub(ssndChunkSizeOffset + 4)
            newHeader = p1 .. p2 .. p3
        end
        
        updatedContent = newHeader .. decodedPcm
    else
        -- WAV
        local totalSize = #newHeader + #decodedPcm
        
        -- 1. Update RIFF chunk size (offset 5)
        local p1 = newHeader:sub(1, 4)
        local p2 = writeLittleEndianInt32(totalSize - 8)
        local p3 = newHeader:sub(9)
        newHeader = p1 .. p2 .. p3
        
        -- 2. Update data chunk size
        if dataChunkSizeOffset then
            p1 = newHeader:sub(1, dataChunkSizeOffset - 1)
            p2 = writeLittleEndianInt32(#decodedPcm)
            p3 = newHeader:sub(dataChunkSizeOffset + 4)
            newHeader = p1 .. p2 .. p3
        end
        
        updatedContent = newHeader .. decodedPcm
    end

    -- Write reconstructed file to outputFilePath
    local out, writeErr = io.open(outputFilePath, "wb")
    if not out then
        return nil, "Failed to open output file for writing: " .. tostring(writeErr)
    end
    out:write(updatedContent)
    out:close()

    print("Audio file successfully reconstructed & written to: " .. outputFilePath)
    print("==========================================\n")
    return true
end

return M
