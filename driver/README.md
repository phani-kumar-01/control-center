# Out-of-Tree Driver Preparation & Phase 4 Enhancements

**Target Machine:** `Acer Aspire A715-79G` (`Version: 1.14`, `BIOS: INSYDE Corp. 1.14RA1`, `EC: 7.13`)
**Kernel:** `7.0.0-38-generic` (`Ubuntu 26.04.1 LTS`, `SecureBoot disabled`)
**Base Driver:** `tuxedocomputers/tuxedo-drivers` (v4.25.2, upstream commit `07a681fc52c4ae0c90991247c1c1d8a62740eda4`, `GPL-2.0+`), copied without `.git` from `research/clevo_repos/tuxedo-drivers/` into `driver/tuxedo-drivers/`.

---

## 1. Why `patched tuxedo-drivers` Was Selected for Step 2

1. **DSDT Interface Match (`recon/acpi/DSDT_ANALYSIS.md`):**
   - `BIOS 1.14RA1` implements Clevo DCHU `CLV0001` (`_SB.DCHU._DSM`, UUID `93f224e4-fbdc-4bbf-add6-db71bdc0afad`) and WMI `ABBC0F6D` (`WMBB`) in full, including:
     - `_DSM 0x0D` (`PK0D`): hardware specs & keyboard backlight type `KBTP` at offset `0x0F`
     - `_DSM 0x46`: enables hotkey ACPI Notify events (`DCHU.HKDR = 1`)
     - `_DSM 0x67`: RGB (`0xF0` single-zone `0xFA=B, 0xFB=R, 0xFC=G`), brightness (`0xF4`), keyboard sleep/power (`0xE0`)
     - `_DSM 0x63` / `0x64` (`GET_FANINFO1/2`), `0x68` (manual fan duty), `0x69` (restore EC auto), `0x79` (`0x19` performance/DPTF profile)
     - `_DSM 0x76` / `0x77` / `0x04` (`0x1E`/`0x1F`) FlexiCharger battery thresholds
2. **Community Verification:**
   - `Atul977/tuxedo-drivers` (used by `Atul977/Aspire-A715-79G-LinuxPackages`) and `nick42d/clevo-drivers` confirm `tuxedo-drivers` works on `Acer Aspire A715-79G` once `tuxedo_is_compatible()` accepts the machine's DMI strings.
3. **Why Not Other Candidates First:**
   - `opendchu` uses white-only LEDs (`_DSM 0x3D`/`0x27`) instead of `_DSM 0x67` RGB.
   - `clevo-acpi-dkms` requires a System76 DMI table patch and custom 1-zone `0xF0` RGB adjustments (kept as the reference for an in-kernel 15s dead-man's-switch fan watchdog + `hwmon` if needed in Phase 4/5).

---

## 2. Exact Patch Applied (`driver/tuxedo-drivers-a715-79g.patch`)

Targeted changes inside `driver/tuxedo-drivers/`:

1. **`src/tuxedo_compatibility_check/tuxedo_compatibility_check.c`:**
   - Upstream `tuxedo_is_compatible()` only allows `TUXEDO` DMI vendor strings (and the CPU fallback `#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 12, 0)` is inactive on kernel `7.0.0-38-generic`).
   - Added a targeted DMI match for `{ DMI_SYS_VENDOR = "Acer", DMI_PRODUCT_NAME = "Aspire A715-79G" }` to `tuxedo_dmi_string_match[]` (safer than an unconditional `return true;` as in `nick42d/clevo-drivers/patch.diff` / `Atul977/tuxedo-drivers`, while behaving identically on this machine).
2. **`src/clevo_leds.h`:**
   - Promoted `pr_debug` to `pr_info` for `CLEVO_CMD_GET_SPECS result->buffer.pointer[0x0f]` (`KBTP`), `CLEVO_CMD_GET_BIOS_FEATURES_1` (`0x52`), `CLEVO_CMD_GET_BIOS_FEATURES_2` (`0x7A`), and `Keyboard backlight type` so `dmesg` logs the exact runtime keyboard type without requiring dynamic debug.
   - Added `ACPI_FREE(result);` before the early `break;` when `PK0D[0x0f]` is non-zero so the ACPI return buffer is not leaked.
   - Verified `clevo_leds.h` already handles `CLEVO_KB_BACKLIGHT_TYPE_1_ZONE_RGB` (`0x06`) using `CLEVO_CMD_SET_KB_RGB_LEDS` (`0x67`), `0xE007F001` power-on, `0xF4` brightness, and `0xF0_BB_RR_GG` color byte order.
3. **`src/clevo_acpi.c` (Phase 4 Read-Only `hwmon` + Leak Fix):**
   - Fixed `clevo_acpi_evaluate()` and `clevo_acpi_evaluate_pkgbuf()` to call `ACPI_FREE(out_obj)` when `result` is `NULL`, and initialized `event_value = 0` in `clevo_acpi_notify()`.
   - Added `platform_set_drvdata(pdev, driver_data)` and registered read-only `hwmon` (`"clevo_acpi"`) via `devm_hwmon_device_register_with_info()` exposing:
     - `fan1_input`, `fan2_input` (`0444`, plus `fan1_label` / `fan2_label`): calls `_DSM 0x0C` (`PK0C`), reads big-endian tach period at bytes `[2..3]` / `[4..5]`, returns `(be16 == 0 || be16 == 0xffff) ? 0 : (2156220L / be16)`.
     - `temp1_input`, `temp2_input` (`0444`, plus `temp1_label` / `temp2_label`): calls `_DSM 0x63` / `0x64` (`GET_FANINFO1/2`), extracts `((u32)val >> 16) & 0xFF`, returns `temp * 1000L`.
     - `pwm1`, `pwm2` (`0444`): calls `_DSM 0x63` / `0x64`, returns `val & 0xFF` (`0..255` duty).
4. **`src/tuxedo_io/tuxedo_io.c` (Phase 4 15 s Dead-Man's-Switch Fan Watchdog):**
   - Added `clevo_fan_lock`, `clevo_fan_manual_active`, and `delayed_work` `clevo_fan_watchdog_work` (`CLEVO_FAN_WATCHDOG_MS = 15000`).
   - `W_CL_FANSPEED` arms/pets the 15 s watchdog via `mod_delayed_work(system_wq, ...)` on success.
   - `W_CL_FANAUTO` clears `clevo_fan_manual_active`, cancels `clevo_fan_watchdog_work` outside `clevo_fan_lock` (`cancel_delayed_work_sync`), and invokes `CLEVO_CMD_SET_FANSPEED_AUTO` (`0x69`).
   - If the watchdog expires (e.g., daemon crash/`kill -9`), it logs a warning and restores `CLEVO_CMD_SET_FANSPEED_AUTO` (`0x0F`). Also restores EC auto on `tuxedo_io_exit()` and system reboot (`register_reboot_notifier`).
5. **`dkms.conf` & `Makefile`:**
   - Added `driver/tuxedo-drivers/dkms.conf` (`PACKAGE_NAME="tuxedo-drivers-a715-79g"`, `PACKAGE_VERSION="4.25.2"`, `AUTOINSTALL="yes"`) building the 5 verified Clevo modules into `/updates/dkms/`.
   - Updated `Makefile` to use `M=$(CURDIR)` instead of `M=$(PWD)` so `make -C /path/to/driver/tuxedo-drivers` works from any working directory and under DKMS.

---

## 3. Non-Root Build & `modinfo` Verification

Built locally (without `make install` or `insmod`) via:
```bash
make -C /home/candy/control/control-center/driver/tuxedo-drivers clean && \
make -C /home/candy/control/control-center/driver/tuxedo-drivers -j"$(nproc)"
```

All 5 required Clevo modules built with zero compiler warnings/errors on modified files and match `vermagic: 7.0.0-38-generic SMP preempt mod_unload modversions`:

| Module (Load Order) | Path (under `driver/tuxedo-drivers/src/`) | `depends` | Key Aliases |
|---|---|---|---|
| 1 | `tuxedo_compatibility_check/tuxedo_compatibility_check.ko` | *(none)* | — |
| 2 | `tuxedo_keyboard.ko` | `sparse-keymap`, `led-class-multicolor`, `tuxedo_compatibility_check` | — |
| 3 | `clevo_acpi.ko` | `tuxedo_keyboard` | `acpi*:CLV0001:*` |
| 4 | `clevo_wmi.ko` | `tuxedo_keyboard`, `wmi` | `wmi:ABBC0F6B-...`, `wmi:ABBC0F6D-...` |
| 5 | `tuxedo_io/tuxedo_io.ko` (`v0.3.9`) | `tuxedo_keyboard` | `/dev/tuxedo_io` |

**Important Load Order Note:** Load `clevo_acpi.ko` **before** `clevo_wmi.ko` so `clevo_keyboard_add_interface()` selects `clevo_acpi` (`CLV0001` `_DSM`) as `active_clevo_interface` right at `clevo_keyboard_probe()` time (supporting both integer and buffer `_DSM` calls such as `PK0D`, `FnLock`, and `cc4_flexicharger`).

---

## 4. `/dev/tuxedo_io` IOCTL ABI Notes & Watch-Outs

- In `src/tuxedo_io/tuxedo_io_ioctl.h`, every `_IOR`/`_IOW` macro uses pointer types (`char*` / `int32_t*`), so on x86_64 the encoded size field is **`sizeof(void *) = 8`**, not `4`.
- `tuxedo_io` v0.3.9 provides: `R_MOD_VERSION`, `R_HWCHECK_CL`, `R_CL_HW_IF_STR`, `R_CL_FANINFO1/2/3`, `R_CL_WEBCAM_SW`, `R_CL_FLIGHTMODE_SW`, `R_CL_TOUCHPAD_SW`, `W_CL_FANSPEED`, `W_CL_FANAUTO`, `W_CL_PERF_PROFILE` (`_DSM 0x79` subcmd `0x19`). It does **not** expose `GET_SPEC` (`0x0D`) or `GET_AP_MODE` ioctls (fan RPMs and raw duty are cross-checked via read-only `ec_sys` `0xCE..0xD3`, and `KBTP` `0x0D[0x0f]` is logged in `dmesg` by `clevo_leds.h`).
- **Watch-out / Safety:** `tuxedo_io` v0.3.9 now includes the 15 s in-kernel dead-man's-switch fan watchdog (`_DSM 0x69 0x0F`), and `clevo_acpi` now registers read-only `hwmon` (`fan1_input`, `fan2_input`, `temp1_input`, `temp2_input`, `pwm1`, `pwm2`). Live `hwmon` and watchdog timeout verification run in Phase 6 (with user approval).
