#include <jni.h>
#include <string>
#include <vector>
#include "opus.h"

extern "C" {

JNIEXPORT jlong JNICALL
Java_plugin_opus_LuaLoader_encoderCreate(JNIEnv* env, jclass clazz, jint sampleRate, jint channels, jint application) {
    int error = OPUS_OK;
    OpusEncoder* enc = opus_encoder_create(sampleRate, channels, application, &error);
    if (error == OPUS_OK && enc != nullptr) {
        return reinterpret_cast<jlong>(enc);
    }
    return 0;
}

JNIEXPORT jbyteArray JNICALL
Java_plugin_opus_LuaLoader_encoderEncode(JNIEnv* env, jclass clazz, jlong encPtr, jbyteArray pcmBytes, jint frameSize) {
    OpusEncoder* enc = reinterpret_cast<OpusEncoder*>(encPtr);
    if (enc == nullptr || pcmBytes == nullptr) return nullptr;

    jbyte* pcm = env->GetByteArrayElements(pcmBytes, nullptr);
    jsize pcmLen = env->GetArrayLength(pcmBytes);

    int maxPacketSize = 4000;
    std::vector<unsigned char> outPacket(maxPacketSize);

    int bytesEncoded = opus_encode(enc, reinterpret_cast<const opus_int16*>(pcm), frameSize, outPacket.data(), maxPacketSize);

    env->ReleaseByteArrayElements(pcmBytes, pcm, JNI_ABORT);

    if (bytesEncoded < 0) {
        return nullptr;
    }

    jbyteArray result = env->NewByteArray(bytesEncoded);
    env->SetByteArrayRegion(result, 0, bytesEncoded, reinterpret_cast<const jbyte*>(outPacket.data()));
    return result;
}

JNIEXPORT jint JNICALL
Java_plugin_opus_LuaLoader_encoderSetDtx(JNIEnv* env, jclass clazz, jlong encPtr, jboolean useDtx) {
    OpusEncoder* enc = reinterpret_cast<OpusEncoder*>(encPtr);
    if (enc == nullptr) return OPUS_BAD_ARG;

    int result = opus_encoder_ctl(enc, OPUS_SET_DTX(useDtx ? 1 : 0));
    return result;
}

JNIEXPORT void JNICALL
Java_plugin_opus_LuaLoader_encoderDestroy(JNIEnv* env, jclass clazz, jlong encPtr) {
    OpusEncoder* enc = reinterpret_cast<OpusEncoder*>(encPtr);
    if (enc != nullptr) {
        opus_encoder_destroy(enc);
    }
}

JNIEXPORT jlong JNICALL
Java_plugin_opus_LuaLoader_decoderCreate(JNIEnv* env, jclass clazz, jint sampleRate, jint channels) {
    int error = OPUS_OK;
    OpusDecoder* dec = opus_decoder_create(sampleRate, channels, &error);
    if (error == OPUS_OK && dec != nullptr) {
        return reinterpret_cast<jlong>(dec);
    }
    return 0;
}

JNIEXPORT jbyteArray JNICALL
Java_plugin_opus_LuaLoader_decoderDecode(JNIEnv* env, jclass clazz, jlong decPtr, jbyteArray packetBytes, jint frameSize, jint channels) {
    OpusDecoder* dec = reinterpret_cast<OpusDecoder*>(decPtr);
    if (dec == nullptr) return nullptr;

    jsize packetLen = 0;
    jbyte* packet = nullptr;
    if (packetBytes != nullptr) {
        packet = env->GetByteArrayElements(packetBytes, nullptr);
        packetLen = env->GetArrayLength(packetBytes);
    }

    int outSamples = frameSize;
    int outBytes = outSamples * channels * sizeof(opus_int16);
    std::vector<opus_int16> outPcm(outSamples * channels);

    int decodedSamples = opus_decode(dec, 
                                     reinterpret_cast<const unsigned char*>(packet), 
                                     packetLen, 
                                     outPcm.data(), 
                                     outSamples, 
                                     0);

    if (packetBytes != nullptr) {
        env->ReleaseByteArrayElements(packetBytes, packet, JNI_ABORT);
    }

    if (decodedSamples < 0) {
        return nullptr;
    }

    int actualOutBytes = decodedSamples * channels * sizeof(opus_int16);
    jbyteArray result = env->NewByteArray(actualOutBytes);
    env->SetByteArrayRegion(result, 0, actualOutBytes, reinterpret_cast<const jbyte*>(outPcm.data()));
    return result;
}

JNIEXPORT void JNICALL
Java_plugin_opus_LuaLoader_decoderDestroy(JNIEnv* env, jclass clazz, jlong decPtr) {
    OpusDecoder* dec = reinterpret_cast<OpusDecoder*>(decPtr);
    if (dec != nullptr) {
        opus_decoder_destroy(dec);
    }
}

JNIEXPORT jbyteArray JNICALL
Java_plugin_opus_LuaLoader_resample(JNIEnv* env, jclass clazz, jbyteArray pcmBytes, jint fromRate, jint toRate, jint channels) {
    if (pcmBytes == nullptr) return nullptr;

    jsize len = env->GetArrayLength(pcmBytes);
    jbyte* data = env->GetByteArrayElements(pcmBytes, nullptr);

    int inputSamples = len / (channels * sizeof(opus_int16));
    const opus_int16* input = reinterpret_cast<const opus_int16*>(data);

    double ratio = static_cast<double>(toRate) / static_cast<double>(fromRate);
    int outputSamples = static_cast<int>(inputSamples * ratio);
    int outputLen = outputSamples * channels * sizeof(opus_int16);

    jbyteArray outArray = env->NewByteArray(outputLen);
    jbyte* outData = env->GetByteArrayElements(outArray, nullptr);
    opus_int16* output = reinterpret_cast<opus_int16*>(outData);

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

    env->ReleaseByteArrayElements(pcmBytes, data, JNI_ABORT);
    env->ReleaseByteArrayElements(outArray, outData, 0);

    return outArray;
}

JNIEXPORT jbyteArray JNICALL
Java_plugin_opus_LuaLoader_normalize(JNIEnv* env, jclass clazz, jbyteArray pcmBytes, jdouble targetRatio) {
    if (pcmBytes == nullptr) return nullptr;

    jsize len = env->GetArrayLength(pcmBytes);
    jbyte* data = env->GetByteArrayElements(pcmBytes, nullptr);

    int numSamples = len / sizeof(opus_int16);
    const opus_int16* pcm = reinterpret_cast<const opus_int16*>(data);

    jbyteArray outArray = env->NewByteArray(len);
    jbyte* outData = env->GetByteArrayElements(outArray, nullptr);
    opus_int16* output = reinterpret_cast<opus_int16*>(outData);

    // 1. Find absolute peak
    int16_t maxVal = 0;
    for (int i = 0; i < numSamples; ++i) {
        int16_t val = pcm[i];
        if (val < 0) {
            if (val == -32768) val = 32767; // Avoid overflow for -32768
            else val = -val;
        }
        if (val > maxVal) {
            maxVal = val;
        }
    }

    // 2. Normalize PCM samples
    if (maxVal > 0) {
        double targetVal = 32767.0 * targetRatio;
        double gain = targetVal / maxVal;

        for (int i = 0; i < numSamples; ++i) {
            double sample = pcm[i] * gain;
            if (sample > 32767.0) sample = 32767.0;
            else if (sample < -32768.0) sample = -32768.0;
            output[i] = static_cast<opus_int16>(sample);
        }
    } else {
        // Silent file, just copy
        std::memcpy(output, pcm, len);
    }

    env->ReleaseByteArrayElements(pcmBytes, data, JNI_ABORT);
    env->ReleaseByteArrayElements(outArray, outData, 0);

    return outArray;
}

}


