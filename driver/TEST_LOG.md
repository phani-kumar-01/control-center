# Phase 3 Step 2 Hardware Test Log — Acer Aspire 7 A715-79G

**Test Date (UTC):** `2026-11-26T02:41:28Z` to `2026-11-26T02:41:50Z` (22 s)  
**Raw Log:** `/home/candy/control/control-center/driver/step2_test.log` (224 lines, exit code `0`)  
**Driver Build Docs:** `/home/candy/control/control-center/driver/README.md` (`driver/tuxedo-drivers-a715-79g.patch`)  
**Test Harness:** `/home/candy/control/control-center/driver/run_step2_test.sh` + `/home/candy/control/control-center/driver/probe_tuxedo_io.py` + `/home/candy/control/control-center/tools/emergency-reset.sh`

---

## 1. Test Environment & Driver Versions

| Item | Verified Value |
|---|---|
| Machine / DMI | `Acer` / `Aspire A715-79G` (`Version: 1.14`, `BIOS: INSYDE Corp. 1.14RA1` `09/08/2025`, `EC: 7.13`) |
| OS / Kernel | `Ubuntu 26.04.1 LTS` / `7.0.0-38-generic` (`SecureBoot disabled`) |
| Driver Source | `tuxedocomputers/tuxedo-drivers` v4.25.2 (commit `07a681fc52c4ae0c90991247c1c1d8a62740eda4`, `GPL-2.0+`), patched via `driver/tuxedo-drivers-a715-79g.patch` |
| `tuxedo_io` Module Version | `0.3.9` (`R_MOD_VERSION=0.3.9`) |
| Exact Command Run (User) | `sudo /home/candy/control/control-center/driver/run_step2_test.sh` |
| User Confirmation | `"all are working great and properly"` |

---

## 2. Chronological Observations (All Verified from `driver/step2_test.log`)

### 2.1 Step `[1]` — Pre-Load Temperature & Read-Only EC Baseline (`02:41:28Z`)
- **Safety Gate (`< 80 C`):** `CPU_PKG=46.0C`, `CPU_MAX=46.0C`, `ACPITZ=47.0C`, `GPU=43.0C`, `MAX=47.0C` (passed).
- **Read-Only `ec_sys` (`write_support=N`):**
  - `0x07 (TMP)` = `47C`
  - `0xCE (DUT1)` = `71/255` (`27.8%`), `0xCF (DUT2)` = `71/255` (`27.8%`)
  - `0xD0..D1 (RPM1)` = `[03 d5]` (`BE = 981` -> **`2198 RPM`** via `round(2156220/981)`, or `2197` integer floor)
  - `0xD2..D3 (RPM2)` = `[03 d5]` (`BE = 981` -> **`2198 RPM`**)

### 2.2 Steps `[2]`–`[4]` — Prerequisite & Out-of-Tree Module Load (`dmesg`)
- `emergency-reset.sh` confirmed no prior experimental modules were loaded.
- Loaded in-kernel prerequisites (`sparse-keymap`, `led-class-multicolor`, `wmi`, `video`), then `insmod` loaded all 5 out-of-tree `.ko` modules cleanly in exact dependency order:
  1. `tuxedo_compatibility_check.ko`
  2. `tuxedo_keyboard.ko`
  3. `clevo_acpi.ko` (loaded before `clevo_wmi.ko` so `CLV0001` `_DSM` is selected as `active_clevo_interface`)
  4. `clevo_wmi.ko`
  5. `tuxedo_io.ko`
- **Key `dmesg` lines (`[6921.224910]`–`[6921.300680]`):**
  - `tuxedo_compatibility_check`: out-of-tree unsigned taint notice only; loaded cleanly (`SecureBoot disabled`).
  - `tuxedo_keyboard: CLEVO_CMD_GET_SPECS result->buffer.pointer[0x0f]: 0x06` (`CLEVO_KB_BACKLIGHT_TYPE_1_ZONE_RGB`)
  - `tuxedo_keyboard: CLEVO_CMD_GET_BIOS_FEATURES_2 result_fallback: 0x70020053`
  - `tuxedo_keyboard: Keyboard backlight type: 0x06`
  - `tuxedo_keyboard: Set keyboard enabled to: 1` (`_DSM 0x67` `0xE007F001`)
  - `tuxedo_keyboard: Set keyboard backlight mode on CUSTOM` (`_DSM 0x67` `0x00000000`)
  - `ACPI: battery: new hook: TUXEDO Flexicharger Extension`
  - `input: TUXEDO Keyboard as /devices/platform/tuxedo_keyboard/input/input32`
  - `clevo_acpi: interface initialized`
  - `clevo_wmi: interface initialized`
  - Zero ACPI errors, zero probe failures, zero kernel oopses.

### 2.3 Step `[5]` — Sysfs & Device Discovery
- **Keyboard LED:** `/sys/class/leds/rgb:kbd_backlight -> ../../devices/platform/tuxedo_keyboard/leds/rgb:kbd_backlight`
- **Keyboard Platform Sysfs:** `/sys/devices/platform/tuxedo_keyboard/fn_lock` (`-rw-r--r--`)
- **IOCTL Device:** `/dev/tuxedo_io` (`crw------- 1 root root 505, 0`)
- **Battery Thresholds (`BAT0`):**
  - `/sys/class/power_supply/BAT0/charge_control_start_threshold` (`-rw-r--r--`)
  - `/sys/class/power_supply/BAT0/charge_control_end_threshold` (`-rw-r--r--`)
  - `/sys/class/power_supply/BAT0/charge_control_start_available_thresholds` (`-r--r--r--`)
  - `/sys/class/power_supply/BAT0/charge_control_end_available_thresholds` (`-r--r--r--`)
  - `/sys/class/power_supply/BAT0/charge_type` (`-rw-r--r--`)
- **Hwmon Nodes:** `hwmon0: AC`, `hwmon1: acpitz_0`, `hwmon2: BAT0`, `hwmon3: nvme`, `hwmon4: iwlwifi_1_6`, `hwmon5: coretemp` (confirms `tuxedo-drivers` Clevo modules do **not** register an `hwmon` fan/PWM node).

### 2.4 Step `[6]` — Keyboard Backlight LED & RGB Color Test
- Initial state: `brightness=0`, `max_brightness=255`, `multi_index: red green blue`, `multi_intensity: 255 255 255`.
- Brightness test: `0 (off) -> 127 -> 255` (0.5 s per step).
- RGB color test (`brightness=255`, 0.6 s per step):
  - `Red (255 0 0)` -> `Green (0 255 0)` -> `Blue (0 0 255)` -> `White (255 255 255)`.
  - Readback verified: `multi_intensity=255 255 255 brightness=255`, then left at White `127`.
- **User visual confirmation:** `"all are working great and properly"` (keyboard is no longer stuck on blue).

### 2.5 Step `[7]` — Read-Only `/dev/tuxedo_io` & `ec_sys` Telemetry Cross-Check
- `R_MOD_VERSION=0.3.9`, `R_HWCHECK_CL=1`, `R_HWCHECK_UW=0`, `R_CL_HW_IF_STR='clevo_acpi'`
- `R_CL_FANINFO1=0x002f2947` (`duty=71/255 27.8%`, `temp1=41C`, `temp2=47C`)
- `R_CL_FANINFO2=0x002d2747` (`duty=71/255 27.8%`, `temp1=39C`, `temp2=45C`)
- `R_CL_FANINFO3=0x00002700` (`duty=0/255 0.0%`, `temp1=39C`, `temp2=0C` — confirms 2 physical fans only, fan 3 absent)
- `switches: webcam=1 flightmode=0 touchpad=1`
- `ec_sys RO`: `0x07(TMP)=47C | 0xCE(DUT1)=71/255 (27.8%) | 0xCF(DUT2)=71/255 (27.8%) | 0xD0..D1=[03 d8] (2191 RPM BE) | 0xD2..D3=[03 d8] (2191 RPM BE)`

### 2.6 Step `[8]` — Fan Control & Performance Profile Test
- Pre-test temp check (`< 75 C`): `CPU_PKG=47.0C CPU_MAX=47.0C ACPITZ=47.0C GPU=44.0C MAX=47.0C`.
- **Step 8a — Explicit `auto` (`W_CL_FANAUTO 0x0F`):**
  - `FANINFO1`: `0x00302958` (`duty=88/255 34.5%`, `temp1=41C`, `temp2=48C`), `0xCE=88`, `0xD0..D1=[03 d7]` (`2194 RPM` BE)
  - `FANINFO2`: `0x002d2747` (`duty=71/255 27.8%`, `temp1=39C`, `temp2=45C`), `0xCF=71`, `0xD2..D3=[03 d8]` (`2191 RPM` BE)
- **Step 8b — Manual 60% duty (`W_CL_FANSPEED 0x009999`, `153/255` on Fan 1 & Fan 2 for 6 s):**
  - Live temperatures (`t=1s..6s`): stayed between `47.0C..50.0C` (`MAX=50.0C`, far below `85 C` abort).
  - `t=2s`: `FANINFO1=0x00312999` (`duty=153/255 60.0%`, `temp2=49C`), `FANINFO2=0x002e2899` (`duty=153/255 60.0%`, `temp2=46C`); `0xCE=153`, `0xCF=153`, `0xD0..D1=[02 0f]` (**`4091 RPM`** BE), `0xD2..D3=[02 15]` (**`4045 RPM`** BE).
  - `t=5s`: `FANINFO1=0x00312999` (`duty=153/255 60.0%`, `temp2=49C`), `FANINFO2=0x002c2899` (`duty=153/255 60.0%`, `temp2=44C`); `0xCE=153`, `0xCF=153`, `0xD0..D1=[02 11]` (**`4076 RPM`** BE), `0xD2..D3=[02 15]` (**`4045 RPM`** BE).
- **Step 8c — Restore `auto` (`W_CL_FANAUTO 0x0F`, verified after 3 s):**
  - `FANINFO1=0x00302a55` (`duty=85/255 33.3%`, `temp2=48C`), `FANINFO2=0x002c2847` (`duty=71/255 27.8%`, `temp2=44C`).
  - `0xD0..D1=[03 3c]` (spinning down to **`2604 RPM`** BE), `0xD2..D3=[03 d6]` (**`2196 RPM`** BE).
- **Step 8d — Performance / DPTF Profile Switching (`W_CL_PERF_PROFILE` -> `_DSM 0x79` subcmd `0x19`):**
  - `W_CL_PERF_PROFILE(0)` (quiet), `W_CL_PERF_PROFILE(2)` (performance), `W_CL_PERF_PROFILE(3)` (balanced/entertainment) all returned `0` (success).
  - Post-profile telemetry: `FANINFO1=0x00302a54` (`duty=84/255 32.9%`, `0xD0..D1=[03 48]` -> **`2567 RPM`** BE), `FANINFO2=0x002c2847` (`duty=71/255 27.8%`, `0xD2..D3=[03 d8]` -> **`2191 RPM`** BE).
- **User acoustic confirmation:** `"all are working great and properly"`.

### 2.7 Cleanup Trap (`tools/emergency-reset.sh`)
- Executed automatically on exit (`exit code was 0`):
  - Restored `/dev/tuxedo_io` fans -> `auto (0x0F)` and perf profile -> `3` (`balanced/entertainment`).
  - Cleanly unloaded all 5 out-of-tree modules (`tuxedo_io`, `clevo_wmi`, `clevo_acpi`, `tuxedo_keyboard`, `tuxedo_compatibility_check`).
  - Completed with zero errors.

---

## 3. Verified Clevo RPM Tach Formula & Driver Architecture Findings

### 3.1 Exact Tach-to-RPM Formula (`0xD0..0xD3` and `_DSM 0x0C` `PK0C`)
Cross-checking `step2_test.log` against `research/clevo_repos/` and `recon/acpi/extracted/dsdt.dsl` settles the tach encoding on `Acer Aspire A715-79G` (`BIOS 1.14RA1`, `EC 7.13`):

1. **Byte Order is Big-Endian (`(b[0] << 8) | b[1]`):**
   - Verified in `clevo-acpi-dkms/src/hwmon.c:25-28` (`(ec_read(0xd0) << 8) + ec_read(0xd1)`), `opendchu/dchu_hwmon.c:42` (`((u16)b[hi] << 8) | b[hi+1]`; note its `le=true` parameter name is a misnomer in `dchu_hwmon.c` because `b[hi]` is shifted `<< 8`), `open-uniwill-cc/uwccd/clevo/manager.py:68` (`(b[2+2*i] << 8) | b[3+2*i]`), and `AspireSense/src/Hardware/AcerInsydeBridge.cs:120-121`.
   - In `dsdt.dsl:103593-103594`, `PK0C` copies `EC.RPM1` (`0xD0..0xD1`) and `EC.RPM2` (`0xD2..0xD3`) directly into `BUFF[0x02..0x05]`.
   - In `step2_test.log`, moving from `27.8%` to `60.0%` duty and back to `auto` caused byte 0 (`0x03 -> 0x02 -> 0x03`) to track the coarse period and byte 1 (`0xd7 -> 0x0f -> 0x11 -> 0x3c -> 0x48`) to track fine steps. Treating those bytes as little-endian (`60M/LE`) produced physically impossible values (`15617 RPM` at `60%` duty and `3905 RPM` while spinning down at `33.3%`).
2. **Conversion Constant (`2156220 / be16`):**
   - `clevo-acpi-dkms/src/hwmon.c:31` (matching `system76-dkms`, `clevo-xsm-wmi`, `clevo-indicator`): **`2156220 / raw_be16`**.
   - `opendchu/dchu_hwmon.c:25-54`: `DIV_ROUND_CLOSEST_ULL(35940 * 60, 1 * raw_be16)` (`2156400 / raw_be16`, derived from `60 / (5.565217e-05 * raw) * 2`).
   - `open-uniwill-cc/uwccd/clevo/manager.py:32`: `RPM_K = 2156250` (`2156250 // raw_be16`).
   - All three constants agree within **0–1 RPM** (< `0.01%`) across the entire operating range:

| `step2_test.log` Phase | Duty (F1 / F2) | Raw `0xD0..D1` / `0xD2..D3` | `BE16` | `round(2156220 / BE16)` | `2156220 // BE16` | `round(2156400 / BE16)` | Rejected `60M / LE16` |
|---|---|---|---|---|---|---|---|
| `[1]` Pre-load idle | `27.8%` / `27.8%` | `[03 d5]` / `[03 d5]` | `981` / `981` | **2198** / **2198** | `2197` / `2197` | `2198` / `2198` | `1100` / `1100` |
| `[7]` Telemetry idle | `27.8%` / `27.8%` | `[03 d8]` / `[03 d8]` | `984` / `984` | **2191** / **2191** | `2191` / `2191` | `2191` / `2191` | `1085` / `1085` |
| `[8a]` Explicit auto | `34.5%` / `27.8%` | `[03 d7]` / `[03 d8]` | `983` / `984` | **2194** / **2191** | `2193` / `2191` | `2194` / `2191` | `1090` / `1085` |
| `[8b]` Manual 60% (`t=2s`) | `60.0%` / `60.0%` | `[02 0f]` / `[02 15]` | `527` / `533` | **4091** / **4045** | `4091` / `4045` | `4092` / `4046` | `15617` / `11157` |
| `[8b]` Manual 60% (`t=5s`) | `60.0%` / `60.0%` | `[02 11]` / `[02 15]` | `529` / `533` | **4076** / **4045** | `4076` / `4045` | `4076` / `4046` | `13780` / `11157` |
| `[8c]` Auto restore (`+3s`) | `33.3%` / `27.8%` | `[03 3c]` / `[03 d6]` | `828` / `982` | **2604** / **2196** | `2604` / `2195` | `2604` / `2196` | `3905` / `1095` |
| `[8d]` Post-profile | `32.9%` / `27.8%` | `[03 48]` / `[03 d8]` | `840` / `984` | **2567** / **2191** | `2566` / `2191` | `2567` / `2191` | `3255` / `1085` |

### 3.2 `tuxedo-drivers` Feature Inspection (Read-Only Source Audit)
1. **Fan RPM Readout Gap in `tuxedo_io` v0.3.9:**
   - `tuxedo_io.c:312-323` and `tuxedo_io_ioctl.h:46-48` only expose `R_CL_FANINFO1/2/3` (`_DSM 0x63/0x64/0x6e` -> duty + 2 temps). `tuxedo_io` does **not** call `_DSM 0x0C` (`PK0C`) and the Clevo modules do **not** register any `hwmon` device.
   - **Phase 4/5 Design Options:**
     - **Option 1 (Preferred):** Add a read-only `hwmon` (`fan1_input`, `fan2_input` via `_DSM 0x0C` `PK0C` using `2156220 / be16`) and a `clevo-acpi-dkms`-style **15 s in-kernel dead-man's-switch fan watchdog** (`_DSM 0x69 0x0F`) to our local `driver/` module + DKMS config.
     - **Option 2 (Userspace RO fallback):** In the root `ccd.py` daemon, read `/sys/kernel/debug/ec/ec0/io` (strictly `ec_sys` RO, `write_support=N`) offsets `0xD0..0xD3` with `2156220 / be16` when no `hwmon` `fan*_input` is exposed.
2. **Performance Profile (`W_CL_PERF_PROFILE` vs `platform_profile`):**
   - The 5 loaded Clevo modules (`tuxedo_compatibility_check`, `tuxedo_keyboard`, `clevo_acpi`, `clevo_wmi`, `tuxedo_io`) contain **zero** references to `platform_profile` (`/sys/firmware/acpi/platform_profile` stays absent; only Uniwill `tuxedo_nb04`/`tuxedo_nb05` implement `platform_profile` in `tuxedo-drivers`).
   - Instead, `tuxedo_io` exposes `W_CL_PERF_PROFILE` (`_DSM 0x79` subcmd `0x19` -> `ECMD 0xD8` + DPTF `Notify`), which has **no firmware readback** (daemon/driver must cache the active profile). Note that DSDT `_DSM 0x79` subcmd `0x01` (`ECMD 0xD7`) is also available for discrete EC thermal/fan presets (`0=balanced`, `1=max-fan`, `5=quiet`, `7=performance`).
3. **Hotkey Handling (`_DSM 0x46` -> Keycodes):**
   - `clevo_keyboard.h:984,1096` calls `CLEVO_CMD_SET_EVENTS_ENABLED` (`_DSM 0x46`) on init (and `resume`), setting `DCHU.HKDR = 1` so `EC._Q50` -> `NEVT` stops dropping keyboard-backlight hotkey events.
   - `clevo_keyboard.h:67-107` maps `0x81` (`KEY_KBDILLUMDOWN`), `0x82` (`KEY_KBDILLUMUP`), `0x9F` (`KEY_KBDILLUMTOGGLE`), `0x83` (`KEY_LIGHTS_TOGGLE` + `set_next_color_whole_kb()`), `0x5D`/`0xFC`/`0xFD` (`KEY_F21`), `0x85` (`KEY_RFKILL`), and `0x25` (`fn_lock` toggle).
   - **Minor Phase 4/5/6 Caveats:**
     - Physical `Fn+backlight` key presses were **not** interactively exercised during the 22 s automated `run_step2_test.sh` run; Phase 6 interactive testing must verify `Fn+backlight` live while the driver is loaded.
     - `tuxedo-drivers/src/clevo_acpi.c:191` passes the ACPI `Notify` code `event` rather than `event_value` (returned by `_DSM 0x01`) to `event_callb()`. On `BIOS 1.14RA1`, `_Q50` calls `NEVT(Local0, Local0)` for `0x81/0x82/0x83/0x9F`, so `event == Local0`; however, using `event_value` (or verifying both) is cleaner if any event uses `0xD0`.
     - `clevo_leds.h:81-87` (`color_scaling`) applies `(180*R)/255` and `(200*B)/255` white-balance scaling for `1_ZONE_RGB`.
4. **Known Gaps / Phase 4–5 Recommendations:**
   - Package the patched driver with **DKMS** (user approval required before system-wide `dkms install`) and include `hwmon` `PK0C` RPM readout + 15 s in-kernel dead-man's-switch watchdog (`_DSM 0x69 0x0F`), in addition to daemon/systemd `ExecStopPost=tools/emergency-reset.sh` failsafe.
   - Verify suspend/resume in Phase 6 (noting Ubuntu Launchpad `#2162661` and `clevo_keyboard_resume` / `clevo_leds_resume` state restoration).

---

## 4. Phase 3 Gate — Per-Feature Support Matrix

| Feature | Status | Verified Mechanism / Path |
|---|---|---|
| **Keyboard brightness** | `WORKS (Path B — patched tuxedo-drivers: clevo_acpi + tuxedo_keyboard)` | `CLV0001._DSM 0x0D` detected `KBTP=0x06` (`1_ZONE_RGB`); `/sys/class/leds/rgb:kbd_backlight/brightness` (`0..255`) calls `_DSM 0x67` (`0xF4`/`0xE0`). Verified `0 -> 127 -> 255` in `step2_test.log` & user confirmed. |
| **Keyboard color** | `WORKS (Path B — patched tuxedo-drivers: clevo_acpi + tuxedo_keyboard)` | `/sys/class/leds/rgb:kbd_backlight/multi_intensity` (`multi_index: red green blue`) calls `_DSM 0x67` (`0xF0_BB_RR_GG` -> `ECMD 0xCA`). Verified Red, Green, Blue, White in `step2_test.log` & user confirmed. |
| **Fan mode** | `WORKS (Path B — patched tuxedo-drivers: clevo_acpi + tuxedo_io)` | `/dev/tuxedo_io` `W_CL_FANSPEED` (`_DSM 0x68`) & `W_CL_FANAUTO` (`_DSM 0x69 0x0F`) control Fan 1 (CPU) & Fan 2 (GPU) duty `0..255` (Fan 3 absent). Verified `auto -> 60% (153/255) -> auto` in `step2_test.log`. |
| **Fan RPM readout** | `WORKS (Path B / EC RO — ec_sys RO 0xD0..0xD3; Phase 4/5: PK0C hwmon)` | `tuxedo_io` v0.3.9 exposes duty+temps (`R_CL_FANINFO1/2`) only. Live RPM verified via RO `ec_sys` (`write_support=N`) `0xD0..D3` with `2156220 / be16` (`~2191 -> 4091/4045 -> 2604/2196 RPM`). Phase 4/5 plan: add `_DSM 0x0C` (`PK0C`) `hwmon` `fan*_input` (with `ec_sys` RO fallback). |
| **Temperature readout** | `WORKS (Path A + Path B — coretemp, acpitz, nvme, nvidia-smi + R_CL_FANINFO1/2)` | Stock `hwmon` (`coretemp`, `acpitz_0`, `nvme`, `iwlwifi_1_6`) + `nvidia-smi` + `/dev/tuxedo_io` `R_CL_FANINFO1/2` (`temp1`, `temp2`). All verified in Phase 1 & `step2_test.log`. |
| **Performance profile** | `WORKS (Path B — tuxedo_io W_CL_PERF_PROFILE / _DSM 0x79)` | `/dev/tuxedo_io` `W_CL_PERF_PROFILE` (`_DSM 0x79` subcmd `0x19`: `0`=quiet, `1`=powersave, `2`=perf, `3`=balanced/entertainment) verified `0/2/3` in `step2_test.log`. (`/sys/firmware/acpi/platform_profile` is absent; no hardware readback, state must be tracked in daemon/driver.) |
| **Battery limit** | `WORKS (Path B — tuxedo_keyboard FlexiCharger hook on BAT0)` | `clevo_keyboard.h` registered `TUXEDO Flexicharger Extension` (`_DSM 0x76`/`0x77` & `0x04` `0x1E`/`0x1F`) exposing `/sys/class/power_supply/BAT0/charge_control_{start,end}_threshold`, `*_available_thresholds`, and `charge_type`. (Presence verified in `step2_test.log`; threshold write test optional in Phase 6.) |
