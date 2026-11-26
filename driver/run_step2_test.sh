#!/usr/bin/env bash
# Phase 3 Step 2 Self-Contained Hardware Test Harness
# Tests patched tuxedo-drivers (clevo_acpi, clevo_wmi, tuxedo_keyboard, tuxedo_io)
# on Acer Aspire 7 A715-79G with live temperature guards and automatic emergency reset.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER_SRC="$SCRIPT_DIR/tuxedo-drivers/src"
PROBE_PY="$SCRIPT_DIR/probe_tuxedo_io.py"
RESET_SH="$REPO_ROOT/tools/emergency-reset.sh"
LOG_FILE="$SCRIPT_DIR/step2_test.log"

usage() {
    cat <<EOF
Usage: sudo $SCRIPT_DIR/run_step2_test.sh [--help | --dry-run]

Runs Phase 3 Step 2 hardware verification for patched tuxedo-drivers:
  1. Checks pre-load CPU/ACPI/GPU temperatures (aborts if >= 80 C).
  2. Loads kernel dependencies and insmods out-of-tree .ko modules in dependency order.
  3. Captures dmesg and inspects sysfs/dev nodes (/sys/class/leds, /dev/tuxedo_io, hwmon).
  4. Tests keyboard backlight brightness and RGB colors (if multicolor LED registered).
  5. Queries read-only /dev/tuxedo_io + read-only ec_sys telemetry (0x07, 0xCE..0xD3).
  6. If temps < 75 C, tests fan auto -> 60% duty (6s, live temp guard < 85 C) -> auto,
     plus DPTF/performance profile switching and restoring balanced.
  7. Always runs tools/emergency-reset.sh on exit/abort and logs to:
     $LOG_FILE (chmod 644).

Options:
  --help     Show this help message and exit (non-root safe).
  --dry-run  Check script prerequisites, built .ko files, and sensor readouts without root or insmod.
EOF
}

if [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ "${1:-}" == "--dry-run" ]]; then
    echo "[dry-run] Checking prerequisites..."
    for f in "$PROBE_PY" "$RESET_SH" \
        "$DRIVER_SRC/tuxedo_compatibility_check/tuxedo_compatibility_check.ko" \
        "$DRIVER_SRC/tuxedo_keyboard.ko" \
        "$DRIVER_SRC/clevo_acpi.ko" \
        "$DRIVER_SRC/clevo_wmi.ko" \
        "$DRIVER_SRC/tuxedo_io/tuxedo_io.ko"; do
        if [[ -e "$f" ]]; then
            echo "[dry-run] OK: $f"
        else
            echo "[dry-run] MISSING: $f" >&2
            exit 1
        fi
    done
    python3 "$PROBE_PY" --dry-run
    echo "[dry-run] Dry-run completed cleanly (no modules loaded, no hardware touched)."
    exit 0
fi

if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: Root privileges are required to load kernel modules and access /dev/tuxedo_io." >&2
    echo "Run: sudo $SCRIPT_DIR/run_step2_test.sh" >&2
    exit 1
fi

if [[ ! -x "$RESET_SH" ]]; then
    echo "ERROR: Emergency reset script missing or not executable: $RESET_SH" >&2
    exit 1
fi

# Redirect all stdout+stderr to both console and step2_test.log
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
exec > >(tee "$LOG_FILE") 2>&1

cleanup() {
    local rc=$?
    echo ""
    echo "=== [CLEANUP TRAP] Running emergency-reset.sh (exit code was $rc) ==="
    "$RESET_SH" || true
    if [[ -f "$LOG_FILE" ]]; then
        chmod 644 "$LOG_FILE" || true
    fi
    echo "=== Step 2 test finished at $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="
    echo "Log saved (mode 644): $LOG_FILE"
}
trap cleanup EXIT INT TERM

echo "=== Acer Aspire 7 A715-79G — Phase 3 Step 2 Hardware Test ==="
echo "Start UTC: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "Kernel:    $(uname -r)"
echo "DMI:       $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true) / $(cat /sys/class/dmi/id/product_name 2>/dev/null || true) (BIOS $(cat /sys/class/dmi/id/bios_version 2>/dev/null || true))"

# Verify built .ko modules exist
KO_MODS=(
    "$DRIVER_SRC/tuxedo_compatibility_check/tuxedo_compatibility_check.ko"
    "$DRIVER_SRC/tuxedo_keyboard.ko"
    "$DRIVER_SRC/clevo_acpi.ko"
    "$DRIVER_SRC/clevo_wmi.ko"
    "$DRIVER_SRC/tuxedo_io/tuxedo_io.ko"
)
for ko in "${KO_MODS[@]}"; do
    if [[ ! -f "$ko" ]]; then
        echo "ERROR: Built kernel module not found: $ko" >&2
        exit 1
    fi
done

echo ""
echo "=== [1] Pre-load Temperature & Read-Only EC Check (Abort if >= 80 C) ==="
if ! python3 "$PROBE_PY" --temps --max-temp 80; then
    echo "ABORT: Pre-load temperature >= 80 C! Not loading test driver."
    exit 1
fi
python3 "$PROBE_PY" --ec-only || true

echo ""
echo "=== [2] Clean any previously loaded experimental modules & load prerequisites ==="
"$RESET_SH" || true
for dep in sparse-keymap led-class-multicolor wmi video; do
    modprobe "$dep" 2>&1 || echo "Note: modprobe $dep returned $?"
done

echo ""
echo "=== [3] insmod Out-of-Tree Patched tuxedo-drivers (exact dependency order) ==="
for ko in "${KO_MODS[@]}"; do
    echo "+ insmod $ko"
    insmod "$ko"
done

sleep 1
echo ""
echo "=== [4] dmesg (last 60 lines after insmod) ==="
dmesg | tail -n 60

echo ""
echo "=== [5] Sysfs & Device Discovery ==="
echo "--- /sys/class/leds/ ---"
ls -la /sys/class/leds/
echo "--- /sys/devices/platform/tuxedo_keyboard/ ---"
ls -la /sys/devices/platform/tuxedo_keyboard/ 2>&1 || echo "(absent)"
echo "--- /dev/tuxedo_io ---"
ls -la /dev/tuxedo_io 2>&1 || echo "(absent)"
echo "--- /sys/class/hwmon/ ---"
for h in /sys/class/hwmon/*; do
    echo "$h: $(cat "$h/name" 2>/dev/null || true)"
done
echo "--- /sys/class/power_supply/BAT0/charge_* ---"
ls -la /sys/class/power_supply/BAT0/charge_* 2>&1 || echo "(none)"

echo ""
echo "=== [6] Keyboard Backlight LED Test ==="
KBD_LED=""
for cand in /sys/class/leds/*kbd_backlight*; do
    if [[ -e "$cand" ]]; then
        KBD_LED="$cand"
        break
    fi
done

if [[ -z "$KBD_LED" ]]; then
    echo "WARNING: No *kbd_backlight LED class device found under /sys/class/leds/."
    echo "Check dmesg above for CLEVO_CMD_GET_SPECS[0x0f] (KBTP) and Keyboard backlight type."
else
    echo "Found keyboard LED: $KBD_LED"
    ls -la "$KBD_LED"
    init_br="$(cat "$KBD_LED/brightness" 2>/dev/null || echo 0)"
    max_br="$(cat "$KBD_LED/max_brightness" 2>/dev/null || echo 255)"
    echo "Initial brightness=$init_br max_brightness=$max_br"

    if [[ -r "$KBD_LED/multi_index" ]]; then
        echo "multi_index: $(cat "$KBD_LED/multi_index")"
    fi
    init_mi=""
    if [[ -r "$KBD_LED/multi_intensity" ]]; then
        init_mi="$(cat "$KBD_LED/multi_intensity")"
        echo "Initial multi_intensity: $init_mi"
    fi

    mid_br=$(( max_br / 2 ))
    echo "Testing brightness: 0 (off) -> $mid_br -> $max_br"
    echo 0 > "$KBD_LED/brightness"
    sleep 0.5
    echo "$mid_br" > "$KBD_LED/brightness"
    sleep 0.5
    echo "$max_br" > "$KBD_LED/brightness"
    sleep 0.5

    if [[ -w "$KBD_LED/multi_intensity" ]]; then
        echo "Testing RGB colors via multi_intensity + brightness=$max_br:"
        for spec in "Red:255 0 0" "Green:0 255 0" "Blue:0 0 255" "White:255 255 255"; do
            cname="${spec%%:*}"
            cvals="${spec#*:}"
            echo "  Setting $cname ($cvals)..."
            echo "$cvals" > "$KBD_LED/multi_intensity"
            echo "$max_br" > "$KBD_LED/brightness"
            sleep 0.6
        done
        echo "Readback multi_intensity=$(cat "$KBD_LED/multi_intensity") brightness=$(cat "$KBD_LED/brightness")"
    else
        echo "multi_intensity not writable/present; white/fixed-color brightness test complete."
    fi

    # Leave keyboard at clean White 50% (or restore initial if >0) so it is visibly no longer stuck on blue
    if [[ -w "$KBD_LED/multi_intensity" ]]; then
        echo "255 255 255" > "$KBD_LED/multi_intensity"
    fi
    echo "$mid_br" > "$KBD_LED/brightness"
fi

echo ""
echo "=== [7] Read-Only Telemetry via /dev/tuxedo_io + ec_sys Cross-Check ==="
if [[ -e /dev/tuxedo_io ]]; then
    python3 "$PROBE_PY" --telemetry
else
    echo "ERROR: /dev/tuxedo_io missing; cannot run telemetry/fan tests."
    exit 1
fi

echo ""
echo "=== [8] Safe Fan & Profile Control Test (ONLY if temps < 75 C) ==="
if ! python3 "$PROBE_PY" --temps --max-temp 75; then
    echo "SKIPPING fan/profile write tests because temperature >= 75 C."
    exit 0
fi

echo "--- Step 8a: Explicit fan auto (W_CL_FANAUTO 0x0F) ---"
python3 "$PROBE_PY" --fan-auto
sleep 1
python3 "$PROBE_PY" --telemetry

echo "--- Step 8b: Moderate manual fan duty 60% (153/255 on fan1 & fan2) for 6s ---"
python3 "$PROBE_PY" --fan-set 153 153
for sec in 1 2 3 4 5 6; do
    sleep 1
    echo -n "  [t=${sec}s] "
    if ! python3 "$PROBE_PY" --temps --max-temp 85; then
        echo "EMERGENCY ABORT: Temp >= 85 C during fan test! Restoring auto."
        python3 "$PROBE_PY" --fan-auto || true
        exit 1
    fi
    if [[ "$sec" -eq 2 || "$sec" -eq 5 ]]; then
        python3 "$PROBE_PY" --telemetry
    fi
done

echo "--- Step 8c: Restore fan auto (W_CL_FANAUTO 0x0F) & verify after 3s ---"
python3 "$PROBE_PY" --fan-auto
sleep 3
python3 "$PROBE_PY" --telemetry

echo "--- Step 8d: Test DPTF/performance profile switching (0=quiet, 2=perf, 3=balanced) ---"
for p in 0 2 3; do
    python3 "$PROBE_PY" --set-profile "$p"
    sleep 0.5
done
python3 "$PROBE_PY" --telemetry

echo ""
echo "=== [9] All Step 2 Hardware Probes Completed Successfully ==="
