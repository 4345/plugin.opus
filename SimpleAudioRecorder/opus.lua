-- opus.lua
-- Повторно используемый модуль Solar2D для транскодирования Opus-1.6.1, обнаружения
-- голосовой активности (VAD) и удаления тишины (файлы AIFF/WAV)

local dll = require("dll")
local M = {}

-- Вспомогательные функции для чтения бинарных данных
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

-- Вспомогательные функции для записи бинарных данных
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

-- Вспомогательная функция для создания заголовка WAVE (WAV, PCM 16-bit)
local function makeWavHeader(sampleRate, channels, pcmSize)
    local header = {}
    header[#header + 1] = "RIFF"
    header[#header + 1] = writeLittleEndianInt32(36 + pcmSize)
    header[#header + 1] = "WAVE"
    header[#header + 1] = "fmt "
    header[#header + 1] = writeLittleEndianInt32(16)
    header[#header + 1] = writeLittleEndianInt16(1) -- PCM format (1)
    header[#header + 1] = writeLittleEndianInt16(channels)
    header[#header + 1] = writeLittleEndianInt32(sampleRate)
    header[#header + 1] = writeLittleEndianInt32(sampleRate * channels * 2)
    header[#header + 1] = writeLittleEndianInt16(channels * 2)
    header[#header + 1] = writeLittleEndianInt16(16) -- bits per sample (16)
    header[#header + 1] = "data"
    header[#header + 1] = writeLittleEndianInt32(pcmSize)
    return table.concat(header)
end

-- Перестановка байтов для конвертации между big-endian (AIFF) и little-endian (Opus/WAV)
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

-- Обнаружение голосовой активности (VAD) и удаление тишины с использованием буферов предварительной (pre-roll) и последующей (post-roll) задержки
local function stripSilence(pcmBytes, bytesPerFrame, frameSize, channels)
    local speechFrames = {}
    local threshold = 400 -- Порог среднеквадратичной амплитуды (RMS) (можно настраивать)
    local originalFrames = 0
    local speechFramesCount = 0
    
    -- Настройка "зависания" (буфера тишины) для предотвращения прерывистого звука/клиппинга
    local preRollLimit = 6   -- Сохранять 6 фреймов (120 мс) тишины ДО начала речи
    local postRollLimit = 15 -- Сохранять 15 фреймов (300 мс) тишины ПОСЛЕ окончания речи
    
    local preRollBuffer = {}  -- Кольцевой буфер для предварительной тишины (pre-roll)
    local postRollCounter = 0 -- Счетчик последующей тишины (post-roll)
    local inSpeech = false
    
    for i = 1, #pcmBytes, bytesPerFrame do
        local chunk = pcmBytes:sub(i, i + bytesPerFrame - 1)
        if #chunk == bytesPerFrame then
            originalFrames = originalFrames + 1
            local sumSqr = 0
            local numSamples = frameSize * channels
            for j = 1, #chunk, 2 do
                local low = chunk:byte(j)
                local high = chunk:byte(j + 1)
                if not low or not high then break end
                local sample = low + high * 256
                if sample >= 32768 then sample = sample - 65536 end
                sumSqr = sumSqr + (sample * sample)
            end
            local rms = math.sqrt(sumSqr / numSamples)
            
            local isSpeechFrame = (rms > threshold)
            
            if isSpeechFrame then
                if not inSpeech then
                    -- Переход от тишины к речи. Сначала сбрасываем буфер pre-roll.
                    for k = 1, #preRollBuffer do
                        speechFrames[#speechFrames + 1] = preRollBuffer[k]
                        speechFramesCount = speechFramesCount + 1
                    end
                    preRollBuffer = {}
                    inSpeech = true
                end
                
                -- Добавляем фрейм речи
                speechFrames[#speechFrames + 1] = chunk
                speechFramesCount = speechFramesCount + 1
                
                -- Поддерживаем активным окно задержки post-roll
                postRollCounter = postRollLimit
            else
                -- Фрейм тишины
                if inSpeech then
                    if postRollCounter > 0 then
                        -- В пределах окна задержки сохраняем фрейм тишины
                        speechFrames[#speechFrames + 1] = chunk
                        speechFramesCount = speechFramesCount + 1
                        postRollCounter = postRollCounter - 1
                    else
                        -- Окно задержки истекло, переход в состояние тишины
                        inSpeech = false
                        preRollBuffer[#preRollBuffer + 1] = chunk
                    end
                else
                    -- В состоянии тишины. Добавляем в кольцевой буфер pre-roll.
                    preRollBuffer[#preRollBuffer + 1] = chunk
                    if #preRollBuffer > preRollLimit then
                        table.remove(preRollBuffer, 1) -- Поддерживаем фиксированный размер
                    end
                end
            end
        end
    end
    
    return table.concat(speechFrames), originalFrames, speechFramesCount
end

-- ==============================================================================
-- API ДЛЯ КОДИРОВАНИЯ ФАЙЛА
-- ==============================================================================
-- Читает аудиоданные WAV/AIFF из inputFilePath, нормализует и ресемплирует их с помощью
-- встроенной библиотеки, удаляет тишину, сжимает во фреймы Opus и записывает в outputOpusPath
-- в пользовательском независимом бинарном формате, содержащем все заголовки и метаданные файла.
-- ==============================================================================
function M.encodeFile(inputFilePath, outputOpusPath, targetSampleRate)
    local f = io.open(inputFilePath, "rb")
    if not f then
        dll.llog("Ошибка: не удалось открыть входной аудиофайл: " .. tostring(inputFilePath))
        return nil, "Не удалось открыть входной файл"
    end
    local content = f:read("*a")
    f:close()

    local fileType = content:sub(1, 4)
    local rawPcm, sampleRate, channels, soundDataOffset, soundDataSize
    local isBigEndian = false
    
    -- Смещение байтов в заголовках для перезаписи размеров при декодировании
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
        return nil, "Не удалось разобрать заголовки аудио WAV/AIFF"
    end

    rawPcm = content:sub(soundDataOffset, soundDataOffset + soundDataSize - 1)

    dll.llog("\n==========================================")
    dll.llog("      КОНВЕЙЕР КОДИРОВАНИЯ OPUS")
    dll.llog("==========================================")
    dll.llog("Свойства исходного аудио:")
    dll.llog("  Формат: " .. (fileType == "FORM" and "AIFF" or "WAV"))
    dll.llog("  Частота дискретизации: " .. sampleRate .. " Гц")
    dll.llog("  Каналы: " .. channels)
    dll.llog("  Исходный размер: " .. #rawPcm .. " байт PCM")

    local opus = require "plugin.opus"
    local hasResample = (opus.resample ~= nil)
    dll.llog("  Встроенный ресемплер: " .. tostring(hasResample))
    dll.llog("  Встроенный нормализатор: " .. tostring(opus.normalize ~= nil))

    -- Определение корректной целевой частоты, поддерживаемой кодеком Opus
    local workingSampleRate = targetSampleRate or sampleRate
    if workingSampleRate ~= 8000 and workingSampleRate ~= 12000 and workingSampleRate ~= 16000 and workingSampleRate ~= 24000 and workingSampleRate ~= 48000 then
        -- Возврат к ближайшей поддерживаемой частоте кодека
        if workingSampleRate < 10000 then workingSampleRate = 8000
        elseif workingSampleRate < 14000 then workingSampleRate = 12000
        elseif workingSampleRate < 20000 then workingSampleRate = 16000
        elseif workingSampleRate < 36000 then workingSampleRate = 24000
        else workingSampleRate = 48000 end
    end

    -- Изменение порядка байтов (endianness), если файл Big-Endian (AIFF)
    local inputPcm = rawPcm
    if isBigEndian then
        inputPcm = swapBytes(rawPcm)
    end

    -- Выполнение ресемплирования средствами JNI, если частоты различаются
    local pcmForOpus = inputPcm
    if sampleRate ~= workingSampleRate then
        if hasResample then
            dll.llog("Ресемплирование исходного PCM с " .. sampleRate .. " Гц до " .. workingSampleRate .. " Гц...")
            pcmForOpus = opus.resample(inputPcm, sampleRate, workingSampleRate, channels)
        else
            dll.llog("Предупреждение: встроенный ресемплер недоступен, используется исходная частота: " .. sampleRate .. " Гц.")
            workingSampleRate = sampleRate
        end
    end

    -- Выполнение нормализации громкости средствами JNI (целевой пик 95% уровня громкости)
    if opus.normalize ~= nil then
        dll.llog("Нормализация пиковой громкости до 95%...")
        pcmForOpus = opus.normalize(pcmForOpus, 0.95)
    end

    -- Проверка поддержки рабочей частоты дискретизации кодеком Opus
    if workingSampleRate ~= 8000 and workingSampleRate ~= 12000 and workingSampleRate ~= 16000 and workingSampleRate ~= 24000 and workingSampleRate ~= 48000 then
        return nil, "Неподдерживаемая рабочая частота дискретизации: " .. workingSampleRate .. " Гц"
    end

    local frameSize = math.floor(workingSampleRate * 0.02) -- фрейм аудио 20 мс
    local bytesPerFrame = frameSize * channels * 2

    -- Удаление тишины из PCM
    dll.llog("Обнаружение и удаление периодов тишины...")
    local activePcm, totalFrames, speechFrames = stripSilence(pcmForOpus, bytesPerFrame, frameSize, channels)
    local silenceFrames = totalFrames - speechFrames
    dll.llog("  Всего фреймов (по 20мс): " .. totalFrames)
    dll.llog("  Сохранено фреймов с речью: " .. speechFrames .. " (" .. string.format("%.1f", speechFrames / totalFrames * 100) .. "%)")
    dll.llog("  Удалено фреймов с тишиной: " .. silenceFrames .. " (" .. string.format("%.1f", silenceFrames / totalFrames * 100) .. "%)")
    dll.llog("  Размер отфильтрованного PCM: " .. #activePcm .. " байт")

    if #activePcm == 0 then
        return nil, "Recorded audio is entirely silent"
    end

    -- Создание встроенного кодера Opus (режим VOIP = 2048)
    local encoder, err = opus.encoder_create(workingSampleRate, channels, 2048)
    if not encoder then
        return nil, "Не удалось создать встроенный кодер: " .. tostring(err)
    end
    
    -- Отключение стандартного DTX для обеспечения стабильного вывода потока кодека
    encoder:set_dtx(false)

    local compressedData = {}
    local totalCompressedSize = 0

    dll.llog("Кодирование фреймов PCM в Opus...")
    for i = 1, #activePcm, bytesPerFrame do
        local chunk = activePcm:sub(i, i + bytesPerFrame - 1)
        if #chunk < bytesPerFrame then
            -- Дополнение нулями хвостового неполного субфрейма
            chunk = chunk .. string.rep(string.char(0), bytesPerFrame - #chunk)
        end
        local packet, encErr = encoder:encode(chunk, frameSize)
        if not packet then
            if encoder.destroy then encoder:destroy() end
            return nil, "Ошибка кодирования на байте " .. i .. ": " .. tostring(encErr)
        end
        compressedData[#compressedData + 1] = packet
        totalCompressedSize = totalCompressedSize + #packet
    end

    if encoder.destroy then encoder:destroy() end

    dll.llog("  Размер сжатого Opus: " .. totalCompressedSize .. " байт")
    local compRatio = #pcmForOpus / totalCompressedSize
    dll.llog("  Коэффициент сжатия: " .. string.format("%.2f", compRatio) .. "x")

    -- Извлечение оригинального заголовка для точного сохранения форматирования WAV/AIFF
    local newHeader = content:sub(1, soundDataOffset - 1)

    -- Запись упакованных данных в пользовательский контейнер файлов .opus
    local out, ioErr = io.open(outputOpusPath, "wb")
    if not out then
        return nil, "Не удалось открыть выходной файл Opus: " .. tostring(ioErr)
    end

    -- Заголовок контейнера:
    -- Magic (4 байта) | Формат (4 байта) | Исходная частота (4 байта) | Каналы (2 байта) | Рабочая частота (2 байта)
    -- CommOffset (4 байта) | SsndOffset (4 байта) | DataOffset (4 байта)
    -- Размер заголовка (4 байта) | Оригинальный заголовок (H байт) | Количество пакетов (4 байта)
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

    -- Полезная нагрузка пакетов
    for i = 1, #compressedData do
        local packet = compressedData[i]
        out:write(writeLittleEndianInt32(#packet))
        out:write(packet)
    end
    out:close()

    dll.llog("Аудиофайл успешно закодирован и упакован в: " .. outputOpusPath)
    dll.llog("==========================================\n")
    return true
end

-- ==============================================================================
-- API ДЛЯ ДЕКОДИРОВАНИЯ ФАЙЛА
-- ==============================================================================
-- Читает упакованный файл .opus из inputOpusPath, декодирует пакеты обратно в PCM,
-- ресемплирует обратно до исходной частоты дискретизации и записывает обновленный WAV/AIFF файл.
-- ==============================================================================
function M.decodeFile(inputOpusPath, outputFilePath)
    local f, ioErr = io.open(inputOpusPath, "rb")
    if not f then
        dll.llog("Ошибка: не удалось открыть входной файл Opus: " .. tostring(inputOpusPath))
        return nil, "Не удалось открыть входной файл: " .. tostring(ioErr)
    end

    -- Чтение и проверка полей заголовка контейнера
    local magic = f:read(4)
    if magic ~= "OPUS" then
        f:close()
        return nil, "Неверный идентификатор формата файла (ожидался 'OPUS')"
    end

    local formatType = f:read(4) -- "AIFF" или "WAVE"
    
    local headerBytes = f:read(4)
    local sampleRate = readLittleEndianInt32(headerBytes, 1)
    
    local channelsBytes = f:read(2)
    local channels = readLittleEndianInt16(channelsBytes, 1)
    
    local workingRateBytes = f:read(2)
    local workingSampleRate = readLittleEndianInt16(workingRateBytes, 1)
    
    -- Загрузка байтовых смещений для перезаписи размеров заголовков
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

    -- Извлечение пакетов
    local compressedData = {}
    for i = 1, packetCount do
        local lenBytes = f:read(4)
        if not lenBytes or #lenBytes < 4 then break end
        local len = readLittleEndianInt32(lenBytes, 1)
        local packet = f:read(len)
        compressedData[#compressedData + 1] = packet
    end
    f:close()

    dll.llog("\n==========================================")
    dll.llog("      КОНВЕЙЕР ДЕКОДИРОВАНИЯ OPUS")
    --dll.llog("==========================================")
    --dll.llog("Свойства пакета Opus:")
    --dll.llog("  Целевой формат: " .. formatType)
    --dll.llog("  Исходная частота дискретизации: " .. sampleRate .. " Гц")
    --dll.llog("  Рабочая частота дискретизации: " .. workingSampleRate .. " Гц")
    --dll.llog("  Каналы: " .. channels)
    --dll.llog("  Всего пакетов: " .. #compressedData)

    local opus = require "plugin.opus"
    local hasResample = (opus.resample ~= nil)

    -- Создание встроенного декодера Opus
    local decoder, err = opus.decoder_create(workingSampleRate, channels)
    if not decoder then
        return nil, "Не удалось создать встроенный декодер: " .. tostring(err)
    end

    local frameSize = math.floor(workingSampleRate * 0.02) -- размер фрейма 20 мс
    local decodedPcmList = {}

    -- dll.llog("Декодирование пакетов Opus...")
    for i = 1, #compressedData do
        local packet = compressedData[i]
        local pcmFrame, decErr = decoder:decode(packet, frameSize)
        if not pcmFrame then
            if decoder.destroy then decoder:destroy() end
            return nil, "Ошибка декодирования на пакете " .. i .. ": " .. tostring(decErr)
        end
        decodedPcmList[#decodedPcmList + 1] = pcmFrame
    end

    if decoder.destroy then decoder:destroy() end

    local decodedPcm = table.concat(decodedPcmList)
    dll.llog("  Исходный размер декодированного PCM: " .. #decodedPcm .. " байт")

    -- Ресемплирование PCM обратно до исходной частоты sampleRate, если они различались
    if sampleRate ~= workingSampleRate then
        if hasResample then
            -- dll.llog("Ресемплирование декодированного PCM с " .. workingSampleRate .. " Гц обратно до " .. sampleRate .. " Гц...")
            decodedPcm = opus.resample(decodedPcm, workingSampleRate, sampleRate, channels)
            dll.llog("  Размер ресемплированного PCM: " .. #decodedPcm .. " байт")
        end
    end

    -- Мы ВСЕГДА реконструируем декодированный файл как WAVE (WAV),
    -- так как этот формат поддерживается нативно на всех платформах (iOS, Android, macOS, Windows).
    -- Данные decodedPcm от Opus декодера уже находятся в little-endian (для WAV), поэтому байты не переставляем.
    local wavHeader = makeWavHeader(sampleRate, channels, #decodedPcm)
    local updatedContent = wavHeader .. decodedPcm

    -- Запись реконструированного файла в outputFilePath
    local out, writeErr = io.open(outputFilePath, "wb")
    if not out then
        return nil, "Не удалось открыть выходной файл для записи: " .. tostring(writeErr)
    end
    out:write(updatedContent)
    out:close()

    dll.llog("Аудиофайл успешно реконструирован и записан в: " .. outputFilePath)
    dll.llog("==========================================\n")
    return true
end

return M
