# Phase 2 Research Notes — Acer Repositories, OpenRGB, NBFC, Windows App & BIOS Check

**Worker:** `worker_phase2_acer_repos` (Phase 2 Research Worker A)
**Date (UTC):** `2026-11-26`
**Mode:** Strictly Read-Only (no installs, no module loading, no hardware writes, no BIOS or app binary downloads)
**Cloned Study Copies Directory:** `/home/candy/control/control-center/research/repos/`
**Phase 1 Baseline Reference:** `/home/candy/control/control-center/recon/SUMMARY.md`

---

## Phase 1 Hardware Baseline Reminder (Compatibility Target)

From `recon/SUMMARY.md`:
- **System / Board:** `Acer` / `Aspire A715-79G` (`Version: 1.14`, `BIOS: INSYDE Corp. 1.14RA1` dated `09/08/2025`, EC `7.13`)
- **WMI GUIDs present on machine (`/sys/bus/wmi/devices/`):**
  - `ABBC0F6B-8EA1-11D1-00A0-C90629100000` (`event`, `notify_id: D0`, `PNP0C14:01`)
  - `ABBC0F6C-8EA1-11D1-00A0-C90629100000` (`event`, `notify_id: D1`, `PNP0C14:01`)
  - `ABBC0F6D-8EA1-11D1-00A0-C90629100000` (`method`, `object_id: BB`, `PNP0C14:01`)
  - `F6CB5C3C-9CAE-4EBD-B577-931EA32A2CC0` (`method`, `object_id: MX`, `PNP0C14:00`)
- **ACPI Platform Devices:** `CLV0001:00` (`MODALIAS=acpi:CLV0001:`), `CLV0002:00` (`MODALIAS=acpi:CLV0002:`)
- **EC / Super-I/O:** ITE chip ID `0x5570` (`IT5570`) at `0x2e/0x2f`; `ec_sys` read-only 256-byte space at `0x66/0x62`
- **Other:** No `acer_wmi` loaded, no `platform_profile`, no `*::kbd_backlight`, no internal USB keyboard HID, no `fan*_input` or `pwm*`.

---

## Summary Compatibility Matrix (Targets 1–10)

| # | Target / Source | Compatible with A715-79G? | Reason / Key Finding |
|---|---|---|---|
| 1 | `Linuwu-Sense` (upstream & `Div-Linuwu-Sense` & forks) | **NO** | Requires Acer `WMID_GUID1..5` / `AMW0_GUID1..2`; none exist on A715-79G (`ABBC0F6D` / `CLV0001` unsupported). |
| 2 | `DAMX` (`Div-Acer-Manager-Max`) | **NO** (arch reference only) | Wraps `Div-Linuwu-Sense` sysfs + `platform_profile` + `ENEK5130` HID (`0CF2:5130`), none present on A715-79G. |
| 3 | `JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module` | **NO** | Extends `acer-wmi`; requires `WMID_GUID3`/`WMID_GUID4` (`7A4DDFE7-...`), absent on A715-79G. |
| 4 | `RuiGuilherme/acer-helios-300-rgb-keyboard-linux-module` | **NO** | Older Helios 300 fork of `facer`; same missing `WMID_GUID3`/`WMID_GUID4` dependency. |
| 5 | `saeedkhatami/Acer-RGB-Keyboard-Linux-Module-GUI` | **NO** (Repo 404; GUI for `facer`) | Original GitHub user/repo returns HTTP 404. Active equivalent `Abhishumat/facer-gui` wraps `facer-rgb` (`/dev/acer-gkbbl-0`). |
| 6 | `nbfc-linux` | **Partial / Framework Only** | No `A715-79G`, `Clevo`, or `IT5570` config exists. EC access (`ec_sys`/`/dev/port`) and ACPI/Lua paths could work *only if* a register/ACPI map is derived (Path C/D). |
| 7 | `acer-wmi-battery` | **NO** | Requires `WMID_GUID5` (`79772EC5-04B1-4bfd-843C-61E7F77B6CC9`), absent on A715-79G. |
| 8 | OpenRGB GitLab Issue #4869 | **Critical Evidence** | Confirms A715-79G runs **Clevo Control Center** on Windows (single-zone RGB slider, 4 brightness levels + off, sleep timer, CPU/GPU fan %, 4 power profiles, FlexiCharger). No packet captures attached. |
| 9 | Microsoft Store `9p1v7skxg6h5` | **Critical Evidence** | App is **"Fn hotkeys and OSD"** by **CLEVO CO.** (`CLEVOCO.FnhotkeysandOSD`), proving Clevo ODM firmware/software architecture. |
| 10 | Acer Support BIOS Check (`1.14RA1`) | **Unconfirmed online (no CLI access past Akamai)** | Current BIOS is `1.14RA1` (`09/08/2025`). No newer version surfaced in web search; `acer.com` downloads SPA blocks headless `curl`. User browser + SNID check needed to be 100% certain. |

---

## Detailed Findings

### 1. Linuwu-Sense (`0x7375646F/Linuwu-Sense`, `PXDiv/Div-Linuwu-Sense`, and Forks)

#### 1.1 Upstream: `0x7375646F/Linuwu-Sense`
- **URL:** `https://github.com/0x7375646F/Linuwu-Sense`
- **Cloned Path:** `research/repos/Linuwu-Sense`
- **Commit Hash (`HEAD`):** `4483b6c38b9bb963ac9ada9ca476578e0c63cc08`
- **Commit Date:** `2026-10-19 15:07:50 +0545` (`Merge pull request #147 from nghiant03/feat/anv15-52`)
- **License:** `GPL-3.0` (`LICENSE` file; `MODULE_LICENSE("GPL")` in `src/linuwu_sense.c`)

#### 1.2 DAMX-Focused Fork: `PXDiv/Div-Linuwu-Sense`
- **URL:** `https://github.com/PXDiv/Div-Linuwu-Sense`
- **Cloned Path:** `research/repos/Div-Linuwu-Sense`
- **Commit Hash (`HEAD`):** `a02ef398ea04c6a478a590e727683f831e6e08d8`
- **Commit Date:** `2026-11-16 14:04:33 +0530` (`feat(predator): add PHN16-72 back logo support (#20)`)
- **License:** `GPL-3.0` (`LICENSE` file; `DRIVER_VERSION "25.701"` in `src/linuwu_sense.c`)
- **Key Additions over Upstream:** Adds `version` sysfs attribute, `enable_all` module parameter (in addition to `predator_v4` and `nitro_v4`), `nitro_sense_v4_attr_group` (exposing `predator_sense_attrs` under `nitro_sense/`), and `back_logo/color` sysfs group for PHN16-72.

#### 1.3 Other Active Forks Checked (via GitHub API)
- `antman666/Linuwu-Sense` (pushed `2026-11-07T14:25:23Z`, `GPL-3.0`): 58 commits ahead of upstream doing kernel-API cleanup (`sysfs_emit`, `kstrtou8`, header/probe fixes); same Acer WMI GUIDs, no Clevo/A715-79G support.
- `Order52/linuwu-sense-cli` (pushed `2025-08-14T05:55:42Z`, `GPL-3.0`): CLI wrapper around Linuwu-Sense.
- `FelipeFMA/nekro-sense` (listed in GitHub fork list, 11 stars): repository endpoint returned `None`/unavailable via GitHub API.

#### 1.4 Required WMI GUIDs (`src/linuwu_sense.c`)
Both upstream and `Div-Linuwu-Sense` are modified forks of mainline `acer-wmi` and require Acer's ACPI-WMI GUIDs:
- `AMW0_GUID1`: `67C3371D-95A3-4C37-BB61-DD47B491DAAB`
- `AMW0_GUID2`: `431F16ED-0C2B-444C-B267-27DEB140CF9C`
- `WMID_GUID1`: `6AF4F258-B401-42FD-BE91-3D4AC2D7C0D3`
- `WMID_GUID2`: `95764E09-FB56-4E83-B31A-37761F60994A`
- `WMID_GUID3`: `61EF69EA-865C-4BC3-A502-A0DEBA0CB531`
- `WMID_GUID4`: `7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56` (gaming profile, fan behavior/speed, gaming sys info, 4-zone/static RGB KB)
- `WMID_GUID5`: `79772EC5-04B1-4bfd-843C-61E7F77B6CC9` (battery health control methods 20/21)
- `ACERWMID_EVENT_GUID`: `676AA15E-6A47-4D9F-A2CC-1E6D18D14026`

#### 1.5 DMI Match Table
- **Upstream `Linuwu-Sense`:** 56 `DMI_PRODUCT_NAME` entries covering Nitro (`AN16-*`, `AN17-*`, `AN515-*`, `AN517-*`, `ANV15-*`, `ANV16*`), Predator (`PH315-*`, `PHN14-51`, `PHN16-*`, `PH16-72`, `PH18-*`, `PTX17-71`), legacy Aspire (`Aspire 1360`, `1520`, `3100`, `3610`, `5100`, `5610`, `5630`, `5650`, `5680`, `9110`, `AOA110`, `AOA150`, `SW3-016`, `SW5-012`), TravelMate (`2490`, `4200`), and non-Acer DMI quirks.
- **`Div-Linuwu-Sense`:** 35 `DMI_PRODUCT_NAME` entries (subset + `enable_all`/`predator_v4`/`nitro_v4` overrides).
- **Zero matches** for `A715-79G`, `Aspire A715-79G`, `ABBC0F6D`, or `CLV0001`.

#### 1.6 Sysfs Nodes Created
Under `/sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/` (i.e. `/sys/devices/platform/acer-wmi/`):
- `predator_sense/`: `lcd_override`, `fan_speed`, `battery_limiter`, `battery_calibration`, `usb_charging`, `backlight_timeout`, `boot_animation_sound` (+ `version` in `Div-Linuwu-Sense`)
- `nitro_sense/`: `fan_speed`, `battery_limiter`, `battery_calibration`, `usb_charging`, `backlight_timeout` (+ `lcd_override`/`boot_animation_sound`/`version` in `Div-Linuwu-Sense` `nitro_v4`)
- `four_zoned_kb/`: `four_zoned_rgb_mode` (upstream) / `four_zone_mode` (`Div-Linuwu-Sense`), `per_zoned_rgb_mode` (upstream) / `per_zone_mode` (`Div-Linuwu-Sense`)
- `turbo_sense/`: `turbo_state` (upstream)
- `back_logo/`: `color` (`Div-Linuwu-Sense`)

#### 1.7 Compatibility Assessment vs Phase 1 Recon
**Not compatible.** `A715-79G` exposes none of `WMID_GUID1..5`, `AMW0_GUID1..2`, or `ACERWMID_EVENT_GUID`. Forcing `enable_all` or adding a DMI entry cannot bridge a completely different ACPI/WMI namespace (`ABBC0F6B/C/D`, `CLV0001/2`).

---

### 2. DAMX (`PXDiv/Div-Acer-Manager-Max`)

- **URL:** `https://github.com/PXDiv/Div-Acer-Manager-Max`
- **Cloned Path:** `research/repos/Div-Acer-Manager-Max`
- **Commit Hash (`HEAD`):** `3b0f690f3b74a1f5133cae45013a06fa7caf6381`
- **Commit Date:** `2026-11-16 22:45:46 +0530` (`fix(power): preserve state when source detection fails (#297)`)
- **License:** `GPL-3.0` (`LICENSE` file)

#### 2.1 Architecture & Communication with Linuwu-Sense
1. **Desktop GUI (`DivAcerManagerMax/`):** C# / `.NET 9.0` (`TargetFramework: net9.0`) application built with **Avalonia UI 12.0.3**, `LiveChartsCore.SkiaSharpView.Avalonia`, and `Material.Icons.Avalonia`. Uses `DAMXClient.cs` to connect as a non-root user to a Unix domain socket at `/var/run/DAMX.sock` using JSON request/response messages (`ping`, `get_supported_features`, `set_fan_speed`, etc.).
2. **Root Daemon (`DAMM-Daemon/DAMX-Daemon.py`, v0.5.2):** Runs as `root`, persists configuration in `/etc/DAMX_Daemon/config.ini`, logs to `/var/log/DAMX_Daemon_Log.log`, and monitors AC/battery power source (`PowerSourceDetection.py`).
3. **Driver Integration:**
   - Checks `/sys/module/linuwu_sense` and detects `predator_sense` vs `nitro_sense` under `/sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/`.
   - Reads/writes sysfs nodes (`fan_speed`, `backlight_timeout`, `battery_limiter`, `battery_calibration`, `usb_charging`, `lcd_override`, `boot_animation_sound`, `four_zoned_kb/per_zone_mode`, `four_zoned_kb/four_zone_mode`, `back_logo/color`).
   - Reads/writes `/sys/firmware/acpi/platform_profile` and `platform_profile_choices`.
   - Can automatically `rmmod linuwu_sense` and `modprobe linuwu_sense` with `nitro_v4`, `predator_v4`, or `enable_all` if laptop type is unknown.
   - Includes a secondary `HIDIOCSFEATURE` hidraw path for `ENEK5130:00 0CF2:5130` (`HID_ID=0018:00000CF2:00005130`) on newer Nitro/Predator models where `linuwu_sense` RGB sysfs writes have no hardware effect.

#### 2.2 Compatibility Assessment vs Phase 1 Recon
**Not compatible** (`linuwu_sense` WMI GUIDs absent, `platform_profile` absent, no `ENEK5130` hidraw device present). Its daemon + Unix socket + feature-discovery UI design is a useful pattern, though our project uses Python + GTK4/Qt rather than .NET Avalonia.

---

### 3. `JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module`

- **URL:** `https://github.com/JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module`
- **Cloned Path:** `research/repos/acer-predator-turbo-and-rgb-keyboard-linux-module`
- **Commit Hash (`HEAD`):** `e97bb6354e4366c0d97121bedec19d536323108d`
- **Commit Date:** `2026-11-11 17:13:28 +0100` (`Make PH315-55 turbo match PredatorSense (operating modes + GPU overclock)`)
- **License:** `GPL-3.0` (`LICENSE` file; `MODULE_LICENSE("GPL")` in `src/facer.c`)

#### 3.1 WMI/HID Protocol, GUIDs & Model Checks
- **Protocol:** Despite offering userspace Python CLIs (`facer_rgb.py`, `keyboard.py`, `facer_gpu_oc.py`), the underlying driver (`src/facer.c`) does **NOT** use USB/HID. It is a modified `acer-wmi` kernel module that creates two character devices:
  - `/dev/acer-gkbbl-0`: accepts 16-byte dynamic RGB configuration payloads (`GAMING_KBBL_CONFIG_LEN 16`) and calls `WMID_GUID4` method `20` (`ACER_WMID_SET_GAMINGKBBL_METHODID`).
  - `/dev/acer-gkbbl-static-0`: accepts 4-byte static per-zone payloads (`GAMING_KBBL_STATIC_CONFIG_LEN 4`) and calls `WMID_GUID4` method `6` (`ACER_WMID_SET_GAMING_STATIC_LED_METHODID`).
  - Also exposes `rgb_ec_enable` module parameter/quirk and WMI gaming methods `2`, `4`, `5`, `14` (fan behavior), `22`/`23` (misc settings / platform profile / GPU OC).
- **GUIDs Required:** `AMW0_GUID1`, `AMW0_GUID2`, `WMID_GUID1`, `WMID_GUID2`, `WMID_GUID3` (`61EF69EA-...`), `WMID_GUID4` (`7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56`), `ACERWMID_EVENT_GUID`.
- **DMI Model Checks:** 56 `DMI_PRODUCT_NAME` entries (Predator `PH*`/`PT*`, `Nitro AN515-58`, legacy Aspire `1360`–`9110`, `SW3-016`, `SW5-012`, TravelMate). No `A715-79G`, `ABBC0F6D`, or `CLV0001`.

#### 3.2 Compatibility Assessment vs Phase 1 Recon
**Not compatible.** Requires `WMID_GUID3`/`WMID_GUID4` which do not exist on `A715-79G`.

---

### 4. `RuiGuilherme/acer-helios-300-rgb-keyboard-linux-module`

- **URL:** `https://github.com/RuiGuilherme/acer-helios-300-rgb-keyboard-linux-module`
- **Cloned Path:** `research/repos/acer-helios-300-rgb-keyboard-linux-module`
- **Commit Hash (`HEAD`):** `eabc633ea308e4c0237994b3375302da62d45fbc`
- **Commit Date:** `2021-11-13 00:36:05 -0300` (`Merge remote-tracking branch 'JafarAkhondali/main' into main`)
- **License:** `GPL-3.0` (`LICENSE` file; `MODULE_LICENSE("GPL")` in `src/facer.c`)

#### 4.1 Protocol, GUIDs & Compatibility
- Older Helios 300 variant/snapshot of `JafarAkhondali`'s `facer.c` (unmaintained since Nov 2021).
- Uses the exact same `WMID_GUID1..4` / `AMW0_GUID1..2` / `ACERWMID_EVENT_GUID` stack and `/dev/acer-gkbbl-0` + `/dev/acer-gkbbl-static-0` char devices.
- 43 `DMI_PRODUCT_NAME` entries (Predator `PH*`/`PT*` + legacy Aspire/TravelMate/Extensa).
- **Compatibility:** **Not compatible** (same missing `WMID_GUID3`/`WMID_GUID4` on `A715-79G`).

---

### 5. `saeedkhatami/Acer-RGB-Keyboard-Linux-Module-GUI`

- **URL Checked:** `https://github.com/saeedkhatami/Acer-RGB-Keyboard-Linux-Module-GUI`
- **Status:** **HTTP 404 (Not Found)** — both the repository and GitHub user `saeedkhatami` (`https://api.github.com/users/saeedkhatami/repos`) return 404 as of `2026-11-26`.
- **Active Equivalent Found:** `Abhishumat/facer-gui` (`https://github.com/Abhishumat/facer-gui`, pushed `2026-11-02T17:03:34Z`, License: `GPL-3.0`), discovered via GitHub repository search for `"Acer-RGB-Keyboard-Linux-Module-GUI"`.
  - **GUI Structure (`Abhishumat/facer-gui`):** Python 3 + `PySide6` (`main.py`, `wallpaper_colors.py` with Pillow/ColorThief) wrapping `facer-rgb` CLI / `/dev/acer-gkbbl-0` from `JafarAkhondali`'s module, plus `udev` rules, XDG desktop autostart, and a systemd shutdown service (`facer-rgb-shutdown.service`).
- **Compatibility Assessment vs Phase 1 Recon:** **Not compatible** — wraps `/dev/acer-gkbbl-0` / `facer` kernel module which requires `WMID_GUID4`.

---

### 6. `nbfc-linux` (`nbfc-linux/nbfc-linux`)

- **URL:** `https://github.com/nbfc-linux/nbfc-linux`
- **Cloned Path:** `research/repos/nbfc-linux`
- **Commit Hash (`HEAD`):** `a110c148ad8ef6204429f2199fda92b795343e4e`
- **Commit Date:** `2026-11-22 17:29:41 +0100` (`Updated model_support.json`)
- **License:** `GPL-3.0` (`LICENSE` file)

#### 6.1 Inspection of `share/nbfc/configs/`, `xml/`, and `model_support.json`
- **A715-79G / Aspire 7 / Clevo / Insyde / IT5570 Search Results:**
  - `A715-79G`: **0 matches**
  - `Clevo` / `Insyde` / `IT5570` / `5570`: **0 matches** anywhere in `share/nbfc/configs/`, `xml/`, or `model_support.json`.
  - **77 Acer configs** exist in `share/nbfc/configs/` (Aspire, Nitro, Predator, Swift, TravelMate, Extensa). The closest by series name is `share/nbfc/configs/Acer Aspire A715-41G.json` (AMD Ryzen model using `ReadWriteWords: true`, `ReadRegister: 19 / 21`, `WriteRegister: 55 / 58`, `MaxSpeedValue: 100`, `MaxSpeedValueRead: 6122`, init writes `reg 34 = 12`, `reg 33 = 48`), alongside newer Nitro models (`Acer Nitro V15-41.json` and `Acer Nitro ANV15-52.json` using `ReadRegister: 92 / 106`, `WriteRegister: 73 / 74`, init `reg 190 (0xBE) = 0`, reset `224 (0xE0)`).
  - **Safety Assessment:** Do **NOT** apply `Acer Aspire A715-41G.json` or Nitro configs to `A715-79G` — `A715-41G` is an older Acer-board platform, whereas `A715-79G` uses a Clevo ODM board (`CLV0001`, `IT5570`).

#### 6.2 NBFC Config JSON Schema (`doc/nbfc_service.json.5.md`)
Key schema fields:
- **Service config (`/etc/nbfc/nbfc.json`):** `SelectedConfigId`, `EmbeddedControllerType` (`ec_sys` | `acpi_ec` | `dev_port` | `dummy`), `FanTemperatureSources[]`.
- **Model config:** `NotebookModel`, `EcPollInterval`, `CriticalTemperature`, `CriticalTemperatureOffset`, `ReadWords` / `WriteWords`, `FirmwareFingerprint[]` (AML method body pattern matching to prevent cross-model mismatches), `FanConfigurations[]`, `RegisterWriteConfigurations[]`.
- **Per-fan (`FanConfiguration`):**
  - Read source (mutually exclusive): `ReadRegister` (0–255), `ReadAcpiMethod`, or `ReadLuaCode` (Lua `acpi_call` / `ec_read` APIs).
  - Write target (mutually exclusive): `WriteRegister` (0–255), `WriteAcpiMethod`, or `WriteLuaCode`.
  - Speed bounds & reset: `MinSpeedValue`, `MaxSpeedValue`, `IndependentReadMinMaxValues`, `MinSpeedValueRead`, `MaxSpeedValueRead`, `ResetRequired`, `FanSpeedResetValue` / `ResetAcpiMethod` / `ResetLuaCode`.
  - Curve & sensors: `Sensors[]` (`@CPU`, `@GPU`, or hwmon names), `TemperatureAlgorithmType` (`Average` | `Min` | `Max`), `TemperatureThresholds[]` (`UpThreshold`, `DownThreshold`, `FanSpeed`), `FanSpeedPercentageOverrides[]`.
- **EC init/reset writes (`RegisterWriteConfiguration`):** `WriteMode` (`Set` | `And` | `Or` | `Call` | `Lua`), `WriteOccasion` (`OnInitialization` | `OnWriteFanSpeed` | `OnSuspend` | `OnResume`), `Register`, `Value` / `AcpiMethod` / `LuaCode`, `ResetRequired`, `ResetValue`.

#### 6.3 How EC Reads/Writes Work (`src/ec.c`, `src/ec_sys_linux.c`, `src/ec_linux.c`)
`EC_FindWorking()` probes backends in priority order:
1. **`ec_sys` (`ec_sys_linux.c`):** Opens `/sys/kernel/debug/ec/ec0/io` (`O_RDWR`); if absent, runs `modprobe ec_sys write_support=1`, then performs `pread()`/`pwrite()` across the 256-byte EC register file.
2. **`acpi_ec` (`ec_sys_linux.c`):** Opens `/dev/ec` (or `modprobe acpi_ec`).
3. **`/dev/port` (`ec_linux.c`):** Opens `/dev/port` (`O_RDWR`) and talks directly to standard ACPI EC I/O ports `0x66` (`EC_SC`) and `0x62` (`EC_DATA`) using ACPI Spec Ch. 12.2/12.3 commands (`RD_EC = 0x80`, `WR_EC = 0x81`), polling `IBF` (`0x02`) and `OBF` (`0x01`) bits.
4. Note: `nbfc-linux` also supports calling ACPI/WMI methods via `acpi_call` (`ReadAcpiMethod` / `WriteAcpiMethod` / `LuaCode`), avoiding raw EC register writes if DSDT ACPI methods exist.

#### 6.4 Compatibility Assessment vs Phase 1 Recon
`ec_sys` read-only access already works cleanly on `A715-79G` (`recon/ec_dump_idle.hex`, ports `0x66/0x62`), **but** no model config exists. Any Path C (`ec_sys write_support=1`) usage would first require deriving and verifying the `IT5570` / Clevo EC register map (and obtaining user approval).

---

### 7. `acer-wmi-battery` (`frederik-h/acer-wmi-battery`)

- **URL:** `https://github.com/frederik-h/acer-wmi-battery`
- **Cloned Path:** `research/repos/acer-wmi-battery`
- **Commit Hash (`HEAD`):** `9f90d75cc9237aeed7964622d10dbdf4d2c7b518`
- **Commit Date:** `2026-01-25 21:07:18 +0100` (`Update MODELS.md`)
- **License:** `GPL-2.0` (`LICENSE` file; `MODULE_LICENSE("GPL")` in `acer-wmi-battery.c`)
- **WMI GUID & Methods:**
  - Checks `wmi_has_guid("79772EC5-04B1-4bfd-843C-61E7F77B6CC9")` (`WMID_GUID5`).
  - Evaluates WMI methods `19` (battery information), `20` (get battery health control status), and `21` (set 80% charge limit / calibration).
- **Supported Models (`MODELS.md`):** Lists `Aspire 7 A715-42G`, plus various Aspire 3/5, Nitro, Predator, and Swift models. Does **not** list `A715-79G` or `ABBC0F6D`.
- **Compatibility Assessment vs Phase 1 Recon:** **Not compatible** (`79772EC5-04B1-4bfd-843C-61E7F77B6CC9` is absent on `A715-79G`).

---

### 8. OpenRGB GitLab Issue #4869 (`CalcProgrammer1/OpenRGB`)

- **URL:** `https://gitlab.com/CalcProgrammer1/OpenRGB/-/work_items/4869`
- **Title:** `New Device Acer Aspire 7 A715-79G`
- **Author / Dates:** Priyansh Prajapat, opened `2025-06-17T10:52:24.026Z`, last updated `2026-08-27T11:32:22.509Z`
- **State / Labels:** `opened` | `DeviceType::IDK`, `Issue Type - New Device`, `NewDevice::Step1 - Missing Info or Captures`
- **Comments:** 0 notes/comments.
- **Full Findings (from issue body + inspection of all 5 attached screenshots):**
  - Reporter notes the keyboard is built-in (not listed as a USB HID device), runs Ubuntu where the backlight is stuck on blue, and previously ran Windows 11 with the OEM control software.
  - **No device/packet captures are attached** (the fifth image under "Please attach device captures here" is only a photo of the laptop running Ubuntu with the keyboard lit blue).
  - **Critical Evidence from the 4 Windows App Screenshots:** The OEM Windows application shown on `A715-79G` is **Clevo Control Center** (window title: **`Control Center`**), exposing:
    1. **LED keyboard tab:**
       - `Override Boot Effect` checkbox
       - **Single-zone** `Color backlight` continuous color slider bar + white slider (**confirms single-zone full-keyboard RGB, NOT 4-zone RGB and NOT white-only**)
       - `Keyboard Sleep timer` (`Disable` / `Enable`, `H:M:S`, shown at `0:0:30`)
       - `Brightness` slider: `OFF`, `1`, `2`, `3`, `4` (5 discrete steps: off + 4 levels)
    2. **System tab:**
       - 4 performance/power profiles: `Performance`, `Entertainment`, `Power Saving`, `Quiet`
       - `FAN speed control`: `Automatic`, `Maximum`, `Custom`
       - Independent `CPU fan speed` and `GPU fan speed` readouts (both `%` and `RPM`)
       - `Preference` hardware toggles (`Win key lock`, `Swap Win-Fn`, `Fn-key Lock`, `Touch Pad`, `Camera`, `Airplane`, `Caps Lock`, `Num Lock`, `Scr Lock`)
    3. **FlexiCharger tab:** `Maximum Battery Charge` (100%), `Recommended Battery Charge` (<70% start, 80% stop), `Custom Battery Charge`.
    4. **Flexikey tab:** Keyboard/Mouse macros (`Fn+Backspace`).

---

### 9. Microsoft Store Windows App (`9p1v7skxg6h5`)

- **URL:** `https://apps.microsoft.com/detail/9p1v7skxg6h5?hl=en-US&gl=IN`
- **Verified Metadata (Microsoft DisplayCatalog v7.0 API):**
  - **Exact Product Title:** `Fn hotkeys and OSD`
  - **Product ID:** `9P1V7SKXG6H5`
  - **Publisher / Developer:** `CLEVO CO.` / `CLEVO` (`http://www.clevo.com.tw/`)
  - **Package Family Name:** `CLEVOCO.FnhotkeysandOSD_6h6z29zh29qx0`
  - **Description:** `Provide hot keys OSD(On Screen Display)`
  - **Release / Last Modified:** `2018-11-16T03:12:46Z` / `2026-10-12T03:22:29Z`
  - **App Capabilities Clue:** `Clevo.keyboardMouseFilter_6h6z29zh29qx0`, `runFullTrust`, `unvirtualizedResources`
- **Hardware Interface Assessment (no binary downloaded or decompiled):**
  - This confirms that the `Acer Aspire A715-79G` runs **Clevo's ODM hotkey/OSD/Control Center software stack** (`CLEVO CO.`) rather than Acer's PredatorSense/NitroSense stack.
  - Together with Phase 1's WMI/ACPI findings (`ABBC0F6B/C/D`, `CLV0001:00`, `CLV0002:00`, `IT5570` EC) and OpenRGB #4869's Clevo Control Center screenshots, this strongly indicates the laptop uses **Clevo WMI (`ABBC0F6D` `object_id: BB` / `ABBC0F6B` `D0` / `ABBC0F6C` `D1`) and/or `CLV0001` ACPI methods** (commonly supported in Linux by Clevo WMI drivers such as `tuxedo-drivers` / `clevo-xsm-wmi` / `clevo_acpi`, to be investigated by Worker B).

---

### 10. Acer Support BIOS Check (`A715-79G` vs `1.14RA1`, `09/08/2025`)

- **Current Installed Firmware (`recon/dmidecode.txt`):**
  - BIOS Vendor: `INSYDE Corp.`
  - BIOS Version: `1.14RA1`
  - Release Date: `09/08/2025`
  - BIOS Revision: `7.14` | EC Firmware Revision: `7.13`
- **Acer Support URLs Identified:**
  - `https://www.acer.com/in-en/support/product-support/Aspire_A715-79G/downloads`
  - `https://www.acer.com/us-en/support/product-support/Aspire_A715-79G/downloads`
  - `https://www.acer.com/ac/en/US/content/drivers` (lookup by SN/SNID; machine SN `[REDACTED]`)
- **Online Check Outcome & Caveat:**
  - Automated `curl` requests to `www.acer.com` support pages/endpoints hang/return empty responses due to Akamai/JavaScript SPA protection, and public search indices did not return any BIOS version newer than `1.14RA1` (e.g., no `1.15RA1`/`1.16RA1` found online).
  - **Result:** Cannot independently verify via headless CLI whether Acer has published a BIOS newer than `1.14RA1` (`09/08/2025`). If desired, the user should check `https://www.acer.com/in-en/support/product-support/Aspire_A715-79G/downloads` in a desktop browser with their SNID. No BIOS package was downloaded or flashed.

---

## Cross-Reference Note (Discovered During GitHub Search for `A715-79G`)

During verification, a GitHub repository search for `"A715-79G"` also surfaced 6 model-specific community repositories (not cloned by Worker A, flagged for Worker B / Phase 2 `FINDINGS.md` synthesis):
- `mayanksaini002/KeyLume` (`https://github.com/mayanksaini002/KeyLume`) — RGB keyboard lighting control for Clevo-based laptops (`Acer Aspire 7 A715-79G / NP50RNA`)
- `netfreakkk/AspireSense` (`https://github.com/netfreakkk/AspireSense`) — Fan control, cooling profiles, and thermal monitor for `A715-79G`
- `Atul977/Aspire-A715-79G-LinuxPackages` (`https://github.com/Atul977/Aspire-A715-79G-LinuxPackages`) — Notes patched `tailor-gui` (TUXEDO/Clevo stack)
- `mogantipraneet/Acer-Aspire-7-A715-79G-RGB` (`https://github.com/mogantipraneet/Acer-Aspire-7-A715-79G-RGB`)
- `anshkr95/acer-a715-79g-rgb` (`https://github.com/anshkr95/acer-a715-79g-rgb`)
- `J-525/Acer-Aspire-A715-79G-KeyBoard` (`https://github.com/J-525/Acer-Aspire-A715-79G-KeyBoard`)
