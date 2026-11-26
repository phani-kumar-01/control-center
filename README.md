# Control Center for Acer Aspire 7 A715-79G (Linux)

A Linux hardware control center (kernel driver, daemon, CLI, and GTK4/libadwaita + tray GUI) for the **Acer Aspire 7 A715-79G** (Clevo/Insyde `CLV0001` / `ABBC0F6D` ODM platform).

## Verified Target Hardware & Environment

- **Laptop:** Acer Aspire 7 (`Aspire A715-79G`, Version `1.14`)
- **BIOS / EC:** `INSYDE Corp. 1.14RA1` (`09/08/2025`, EC Revision `7.13`)
- **CPU / GPU:** Intel Core 5 210H + NVIDIA GeForce RTX 4050 Max-Q / Mobile (`595.99.02`)
- **OS / Kernel:** Ubuntu 26.04.1 LTS (`7.0.0-38-generic`, `SecureBoot disabled`)

## Features (Verified in Phase 3 Hardware Testing)

- **Keyboard Backlight (`1_ZONE_RGB`, `KBTP=0x06`):** Full brightness (`0..255`), RGB color control via `/sys/class/leds/rgb:kbd_backlight`, `fn_lock`, and `Fn` backlight hotkeys (`_DSM 0x46`).
- **Fan Control & Safety Watchdog:** Dual-fan manual duty (`0..255`), firmware `auto` mode, custom hysteresis/ramp fan curve (daemon), 15-second in-kernel dead-man's-switch watchdog (`_DSM 0x69 0x0F`) in `tuxedo_io`, plus `tools/emergency-reset.sh`.
- **Hardware Monitoring (`hwmon`):** Read-only `clevo_acpi` hwmon exposing `fan1_input`, `fan2_input` (`_DSM 0x0C` `PK0C` via `2156220 / be16`), `temp1_input`, `temp2_input`, `pwm1`, and `pwm2`, alongside `coretemp`, `nvme`, `acpitz_0`, and `nvidia-smi`.
- **Performance Profiles:** `quiet`, `balanced`, `performance`, and `powersave` via `/dev/tuxedo_io` (`_DSM 0x79` subcmd `0x19`).
- **Battery Charge Limit:** FlexiCharger start/end thresholds on `/sys/class/power_supply/BAT0/`.

## Directory Layout

- `recon/` — Phase 1 read-only system reconnaissance & ACPI DSDT/SSDT analysis
- `research/` — Phase 2 kernel/GitHub findings (`FINDINGS.md`)
- `driver/` — Patched `tuxedo-drivers` (v4.25.2) with A715-79G DMI match, `clevo_acpi` `hwmon`, 15 s `tuxedo_io` fan watchdog, `dkms.conf`, and `tuxedo-drivers-a715-79g.patch`
- `tools/` — `emergency-reset.sh` (restores EC auto/balanced & unloads modules) and `collect-diagnostics.sh`
- `core/` — Python hardware abstraction backends & fan curve engine
- `daemon/` — Systemd root daemon (`ccd.py`) & `config.toml`
- `cli/` — `cc` command-line client
- `gui/` — GTK4/libadwaita dashboard & StatusNotifierItem tray icon
- `packaging/` — Systemd unit, D-Bus, Polkit, udev, desktop entry, `install.sh`, `uninstall.sh`
- `tests/` — Unit & mock backend tests
- `docs/` — Hardware notes, troubleshooting, and test results

## License

This project is licensed under the **GNU General Public License v3.0 (GPLv3)** — see [`LICENSE`](LICENSE). The bundled kernel modules under `driver/tuxedo-drivers/` retain their upstream `GPL-2.0+` license (`driver/tuxedo-drivers/LICENSE`).
