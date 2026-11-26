#!/usr/bin/env bash
# Non-destructive diagnostics collector for Acer Aspire 7 A715-79G Control Center
# Scrubs hardware Serial Number, DMI UUID, and root partition UUID before archiving.
set -u

TIMESTAMP="$(date -u +%Y%m%d-%H%M%SZ)"
OUT_NAME="control-center-diag-${TIMESTAMP}"
STAGE_DIR="/tmp/${OUT_NAME}"
TARBALL="/tmp/${OUT_NAME}.tar.gz"

mkdir -p "$STAGE_DIR"

redact_stream() {
    sed -E \
        -e 's/(Serial Number:[[:space:]]*).*/\1[REDACTED]/g' \
        -e 's/(UUID:[[:space:]]*).*/\1[REDACTED]/g' \
        -e 's/(root=UUID=)[^[:space:]]+/\1[REDACTED]/g'
}

{
    echo "=== Timestamp (UTC) ==="
    date -u
    echo "=== uname -a ==="
    uname -a
    echo "=== /etc/os-release ==="
    cat /etc/os-release 2>/dev/null || true
    echo "=== /proc/cmdline (redacted) ==="
    cat /proc/cmdline 2>/dev/null | redact_stream || true
    echo "=== Secure Boot ==="
    mokutil --sb-state 2>&1 || true
    echo "=== DKMS Status ==="
    dkms status 2>&1 || true
} > "$STAGE_DIR/os_kernel.txt"

{
    echo "=== /sys/class/dmi/id (non-sensitive) ==="
    for f in sys_vendor product_name product_version product_family product_sku board_vendor board_name board_version bios_vendor bios_version bios_date bios_release; do
        if [[ -r "/sys/class/dmi/id/$f" ]]; then
            printf '%s: %s\n' "$f" "$(cat "/sys/class/dmi/id/$f" 2>/dev/null || true)"
        fi
    done
    if [[ "$(id -u)" -eq 0 ]] && command -v dmidecode >/dev/null 2>&1; then
        echo "=== dmidecode (redacted) ==="
        dmidecode -t system -t baseboard -t bios 2>/dev/null | redact_stream || true
    else
        echo "=== dmidecode skipped (requires root) ==="
    fi
} > "$STAGE_DIR/dmi.txt"

lsmod 2>/dev/null | sort > "$STAGE_DIR/lsmod.txt" || true

{
    if dmesg >/dev/null 2>&1; then
        dmesg | grep -Ei 'acer|clevo|tuxedo|wmi|acpi|ec|thermal|fan|rgb|hwmon' || true
    elif journalctl -k -b >/dev/null 2>&1; then
        journalctl -k -b --no-pager | grep -Ei 'acer|clevo|tuxedo|wmi|acpi|ec|thermal|fan|rgb|hwmon' || true
    else
        echo "dmesg/journalctl unavailable without elevated privileges"
    fi
} > "$STAGE_DIR/dmesg_filtered.txt"

{
    echo "=== /sys/bus/wmi/devices ==="
    for d in /sys/bus/wmi/devices/*; do
        [[ -e "$d" ]] || continue
        printf '%s -> guid=%s\n' "$d" "$(cat "$d/guid" 2>/dev/null || echo unreadable)"
    done
} > "$STAGE_DIR/wmi_devices.txt"

{
    echo "=== /sys/class/leds ==="
    for l in /sys/class/leds/*; do
        [[ -e "$l" ]] || continue
        printf '== %s ==\n' "$l"
        ls -la "$l" 2>/dev/null || true
        for attr in brightness max_brightness multi_index multi_intensity; do
            if [[ -r "$l/$attr" ]]; then
                printf '  %s: %s\n' "$attr" "$(cat "$l/$attr" 2>/dev/null || true)"
            fi
        done
    done
} > "$STAGE_DIR/leds.txt"

{
    echo "=== /sys/class/hwmon ==="
    for h in /sys/class/hwmon/*; do
        [[ -e "$h" ]] || continue
        printf '== %s (%s) ==\n' "$h" "$(cat "$h/name" 2>/dev/null || echo unknown)"
        for f in "$h"/*_input "$h"/*_label "$h"/pwm*; do
            [[ -r "$f" ]] || continue
            printf '  %s: %s\n' "$(basename "$f")" "$(cat "$f" 2>/dev/null || true)"
        done
    done
} > "$STAGE_DIR/hwmon.txt"

{
    echo "=== /sys/class/power_supply/BAT0 ==="
    if [[ -d /sys/class/power_supply/BAT0 ]]; then
        for f in /sys/class/power_supply/BAT0/*; do
            [[ -f "$f" && -r "$f" ]] || continue
            val="$(cat "$f" 2>/dev/null || true)"
            if [[ "$(basename "$f")" == "serial_number" ]]; then
                val="[REDACTED]"
            fi
            printf '%s: %s\n' "$(basename "$f")" "$val"
        done
    else
        echo "BAT0 not found"
    fi
} > "$STAGE_DIR/battery.txt"

sensors 2>&1 > "$STAGE_DIR/sensors.txt" || true
nvidia-smi 2>&1 > "$STAGE_DIR/nvidia_smi.txt" || true

{
    echo "=== control-center.service ==="
    systemctl status control-center --no-pager -l 2>&1 || true
    echo "=== thermald.service ==="
    systemctl status thermald --no-pager -l 2>&1 || true
} > "$STAGE_DIR/services.txt"

if [[ -d /etc/control-center ]]; then
    mkdir -p "$STAGE_DIR/etc_control_center"
    cp -a /etc/control-center/. "$STAGE_DIR/etc_control_center/" 2>/dev/null || true
fi

if tar -czf "$TARBALL" -C /tmp "$OUT_NAME"; then
    rm -rf "$STAGE_DIR"
    printf 'Diagnostics saved to %s\n' "$TARBALL"
    exit 0
else
    printf 'Diagnostics collected in directory %s (tar failed)\n' "$STAGE_DIR" >&2
    exit 1
fi
