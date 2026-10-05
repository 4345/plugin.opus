#!/bin/bash -e

# build_mac.sh
# Compiles the Opus plugin as a macOS dynamic library (plugin_opus.dylib)

path=$(cd "$(dirname "$0")"; pwd)
OPUS_DIR="$path/../opus-1.6.1"

# Opus в репозитории не хранится: его скачивает tools/poluchit_opus.py
if [ ! -f "$OPUS_DIR/COPYING" ]; then
    echo "Нет исходников Opus в $OPUS_DIR — выполните из корня репозитория: python3 tools/poluchit_opus.py" >&2
    exit 1
fi
# config.h для сборки Opus (-DHAVE_CONFIG_H) — свой, из opus_config/
OPUS_CONFIG_DIR="$path/../opus_config"
BUILD_DIR="$path/build/mac_build"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

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

OPUS_ARM_SOURCES=(
    "$OPUS_DIR/celt/arm/celt_neon_intr.c"
    "$OPUS_DIR/celt/arm/pitch_neon_intr.c"
    "$OPUS_DIR/silk/arm/biquad_alt_neon_intr.c"
    "$OPUS_DIR/silk/arm/LPC_inv_pred_gain_neon_intr.c"
    "$OPUS_DIR/silk/arm/NSQ_del_dec_neon_intr.c"
    "$OPUS_DIR/silk/arm/NSQ_neon.c"
)

CORONA_ROOT="$HOME/Library/Application Support/Corona/Native"
LUA_INC="$CORONA_ROOT/Corona/shared/include/lua"
CORONA_INC="$CORONA_ROOT/Corona/shared/include/Corona"

compile_dylib() {
    ARCH=$1
    TARGET_DYLIB="$BUILD_DIR/plugin_opus_$ARCH.dylib"

    echo "=== Compiling macOS dylib for $ARCH ==="

    CC=$(xcrun -f clang)
    SDK_PATH=$(xcrun --show-sdk-path)

    CFLAGS=(
        "-Os"
        "-arch" "$ARCH"
        "-isysroot" "$SDK_PATH"
        "-DHAVE_CONFIG_H"
        "-fvisibility=hidden"
        "-ffunction-sections"
        "-fdata-sections"
        "-dynamiclib"
        "-undefined" "dynamic_lookup"
        "-mmacosx-version-min=10.12"
        "-I$OPUS_DIR/include"
        "-I$OPUS_DIR/celt"
        "-I$OPUS_DIR/silk"
        "-I$OPUS_DIR/silk/float"
        "-I$OPUS_CONFIG_DIR"
        "-I$OPUS_DIR"
        "-I$LUA_INC"
        "-I$CORONA_INC"
        "-I$path/Plugin"
        "-framework" "Foundation"
    )

    FILES=("${OPUS_SOURCES[@]}" "$path/Plugin/PluginLibrary.mm")
    if [ "$ARCH" == "arm64" ]; then
        FILES+=("${OPUS_ARM_SOURCES[@]}")
    fi

    $CC "${CFLAGS[@]}" "${FILES[@]}" -o "$TARGET_DYLIB"
}

compile_dylib arm64
compile_dylib x86_64

# Merge
echo "=== Merging macOS dylib binaries ==="
FINAL_DYLIB="$BUILD_DIR/plugin_opus.dylib"
lipo -create \
    "$BUILD_DIR/plugin_opus_arm64.dylib" \
    "$BUILD_DIR/plugin_opus_x86_64.dylib" \
    -output "$FINAL_DYLIB"

# Strip
echo "=== Stripping debug/local symbols from macOS dylib ==="
strip -x "$FINAL_DYLIB"

# Deploy to Simulator Plugins folder
DEST_DIR="$HOME/Library/Application Support/Corona/Simulator/Plugins"
mkdir -p "$DEST_DIR"
cp "$FINAL_DYLIB" "$DEST_DIR/"
echo "=== Successfully deployed plugin_opus.dylib to $DEST_DIR/ ==="

# Also copy to workspace BuiltPlugin/mac-sim
BUILT_MAC_DIR="$path/BuiltPlugin/mac-sim"
mkdir -p "$BUILT_MAC_DIR"
cp "$FINAL_DYLIB" "$BUILT_MAC_DIR/"
cp "$path/metadata.lua" "$BUILT_MAC_DIR/"
echo "=== Successfully copied plugin_opus.dylib to $BUILT_MAC_DIR/ ==="
