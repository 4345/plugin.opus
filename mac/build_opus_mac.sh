#!/bin/bash -e

# build_opus_mac.sh
# Компилирует библиотеку Opus 1.6.1 для macOS (arm64 и x86_64) в универсальную статическую библиотеку

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
OPUS_DIR="$SCRIPT_DIR/../opus-1.6.1"

# Opus в репозитории не хранится: его скачивает tools/poluchit_opus.py
if [ ! -f "$OPUS_DIR/COPYING" ]; then
    echo "Нет исходников Opus в $OPUS_DIR — выполните из корня репозитория: python3 tools/poluchit_opus.py" >&2
    exit 1
fi
# config.h для сборки Opus (-DHAVE_CONFIG_H) — свой, из opus_config/
OPUS_CONFIG_DIR="$SCRIPT_DIR/../opus_config"
BUILD_DIR="$SCRIPT_DIR/build/opus_build"

# Очистка предыдущих сборок
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Основные исходные файлы Opus
OPUS_SOURCES=(
    "$OPUS_DIR/src/opus.c"
    "$OPUS_DIR/src/opus_decoder.c"
    "$OPUS_DIR/src/opus_encoder.c"
    "$OPUS_DIR/src/extensions.c"
    "$OPUS_DIR/src/repacketizer.c"
    "$OPUS_DIR/src/analysis.c"
    "$OPUS_DIR/src/mlp.c"
    "$OPUS_DIR/src/mlp_data.c"

    "$OPUS_DIR/celt/bands.c"
    "$OPUS_DIR/celt/celt.c"
    "$OPUS_DIR/celt/celt_encoder.c"
    "$OPUS_DIR/celt/celt_decoder.c"
    "$OPUS_DIR/celt/cwrs.c"
    "$OPUS_DIR/celt/entcode.c"
    "$OPUS_DIR/celt/entdec.c"
    "$OPUS_DIR/celt/entenc.c"
    "$OPUS_DIR/celt/kiss_fft.c"
    "$OPUS_DIR/celt/laplace.c"
    "$OPUS_DIR/celt/mathops.c"
    "$OPUS_DIR/celt/mdct.c"
    "$OPUS_DIR/celt/modes.c"
    "$OPUS_DIR/celt/pitch.c"
    "$OPUS_DIR/celt/celt_lpc.c"
    "$OPUS_DIR/celt/quant_bands.c"
    "$OPUS_DIR/celt/rate.c"
    "$OPUS_DIR/celt/vq.c"

    "$OPUS_DIR/silk/CNG.c"
    "$OPUS_DIR/silk/code_signs.c"
    "$OPUS_DIR/silk/init_decoder.c"
    "$OPUS_DIR/silk/decode_core.c"
    "$OPUS_DIR/silk/decode_frame.c"
    "$OPUS_DIR/silk/decode_parameters.c"
    "$OPUS_DIR/silk/decode_indices.c"
    "$OPUS_DIR/silk/decode_pulses.c"
    "$OPUS_DIR/silk/decoder_set_fs.c"
    "$OPUS_DIR/silk/dec_API.c"
    "$OPUS_DIR/silk/enc_API.c"
    "$OPUS_DIR/silk/encode_indices.c"
    "$OPUS_DIR/silk/encode_pulses.c"
    "$OPUS_DIR/silk/gain_quant.c"
    "$OPUS_DIR/silk/interpolate.c"
    "$OPUS_DIR/silk/LP_variable_cutoff.c"
    "$OPUS_DIR/silk/NLSF_decode.c"
    "$OPUS_DIR/silk/NSQ.c"
    "$OPUS_DIR/silk/NSQ_del_dec.c"
    "$OPUS_DIR/silk/PLC.c"
    "$OPUS_DIR/silk/shell_coder.c"
    "$OPUS_DIR/silk/tables_gain.c"
    "$OPUS_DIR/silk/tables_LTP.c"
    "$OPUS_DIR/silk/tables_NLSF_CB_NB_MB.c"
    "$OPUS_DIR/silk/tables_NLSF_CB_WB.c"
    "$OPUS_DIR/silk/tables_other.c"
    "$OPUS_DIR/silk/tables_pitch_lag.c"
    "$OPUS_DIR/silk/tables_pulses_per_block.c"
    "$OPUS_DIR/silk/VAD.c"
    "$OPUS_DIR/silk/control_audio_bandwidth.c"
    "$OPUS_DIR/silk/quant_LTP_gains.c"
    "$OPUS_DIR/silk/VQ_WMat_EC.c"
    "$OPUS_DIR/silk/HP_variable_cutoff.c"
    "$OPUS_DIR/silk/NLSF_encode.c"
    "$OPUS_DIR/silk/NLSF_VQ.c"
    "$OPUS_DIR/silk/NLSF_unpack.c"
    "$OPUS_DIR/silk/NLSF_del_dec_quant.c"
    "$OPUS_DIR/silk/process_NLSFs.c"
    "$OPUS_DIR/silk/stereo_LR_to_MS.c"
    "$OPUS_DIR/silk/stereo_MS_to_LR.c"
    "$OPUS_DIR/silk/check_control_input.c"
    "$OPUS_DIR/silk/control_SNR.c"
    "$OPUS_DIR/silk/init_encoder.c"
    "$OPUS_DIR/silk/control_codec.c"
    "$OPUS_DIR/silk/A2NLSF.c"
    "$OPUS_DIR/silk/ana_filt_bank_1.c"
    "$OPUS_DIR/silk/biquad_alt.c"
    "$OPUS_DIR/silk/bwexpander_32.c"
    "$OPUS_DIR/silk/bwexpander.c"
    "$OPUS_DIR/silk/debug.c"
    "$OPUS_DIR/silk/decode_pitch.c"
    "$OPUS_DIR/silk/inner_prod_aligned.c"
    "$OPUS_DIR/silk/lin2log.c"
    "$OPUS_DIR/silk/log2lin.c"
    "$OPUS_DIR/silk/LPC_analysis_filter.c"
    "$OPUS_DIR/silk/LPC_inv_pred_gain.c"
    "$OPUS_DIR/silk/table_LSF_cos.c"
    "$OPUS_DIR/silk/NLSF2A.c"
    "$OPUS_DIR/silk/NLSF_stabilize.c"
    "$OPUS_DIR/silk/NLSF_VQ_weights_laroia.c"
    "$OPUS_DIR/silk/pitch_est_tables.c"
    "$OPUS_DIR/silk/resampler.c"
    "$OPUS_DIR/silk/resampler_down2_3.c"
    "$OPUS_DIR/silk/resampler_down2.c"
    "$OPUS_DIR/silk/resampler_private_AR2.c"
    "$OPUS_DIR/silk/resampler_private_down_FIR.c"
    "$OPUS_DIR/silk/resampler_private_IIR_FIR.c"
    "$OPUS_DIR/silk/resampler_private_up2_HQ.c"
    "$OPUS_DIR/silk/resampler_rom.c"
    "$OPUS_DIR/silk/sigm_Q15.c"
    "$OPUS_DIR/silk/sort.c"
    "$OPUS_DIR/silk/sum_sqr_shift.c"
    "$OPUS_DIR/silk/stereo_decode_pred.c"
    "$OPUS_DIR/silk/stereo_encode_pred.c"
    "$OPUS_DIR/silk/stereo_find_predictor.c"
    "$OPUS_DIR/silk/stereo_quant_pred.c"
    "$OPUS_DIR/silk/LPC_fit.c"

    "$OPUS_DIR/silk/float/apply_sine_window_FLP.c"
    "$OPUS_DIR/silk/float/corrMatrix_FLP.c"
    "$OPUS_DIR/silk/float/encode_frame_FLP.c"
    "$OPUS_DIR/silk/float/find_LPC_FLP.c"
    "$OPUS_DIR/silk/float/find_LTP_FLP.c"
    "$OPUS_DIR/silk/float/find_pitch_lags_FLP.c"
    "$OPUS_DIR/silk/float/find_pred_coefs_FLP.c"
    "$OPUS_DIR/silk/float/LPC_analysis_filter_FLP.c"
    "$OPUS_DIR/silk/float/LTP_analysis_filter_FLP.c"
    "$OPUS_DIR/silk/float/LTP_scale_ctrl_FLP.c"
    "$OPUS_DIR/silk/float/noise_shape_analysis_FLP.c"
    "$OPUS_DIR/silk/float/process_gains_FLP.c"
    "$OPUS_DIR/silk/float/regularize_correlations_FLP.c"
    "$OPUS_DIR/silk/float/residual_energy_FLP.c"
    "$OPUS_DIR/silk/float/warped_autocorrelation_FLP.c"
    "$OPUS_DIR/silk/float/wrappers_FLP.c"
    "$OPUS_DIR/silk/float/autocorrelation_FLP.c"
    "$OPUS_DIR/silk/float/burg_modified_FLP.c"
    "$OPUS_DIR/silk/float/bwexpander_FLP.c"
    "$OPUS_DIR/silk/float/energy_FLP.c"
    "$OPUS_DIR/silk/float/inner_product_FLP.c"
    "$OPUS_DIR/silk/float/k2a_FLP.c"
    "$OPUS_DIR/silk/float/LPC_inv_pred_gain_FLP.c"
    "$OPUS_DIR/silk/float/pitch_analysis_core_FLP.c"
    "$OPUS_DIR/silk/float/scale_copy_vector_FLP.c"
    "$OPUS_DIR/silk/float/scale_vector_FLP.c"
    "$OPUS_DIR/silk/float/schur_FLP.c"
    "$OPUS_DIR/silk/float/sort_FLP.c"
)

# Оптимизированные ARM Neon исходные файлы для arm64
OPUS_ARM_SOURCES=(
    "$OPUS_DIR/celt/arm/celt_neon_intr.c"
    "$OPUS_DIR/celt/arm/pitch_neon_intr.c"
    "$OPUS_DIR/silk/arm/biquad_alt_neon_intr.c"
    "$OPUS_DIR/silk/arm/LPC_inv_pred_gain_neon_intr.c"
    "$OPUS_DIR/silk/arm/NSQ_del_dec_neon_intr.c"
    "$OPUS_DIR/silk/arm/NSQ_neon.c"
)

# Функция для компиляции статической библиотеки под конкретную архитектуру
compile_target() {
    ARCH=$1
    TARGET_OUT_DIR="$BUILD_DIR/mac-$ARCH"
    mkdir -p "$TARGET_OUT_DIR"

    echo "=== Компиляция Opus для macOS ($ARCH) ==="

    CC=$(xcrun -sdk macosx -f clang)
    SDK_PATH=$(xcrun -sdk macosx --show-sdk-path)

    CFLAGS=(
        "-Os"
        "-arch" "$ARCH"
        "-isysroot" "$SDK_PATH"
        "-mmacosx-version-min=10.13"
        "-DHAVE_CONFIG_H"
        "-fvisibility=hidden"
        "-ffunction-sections"
        "-fdata-sections"
        "-I$OPUS_DIR/include"
        "-I$OPUS_DIR/celt"
        "-I$OPUS_DIR/silk"
        "-I$OPUS_DIR/silk/float"
        "-I$OPUS_CONFIG_DIR"
        "-I$OPUS_DIR"
    )

    # Выбор исходников: добавляем оптимизации для arm64
    FILES=("${OPUS_SOURCES[@]}")
    if [ "$ARCH" == "arm64" ]; then
        FILES+=("${OPUS_ARM_SOURCES[@]}")
    fi

    OBJECTS=()
    for file in "${FILES[@]}"; do
        base=$(basename "$file" .c)
        # Получаем уникальный путь для объектного файла, избегая коллизий имен
        rel_path=$(echo "$file" | sed 's|.*/opus-1.6.1/||' | tr '/' '_')
        obj="$TARGET_OUT_DIR/${rel_path%.c}.o"
        OBJECTS+=("$obj")

        # Компилируем, если объектный файл устарел или отсутствует
        if [ ! -f "$obj" ] || [ "$file" -nt "$obj" ]; then
            $CC "${CFLAGS[@]}" -c "$file" -o "$obj"
        fi
    done

    # Создание статической библиотеки
    echo "Создание статической библиотеки для macOS ($ARCH)..."
    xcrun -sdk macosx libtool -static -o "$TARGET_OUT_DIR/libopus.a" "${OBJECTS[@]}"
}

# Компиляция под обе целевые архитектуры macOS
compile_target arm64
compile_target x86_64

# Создание универсальной статической библиотеки через lipo
echo "=== Создание универсальной библиотеки libopus.a ==="
lipo -create \
    "$BUILD_DIR/mac-arm64/libopus.a" \
    "$BUILD_DIR/mac-x86_64/libopus.a" \
    -output "$SCRIPT_DIR/libopus.a"

echo "=== Сборка Opus для macOS успешно завершена ==="
