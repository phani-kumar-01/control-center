# Phase 2 Research Notes: Mainline Kernel, Bugtrackers, Arch Wiki & Clevo/Insyde WMI/ACPI Drivers

**Prepared by:** Worker B (`worker_phase2_kernel_clevo`)  
**Timestamp (UTC):** `2026-11-26T02:05:00Z`  
**Mode:** Strictly Read-Only (no installs, no module loading, no hardware writes)  
**Target Hardware (from `recon/SUMMARY.md`):**
- **System:** `Acer` / `Aspire A715-79G` (Version `1.14`, BIOS `INSYDE Corp. 1.14RA1` 09/08/2025, EC Firmware `7.13`, CPU `Intel Core 5 210H`, dGPU `NVIDIA RTX 4050 Mobile [10de:28a1]`)
- **Kernel / OS:** `7.0.0-38-generic` (Ubuntu 26.04.1 LTS), `SecureBoot disabled`
- **WMI GUIDs present:**
  - `ABBC0F6B-8EA1-11D1-00A0-C90629100000` (event, `notify_id: D0`, `PNP0C14:01`)
  - `ABBC0F6C-8EA1-11D1-00A0-C90629100000` (event, `notify_id: D1`, `PNP0C14:01`)
  - `ABBC0F6D-8EA1-11D1-00A0-C90629100000` (method, `object_id: BB`, `PNP0C14:01`)
  - `F6CB5C3C-9CAE-4EBD-B577-931EA32A2CC0` (method, `object_id: MX`, `PNP0C14:00` — NVIDIA `mxm_wmi`)
- **ACPI Platform Devices present (unbound):** `CLV0001:00`, `CLV0002:00`
- **Super-I/O / EC:** ITE `0x5570` (`IT5570`) probed at `0x2e/0x2f`; ACPI EC at `0x62/0x66` (`GPE=0x6e`, `ec_sys` loaded RO)
- **Microsoft Store App (`9p1v7skxg6h5`):** **"Fn hotkeys and OSD"** by **CLEVO CO.** (`https://apps.microsoft.com/detail/9p1v7skxg6h5`) — confirms the Acer Aspire 7 A715-79G is a **Clevo ODM chassis** (NP50RNA / NP5x/NP7x family) running Insyde BIOS + Clevo DCHU firmware, NOT an Acer Predator/Nitro WMI board.

---

## 1. Mainline Linux Kernel (`acer-wmi.c`, `linux-next`, `platform/x86/*`) & Local Kernel `7.0.0-38-generic`

### 1.1 Local Kernel (`7.0.0-38-generic`)
Inspected `/lib/modules/7.0.0-38-generic/kernel/drivers/platform/x86/`:
- **`acer-wmi.ko.zst`** (`modinfo acer-wmi`):
  - Only binds to WMI GUID aliases:
    - `wmi:676AA15E-6A47-4D9F-A2CC-1E6D18D14026` (`ACERWMID_EVENT_GUID`)
    - `wmi:6AF4F258-B401-42FD-BE91-3D4AC2D7C0D3` (`WMID_GUID1`)
    - `wmi:67C3371D-95A3-4C37-BB61-DD47B491DAAB` (`AMW0_GUID1`)
  - **None of these GUIDs exist on A715-79G**, so `acer_wmi` does not autoload or bind.
- **`system76_acpi.ko.zst`** (`modinfo system76_acpi`):
  - Only aliases `acpi*:17761776:*` (System76 open EC firmware), NOT `CLV0001` or `ABBC0F6D`.
- **`tuxedo/nb04/tuxedo_nb04_wmi_ab.ko.zst`**:
  - Present in local kernel 7.0.0-38-generic, but only binds to `80C9BAA6-AC48-4538-9234-9F81A55E7C85` (TUXEDO NB04 LampArray HID WMI), NOT `ABBC0F6D` or `CLV0001`.
- **No `clevo*` module exists in mainline or Ubuntu `7.0.0-38-generic`.**

### 1.2 Mainline (`torvalds/linux`) and `linux-next` Inspection
Checked `torvalds/linux` (`https://github.com/torvalds/linux`) and `linux-next` (`https://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git/log/drivers/platform/x86/acer-wmi.c`):
- **Recent `acer-wmi.c` commits (2025–2026):**
  - `0cc5153f1339` (2025-10-16): `platform/x86: acer-wmi: Add fan control support`
  - `d727823c134a` (2025-10-16): `Enable fan control for PH16-72 and PT14-51`
  - `45cf02f298f3` (2025-10-16): `Add support for PHN16-72`
  - `40901719bd28` (2026-01-08): `Extend support for Acer Nitro AN515-58`
  - `4bee415640e9` / `3bd07ec2893b` (2026-08-19): `split hwmon from platform profile quirk` / `enable hwmon on Aspire A315-58G`
  - `9319f8ff8394` (2026-09-20): `Add support for Acer Nitro ANV15-51`
  - `164de1f81266` (2026-10-17): `Add support for Acer Nitro AN16-41`
  - `9b5a2d0e91c8` (`linux-next`): `Keep Bluetooth powered on Aspire E5-573`
- **`acer-wmi.c` GUIDs & DMI Table:**
  - Uses Acer WMI GUIDs (`AMW0_GUID1/2`, `WMID_GUID1..4`, `ACERWMID_EVENT_GUID`). Gaming/fan/hwmon/platform_profile quirks (`Aspire A315-58G`, `Nitro AN16-41`, `AN515-58`, `ANV15-51`, `Predator PH315-53`, `PHN16-71`, `PH16-71/72`, `PHN16-72`, `PH18-71`, `PT14-51`) all rely on Acer's `WMID_GUID4` (`7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56`).
  - **Neither `Aspire A715-79G`, `ABBC0F6B/C/D`, `CLV0001`, `CLV0002`, nor `IT5570` appears anywhere in mainline `torvalds/linux` or `linux-next`.**
- **`drivers/platform/x86/acer-wmi-battery.c`:**
  - Binds to `79772EC5-04B1-4BFD-843C-61E7F77B6CC9` (`ACER_BATTERY_GUID`) and DMI-whitelists older/native-Acer Aspire models including **`Aspire A715-42G`** (not `A715-79G`). `79772EC5-...` is absent on `A715-79G`.
- **Mainline Conclusion:** Upgrading to a newer mainline or HWE kernel will **not** bring `acer-wmi` support for `A715-79G`, because this chassis uses Clevo WMI/ACPI interfaces (`ABBC0F6B/C/D` & `CLV0001`), not Acer's WMI GUIDs.

---

## 2. Linux Kernel Bugzilla & Ubuntu Launchpad

Queried `https://bugzilla.kernel.org/rest/bug` and `https://api.launchpad.net/1.0/bugs`:

### 2.1 Kernel Bugzilla — Direct Match Found!
- **Bug #222019** (`https://bugzilla.kernel.org/show_bug.cgi?id=222019`) — **Status: `NEW`**, filed `2026-09-16` by Muhammed Anas (`drivers_platform_x86`):
  - **Summary:** `"acer-wmi: no device matching for Acer Aspire A715-79G - EC automatic fan control inactive at boot"`
  - **Reported Hardware:** Acer Aspire A715-79G (BIOS `1.07.01TACI`, ITE EC), WMI GUIDs `ABBC0F6B / ABBC0F6C / ABBC0F6D`, kernel 7.1.13 / 7.2.5 (Fedora 44).
  - **Symptom Reported:** With no driver claiming the GUIDs, the EC keeps its default quiet thermal profile; fans stay quiet/off at low/moderate temperatures (`60–75 °C`). Fan starts only via `Fn+1` (Cooler Boost) or writing EC profile via ACPI `SCMD`.
  - **Workaround Noted in Bug:** Issuing `SCMD(0x69, BIT(2-1))` = balanced profile at boot makes fans run ~1300 RPM idle and ramp under load.
- Queries for `"CLV0001"` on Bugzilla returned 0 bugs; `"ABBC0F6D"` returned Bug #222019; `"Aspire 7"` returned older unrelated Acer Aspire bugs (`#51041`–`#211585`).

### 2.2 Ubuntu Launchpad
- **Bug #2162661** (`https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2162661`) — **Status: `New`**, filed `2026-08-02`:
  - **Title:** `"suspend/resume doesn't work on 7.0.0-28-generic"` on **Acer Aspire A715-79G** (BIOS `1.07.01TACI`, Ubuntu 26.04, `7.0.0-28-generic`).
  - **Key Note:** Reporter stated suspend/resume worked on `7.0.0-14-generic` and hung with black screen on resume on `7.0.0-28-generic` even with Intel graphics (`prime-select intel`). Good caveat for testing suspend/resume hooks on our `7.0.0-38-generic` kernel!
- **Bug #2164843** (`https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2164843`) — Predator `PH315-54` Turbo button (unrelated WMI).
- Queries for `"Aspire 7 fan"`, `"CLV0001"`, `"ABBC0F6D"` on Launchpad returned 0 bugs.

---

## 3. Arch Wiki (`Laptop/Acer`, `Clevo`)

Inspected `https://wiki.archlinux.org/title/Laptop/Acer` and queried `wiki.archlinux.org/api.php`:
- **No dedicated Arch Wiki page** exists for `Aspire 7`, `A715`, `A715-79G`, `CLV0001`, or `ABBC0F6D`.
- **`Laptop/Acer` Aspire table** lists older/other Aspire models (up to `Aspire AG15-42P`, `Aspire A515-57`, `Aspire A315-510P`) — **does not list `A715-79G`**.
- **Documented Acer/Clevo Linux Quirks from `Laptop/Acer`:**
  1. **Gaming mode/fan monitoring:** Recommends `acer_wmi.predator_v4=1` / `acer_wmi.cycle_gaming_thermal_profile` (since kernel 6.8+) — **not applicable to A715-79G** because `acer_wmi` does not bind to Clevo GUIDs.
  2. **Flaky Secure Boot / UEFI NVRAM:** Warning on Acer BIOSes requiring `.efi` binaries to be trusted or avoiding corrupting ACPI/NVRAM settings (already `SecureBoot disabled` on our unit).
  3. **NVMe/VMD hidden BIOS menu:** `Ctrl+S` in Main BIOS tab (or Supervisor password) reveals VMD/AHCI settings (already running Linux cleanly on NVMe here).
  4. **`acpi_osi` parameters:** Older Aspire models sometimes used `acpi_osi=Linux` or `acpi_osi=! acpi_osi="Windows 2009"` for hotkeys/suspend, though on our unit `Fn+F1..F12` already work except keyboard backlight, and Windows uses `CLV0001` `_DSM` / `InsydeDCHU.dll` rather than OS-string gating.
- **Arch Wiki Clevo pages** (`Clevo P650RS`, `Clevo N15xZU`, `Clevo NL51RU`, `Clevo W840SU`) point to `tuxedo-keyboard` / `tuxedo-drivers` and `clevo-indicator` / `nbfc-linux` for fan & keyboard control.

---

## 4. Broad GitHub Search Findings

Searched GitHub via `gh search repos` and `gh search code` for `A715-79G`, `ABBC0F6D-8EA1-11D1-00A0-C90629100000`, `CLV0001`, `CLV0002`, `acer aspire fan`, `nitrosense linux`, `predatorsense linux`, `IT5570`, `clevo-xsm-wmi`, `clevo-indicator`, `tuxedo-drivers`, `system76-acpi`:

### 4.1 A715-79G-Specific Repositories Discovered
| Repo | URL | Last Commit Hash & Date | License | Platform / Mechanism |
|---|---|---|---|---|
| **Atul977/Aspire-A715-79G-LinuxPackages** | `https://github.com/Atul977/Aspire-A715-79G-LinuxPackages` | `3fbae86cdca0c8c26a177a19083d367cefc07a5a` (2026-11-08) | `GPL-2.0-or-later` (PKGBUILDs) | Arch packaging of patched `Atul977/tuxedo-drivers` + `tailord` + `tailor-gui` for **Acer Aspire A715-79G** & Acer ALG. Enables RGB keyboard, fan curves, and power profiles via `tuxedo-drivers` (`clevo_acpi`/`clevo_wmi`/`tuxedo_keyboard`/`tuxedo_io`). |
| **the3rdchild/nixos-config** (`Reference/acer-aspire-A715-79G/acer-ec`) | `https://github.com/the3rdchild/nixos-config` | `fb0e6276ef7d21240cabb931a2f791eb7ac90711` (2026-11-21) | `GPL-2.0` | **Custom Linux kernel modules (`acer_ec_core`, `acer_fanctl`, `acer_ec_kbd`) specifically reverse-engineered for Acer Aspire A715-79G** (tested Fedora 44). Documents DSDT, `SCMD 0x68/0x69`, `ECMD 0xC0/0xC1/0xCA`, and EC SystemMemory `0xFE0B0100` offsets! |
| **J-525/Acer-Aspire-A715-79G-KeyBoard** | `https://github.com/J-525/Acer-Aspire-A715-79G-KeyBoard` | `11a5f24154a0df460af6aa6813afbd7d6413e635` (2026-07-28) | None specified | Linux `ec_sys` (`write_support=1`) shell scripts (`rgb.sh`, `brightness.sh`) writing EC mailbox `0xF8..0xFD` command `0xCA` (zone `0x03` RGB, subcmd `0x06` brightness). |
| **mayanksaini002/KeyLume** | `https://github.com/mayanksaini002/KeyLume` | `0dcdd173d058d8865f2e7ef1b5fd1335c5abd5c5` (2026-11-16) | `MIT` | Windows C# RGB controller tested on **Acer Aspire 7 A715-79G / NP50RNA**. Uses `InsydeDCHU.dll` `SetDCHU_Data(103 /* 0x67 */, buf[4])` with **single-zone `0xF0` in GRB byte order**, `0xF4` brightness, `0x00,0x10/0xA0` power on/off. |
| **netfreakkk/AspireSense** | `https://github.com/netfreakkk/AspireSense` | `68c0117b42c503fd9f3f9293ed7bd991b33974f4` (2026-11-04) | `MIT` | Windows C# fan/thermal controller for **Acer Aspire 7 A715-79G** using `InsydeDCHU.dll`: `GetDCHU_Data_Buffer(12 /* 0x0C */)` for RPM/duty/temp, `GetDCHU_Data_Buffer(13 /* 0x0D */)` + `SetDCHU_Data(14 /* 0x0E */)` for fan table, `SetDCHU_Data(121 /* 0x79 */)` for modes (`0`=auto, `1`, `3`, `6`=custom) and offset (`14`). |
| **mogantipraneet/Acer-Aspire-7-A715-79G-RGB** | `https://github.com/mogantipraneet/Acer-Aspire-7-A715-79G-RGB` | `97a8d8bc58a6af51578c41c7451a0681c20b31f2` (2026-10-11) | None specified | Windows Python RGB controller using `InsydeDCHU.dll` `SetDCHU_Data(0x67, [G, R, B, Zone])` (`0xF0`–`0xF2`, `0xFF`). |
| **anshkr95/acer-a715-79g-rgb** | `https://github.com/anshkr95/acer-a715-79g-rgb` | `16a90262b7aa1e18895fc736a1e26bbf9c2a6a25` (2026-10-29) | None specified | README-only repo documenting A715-79G RGB. |

### 4.2 Other Notable Repos (Distinguishing Incompatible Acer Variants vs Clevo/IT5570)
- **`gwkalp/Acer-Aspire-Fan`** (`https://github.com/gwkalp/Acer-Aspire-Fan`, commit `aa09e131e5f1db00f92cb477fdcc00f941f7b779`, 2026-11-23, `GPL-3.0`): Built for **Acer Aspire 7 A715-43G** (Ryzen 5625U) using `Linuwu-Sense` and Acer WMI GUID `7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56`. **INCOMPATIBLE with A715-79G** (README explicitly checks `ls /sys/bus/wmi/devices/ | grep 7A4DDFE7`, which is absent on A715-79G).
- **`passiveEndeavour/it5570-fan` / `LaVashikk/Lecoo-Control-Center`**: Direct Super-I/O `0x2e/0x2f` drivers for mini-PCs/Lecoo laptops with `IT5570`. **High risk / likely non-applicable**: `the3rdchild` tested LPC SIO probes at `0x2e/0x2f` and `0x4e/0x4f` on A715-79G and read `0xFF`; Clevo/Insyde firmware routes EC access through ACPI (`CLV0001` `_DSM` / `0x62/0x66`), not raw LPC SIO RAM.

---

## 5. Clevo/Insyde WMI & ACPI Driver Investigation (`research/clevo_repos/`)

All repositories below were cloned read-only into `/home/candy/control/control-center/research/clevo_repos/` and inspected directly.

### 5.1 Repository Comparison Matrix

| Repository | URL | Last Commit & Date | License | Hardware Binding (`GUID` / `HID` / `DMI`) | Interfaces Exposed | Key Commands / Methods Used | Compatibility with A715-79G |
|---|---|---|---|---|---|---|---|
| **`tuxedo-drivers`** (upstream) | `https://github.com/tuxedocomputers/tuxedo-drivers` (mirror of GitLab) | `07a681fc52c4ae0c90991247c1c1d8a62740eda4` (2026-11-13, v4.25.2) | `GPL-2.0+` / `GPL-2.0-or-later` | `clevo_acpi.ko` binds ACPI HID **`CLV0001`** (`_DSM` `93f224e4-fbdc-4bbf-add6-db71bdc0afad`, rev 0). `clevo_wmi.ko` binds WMI **`ABBC0F6B`** + checks **`ABBC0F6D`** + tests `0x52`. **HOWEVER**, `tuxedo_keyboard.ko` calls **`tuxedo_is_compatible()`** (`DMI_SYS_VENDOR/BOARD_VENDOR/CHASSIS_VENDOR == "TUXEDO"`; CPU fallback `#if < 6.12` is compiled out on kernel 7.0!). | `/sys/class/leds/rgb:kbd_backlight` (or `white:kbd_backlight`), `/sys/devices/platform/tuxedo_keyboard/`, `/dev/tuxedo_io` (`ioctl` for `tailord`/TCC). *Does NOT create `hwmon` fan nodes or `platform_profile` for Clevo.* | `0x52`/`0x0D`/`0x7A` (kbd type), `0x67` (`0xE0` on/off, `0xF0..0xF3` RGB GRB, `0xF4` brightness), `0x63`/`0x64`/`0x6E` (fan info), `0x68` (set fan duty), `0x69` (set fan auto), `0x79`/`0x19` (perf profile), `0x46` (enable events). | **Blocked out-of-the-box by `tuxedo_is_compatible()`** because `Manufacturer=Acer`. |
| **`Atul977/tuxedo-drivers`** & **`nick42d/clevo-drivers`** | `https://github.com/nick42d/clevo-drivers` (and `Atul977/tuxedo-drivers` commit `96ae0c8eb6ed`) | `8f449632280c727dcf7b3c2af542f15b09813f64` (2026-10-31) / `96ae0c8eb6ed` (2025-10-26) | `GPL-2.0+` | Patches `tuxedo_is_compatible()` to **`return true;`**. Then `clevo_acpi` binds to `CLV0001` (taking priority over `clevo_wmi` in `clevo_keyboard_add_interface()`). No Acer DMI check needed. | Same as `tuxedo-drivers` (`/sys/class/leds/rgb:kbd_backlight`, `/dev/tuxedo_io`). | Same as `tuxedo-drivers` (`CLV0001` `_DSM`). | **Reported WORKING on A715-79G** (Atul977 README + patched `tuxedo-drivers`). Needs verification on our BIOS `1.14RA1` (see caveat in §5.2). |
| **`opendchu`** | `https://github.com/hUwUtao/opendchu` | `e971462550f7dd4786c68ff5cb069c56d9c6e19c` (2025-09-13) | `GPL-2.0-only` | `dchu_core.ko` calls `acpi_dev_get_first_match_dev("CLV0001", NULL, -1)`. **NO DMI check at all.** Uses `_DSM` UUID `93f224e4-fbdc-4bbf-add6-db71bdc0afad` (rev 1). | Standard Linux **`hwmon` (`/sys/class/hwmon/hwmonX/` `name=dchu`)**: `fan1..3_input`, `pwm1..3`, `temp1..3_input`, `fan_mode` (`auto/max/silent/maxq/custom/turbo`); **`/sys/class/leds/dchu::kbd_backlight`** (white 0..5 only). | `_DSM 0x0C` (12: read fans/duty/temps), `_DSM 0x79` (121: set `fan_mode`), `_DSM 61/39` (white kbd brightness only). | **Binds cleanly to `CLV0001` with zero DMI gate**; great for standard `hwmon` fan/temp readout + `fan_mode`, but **no RGB** (`dchu_leds` is white-only). |
| **`clevo-acpi-dkms`** (fork of `pop-os/system76-dkms`) | `https://github.com/arbitrary-string/clevo-acpi-dkms` | `666aa69e567f9e9929657d2e5643de40ac11eae7` (2026-08-23) | `GPL-2.0-or-later` | Binds ACPI HID **`CLV0001`**, **PLUS strict `system76_dmi_table` DMI check** (only `System76` models and `L55xJNP_N_Mx`). Refuses to probe on `Acer`/`Aspire A715-79G` unless patched. | Multi-zone RGB LEDs (`leds`), `performance_mode` sysfs, continuous per-fan duty sysfs with **15s in-kernel watchdog dead-man's-switch** (auto-releases on timeout or `rmmod`). | `_DSM` `93f224e4-...`: `0x63`/`0x64`/`0x6e`, `0x68`, `0x69` (`0x0F` release), `0x79` (`(1<<24)\|mode`), `0x67` RGB. | **Blocked by `system76_dmi_table`** unless `Aspire A715-79G` is added; excellent safety/watchdog code reference. |
| **`pop-os/system76-dkms`** | `https://github.com/pop-os/system76-dkms` | `90ea5e69af3bbc64ad373c7b8fec8c1197e8bd4f` (2026-07-29) | `GPL-2.0-or-later` | `clevo-acpi.c` binds `CLV0001` + System76 DMI whitelist; `system76.c` binds `ABBC0F6B`/`ABBC0F6D` + `s76_dmi_table` (`DMI_SYS_VENDOR == "System76"`). | `hwmon`, `leds`, sparse keymap. | `ABBC0F6D` `WMBB` / `CLV0001` `_DSM`. | **Blocked by strict `System76` DMI whitelist.** |
| **`pop-os/system76-acpi-dkms`** | `https://github.com/pop-os/system76-acpi-dkms` | `20cc5e3a52a2d86b10a7a49dd62062613d27b7bd` (2026-08-31) | `GPL-2.0-or-later` | Only binds ACPI HID `17761776` (System76 open EC). | N/A | N/A | **Incompatible** (`17761776` absent). |
| **`rafaelgieschke/clevo-xsm-wmi`** | `https://github.com/rafaelgieschke/clevo-xsm-wmi` | `55dd011a226a0d9e8a44eee4cf52d92efbcceeb1` (2025-09-14) | `GPL` | Checks WMI **`ABBC0F6B`** + **`ABBC0F6D`** (`wmi_has_guid`). `dmi_check_system(clevo_xsm_dmi_table)` is **non-fatal** (logs if matched, still probes without DMI match!). | Platform sysfs (`kb_brightness`, `kb_state`, `kb_mode`, `kb_color`), `leds`, `hwmon` (`fan1/2_input`, `pwm1/2`, `pwm1/2_enable`). | `wmi_evaluate_method(ABBC0F6D, 0x01, method_id)` (`WMBB`) only — **no `CLV0001` `_DSM` support**. | **Risky/Incomplete:** Only uses legacy `ABBC0F6D` WMI (`WMBB` instance `0x01`, whereas `tuxedo` uses `0x00`), lacks `CLV0001` `_DSM` and 1-zone RGB `0x52` detection. |
| **`open-uniwill-cc`** (`uwcc.ko` + `uwccd/clevo/`) | `https://github.com/aspidovss/open-uniwill-cc` | `48fc0aa8800383f695fad6589e6c5d4f449010a2` (2026-11-23) | `MIT` (userspace) / `GPL-2.0` (`kernel/uwcc.c`) | `uwcc.ko` binds `CLV0001` (`_DSM` `93f224e4-...`) or `ABBC0F6D` **with NO DMI check** (`UWCC_IOC_CLEVO`). | `/dev/uwcc` char device + Python daemon (`uwccd`), GUI, CLI (`uwccctl`), tray. | Full Clevo DCHU set: `0x04`, `0x0C`, `0x0D`, `0x0E`, `0x10`, `0x46`, `0x52`, `0x60`, `0x67`, `0x79`, `0x7A`. | **High compatibility potential** (`CLV0001` + no DMI check), though Clevo module is marked experimental. |
| **`clevo-indicator` & `clevo-axioo-dual-fan-linux`** | `https://github.com/SkyLandTW/clevo-indicator`, `https://github.com/hajilok/clevo-axioo-dual-fan-linux` | `67facb8ebb3a5b098f11618205e4f42353c6981e` (2017-04-26) / `d24f82842872eb59f87ffa1e5250631626650d83` (2026-08-01) | Unlicense / `GPL-2.0` | **Userspace direct I/O ports `0x62/0x66`** (`ioperm`), **no WMI/ACPI/DMI check**. | Tray applet + CLI. | EC command `0x99` (fan 1/2 duty, `0xff` auto), reads EC `0x07`, `0xCD`, `0xCE`, `0xD0..0xD3`. | **Unsafe / Unverified:** Bypasses kernel `acpi_ec` lock via raw `inb/outb` `0x62/0x66`, and `the3rdchild` showed A715-79G EC uses `SCMD`/`ECMD` (`0xF8..0xFD`), not legacy `0x99`. |

### 5.2 Critical Cross-Check: `recon/ec_dump_idle.hex` vs A715-79G EC Layout
Cross-checking our Phase 1 read-only EC dump (`recon/ec_dump_idle.hex`) against `the3rdchild/nixos-config` (`acer_fanctl.c` & `reverse-engineering.md`) confirms **byte-for-byte alignment** of the EC SystemMemory / RAM register map:

| EC Offset | Field (`the3rdchild`) | Observed Value in `recon/ec_dump_idle.hex` | Verification against Phase 1 Sensors |
|---|---|---|---|
| `0x07` | `TMP` (ACPI temp °C) | `0x31` = **49 °C** | Exact match to `sensors.txt`: `acpitz_0-acpi-0: temp1 (+49.0°C)` |
| `0xCE` | `DUT1` (Fan 1 / CPU duty 0–255) | `0x47` = **71 / 255 (~28%)** | Matches quiet idle curve |
| `0xCF` | `DUT2` (Fan 2 / GPU duty 0–255) | `0x47` = **71 / 255 (~28%)** | Matches quiet idle curve |
| `0xD0..0xD1` | `RPM1` (LE u16 tach period) | `0x03 0xd8` → `0xD803` = `55299` | `60,000,000 / 55299` ≈ **1085 RPM** per `the3rdchild` (`ioread16` LE); legacy Clevo `2156220 / ((hi<<8)\|lo)` would give 2191 RPM (unlikely for silent idle) |
| `0xD2..0xD3` | `RPM2` (LE u16 tach period) | `0x03 0xdb` → `0xDB03` = `56067` | `60,000,000 / 56067` ≈ **1070 RPM** per `the3rdchild` (`ioread16` LE) |
| `0xD4..0xD5` | `RPM4` (unused slot) | `0x00 0x00` | `0` (unused) |
| `0xE0..0xE1` | `RPM3` (unused slot) | `0x00 0x00` | `0` (unused) |
| `0xD7..0xDB` | `DTHL`, `DTBP`, `AIRP`, `WINF`, `RINF` | `0f`, `63`, `00`, `05`, `91` | Non-zero EC state bytes present |

### 5.3 Key Open Firmware Question for Phase 3 (Important Discrepancy to Verify Read-Only!)
Two verified A715-79G sources agree on fan/profile control but differ on **which ACPI/EC path drives the keyboard RGB** on different A715-79G BIOS/sub-models:
1. **DCHU `_DSM` Path (`CLV0001` `_DSM` UUID `93f224e4-fbdc-4bbf-add6-db71bdc0afad`):**
   - Used by `tuxedo-drivers` (patched `Atul977` / `nick42d`), `opendchu`, `clevo-acpi-dkms`, `open-uniwill-cc`, `KeyLume`, `AspireSense`, and `Acer-Aspire-7-A715-79G-RGB`.
   - Commands: `0x67` (RGB GRB `0xF0..0xF2`, brightness `0xF4`, power `0xE0`), `0x63/0x64/0x6E` & `0x0C` (fan read), `0x68` (fan duty), `0x69` (fan auto/profile), `0x79` (perf/fan mode).
2. **Direct `SCMD` / EC Mailbox Path (`the3rdchild` + `J-525`):**
   - `the3rdchild` (on `BIOS 1.07.01TACI` / `A715-59G` & `A715-79G`) reported that `SCMD 0x67` (`WMBB`) was dropped by its EC firmware, whereas `SCMD 0x68/0x69` worked for fans/profiles and direct EC mailbox `0xF8..0xFD` command `0xCA` (subcmd `0x06` brightness, `zone 0x03` `[B, R, G, 0]`) worked for keyboard RGB.
- **Resolution in Phase 3 (Path D / Path B):** Before loading any module or writing any EC register, **read-only DSDT (`acpidump` + `iasl -d`) + `/sys/bus/wmi/bmof/*` (`bmfdec`) inspection** on our exact `BIOS 1.14RA1` will immediately show what `CLV0001._DSM` and `WMBB`/`SCMD` actually implement in our DSDT!
