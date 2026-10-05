//
//  PluginLibrary.mm
//  TemplateApp
//

#import "PluginLibrary.h"

// На macOS не требуется заголовок CoronaRuntime.h для iOS
#if TARGET_OS_IPHONE
#include <CoronaRuntime.h>
#endif

#include <vector>
#include <cstring>
#include <cmath>
#include "../../opus-1.6.1/include/opus.h"

// Определение структур для хранения объектов в Lua userdata
typedef struct {
    OpusEncoder *encoder;
    int channels;
    int sample_rate;
} LuaOpusEncoder;

typedef struct {
    OpusDecoder *decoder;
    int channels;
    int sample_rate;
} LuaOpusDecoder;

// Предварительные объявления функций биндингов
static int encoder_create( lua_State *L );
static int encoder_encode( lua_State *L );
static int encoder_set_bitrate( lua_State *L );
static int encoder_set_complexity( lua_State *L );
static int encoder_set_vbr( lua_State *L );
static int encoder_set_dtx( lua_State *L );
static int encoder_gc( lua_State *L );

static int decoder_create( lua_State *L );
static int decoder_decode( lua_State *L );
static int decoder_gc( lua_State *L );

static int plugin_resample( lua_State *L );
static int plugin_normalize( lua_State *L );

// Список методов для работы с кодировщиком
static const luaL_Reg kEncoderMethods[] = {
    { "encode", encoder_encode },
    { "set_bitrate", encoder_set_bitrate },
    { "set_complexity", encoder_set_complexity },
    { "set_vbr", encoder_set_vbr },
    { "set_dtx", encoder_set_dtx },
    { NULL, NULL }
};

// Список методов для работы с декодировщиком
static const luaL_Reg kDecoderMethods[] = {
    { "decode", decoder_decode },
    { NULL, NULL }
};

// ----------------------------------------------------------------------------
// Открытие библиотеки и инициализация модулей
// ----------------------------------------------------------------------------

int luaopen_plugin_opus( lua_State *L )
{
    // Инициализация метатаблиц для пользовательских userdata типов
    
    // Создание метатаблицы для кодировщика (Encoder Metatable)
    luaL_newmetatable( L, "OpusEncoderMetatable" );
    
    lua_pushcfunction( L, encoder_gc );
    lua_setfield( L, -2, "__gc" );
    
    lua_pushvalue( L, -1 );
    lua_setfield( L, -2, "__index" );
    
    luaL_register( L, NULL, kEncoderMethods );
    lua_pop( L, 1 );
    
    // Создание метатаблицы для декодировщика (Decoder Metatable)
    luaL_newmetatable( L, "OpusDecoderMetatable" );
    
    lua_pushcfunction( L, decoder_gc );
    lua_setfield( L, -2, "__gc" );
    
    lua_pushvalue( L, -1 );
    lua_setfield( L, -2, "__index" );
    
    luaL_register( L, NULL, kDecoderMethods );
    lua_pop( L, 1 );
    
    // Глобальные методы плагина
    const luaL_Reg kPluginFunctions[] = {
        { "encoder_create", encoder_create },
        { "decoder_create", decoder_create },
        { "resample", plugin_resample },
        { "normalize", plugin_normalize },
        { NULL, NULL }
    };
    
    // Глобальная регистрация библиотеки "plugin.opus"
    luaL_register( L, "plugin.opus", kPluginFunctions );
    
    return 1;
}

// ----------------------------------------------------------------------------
// Реализация методов кодировщика (Encoder)
// ----------------------------------------------------------------------------

static int encoder_create( lua_State *L )
{
    int sample_rate = luaL_checkinteger( L, 1 );
    int channels = luaL_checkinteger( L, 2 );
    
    // Режим по умолчанию: OPUS_APPLICATION_AUDIO
    int application = OPUS_APPLICATION_AUDIO;
    if ( lua_isnumber( L, 3 ) ) {
        application = lua_tointeger( L, 3 );
    }
    
    // Проверка допустимой частоты дискретизации для кодека Opus
    if ( sample_rate != 8000 && sample_rate != 12000 && sample_rate != 16000 &&
         sample_rate != 24000 && sample_rate != 48000 )
    {
        return luaL_error( L, "Invalid sample rate. Opus only supports 8000, 12000, 16000, 24000, or 48000 Hz." );
    }
    
    // Проверка допустимого количества каналов (1 - моно, 2 - стерео)
    if ( channels != 1 && channels != 2 ) {
        return luaL_error( L, "Invalid channel count. Opus only supports 1 (mono) or 2 (stereo)." );
    }
    
    int err = 0;
    OpusEncoder *enc = opus_encoder_create( sample_rate, channels, application, &err );
    if ( err != OPUS_OK || !enc ) {
        lua_pushnil( L );
        lua_pushfstring( L, "Failed to create encoder: error code %d", err );
        return 2;
    }
    
    LuaOpusEncoder *lua_enc = (LuaOpusEncoder *)lua_newuserdata( L, sizeof( LuaOpusEncoder ) );
    lua_enc->encoder = enc;
    lua_enc->channels = channels;
    lua_enc->sample_rate = sample_rate;
    
    luaL_getmetatable( L, "OpusEncoderMetatable" );
    lua_setmetatable( L, -2 );
    
    return 1;
}

static int encoder_encode( lua_State *L )
{
    LuaOpusEncoder *lua_enc = (LuaOpusEncoder *)luaL_checkudata( L, 1, "OpusEncoderMetatable" );
    if ( !lua_enc || !lua_enc->encoder ) {
        return luaL_error( L, "Invalid OpusEncoder object." );
    }
    
    size_t pcm_bytes = 0;
    const char *pcm_data = luaL_checklstring( L, 2, &pcm_bytes );
    int frame_size = luaL_checkinteger( L, 3 );
    
    // Проверка соответствия размера кадра допустимым интервалам Opus
    int sr = lua_enc->sample_rate;
    if ( frame_size != sr / 400 && frame_size != sr / 200 && frame_size != sr / 100 &&
         frame_size != sr / 50 && frame_size != sr / 25 && frame_size != 3 * sr / 50 )
    {
        return luaL_error( L, "Invalid frame size for sample rate %d.", sr );
    }
    
    // Ожидаемый размер PCM буфера в байтах
    size_t expected_bytes = frame_size * lua_enc->channels * sizeof( int16_t );
    if ( pcm_bytes < expected_bytes ) {
        return luaL_error( L, "PCM buffer too small. Expected at least %d bytes, got %d.", (int)expected_bytes, (int)pcm_bytes );
    }
    
    unsigned char out_buf[4000];
    opus_int32 bytes_encoded = opus_encode( lua_enc->encoder,
                                            (const opus_int16 *)pcm_data,
                                            frame_size,
                                            out_buf,
                                            sizeof( out_buf ) );
    
    if ( bytes_encoded < 0 ) {
        lua_pushnil( L );
        lua_pushfstring( L, "Opus encoding failed: error code %d", bytes_encoded );
        return 2;
    }
    
    lua_pushlstring( L, (const char *)out_buf, bytes_encoded );
    return 1;
}

static int encoder_set_bitrate( lua_State *L )
{
    LuaOpusEncoder *lua_enc = (LuaOpusEncoder *)luaL_checkudata( L, 1, "OpusEncoderMetatable" );
    int bitrate = luaL_checkinteger( L, 2 );
    if ( lua_enc && lua_enc->encoder ) {
        opus_encoder_ctl( lua_enc->encoder, OPUS_SET_BITRATE( bitrate ) );
    }
    return 0;
}

static int encoder_set_complexity( lua_State *L )
{
    LuaOpusEncoder *lua_enc = (LuaOpusEncoder *)luaL_checkudata( L, 1, "OpusEncoderMetatable" );
    int complexity = luaL_checkinteger( L, 2 );
    if ( complexity < 0 || complexity > 10 ) {
        return luaL_error( L, "Complexity must be between 0 and 10." );
    }
    if ( lua_enc && lua_enc->encoder ) {
        opus_encoder_ctl( lua_enc->encoder, OPUS_SET_COMPLEXITY( complexity ) );
    }
    return 0;
}

static int encoder_set_vbr( lua_State *L )
{
    LuaOpusEncoder *lua_enc = (LuaOpusEncoder *)luaL_checkudata( L, 1, "OpusEncoderMetatable" );
    int vbr = lua_toboolean( L, 2 );
    if ( lua_enc && lua_enc->encoder ) {
        opus_encoder_ctl( lua_enc->encoder, OPUS_SET_VBR( vbr ) );
    }
    return 0;
}

static int encoder_set_dtx( lua_State *L )
{
    LuaOpusEncoder *lua_enc = (LuaOpusEncoder *)luaL_checkudata( L, 1, "OpusEncoderMetatable" );
    int dtx = lua_toboolean( L, 2 );
    if ( lua_enc && lua_enc->encoder ) {
        opus_encoder_ctl( lua_enc->encoder, OPUS_SET_DTX( dtx ) );
    }
    return 0;
}

static int encoder_gc( lua_State *L )
{
    LuaOpusEncoder *lua_enc = (LuaOpusEncoder *)luaL_checkudata( L, 1, "OpusEncoderMetatable" );
    if ( lua_enc && lua_enc->encoder ) {
        opus_encoder_destroy( lua_enc->encoder );
        lua_enc->encoder = NULL;
    }
    return 0;
}

// ----------------------------------------------------------------------------
// Реализация методов декодировщика (Decoder)
// ----------------------------------------------------------------------------

static int decoder_create( lua_State *L )
{
    int sample_rate = luaL_checkinteger( L, 1 );
    int channels = luaL_checkinteger( L, 2 );
    
    // Проверка допустимой частоты дискретизации
    if ( sample_rate != 8000 && sample_rate != 12000 && sample_rate != 16000 &&
         sample_rate != 24000 && sample_rate != 48000 )
    {
        return luaL_error( L, "Invalid sample rate. Opus only supports 8000, 12000, 16000, 24000, or 48000 Hz." );
    }
    
    // Проверка допустимого количества каналов
    if ( channels != 1 && channels != 2 ) {
        return luaL_error( L, "Invalid channel count. Opus only supports 1 (mono) or 2 (stereo)." );
    }
    
    int err = 0;
    OpusDecoder *dec = opus_decoder_create( sample_rate, channels, &err );
    if ( err != OPUS_OK || !dec ) {
        lua_pushnil( L );
        lua_pushfstring( L, "Failed to create decoder: error code %d", err );
        return 2;
    }
    
    LuaOpusDecoder *lua_dec = (LuaOpusDecoder *)lua_newuserdata( L, sizeof( LuaOpusDecoder ) );
    lua_dec->decoder = dec;
    lua_dec->channels = channels;
    lua_dec->sample_rate = sample_rate;
    
    luaL_getmetatable( L, "OpusDecoderMetatable" );
    lua_setmetatable( L, -2 );
    
    return 1;
}

static int decoder_decode( lua_State *L )
{
    LuaOpusDecoder *lua_dec = (LuaOpusDecoder *)luaL_checkudata( L, 1, "OpusDecoderMetatable" );
    if ( !lua_dec || !lua_dec->decoder ) {
        return luaL_error( L, "Invalid OpusDecoder object." );
    }
    
    size_t packet_bytes = 0;
    const char *packet_data = NULL;
    
    if ( !lua_isnil( L, 2 ) ) {
        packet_data = luaL_checklstring( L, 2, &packet_bytes );
    }
    
    int frame_size = luaL_checkinteger( L, 3 );
    
    // Проверка размера кадра
    int sr = lua_dec->sample_rate;
    if ( frame_size != sr / 400 && frame_size != sr / 200 && frame_size != sr / 100 &&
         frame_size != sr / 50 && frame_size != sr / 25 && frame_size != 3 * sr / 50 )
    {
        return luaL_error( L, "Invalid frame size for sample rate %d.", sr );
    }
    
    std::vector<opus_int16> pcm_buf( frame_size * lua_dec->channels );
    
    int decoded_samples = opus_decode( lua_dec->decoder,
                                       (const unsigned char *)packet_data,
                                       (opus_int32)packet_bytes,
                                       pcm_buf.data(),
                                       frame_size,
                                       0 ); // decode_fec = 0
    
    if ( decoded_samples < 0 ) {
        lua_pushnil( L );
        lua_pushfstring( L, "Opus decoding failed: error code %d", decoded_samples );
        return 2;
    }
    
    lua_pushlstring( L, (const char *)pcm_buf.data(), decoded_samples * lua_dec->channels * sizeof( int16_t ) );
    return 1;
}

static int decoder_gc( lua_State *L )
{
    LuaOpusDecoder *lua_dec = (LuaOpusDecoder *)luaL_checkudata( L, 1, "OpusDecoderMetatable" );
    if ( lua_dec && lua_dec->decoder ) {
        opus_decoder_destroy( lua_dec->decoder );
        lua_dec->decoder = NULL;
    }
    return 0;
}

// ----------------------------------------------------------------------------
// Дополнительные методы: Ресемплирование и Нормализация звука (C++)
// ----------------------------------------------------------------------------

static int plugin_resample( lua_State *L )
{
    size_t pcm_len = 0;
    const char *pcm_data = luaL_checklstring( L, 1, &pcm_len );
    int from_rate = luaL_checkinteger( L, 2 );
    int to_rate = luaL_checkinteger( L, 3 );
    int channels = luaL_checkinteger( L, 4 );
    
    if ( from_rate <= 0 || to_rate <= 0 || channels <= 0 ) {
        return luaL_error( L, "Invalid arguments for resample (sample rates and channels must be positive)." );
    }
    
    int input_samples = (int)(pcm_len / (channels * sizeof(int16_t)));
    if ( input_samples <= 0 ) {
        lua_pushlstring( L, "", 0 );
        return 1;
    }
    
    const int16_t *input = reinterpret_cast<const int16_t *>(pcm_data);
    double ratio = static_cast<double>(to_rate) / static_cast<double>(from_rate);
    int output_samples = static_cast<int>(input_samples * ratio);
    
    if ( output_samples <= 0 ) {
        lua_pushlstring( L, "", 0 );
        return 1;
    }
    
    std::vector<int16_t> output( output_samples * channels );
    
    for (int i = 0; i < output_samples; ++i) {
        double src_pos = i / ratio;
        int src_idx = static_cast<int>(src_pos);
        double frac = src_pos - src_idx;
        
        int next_idx = src_idx + 1;
        if ( next_idx >= input_samples ) {
            next_idx = src_idx;
        }
        
        for (int c = 0; c < channels; ++c) {
            int16_t s0 = input[src_idx * channels + c];
            int16_t s1 = input[next_idx * channels + c];
            double sample = s0 + frac * (s1 - s0);
            
            // Ограничение диапазона значений (clipping)
            if ( sample > 32767.0 ) sample = 32767.0;
            else if ( sample < -32768.0 ) sample = -32768.0;
            
            output[i * channels + c] = static_cast<int16_t>(sample);
        }
    }
    
    lua_pushlstring( L, reinterpret_cast<const char *>(output.data()), output.size() * sizeof(int16_t) );
    return 1;
}

static int plugin_normalize( lua_State *L )
{
    size_t pcm_len = 0;
    const char *pcm_data = luaL_checklstring( L, 1, &pcm_len );
    double target_ratio = luaL_checknumber( L, 2 );
    
    int num_samples = (int)(pcm_len / sizeof(int16_t));
    if ( num_samples <= 0 ) {
        lua_pushlstring( L, "", 0 );
        return 1;
    }
    
    const int16_t *pcm = reinterpret_cast<const int16_t *>(pcm_data);
    std::vector<int16_t> output( num_samples );
    
    // 1. Поиск абсолютного пика амплитуды
    int16_t max_val = 0;
    for (int i = 0; i < num_samples; ++i) {
        int16_t val = pcm[i];
        if ( val < 0 ) {
            if ( val == -32768 ) val = 32767;
            else val = -val;
        }
        if ( val > max_val ) {
            max_val = val;
        }
    }
    
    // 2. Нормализация сэмплов PCM
    if ( max_val > 0 ) {
        double target_val = 32767.0 * target_ratio;
        double gain = target_val / max_val;
        
        for (int i = 0; i < num_samples; ++i) {
            double sample = pcm[i] * gain;
            if ( sample > 32767.0 ) sample = 32767.0;
            else if ( sample < -32768.0 ) sample = -32768.0;
            output[i] = static_cast<int16_t>(sample);
        }
    } else {
        // Если тишина, просто копируем исходные данные
        std::memcpy( output.data(), pcm, pcm_len );
    }
    
    lua_pushlstring( L, reinterpret_cast<const char *>(output.data()), pcm_len );
    return 1;
}
