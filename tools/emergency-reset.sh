#!/usr/bin/env bash
# Emergency reset script for Acer Aspire 7 A715-79G Control Center
# Implements AGENT_WORKFLOW.md Safety Rule 1.4:
#   - Restores any writable fan/profile controls back to auto/balanced
#   - Unloads any experimental out-of-tree kernel modules if currently loaded
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info() {
    printf '[emergency-reset] %s\n' "$*"
}

log_warn() {
    printf '[emergency-reset] WARNING: %s\n' "$*" >&2
}

if [[ "$(id -u)" -ne 0 ]]; then
    printf '[emergency-reset] ERROR: Root privileges are required to restore hardware controls and unload modules.\n' >&2
    printf '[emergency-reset] Please run with sudo:\n' >&2
    printf '  sudo %s\n' "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" >&2
    exit 1
fi

errors=0

log_info "Starting emergency reset (restoring fan/profile controls to auto/balanced)..."

# 1. ACPI platform_profile -> balanced (if present and supported)
if [[ -w /sys/firmware/acpi/platform_profile ]]; then
    choices=""
    if [[ -r /sys/firmware/acpi/platform_profile_choices ]]; then
        choices="$(cat /sys/firmware/acpi/platform_profile_choices 2>/dev/null || true)"
    fi
    if [[ " $choices " == *" balanced "* ]] || [[ -z "$choices" ]]; then
        if printf 'balanced' > /sys/firmware/acpi/platform_profile 2>/dev/null; then
            log_info "Restored /sys/firmware/acpi/platform_profile -> balanced"
        else
            log_warn "Failed to write balanced to /sys/firmware/acpi/platform_profile"
            errors=$((errors + 1))
        fi
    else
        log_info "platform_profile present (choices: $choices), 'balanced' not listed; skipping."
    fi
fi

# 2. Generic hwmon pwm*_enable -> 2 (auto)
shopt -s nullglob
for pwm_en in /sys/class/hwmon/*/pwm*_enable; do
    if [[ -w "$pwm_en" ]]; then
        hwmon_dir="$(dirname "$pwm_en")"
        hwmon_name="$(cat "$hwmon_dir/name" 2>/dev/null || echo "unknown")"
        if printf '2' > "$pwm_en" 2>/dev/null; then
            log_info "Restored $pwm_en ($hwmon_name) -> 2 (auto)"
        else
            log_warn "Failed to write 2 to $pwm_en ($hwmon_name)"
            errors=$((errors + 1))
        fi
    fi
done

# 3. dchu / clevo_acpi fan_mode sysfs -> auto
for fm in /sys/class/hwmon/*/fan_mode /sys/devices/platform/*/fan_mode /sys/devices/platform/*/*/fan_mode; do
    if [[ -w "$fm" ]]; then
        if printf 'auto' > "$fm" 2>/dev/null; then
            log_info "Restored $fm -> auto"
        else
            log_warn "Failed to write auto to $fm"
            errors=$((errors + 1))
        fi
    fi
done
shopt -u nullglob

# 4. /dev/tuxedo_io fan-auto ioctl (W_CL_FANAUTO = _IOW(0xEE, 0x11, int32_t*)) if tuxedo_io loaded
if lsmod | awk '{print $1}' | grep -qx 'tuxedo_io'; then
    if [[ -e /dev/tuxedo_io ]]; then
        if command -v python3 >/dev/null 2>&1; then
            if python3 - <<'PY'
import ctypes, fcntl, struct
# _IOW(MAGIC_WRITE_CL=0xEE, 0x11, int32_t*) -> pointer size = sizeof(void*)
ptr_sz = ctypes.sizeof(ctypes.c_void_p)
W_CL_FANAUTO = (1 << 30) | (ptr_sz << 16) | (0xEE << 8) | 0x11
W_CL_PERF_PROFILE = (1 << 30) | (ptr_sz << 16) | (0xEE << 8) | 0x15
with open("/dev/tuxedo_io", "rb+", buffering=0) as fd:
    # 0x0F = bitmask for fans 1..4 -> EC auto
    fcntl.ioctl(fd.fileno(), W_CL_FANAUTO, struct.pack("<i", 0x0F))
    # Restore balanced/entertainment DPTF/power profile 3 (APPM[3]=0x00)
    fcntl.ioctl(fd.fileno(), W_CL_PERF_PROFILE, struct.pack("<i", 3))
PY
            then
                log_info "Restored /dev/tuxedo_io fans -> auto (0x0F) and perf profile -> 3 (balanced/entertainment)"
            else
                log_warn "Failed to send W_CL_FANAUTO via /dev/tuxedo_io"
                errors=$((errors + 1))
            fi
        else
            log_warn "python3 not found; cannot send W_CL_FANAUTO ioctl to /dev/tuxedo_io"
            errors=$((errors + 1))
        fi
    else
        log_warn "tuxedo_io is loaded but /dev/tuxedo_io does not exist"
    fi
fi

# 5. Unload experimental out-of-tree kernel modules in safe reverse dependency order
EXPERIMENTAL_MODULES=(
    tuxedo_io
    uniwill_wmi
    clevo_wmi
    clevo_acpi
    tuxedo_keyboard
    tuxedo_compatibility_check
    dchu_hwmon
    dchu_leds
    dchu_core
    clevo_acpi_dkms
    clevo_acpi_sys76
    uwcc
)

unloaded_any=0
for mod in "${EXPERIMENTAL_MODULES[@]}"; do
    if lsmod | awk '{print $1}' | grep -qx "$mod"; then
        if rmmod "$mod" 2>/dev/null; then
            log_info "Unloaded module: $mod"
            unloaded_any=1
        else
            log_warn "Failed to unload module: $mod (in use or error)"
            errors=$((errors + 1))
        fi
    fi
done

if [[ "$unloaded_any" -eq 0 ]]; then
    log_info "No experimental out-of-tree modules were loaded."
fi

if [[ "$errors" -eq 0 ]]; then
    log_info "Emergency reset completed cleanly."
    exit 0
else
    log_warn "Emergency reset finished with $errors error(s)."
    exit 1
fi
