// plugin_opus.cpp
// Реализация C++ обертки для плагина plugin.opus под Windows Simulator (Solar2D)

extern "C" {
#include "lua.h"
#include "lauxlib.h"
}

#include "opus.h"
#include <vector>
#include <cstring>
#include <cmath>

// Структуры для хранения состояния объектов в Lua
struct LuaOpusEncoder {
    OpusEncoder *enc;
    int channels;
};

struct LuaOpusDecoder {
    OpusDecoder *dec;
    int channels;
};

// ==============================================================================
// МЕТОДЫ ЭНКОДЕРА (OpusEncoder)
// ==============================================================================

// encoder:encode(pcmBytesString, frameSize)
// Сжимает фрейм 16-битных PCM сэмплов в пакет Opus
static int encoder_encode(lua_State *L) {
    LuaOpusEncoder *luaEnc = (LuaOpusEncoder *)luaL_checkudata(L, 1, "OpusEncoder");
    if (luaEnc->enc == nullptr) {
        return luaL_error(L, "Encoder already destroyed");
    }

    size_t pcmLen = 0;
    const char *pcm = luaL_checklstring(L, 2, &pcmLen);
    int frameSize = luaL_checkinteger(L, 3);

    // Проверяем корректность размера входного буфера PCM
    int expectedBytes = frameSize * luaEnc->channels * sizeof(opus_int16);
    if ((int)pcmLen < expectedBytes) {
        lua_pushnil(L);
        lua_pushstring(L, "Input PCM buffer is smaller than expected frame size");
        return 2;
    }

    int maxPacketSize = 4000;
    std::vector<unsigned char> outPacket(maxPacketSize);

    int bytesEncoded = opus_encode(luaEnc->enc, 
                                   reinterpret_cast<const opus_int16*>(pcm), 
                                   frameSize, 
                                   outPacket.data(), 
                                   maxPacketSize);

    if (bytesEncoded < 0) {
        lua_pushnil(L);
        lua_pushfstring(L, "Encoding error code: %d", bytesEncoded);
        return 2;
    }

    lua_pushlstring(L, reinterpret_cast<const char*>(outPacket.data()), bytesEncoded);
    return 1;
}

// encoder:set_dtx(useDtx)
// Включает или выключает режим DTX (Discontinuous Transmission)
static int encoder_set_dtx(lua_State *L) {
    LuaOpusEncoder *luaEnc = (LuaOpusEncoder *)luaL_checkudata(L, 1, "OpusEncoder");
    if (luaEnc->enc == nullptr) return luaL_error(L, "Encoder already destroyed");

    bool useDtx = lua_toboolean(L, 2);
    int res = opus_encoder_ctl(luaEnc->enc, OPUS_SET_DTX(useDtx ? 1 : 0));
    lua_pushinteger(L, res);
    return 1;
}

// encoder:set_bitrate(bitrate)
// Устанавливает целевой битрейт для кодирования
static int encoder_set_bitrate(lua_State *L) {
    LuaOpusEncoder *luaEnc = (LuaOpusEncoder *)luaL_checkudata(L, 1, "OpusEncoder");
    if (luaEnc->enc == nullptr) return luaL_error(L, "Encoder already destroyed");

    int bitrate = luaL_checkinteger(L, 2);
    int res = opus_encoder_ctl(luaEnc->enc, OPUS_SET_BITRATE(bitrate));
    lua_pushinteger(L, res);
    return 1;
}

// encoder:set_complexity(complexity)
// Устанавливает сложность алгоритма кодирования (0-10)
static int encoder_set_complexity(lua_State *L) {
    LuaOpusEncoder *luaEnc = (LuaOpusEncoder *)luaL_checkudata(L, 1, "OpusEncoder");
    if (luaEnc->enc == nullptr) return luaL_error(L, "Encoder already destroyed");

    int complexity = luaL_checkinteger(L, 2);
    int res = opus_encoder_ctl(luaEnc->enc, OPUS_SET_COMPLEXITY(complexity));
    lua_pushinteger(L, res);
    return 1;
}

// encoder:set_vbr(useVbr)
// Включает или выключает переменный битрейт (VBR)
static int encoder_set_vbr(lua_State *L) {
    LuaOpusEncoder *luaEnc = (LuaOpusEncoder *)luaL_checkudata(L, 1, "OpusEncoder");
    if (luaEnc->enc == nullptr) return luaL_error(L, "Encoder already destroyed");

    bool useVbr = lua_toboolean(L, 2);
    int res = opus_encoder_ctl(luaEnc->enc, OPUS_SET_VBR(useVbr ? 1 : 0));
    lua_pushinteger(L, res);
    return 1;
}

// encoder:destroy()
// Освобождает нативные ресурсы энкодера
static int encoder_destroy(lua_State *L) {
    LuaOpusEncoder *luaEnc = (LuaOpusEncoder *)luaL_checkudata(L, 1, "OpusEncoder");
    if (luaEnc->enc != nullptr) {
        opus_encoder_destroy(luaEnc->enc);
        luaEnc->enc = nullptr;
    }
    return 0;
}

// ==============================================================================
// МЕТОДЫ ДЕКОДЕРА (OpusDecoder)
// ==============================================================================

// decoder:decode(packetBytesString, frameSize)
// Декодирует Opus пакет обратно в 16-битный PCM
static int decoder_decode(lua_State *L) {
    LuaOpusDecoder *luaDec = (LuaOpusDecoder *)luaL_checkudata(L, 1, "OpusDecoder");
    if (luaDec->dec == nullptr) {
        return luaL_error(L, "Decoder already destroyed");
    }

    size_t packetLen = 0;
    const char *packet = nullptr;
    if (!lua_isnil(L, 2)) {
        packet = luaL_checklstring(L, 2, &packetLen);
    }
    int frameSize = luaL_checkinteger(L, 3);

    int outSamples = frameSize;
    std::vector<opus_int16> outPcm(outSamples * luaDec->channels);

    int decodedSamples = opus_decode(luaDec->dec, 
                                     reinterpret_cast<const unsigned char*>(packet), 
                                     packetLen, 
                                     outPcm.data(), 
                                     outSamples, 
                                     0);

    if (decodedSamples < 0) {
        lua_pushnil(L);
        lua_pushfstring(L, "Decoding error code: %d", decodedSamples);
        return 2;
    }

    int actualOutBytes = decodedSamples * luaDec->channels * sizeof(opus_int16);
    lua_pushlstring(L, reinterpret_cast<const char*>(outPcm.data()), actualOutBytes);
    return 1;
}

// decoder:destroy()
// Освобождает ресурсы декодера
static int decoder_destroy(lua_State *L) {
    LuaOpusDecoder *luaDec = (LuaOpusDecoder *)luaL_checkudata(L, 1, "OpusDecoder");
    if (luaDec->dec != nullptr) {
        opus_decoder_destroy(luaDec->dec);
        luaDec->dec = nullptr;
    }
    return 0;
}

// ==============================================================================
// СТАТИЧЕСКИЕ ФУНКЦИИ МОДУЛЯ (plugin.opus)
// ==============================================================================

// opus.encoder_create(sampleRate, channels, application)
// Создает нативный объект кодирования Opus
static int encoder_create(lua_State *L) {
    int sampleRate = luaL_checkinteger(L, 1);
    int channels = luaL_checkinteger(L, 2);
    int application = OPUS_APPLICATION_AUDIO; // По умолчанию
    if (lua_isnumber(L, 3)) {
        application = lua_tointeger(L, 3);
    }

    int error = OPUS_OK;
    OpusEncoder *enc = opus_encoder_create(sampleRate, channels, application, &error);
    if (error != OPUS_OK || enc == nullptr) {
        lua_pushnil(L);
        lua_pushfstring(L, "Failed to create encoder: %d", error);
        return 2;
    }

    LuaOpusEncoder *luaEnc = (LuaOpusEncoder *)lua_newuserdata(L, sizeof(LuaOpusEncoder));
    luaEnc->enc = enc;
    luaEnc->channels = channels;

    luaL_getmetatable(L, "OpusEncoder");
    lua_setmetatable(L, -2);
    return 1;
}

// opus.decoder_create(sampleRate, channels)
// Создает нативный объект декодирования Opus
static int decoder_create(lua_State *L) {
    int sampleRate = luaL_checkinteger(L, 1);
    int channels = luaL_checkinteger(L, 2);

    int error = OPUS_OK;
    OpusDecoder *dec = opus_decoder_create(sampleRate, channels, &error);
    if (error != OPUS_OK || dec == nullptr) {
        lua_pushnil(L);
        lua_pushfstring(L, "Failed to create decoder: %d", error);
        return 2;
    }

    LuaOpusDecoder *luaDec = (LuaOpusDecoder *)lua_newuserdata(L, sizeof(LuaOpusDecoder));
    luaDec->dec = dec;
    luaDec->channels = channels;

    luaL_getmetatable(L, "OpusDecoder");
    lua_setmetatable(L, -2);
    return 1;
}

// opus.resample(pcmBytesString, fromRate, toRate, channels)
// Ресемплирует PCM-аудиоданные до новой частоты
static int l_resample(lua_State *L) {
    size_t len = 0;
    const char *pcm = luaL_checklstring(L, 1, &len);
    int fromRate = luaL_checkinteger(L, 2);
    int toRate = luaL_checkinteger(L, 3);
    int channels = luaL_checkinteger(L, 4);

    int inputSamples = len / (channels * sizeof(opus_int16));
    const opus_int16* input = reinterpret_cast<const opus_int16*>(pcm);

    double ratio = static_cast<double>(toRate) / static_cast<double>(fromRate);
    int outputSamples = static_cast<int>(inputSamples * ratio);
    int outputLen = outputSamples * channels * sizeof(opus_int16);

    std::vector<opus_int16> output(outputSamples * channels);

    for (int i = 0; i < outputSamples; ++i) {
        double srcPos = i / ratio;
        int srcIdx = static_cast<int>(srcPos);
        double frac = srcPos - srcIdx;

        int nextIdx = srcIdx + 1;
        if (nextIdx >= inputSamples) {
            nextIdx = srcIdx;
        }

        for (int c = 0; c < channels; ++c) {
            opus_int16 s0 = input[srcIdx * channels + c];
            opus_int16 s1 = input[nextIdx * channels + c];
            double sample = s0 + frac * (s1 - s0);
            output[i * channels + c] = static_cast<opus_int16>(sample);
        }
    }

    lua_pushlstring(L, reinterpret_cast<const char*>(output.data()), outputLen);
    return 1;
}

// opus.normalize(pcmBytesString, targetRatio)
// Нормализует амплитуду звука до заданного уровня пика громкости
static int l_normalize(lua_State *L) {
    size_t len = 0;
    const char *pcm = luaL_checklstring(L, 1, &len);
    double targetRatio = luaL_checknumber(L, 2);

    int numSamples = len / sizeof(opus_int16);
    const opus_int16* pcmData = reinterpret_cast<const opus_int16*>(pcm);

    std::vector<opus_int16> output(numSamples);

    // 1. Поиск абсолютного пика амплитуды
    int16_t maxVal = 0;
    for (int i = 0; i < numSamples; ++i) {
        int16_t val = pcmData[i];
        if (val < 0) {
            if (val == -32768) val = 32767; // Предотвращаем переполнение
            else val = -val;
        }
        if (val > maxVal) {
            maxVal = val;
        }
    }

    // 2. Масштабирование PCM сэмплов под целевой пик
    if (maxVal > 0) {
        double targetVal = 32767.0 * targetRatio;
        double gain = targetVal / maxVal;

        for (int i = 0; i < numSamples; ++i) {
            double sample = pcmData[i] * gain;
            if (sample > 32767.0) sample = 32767.0;
            else if (sample < -32768.0) sample = -32768.0;
            output[i] = static_cast<opus_int16>(sample);
        }
    } else {
        // Запись тишины без изменений
        std::memcpy(output.data(), pcmData, len);
    }

    lua_pushlstring(L, reinterpret_cast<const char*>(output.data()), len);
    return 1;
}

// Вспомогательная функция для регистрации метатаблицы
static void create_metatable(lua_State *L, const char *name, const luaL_Reg *methods) {
    luaL_newmetatable(L, name);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    luaL_register(L, NULL, methods);
    lua_pop(L, 1);
}

// Инициализация библиотеки DLL (экспортируемая точка входа)
extern "C" __declspec(dllexport) int luaopen_plugin_opus(lua_State *L) {
    static const luaL_Reg module_methods[] = {
        {"encoder_create", encoder_create},
        {"decoder_create", decoder_create},
        {"resample", l_resample},
        {"normalize", l_normalize},
        {NULL, NULL}
    };

    static const luaL_Reg encoder_methods[] = {
        {"encode", encoder_encode},
        {"set_dtx", encoder_set_dtx},
        {"set_bitrate", encoder_set_bitrate},
        {"set_complexity", encoder_set_complexity},
        {"set_vbr", encoder_set_vbr},
        {"destroy", encoder_destroy},
        {"__gc", encoder_destroy},
        {NULL, NULL}
    };

    static const luaL_Reg decoder_methods[] = {
        {"decode", decoder_decode},
        {"destroy", decoder_destroy},
        {"__gc", decoder_destroy},
        {NULL, NULL}
    };

    // Создаем метатаблицы для объектов классов
    create_metatable(L, "OpusEncoder", encoder_methods);
    create_metatable(L, "OpusDecoder", decoder_methods);

    // Возвращаем библиотеку как таблицу
    lua_newtable(L);
    luaL_register(L, NULL, module_methods);

    return 1;
}
