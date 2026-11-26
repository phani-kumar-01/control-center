# Phase 1 Environment Recon Summary — Acer Aspire 7 A715-79G

**Initial Recon (UTC):** `2026-11-26T01:30:17Z`
**Updated with Privileged & Load Recon (UTC):** `2026-11-26T01:46:00Z`
**Mode:** Strictly Read-Only (no hardware writes, no GRUB/modprobe config changes, `ec_sys` loaded read-only with `write_support=N`)
**Output Directory:** `/home/candy/control/control-center/recon/`

---

## 1. System Identity & BIOS

Verified from `dmidecode.txt` (`dmidecode 3.6`, SMBIOS 3.4) and `system_identity.txt` (`/sys/class/dmi/id/` & `lscpu`):

| Field | Value | Source |
|---|---|---|
| `Manufacturer` / `sys_vendor` | `Acer` | `dmidecode.txt`, `system_identity.txt` |
| `Product Name` / `product_name` | `Aspire A715-79G` | `dmidecode.txt`, `system_identity.txt` |
| `Version` / `product_version` | `1.14` | `dmidecode.txt`, `system_identity.txt` |
| `Family` / `product_family` | `Aspire 7` | `dmidecode.txt`, `system_identity.txt` |
| `SKU Number` / `product_sku` | `0000000000000000` | `dmidecode.txt`, `system_identity.txt` |
| `Serial Number` | `[REDACTED]` | `dmidecode.txt` |
| `UUID` | `[REDACTED]` | `dmidecode.txt` |
| `Base Board` | `Acer` / `Aspire A715-79G` / `1.14` | `dmidecode.txt` |
| `BIOS Vendor` | `INSYDE Corp.` | `dmidecode.txt` |
| `BIOS Version` | `1.14RA1` | `dmidecode.txt` |
| `BIOS Release Date` | `09/08/2025` | `dmidecode.txt` |
| `BIOS Revision` | `7.14` (`ROM Size: 16 MB`, `Runtime Size: 128 kB`) | `dmidecode.txt` |
| `Firmware Revision` (EC) | `7.13` | `dmidecode.txt` |
| CPU | `Intel(R) Core(TM) 5 210H` (8 cores / 12 logical CPUs) | `system_identity.txt` |
| OS | `Ubuntu 26.04.1 LTS (Resolute Raccoon)` | `system_identity.txt` |

*Note (Section 2.1):* Whether a newer BIOS exists on Acer's support site will be checked read-only during Phase 2 web research (do not flash BIOS/EC firmware without explicit approval).

---

## 2. Kernel, Boot, Security & Tools

- **Kernel:** `7.0.0-38-generic #38-Ubuntu SMP PREEMPT_DYNAMIC Fri Sep  4 09:10:14 UTC 2026 x86_64`
- **Cmdline:** `BOOT_IMAGE=/boot/vmlinuz-7.0.0-38-generic root=UUID=[REDACTED] ro quiet splash crashkernel=2G-4G:320M,4G-32G:512M,32G-64G:1024M,64G-128G:2048M,128G-:4096M`
- **Secure Boot:** `SecureBoot disabled` (`mokutil --sb-state`)
- **Section 2 Tools Installed (verified):**
  - `dkms`: `/usr/sbin/dkms` (`dkms status` is empty — no DKMS modules currently installed)
  - `stress-ng`: `/usr/bin/stress-ng`
  - `sensors`: `/usr/bin/sensors` (`lm-sensors`)
  - `i2cdetect`: `/usr/sbin/i2cdetect` (`i2c-tools`)
  - `brightnessctl`: `/usr/bin/brightnessctl`
  - `fancontrol`: `/usr/sbin/fancontrol`
- **Relevant loaded modules:** `wmi`, `mxm_wmi`, `platform_profile` (used by `processor_thermal_soc_slider`), `coretemp`, `intel_hid`, `int3400_thermal`, `int3403_thermal`, `processor_thermal_device*`, `i915`, `nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm`, `ec_sys` (`write_support=N`).
- **`acer_wmi` status:** NOT loaded. `modinfo acer_wmi` shows it only aliases WMI GUIDs `676AA15E-6A47-4D9F-A2CC-1E6D18D14026`, `6AF4F258-B401-42FD-BE91-3D4AC2D7C0D3`, and `67C3371D-95A3-4C37-BB61-DD47B491DAAB` — **none of which exist on this machine**.

---

## 3. WMI GUIDs, ACPI Platform State & `dmesg` Findings

Complete list of WMI devices under `/sys/bus/wmi/devices/`:

| WMI GUID | Type | Detail | Bus Path |
|---|---|---|---|
| `ABBC0F6B-8EA1-11D1-00A0-C90629100000` | `event` | `notify_id: D0`, `instance_count: 1` | `PNP0C14:01` |
| `ABBC0F6C-8EA1-11D1-00A0-C90629100000` | `event` | `notify_id: D1`, `instance_count: 1` | `PNP0C14:01` |
| `ABBC0F6D-8EA1-11D1-00A0-C90629100000` | `method` | `object_id: BB`, `instance_count: 1` | `PNP0C14:01` |
| `F6CB5C3C-9CAE-4EBD-B577-931EA32A2CC0` | `method` | `object_id: MX`, `instance_count: 1` | `PNP0C14:00` |

- `/sys/bus/wmi/drivers/` is **empty** (no WMI driver is bound to any of these GUIDs).
- **Notable ACPI platform devices:** `CLV0001:00` (`MODALIAS=acpi:CLV0001:`) and `CLV0002:00` (`MODALIAS=acpi:CLV0002:`) are present in `/sys/devices/platform/` with no bound driver (alongside `PNP0C14:01`, `INTC1051:00`, `INTC1055:00`, `INTC10A0:00`). *Note for Phase 2:* `ABBC0F6B/C/D` and `CLV0001/2` are strong indicators of a Clevo/Insyde ODM ACPI/WMI design rather than standard Acer Predator/Nitro WMI GUIDs.
- **`platform_profile` & `platform_profile_choices`:** **ABSENT**
  - `/sys/firmware/acpi/platform_profile*`: No such file or directory
  - `/sys/class/platform-profile/`: Empty directory
- **`dmesg_filtered.txt` & `journalctl -k -b` findings:**
  - **No `acer`, `acer_wmi`, `clevo`, `predator`, `nitro`, or `fan` driver/device messages** appear in `dmesg_filtered.txt`.
  - **EC initialization:** Cleanly initialized at `EC_CMD/EC_SC=0x66, EC_DATA=0x62`, `GPE=0x6e` (`\_SB_.PC00.LPCB.EC__: Boot DSDT EC used to handle transactions` and events).
  - **Thermal subsystem:** Registered kernel thermal governors (`fair_share`, `bang_bang`, `step_wise`, `user_space`, `power_allocator`) and `acpi LNXTHERM:00` (`Thermal Zone [TZ0] (38 C)` -> `thermal_zone0`).
  - **ACPI BIOS errors:** `AE_NOT_FOUND` on `\_SB.PC00.MHBR`, `\_SB.PTID.PBAR`, `^^RP28.PXSX.WIST` (aborting `\_SB.PC00.CNVW.IFUN`/`_DSM`), and `\_TZ.ETMD` (aborting `\_SB.IETM._OSC`).
  - **Boot module taint/oops trace (`4.021s`):** `dmesg_filtered.txt` includes a `Modules linked in:` / `Code:` dump at `t=4.021s` during early module probe (`spi_nor(+)`, `iwlmvm(+)`, `nvidia(PO+)`, `i915(+)`) that matched the grep filter via `wmi`/`thermal` module names.

---

## 4. Keyboard Backlight, Input, USB/HID & I2C Discovery

- **`/sys/class/leds/` devices found:**
  - `enp3s0-0::lan`, `enp3s0-1::lan`, `enp3s0-2::lan`
  - `input4::capslock`, `input4::numlock`, `input4::scrolllock` (internal PS/2 `AT Translated Set 2 keyboard`)
  - `input6::capslock`, `input6::compose`, `input6::kana`, `input6::numlock`, `input6::scrolllock` (external USB `3554:fc04 2.4G Receiver`)
  - `mmc0::`, `phy0-led`
- **`brightnessctl.txt` (`brightnessctl --list`):** Lists 14 devices total — `intel_backlight` (`2400 / 48000`, `5%`) plus the 13 `leds` devices above. Confirms **no `*::kbd_backlight` LED device exists**.
- **`multi_intensity` / `multi_index`:** **ABSENT** on every `/sys/class/leds/*` entry.
- **Section 2.4b Physical `Fn` + keyboard backlight check (User Observation):** User tested all `Fn` hotkeys and reported: `"all fn + 12 buttons works expect keyboard backlight"` — every `Fn+F1..F12` hotkey works **except** the keyboard backlight key, which does nothing (backlight remains stuck on blue).
- **USB (`lsusb`):** No internal USB keyboard or RGB controller detected (`3554:fc04` is an external 2.4G wireless receiver, `04f2:b729` is Chicony USB2.0 Camera, `8087:0026` is Intel AX201 Bluetooth).
- **`/dev/hidraw*`:** `hidraw0` & `hidraw1` belong to `3554:FC04` (2.4G Receiver); `hidraw2` belongs to `i2c-FTCS1000:01` (`2808:0101` Touchpad).
- **`i2cdetect.txt` (`sudo i2cdetect -l`, 14 buses):**
  - `i2c-0`: `Synopsys DesignWare I2C adapter` (`i2c`)
  - `i2c-1`: `SMBus I801 adapter at 0000:00:1f.4` (`smbus`)
  - `i2c-2`..`i2c-10`: `i915 gmbus dpa`, `dpb`, `dpc`, `tc1`..`tc6` (`i2c`)
  - `i2c-11`: `AUX A/DDI A/PHY A` (`i2c`)
  - `i2c-12`, `i2c-13`: `NVIDIA i2c adapter 1` and `3` at `1:00.0` (`i2c`)

---

## 5. Fans, Sensors & Thermal State

- **`sensors_detect.txt` (`sudo sensors-detect --auto`, v3.6.2):**
  - Detected `Intel digital thermal sensor` (`coretemp`, confidence 9) as the only sensor driver.
  - Super-I/O probe at `0x2e/0x2f`: `National Semiconductor/ITE` -> **`Found unknown chip with ID 0x5570`** (consistent with an ITE IT5570 Embedded Controller / Super-I/O; no Linux hwmon driver bound). Probes at `0x4e/0x4f` and ISA `0x290` found nothing.
  - I2C/SMBus probe on `i2c-1` (`SMBus I801` `8086:51a3`): client at `0x50` handled by `ee1004` (RAM SPD EEPROM, not a thermal/fan sensor).
- **`sensors.txt` (`sensors`):**
  - `iwlwifi_1_6-virtual-0`: `temp1` (`+39.0°C`)
  - `BAT0-acpi-0`: `in0` (`15.22 V`), `curr1` (`1.03 A`)
  - `coretemp-isa-0000`: `Package id 0` (`+46.0°C`), `Core 0, 4, 8, 12, 20, 21, 22, 23` (`+37.0°C` to `+44.0°C`, `high/crit = +100.0°C`)
  - `nvme-pci-0200`: `Composite` (`+34.9°C`), `Sensor 1` (`+34.9°C`), `Sensor 2` (`+31.9°C`)
  - `acpitz_0-acpi-0`: `temp1` (`+49.0°C`)
- **`hwmon` devices verified in `/sys/class/hwmon/` (including post-`sensors-detect` check):**
  - `hwmon0`: `AC`
  - `hwmon1`: `acpitz_0`
  - `hwmon2`: `BAT0` (`curr1_input`, `in0_input`)
  - `hwmon3`: `nvme` (`Composite`, `Sensor 1`, `Sensor 2`)
  - `hwmon4`: `iwlwifi_1_6`
  - `hwmon5`: `coretemp` (`Package id 0`, `Core 0..23`)
- **`fan*_input` and hwmon `pwm*`:** **STILL ABSENT** — zero `fan*_input` files anywhere in `/sys/class/hwmon/` or `sensors.txt`, and zero hwmon `pwm*` files. (`/sys/devices/platform/INTC1055:00/pwm/pwmchip0` is the Intel `tigerlake-pinctrl` GPIO/PWM chip, not a fan controller.)
- **`thermal_zone0..7`:** `acpitz`, `INT3400 Thermal`, `SEN2`, `SEN3`, `TCPU`, `TCPU_PCI`, `iwlwifi_1`, `x86_pkg_temp`. All have `policy=user_space`.
- **`thermald`:** `active (running)` (`--systemd --dbus-enable --adaptive`).

---

## 6. GPU & NVIDIA Driver State

- **iGPU:** `Intel Corporation Raptor Lake-P [Intel Graphics] [8086:a7ab]` — driver `i915`.
- **dGPU:** `NVIDIA Corporation AD107M [GeForce RTX 4050 Max-Q / Mobile] [10de:28a1]` (Subsystem `1025:1900`, Acer) — proprietary driver `nvidia` **595.99.02** (CUDA 13.2).
- **`nvidia-smi` readout:** Functional. Initial temp `41 C`, Fan `N/A`, Pwr `14W / 35W`, `Target Temperature: 82 C`.

---

## 7. EC Visibility Status (`ec_dump_idle.hex`)

- `ec_sys` kernel module is loaded (`ec_sys 12288 0`) with `write_support=N` (confirmed via `/sys/module/ec_sys/parameters/write_support` — strictly read-only).
- `/sys/kernel/debug/ec/` remains root-only (`Permission denied` without `sudo`).
- **`recon/ec_dump_idle.hex` verification:** Cleanly captured read-only via `sudo hexdump -C /sys/kernel/debug/ec/ec0/io`.
  - **Size:** `17` lines (`1,196` bytes text), covering the complete **256-byte EC register space (`0x00`–`0xFF`, EOF `00000100`)** (`240` explicit hex bytes + `*` collapsing `0xB0`–`0xBF` all-zero row = `256` bytes).
  - **Non-zero summary:** **91 non-zero bytes** across `0x00–0x3F`, `0x4A–0x69` (includes ASCII strings `dcd1-`, `p71-V-3SMP-VK-3`, `LIONVK-3`), `0x86`, `0x92–0x94`, and `0xC8–0xFF`.

---

## 8. Thermal Baseline Results (`temps_idle.csv` & `temps_load.csv`)

### Idle Baseline (`recon/temps_idle.csv` — 24 samples @ 5s, 119.0 s: `01:28:10Z`–`01:30:09Z`)
All idle temperatures are well below the 80 C safety limit (and below 60 C):

| Sensor | Min (C) | Avg (C) | Max (C) | Samples |
|---|---|---|---|---|
| CPU Package (`coretemp`) | 45.0 | 46.42 | 47.0 | 24 |
| `acpitz` (`thermal_zone0`) | 46.0 | 47.17 | 48.0 | 24 |
| `TCPU` (`thermal_zone4`) | 45.0 | 46.46 | 49.0 | 24 |
| `SEN2` (`thermal_zone2`) | 39.0 | 40.88 | 42.0 | 24 |
| `SEN3` (`thermal_zone3`) | 39.0 | 40.08 | 41.0 | 24 |
| NVMe Composite | 30.9 | 33.27 | 35.9 | 24 |
| NVIDIA RTX 4050 (`nvidia-smi`) | 42.0 | 42.25 | 44.0 | 24 |
| Fan RPM | `NA` | `NA` | `NA` | 24 |

### Load Baseline (`recon/temps_load.csv` — 27 samples over 60.0 s: `01:38:48Z`–`01:39:48Z`, `stress-ng --cpu 12 --timeout 60s`)
No overheating occurred; all temperatures remained well below the **90 C** load safety limit:

| Sensor | Start (C) | End (C) | Min (C) | Avg (C) | Max (C) | Samples |
|---|---|---|---|---|---|---|
| CPU Package (`coretemp`) | 46.0 | 63.0 | 46.0 | 60.07 | 63.0 | 27 |
| `acpitz` (`thermal_zone0`) | 48.0 | 64.0 | 48.0 | 60.11 | 64.0 | 27 |
| `TCPU` (`thermal_zone4`) | 46.0 | 63.0 | 46.0 | 60.00 | 64.0 | 27 |
| `SEN2` (`thermal_zone2`) | 40.0 | 45.0 | 40.0 | 42.26 | 45.0 | 27 |
| `SEN3` (`thermal_zone3`) | 39.0 | 42.0 | 39.0 | 40.30 | 42.0 | 27 |
| NVMe Composite | 35.9 | 31.9 | 30.9 | 33.12 | 35.9 | 27 |
| NVIDIA RTX 4050 (`nvidia-smi`) | 43.0 | 47.0 | 43.0 | 45.04 | 47.0 | 27 |
| Fan RPM | `NA` | `NA` | `NA` | `NA` | `NA` | 27 |

- **User Acoustic & Fan Observation:** The user reported `"done i did not heaer"` — fans were **not heard spinning up** during the 60s CPU stress test.
- **Fan RPM Readout:** `NA` (`temps_load.csv` has no `fan_rpm` column because zero `fan*_input` / `pwm*` nodes exist in sysfs/hwmon and `nvidia-smi` reports `N/A`).
- **Thermal Assessment:** Because peak CPU Package reached only **63.0 C** (`acpitz`/`TCPU` **64.0 C**, GPU **47.0 C**) — 26 C below the 90 C safety threshold — the machine did **not** overheat during the 60s CPU load test. However, combined with the lack of audible fan spin-up and the absence of `acer_wmi`, `platform_profile`, and `fan*_input`, it remains an open question for Phases 2–3 whether the firmware fan curve keeps fans off below ~65 C or whether firmware thermal/fan control requires a Clevo/Insyde WMI/ACPI driver or EC init.

---

## 9. Phase 1 Gate Status & Open User Questions

All Phase 1 recon artifacts are now complete and verified:
- **Section 2.4b (`Fn`+backlight) resolved:** User confirmed all `Fn` hotkeys work except keyboard backlight (stuck blue).
- **Thermal safety check passed:** Idle max 49.0 C (< 80 C); 60s CPU load max 64.0 C (< 90 C). No overheating.
- **Remaining open item for Gate 1:** Explicit user approval to proceed to **Phase 2 (GitHub & Kernel Research — read-only web/`git clone` investigation into Clevo/Insyde WMI GUIDs `ABBC0F6B/C/D`, `CLV0001/2`, ITE `0x5570` EC, Acer A715-79G / OpenRGB #4869 / Linuwu-Sense / nbfc-linux / mainline `acer-wmi` & `clevo` drivers, and checking Acer's site for newer BIOS versions)**.

---

## 10. Recon Files Inventory

- `/home/candy/control/control-center/recon/system_identity.txt`
- `/home/candy/control/control-center/recon/dmidecode.txt`
- `/home/candy/control/control-center/recon/boot_kernel.txt`
- `/home/candy/control/control-center/recon/wmi_acpi.txt`
- `/home/candy/control/control-center/recon/dmesg_filtered.txt`
- `/home/candy/control/control-center/recon/kbd_backlight.txt`
- `/home/candy/control/control-center/recon/brightnessctl.txt`
- `/home/candy/control/control-center/recon/i2cdetect.txt`
- `/home/candy/control/control-center/recon/fans_sensors.txt`
- `/home/candy/control/control-center/recon/sensors_detect.txt`
- `/home/candy/control/control-center/recon/sensors.txt`
- `/home/candy/control/control-center/recon/gpu.txt`
- `/home/candy/control/control-center/recon/ec_visibility.txt`
- `/home/candy/control/control-center/recon/ec_dump_idle.hex`
- `/home/candy/control/control-center/recon/temps_idle.csv`
- `/home/candy/control/control-center/recon/temps_load.csv`
- `/home/candy/control/control-center/recon/SUMMARY.md`
