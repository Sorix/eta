#!/bin/bash
# Fake build simulation for testing eta progress rendering.
# It does not build, compile, link, or test anything real.
#
# Copy/paste examples:
#   ETA_SIM_PROFILE=stable swift run eta './examples/simulate.sh'
#   ETA_SIM_PROFILE=random swift run eta './examples/simulate.sh'
#   ETA_SIM_PROFILE=slow swift run eta './examples/simulate.sh'
#   ETA_SIM_PROFILE=random swift run eta --solid './examples/simulate.sh'
#
# Profiles:
#   stable  fixed baseline sleeps
#   fast    about 55% of baseline sleeps
#   slow    about 175% of baseline sleeps
#   random  random sleeps between ETA_SIM_MIN_PERCENT and ETA_SIM_MAX_PERCENT

print_intro() {
    echo "Fake eta simulation: no real build, compile, link, or tests are running."
    echo "Copy/paste examples:"
    echo "  ETA_SIM_PROFILE=stable swift run eta './examples/simulate.sh'"
    echo "  ETA_SIM_PROFILE=random swift run eta './examples/simulate.sh'"
    echo "  ETA_SIM_PROFILE=slow swift run eta './examples/simulate.sh'"
    echo "  ETA_SIM_PROFILE=random swift run eta --solid './examples/simulate.sh'"
    echo
}

sleep_step() {
    local base="$1"
    local profile="${ETA_SIM_PROFILE:-random}"
    local factor

    case "$profile" in
        stable)
            factor=100
            ;;
        fast)
            factor=55
            ;;
        slow)
            factor=175
            ;;
        random)
            local min="${ETA_SIM_MIN_PERCENT:-45}"
            local max="${ETA_SIM_MAX_PERCENT:-180}"
            if (( max < min )); then
                max="$min"
            fi
            factor=$((min + RANDOM % (max - min + 1)))
            ;;
        *)
            factor=100
            ;;
    esac

    local seconds
    seconds="$(awk -v base="$base" -v factor="$factor" 'BEGIN { printf "%.2f", base * factor / 100 }')"
    sleep "$seconds"
}

print_intro

echo "==> Configuring project..."
sleep_step 1.2

echo "==> Resolving dependencies..."
sleep_step 0.8

echo "[1/8] Compiling utils.c"
sleep_step 2.0

echo "[2/8] Compiling parser.c"
sleep_step 3.1

echo "[3/8] Compiling lexer.c"
sleep_step 2.5

echo "[4/8] Compiling codegen.c"
sleep_step 1.8

echo "[5/8] Compiling optimizer.c"
sleep_step 2.4

echo "[6/8] Compiling runtime.c"
sleep_step 1.5

echo "[7/8] Compiling main.c"
sleep_step 1.0

echo "[8/8] Compiling tests.c"
sleep_step 0.9

echo "==> Linking binary..."
sleep_step 1.8

echo "==> Running 42 tests..."
sleep_step 1.2

echo "All tests passed."
echo "Build complete! ($(date +%s)s)"
