# Phase 3 Gate — Per-Feature Support Matrix (`Acer Aspire A715-79G`, `BIOS 1.14RA1`)

**Verified Against:**
- `recon/SUMMARY.md` & `recon/acpi/DSDT_ANALYSIS.md`
- `driver/step2_test.log` (224 lines, exit code `0`, `kernel 7.0.0-38-generic`)
- `driver/TEST_LOG.md` & `driver/README.md`

---

## Per-Feature Support Table

| Feature | Gate Status | Hardware / Driver Path | Verified Evidence & Phase 4/5 Notes |
|---|---|---|---|
| **Keyboard brightness** | `WORKS (Path B — patched tuxedo-drivers)` | `CLV0001` (`clevo_acpi.ko`) + `tuxedo_keyboard.ko` -> `/sys/class/leds/rgb:kbd_backlight/brightness` (`0..255`) | `PK0D[0x0f]` returned `KBTP=0x06` (`1_ZONE_RGB`). Brightness sweep `0 -> 127 -> 255` (`_DSM 0x67` `0xF4`/`0xE0`) verified in `step2_test.log` & confirmed by user (`"all are working great and properly"`). |
| **Keyboard color** | `WORKS (Path B — patched tuxedo-drivers)` | `CLV0001` (`clevo_acpi.ko`) + `tuxedo_keyboard.ko` -> `/sys/class/leds/rgb:kbd_backlight/multi_intensity` (`red green blue`) | `_DSM 0x67` (`0xF0_BB_RR_GG` -> `ECMD 0xCA`). Red `(255 0 0)`, Green `(0 255 0)`, Blue `(0 0 255)`, White `(255 255 255)` verified in `step2_test.log` & confirmed by user. (`clevo_leds.h` applies `180/255` R, `200/255` B scaling.) |
| **Fan mode** | `WORKS (Path B — patched tuxedo-drivers)` | `/dev/tuxedo_io` `W_CL_FANSPEED` (`_DSM 0x68`) & `W_CL_FANAUTO` (`_DSM 0x69 0x0F`) | Verified 2 physical fans (`FANINFO3` absent): `auto` (`27.8%`/`34.5%`) -> `60%` (`153/255`) -> `auto` (`33.3%`/`27.8%`). Phase 4/5 plan: add `clevo-acpi-dkms`-style 15 s in-kernel watchdog + daemon/systemd `emergency-reset.sh` failsafe. |
| **Fan RPM readout** | `WORKS (Path B / EC RO — ec_sys RO 0xD0..0xD3; Phase 4/5: PK0C hwmon)` | Currently: `ec_sys` RO (`write_support=N`) `0xD0..D3` with `2156220 / be16`; Phase 4/5 target: `_DSM 0x0C` (`PK0C`) `hwmon` `fan1_input`/`fan2_input` | `tuxedo_io` v0.3.9 only exposes duty+temps (`R_CL_FANINFO1/2`), not RPM. Cross-check of `clevo-acpi-dkms`, `opendchu`, and `open-uniwill-cc` confirms BE16 tach period with `~2156220 / be16`: `2191–2198 RPM` (27.8%) -> `4076–4091 / 4045 RPM` (60%) -> `2604 / 2196 RPM` (auto). |
| **Temperature readout** | `WORKS (Path A + Path B — hwmon + nvidia-smi + R_CL_FANINFO1/2)` | Path A: `coretemp`, `acpitz_0`, `nvme`, `iwlwifi_1_6`, `nvidia-smi`; Path B: `R_CL_FANINFO1/2` (`temp1`, `temp2`) | All readouts verified live in Phase 1 (`temps_load.csv` max `64.0 C`) and `step2_test.log` (`43.0–50.0 C`). |
| **Performance profile** | `WORKS (Path B — tuxedo_io W_CL_PERF_PROFILE)` | `/dev/tuxedo_io` `W_CL_PERF_PROFILE` (`_DSM 0x79` subcmd `0x19` -> `ECMD 0xD8` + DPTF notify) | Tested `0` (quiet), `2` (performance), `3` (balanced/entertainment) in `step2_test.log`; all succeeded. `/sys/firmware/acpi/platform_profile` is absent; no hardware readback exists, so daemon caches active state. |
| **Battery limit** | `WORKS (Path B — tuxedo_keyboard FlexiCharger hook)` | `/sys/class/power_supply/BAT0/charge_control_{start,end}_threshold`, `*_available_thresholds`, `charge_type` | `TUXEDO Flexicharger Extension` (`_DSM 0x76`/`0x77` & `0x04` `0x1E`/`0x1F`) registered cleanly on `BAT0` in `step2_test.log`. (Threshold write verification planned in Phase 6.) |

---

## Gate Summary & Scope for Phases 4–5
- **All 7 required features in `AGENT_WORKFLOW.md` §4 Phase 3 Gate are `WORKS`** (`0` `NOT POSSIBLE`, `0` `READ-ONLY`-only blockers).
- **No GRUB `acpi_osi` changes, no `ec_sys write_support=1`, and no Secure Boot changes are needed.**
- **Pause before permanent system modification (Safety Rule 9):** System-wide DKMS installation (`dkms install`), systemd service enablement, udev/polkit rules, and optional `clevo_acpi` `hwmon` (`PK0C`) + 15 s watchdog extension require user approval at the Phase 3 Gate before Phase 4/5 deployment.
