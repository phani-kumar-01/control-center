# Phase 3 Step 1: Read-Only Path A Check & ACPI DSDT/SSDT Analysis (`BIOS 1.14RA1`)

**Date (UTC):** `2026-11-26`  
**Target Machine:** `Acer Aspire A715-79G` (`Version: 1.14`, `BIOS: INSYDE Corp. 1.14RA1` dated `09/08/2025`, `EC: 7.13`)  
**Kernel / OS:** `7.0.0-38-generic` (`Ubuntu 26.04.1 LTS`), `SecureBoot disabled`  
**Mode:** Strictly Read-Only (zero kernel module compilation/loading, zero GRUB changes, zero hardware/EC writes)  
**Source Tables:** `/home/candy/control/control-center/recon/acpi/acpi.dat` extracted and disassembled into `/home/candy/control/control-center/recon/acpi/extracted/*.dsl`

---

## 1. Path A Live Read-Only Verification

### 1.1 `thermald` Health & Active Management
- Command: `systemctl status thermald --no-pager -l`
  - **State:** `active (running)` since `2026-11-26 06:16:13 IST` (`Main PID: 1122`, `Memory: 3.5M`).
  - **Command line:** `/usr/sbin/thermald --systemd --dbus-enable --adaptive` (`enabled` preset).
- Command: `journalctl -u thermald -b --no-pager | tail -n 40`
  - Verbatim log lines:
    ```
    Nov 26 06:16:13 candy-Aspire-A715-79G systemd[1]: Starting thermald.service - Thermal Daemon Service...
    Nov 26 06:16:13 candy-Aspire-A715-79G thermald[1122]: 32 CPUID levels; family:model:stepping 0x6:ba:2 (6:186:2)
    Nov 26 06:16:13 candy-Aspire-A715-79G thermald[1122]: 32 CPUID levels; family:model:stepping 0x6:ba:2 (6:186:2)
    Nov 26 06:16:13 candy-Aspire-A715-79G thermald[1122]: Polling mode is enabled: 4
    Nov 26 06:16:13 candy-Aspire-A715-79G systemd[1]: Started thermald.service - Thermal Daemon Service.
    ```
  - `thermald` is running cleanly in polling mode (`4`) for CPU family/model `0x6:ba:2` (Raptor Lake-P / Core 5 210H).

### 1.2 Power Supply & Battery Sysfs (`/sys/class/power_supply/*`)
- **`/sys/class/power_supply/AC`:**
  - `type`: `Mains`
  - `online`: `0` (on battery during check)
- **`/sys/class/power_supply/BAT0`:**
  - `type`: `Battery`, `present`: `1`, `status`: `Discharging`, `capacity`: `57`, `capacity_level`: `Normal`
  - `manufacturer`: `Notebook`, `model_name`: `BAT`, `serial_number`: `0001`, `technology`: `Li-ion`
  - `charge_full_design`: `3410000`, `charge_full`: `2786000`, `charge_now`: `1592000`, `current_now`: `578000`, `voltage_min_design`: `15400000`, `voltage_now`: `15049000`, `cycle_count`: `0`
  - **`charge_control_*` / `charge_type`:** **ABSENT** natively in sysfs (requires FlexiCharger `_DSM 0x76`/`0x77` or `0x04` subcommand `0x1E`/`0x1F` via `acpi_battery_hook` if exposed).

### 1.3 `platform_profile`, Keyboard LEDs, and WMI BMOF
- `/sys/firmware/acpi/platform_profile*`: **Absent** (`No such file or directory`); `/sys/class/platform-profile/` is empty.
- `/sys/class/leds/*kbd*`: **Absent** (`No such file or directory`).
- `/sys/bus/wmi/devices/*/bmof`: **Absent** (`No such file or directory`).
  - `/sys/bus/wmi/devices/` still lists exactly 4 WMI devices: `ABBC0F6B-8EA1-11D1-00A0-C90629100000`, `ABBC0F6C-8EA1-11D1-00A0-C90629100000`, `ABBC0F6D-8EA1-11D1-00A0-C90629100000` (on `PNP0C14:01`), and `F6CB5C3C-9CAE-4EBD-B577-931EA32A2CC0` (on `PNP0C14:00`).

---

## 2. ACPI Table Extraction & Disassembly Summary

Commands run inside `/home/candy/control/control-center/recon/acpi/extracted/` (`../acpi.dat` kept intact at `3,844,039` bytes):
1. `acpixtract -a ../acpi.dat` extracted `dsdt.dat` (`544,982` bytes), `ssdt1.dat`..`ssdt25.dat`, `apic.dat`, `bgrt.dat`, `dbg2.dat`, `dbgp.dat`, `dmar.dat`, `facp.dat`, `facs.dat`, `fpdt.dat`, `hpet.dat`, `mcfg.dat`, `msdm.dat`, `nhlt.dat`, `phat.dat`, `tpm2.dat`, `uefi.dat`, `wsmt.dat`.
2. `iasl -d *.dat` disassembled all tables; `ssdt5.dat` (`4,486` bytes, `xh_adlLP`) initially produced a 0-byte file in the wildcard batch and disassembled cleanly when run individually (`iasl -d ssdt5.dat` -> `31,241` bytes).
3. `iasl -d dsdt.dat` disassembled `dsdt.dsl` (`108,709` lines, `3,687,253` bytes, table header `DSDT ... ACRSYS ACRPRDCT`) with 4 benign warnings (`ACPI Warning: NsLookup: Type mismatch on PHG0 (BufferField), searching for (Buffer)`) and the standard external-method-count notice (`238 external control methods found ... 494 resolved`). Note: `iasl -e ssdt*.dat -d dsdt.dat` fails with `Firmware Error (ACPI): Failure creating named object [\_SB.PC00.XHCI.RHUB.HS10.SADX], AE_ALREADY_EXISTS` due to duplicate SSDT device naming, so standalone `iasl -d dsdt.dat` is the clean disassembly.

---

## 3. Critical Binary Answer: `_DSM 0x67` vs `WMBB 0x67` vs `ECMD 0xCA` on `BIOS 1.14RA1`

**YES — `BIOS 1.14RA1` implements keyboard RGB/brightness command `0x67` in FULL across BOTH `CLV0001._DSM` AND `WMBB` (`ABBC0F6D`), AND internally translates `0xF0..0xF6` subcommands directly into `ECMD 0xCA` mailbox writes (`EC81` `0xF8..0xFD`)!**

Unlike `BIOS 1.07.01TACI` (where `the3rdchild` observed `0x67` dropped by EC firmware), `BIOS 1.14RA1` unifies Clevo DCHU `_DSM 0x67` and the `ECMD 0xCA` mailbox in `dsdt.dsl`:

### 3.1 Exact ASL Call Chain (`_DSM` / `WMBB` -> `SCMD` -> `ECMD` -> `EC81` RAM)
1. **Entry point 1 — `CLV0001` (`\_SB.DCHU._DSM`, `dsdt.dsl:102583–102705`):**
   - Matches UUID `93f224e4-fbdc-4bbf-add6-db71bdc0afad` (`dsdt.dsl:102585`).
   - `Arg2 == 0x67` (`dsdt.dsl:102688`) dispatches to `DCHU.SCMD (Arg1, Arg2, Arg3)` (`dsdt.dsl:102703`).
2. **Entry point 2 — `PNP0C14:01` (`\_SB.WMI.WMBB`, `dsdt.dsl:100074–100210`):**
   - Bound to WMI method GUID `ABBC0F6D-8EA1-11D1-00A0-C90629100000` (`_WDG` `dsdt.dsl:96055–96065`, object ID `"BB"`).
   - Acquires `EC.PATM` mutex (`100077`) and dispatches `Arg1 == 0x67` (`100184`) to `WMI.SCMD (Arg0, Arg1, Arg2)` (`100199`).
3. **Entry point 3 — Batch `CPKG` (`Arg2 == 0x02`, `DCHU.CPKG` `dsdt.dsl:104891–105069`, `WMI.CPKG`):**
   - When `WQW2 >> 0x26` and `WRW2 >> 0x26` are set, reads dword `PH30` at `ARGP[0xB2..0xB5]` and executes the exact same `0x67` logic.
4. **Inside `DCHU.SCMD` (`dsdt.dsl:106872–107047`) / `WMI.SCMD` (`dsdt.dsl:97304–97479`):**
   ```asl
   If ((ToInteger (Arg1) == 0x67))
   {
       Local2 = ((ARGS >> 0x0C) & 0x0F)
       ...
       Local3 = ((ARGS >> 0x10) & 0xFF)
       Local4 = ((ARGS >> 0x18) & 0x0F)
       Local7 = ((ARGS >> 0x1C) & 0x0F)
       If (^^PC00.LPCB.EC.ECOK)
       {
           If (((Local7 >= 0x07) && (Local7 <= 0x0B))) // 0x70..0xB0 effects
           { ... ECMD([0x02, 0x00, 0xC4, Local7, ...]) }
           Else
           {
               If ((Local7 == Zero)) { ... ECMD([0x03, 0x00, 0xC2, ...]) }       // 9-bit legacy RGB
               If ((Local7 == One))  { ... ECMD([0x03, 0x00, 0xC4, 0x03, Local3]) }
               If ((Local7 == 0x02)) { ... ECMD([0x03, 0x00, 0xC4, 0x04, Local3]) }
               If ((Local7 == 0x03)) { ... ECMD([0x04, 0x00, 0xC4, 0x06, Local3, Local4]) }
               If ((Local7 == 0x04)) { ... ECMD([0x02, 0x00, 0xC4, Local3 ? 0x0D : 0x0E]) }
               If ((Local7 == 0x0D)) { ... ECMD([0x03, 0x00, 0xC4, 0x02, Local2]) }
               If ((Local7 == 0x0E)) { ... ECMD([0x03, 0x00, 0xC4, 0x0C, Local1]) } // 0xE0xxxxxx power/timeout
               If ((Local7 == 0x0F))                                                // 0xF0..0xF6 -> ECMD 0xCA!
               {
                   Local6 = Zero
                   Local3 = (ARGS & 0xFF)
                   Local2 = ((ARGS >> 0x08) & 0xFF)
                   Local1 = ((ARGS >> 0x10) & 0xFF)
                   If ((Local4 < 0x03))      // 0xF0, 0xF1, 0xF2 -> zones 0x03, 0x04, 0x05
                   {
                       Local0 = (Local4 + 0x03)
                       Local6 = 0xCA
                   }
                   ElseIf ((Local4 == 0x03)) // 0xF3 -> 0x07
                   {
                       Local0 = 0x07
                       Local6 = 0xCA
                   }
                   ElseIf ((Local4 == 0x04)) // 0xF4 -> brightness (0x06)
                   {
                       Local0 = 0x06
                       Local1 = (ARGS & 0xFF)
                       Local6 = 0xCA
                   }
                   ElseIf ((Local4 == 0x06)) // 0xF6 -> 0x09 + 0x0A
                   {
                       ECMD([0x05, 0x00, 0xCA, 0x09, Local1, Local2, Local3, 0x00])
                       Local0 = 0x0A
                       Local6 = 0xCA
                   }
                   If (Local6)
                   {
                       ECMD([0x05, 0x00, 0xCA, Local0, Local1, Local2, Local3, 0x00])
                   }
               }
           }
       }
       Return (0x67)
   }
   ```
5. **Inside `EC.ECMD` (`dsdt.dsl:100997–101061`) -> `EC81` (`dsdt.dsl:100795–100805`):**
   - Acquires `PATM` mutex (`101005`).
   - Writes payload bytes to `EmbeddedControl` `EC81` offsets `0xF8..0xFD`:
     - `FDAT (0xF9) = Arg0[3]` (`0x03` for zone 0 `0xF0`, `0x06` for brightness `0xF4`)
     - `FBUF (0xFA) = Arg0[4]` (`Local1`: for `0xF0`, `(ARGS >> 16) & 0xFF` = **Blue** in `tuxedo-drivers`/`KeyLume`; for `0xF4`, `ARGS & 0xFF` = brightness)
     - `FBF1 (0xFB) = Arg0[5]` (`Local2`: for `0xF0`, `(ARGS >> 8) & 0xFF` = **Red**)
     - `FBF2 (0xFC) = Arg0[6]` (`Local3`: for `0xF0`, `ARGS & 0xFF` = **Green**)
     - `FBF3 (0xFD) = Arg0[7]` (`0x00` when len=6)
     - `FCMD (0xF8) = Arg0[2]` (`0xCA`) — triggers EC command execution!
   - **Color byte order verification:** In `tuxedo-drivers` (`clevo_leds.h:105`), `cset = ((B) << 16) | (R << 8) | G` -> `0xF0_BB_RR_GG`. In `KeyLume` (`KeyboardDevice.cs:201–203`), `[G, R, B, 0xF0]` as little-endian `u32` is identically `0xF0_BB_RR_GG`. In `clevo-acpi-dkms` (`clevo-acpi.c:192–194`), `ECMD 0xCA` writes `buf[4]=B, buf[5]=R, buf[6]=G`. All three match `BIOS 1.14RA1` (`0xFA=B, 0xFB=R, 0xFC=G`).

---

## 4. Complete `CLV0001` (`DCHU`) & `CLV0002` (`DCHP`) Implementation Reference

### 4.1 `CLV0002` (`\_SB.DCHP`, `dsdt.dsl:108023–108036`)
- Contains only `_HID = "CLV0002"`, `_UID = 1`, and `_STA` (returns `0x0F` when `(PSF0 & 0x80) && (OSYS >= 0x07DC)`).
- Has **no `_DSM` and no child methods** — it is a companion ACPI presence stub.

### 4.2 `CLV0001` (`\_SB.DCHU`, `dsdt.dsl:102539–108021`) `_DSM` Details
- **UUID (`Arg0`):** `93f224e4-fbdc-4bbf-add6-db71bdc0afad` (`dsdt.dsl:102585`). Two other proprietary UUID buffers at `102712–102728` immediately return `0x80000002`.
- **Revision (`Arg1`) handling (`rev 0` vs `rev 1`):** **NOT checked.** `DCHU._DSM` passes `Arg1` as the unused first parameter of `CPKG`, `OCWR`, `CC30`, `GCMD`, and `SCMD` (`102591–102704`). Both `rev 0` (`tuxedo-drivers`, `clevo-acpi-dkms`) and `rev 1` (`opendchu`) execute identically.
- **Function `Arg2 == 0x00` (standard `_DSM` query):** **NOT implemented.** `0x00` is absent from `Switch (Arg2)` (`102587–102707`), so `_DSM(..., 0, 0, ...)` returns `0x80000002` (`STATUS_INVALID_PARAMETER`). Callers must invoke target function IDs directly without gating on `Arg2 == 0x00`.
- **Argument format (`Arg3`):** `DCHU.GCMD` (`105671–105673`) and `DCHU.SCMD` (`106414–106416`) expect a `Package` whose first element (`Arg3[0]`) is an `Integer` (or `Buffer` of >=4 bytes read via `CreateField(ARGP, 0, 32, BINT)`). `PK04`/`PK0E`/`OCWR` expect `Arg3[0]` to be a `Buffer`. Note: `WMI.WMBB` passes `Arg2` directly without `DerefOf(Arg2[0])`!

#### Supported `_DSM` Functions (`Switch (Arg2)` in `dsdt.dsl:102587–102707`)

| `_DSM` `Arg2` | Dispatcher (`dsdt.dsl` lines) | Underlying Action / EC Command | Purpose & Return Format |
|---|---|---|---|
| **`0x02`** | `CPKG` (`103901–105662`) | Bitmask `WQW1/WQW2` (read) & `WRW1/WRW2` (write) | 256-byte batch get/set covering `0x01..0x7A` in one call. |
| **`0x03`** | `OCWR` (`103855–103899`) | Writes `PFBA+0xC0..0xDF`, triggers SMI `PRM0=0x0F, SSMP=0xC0` | Overclocking/BIOS memory mailbox write; returns `0x03`. |
| **`0x04`** | `CC30 -> PK04` (`102794–103550`) | Subcommand in `Arg3[0][0]`: `0x01` (raw `ECMD`), `0x03`/`0x05`/`0x06` (read/write `0xFE0B0100` / `0xFE0B0380` / phys), `0x08` (PSF1..6/CCF0..1), `0x09` (NV limits), `0x0A..0x17`, `0x18`/`0x19` (Win-key/Fn-lock/Touchpad-lock `ECKS`/`B2E9`), `0x1C` (`PMAC`), `0x1D` (`PMPP`), `0x1E`/`0x1F` (CC4 FlexiCharger `ECMD 0xCB`), `0x21..0x31` (`CPLY`), **`0x3F`** (if `KBTY & 0x06`: `ECMD [0x04,0x00,0xCA,0x0F]`) | 256-byte structured DCHU query/control package. |
| **`0x07`** | `CC30 -> PK07` (`103552–103565`) | Reads `EC.BMD0` into `BUFF[2..3]` | Battery model/data word. |
| **`0x0C`** | `CC30 -> PK0C` (`103567–103647`) | Reads `EC.RPM1..3`, `BPV0`, `BPR0`, `ECMD 0xB1 0x19`, **`ECMD 0xC0 0x00..0x03`** (fans 1–3 duty/temp), `AIRP >> 7` | 256-byte live telemetry buffer (`b[2..7]` = `RPM1..3` tach periods, `b[16/19/22]` = fan 1/2/3 duty, `b[17/18, 20/21, 23/24]` = fan temps). |
| **`0x0D`** | `CC30 -> PK0D` (`103649–103702`) | Reads `RAM3` (`KLCR..KRCB`, `KBBH`, `FANQ`, **`KBTP` at `[0x0F]`**, fan curves `F1T1..F3D4`, `KPCR`) + `ECMD 0xD7 0x00` at `[0x0E]` | Hardware specs & keyboard type (`BUFF[0x0F] = EC.KBTP`, `tuxedo-drivers` `CLEVO_CMD_GET_SPECS`). |
| **`0x0E`** | `CC30 -> PK0E` (`103704–103758`) | Writes `F1T2..F3R3` in `RAM3` (`0xFE0B0380+`) | Custom firmware fan curve table write; returns `0x14`. |
| **`0x11`** | `CC30 -> PK11` (`103760–103853`) | Reads `CMID`, `CCID`, `CSID`, `CC3M`, `COLM`, `OG1..4*`, `WBL0..A`/`ABL0..A` | Color/OEM/backlight capability table. |
| **`0x01`** | `GCMD` (`105675–105683`) | Returns `DCHU.EVNT` if `HKDR != 0` | Get last hotkey/EC event code (`CLEVO_CMD_GET_EVENT`). |
| **`0x05, 0x06, 0x09, 0x0A`** | `GCMD` (`105685–105850`) | `ECMD 0xB8 0xA1` + `EC.OEM3` bits | Get Airplane/Webcam/Touchpad/Bluetooth switch status. |
| **`0x08`** | `GCMD` (`105771–105775`) | Calls `GHPI ()` (returns `Ones` / `0xFFFFFFFF` at `108053`) | Hotkey page/platform ID. |
| **`0x10`** | `GCMD` (`105852–105881`) | Computes `PSF5` feature mask | BIOS capability mask 5. |
| **`0x12`** | `GCMD` (`105883–105901`) | Reads 256 bytes from `PFBA` (`SystemMemory`) | BIOS performance/profile buffer. |
| **`0x32, 0x33, 0x34, 0x38, 0x3F, 0x42, 0x43, 0x45, 0x51, 0x62`** | `GCMD` (`105903–106093`) | `BDC0`, `BKST`, stubs (`0`/`1`/`Ones`) | Misc getters (`0x33/0x34/0x43` stubbed empty; `0x38` returns `1`; `0x3F`/`0x62` return `0`). |
| **`0x39`** | `GCMD` (`105945–105948`) | `PC00.TMSS.GTMP ()` (`PCI 00:12.0` thermal sensor BAR) | CPU/SoC thermal sensor temperature. |
| **`0x3B`** | `GCMD` (`105950–105964`) | `ECMD([0x04, 0x80, 0xB1, 0x06, 0x01, 0x02])` | EC read (`0xB1` subcmd). |
| **`0x3C`** | `GCMD` (`105966–105981`) | `GFX0.PDDS(0x0300)` if `!(PSF0 & 0x10)` | Display device status. |
| **`0x3D`** | `GCMD` (`105983–105999`) | `ECMD([0x02, 0x80, 0xCA, 0x01])` -> returns byte `[2]` | White-only kbd brightness getter (`CLEVO_CMD_GET_KB_WHITE_LEDS`). |
| **`0x3E`** | `GCMD` (`106001–106017`) | `ECMD([0x02, 0x80, 0xB8, 0xA2])` | Wireless/radio status bit. |
| **`0x41`** | `GCMD` (`106025–106041`) | `ECMD([0x04, 0x80, arg[7:0], arg[31:24], arg[23:16], arg[15:8]])` | Generic 4-byte `ECMD` read passthrough. |
| **`0x52`** | `GCMD` (`106071–106074`) | Returns `PSF1` (`CLEVO_CMD_GET_BIOS_FEATURES_1`) | BIOS features word 1. |
| **`0x60`** | `GCMD` (`106076–106088`) | Returns `PSF4` (`\| 0x10` if `PSF6 & 0xF && EC.RINF & 0x10`) | BIOS features word 4. |
| **`0x63`** | `GCMD` (`106095–106134`) | `ECMD 0xC0 0x02` & `0xC0 0x03` -> `(temp2<<16)\|(temp1<<8)\|duty` | **Fan 1** (CPU) duty + temps (`CLEVO_CMD_GET_FANINFO1`). |
| **`0x64`** | `GCMD` (`106136–106163`) | `ECMD 0xC0 0x00` -> `(temp2<<16)\|(temp1<<8)\|duty` | **Fan 2** (GPU) duty + temps (`CLEVO_CMD_GET_FANINFO2`). |
| **`0x6E`** | `GCMD` (`106165–106192`) | `ECMD 0xC0 0x01` -> `(temp2<<16)\|(temp1<<8)\|duty` | **Fan 3** duty + temps (`CLEVO_CMD_GET_FANINFO3`). |
| **`0x6F, 0x70, 0x71`** | `GCMD` (`106194–106306`) | `ECMD 0xC0 0x02..0x05` | Additional fan/sensor telemetry words. |
| **`0x73`** | `GCMD` (`106308–106372`) | Reads 1/2/4 bytes at `0xFE0B0100 + (INDX & 0xFF)` | Read EC `RAM` offset selected by `SCMD 0x6B` (`INDX`). |
| **`0x77`** | `GCMD` (`106374–106380`) | `(BAEE >> 1) \| (BSCP << 8) \| (BTCP << 16)` | Legacy FlexiCharger read (`status | start<<8 | end<<16`). |
| **`0x7A`** | `GCMD` (`106382–106402`) | Returns `PSF2` (with `0x0400`/`0x40000000` bits) | BIOS features word 2 (`CLEVO_CMD_GET_BIOS_FEATURES_2`). |
| **`0x13`** | `SCMD` (`106418–106434`) | Sets/clears `ECKS` bit 7 (`0x80`) | Touchpad/hotkey lock bit. |
| **`0x14, 0x1D, 0x26, 0x2C, 0x31, 0x47, 0x4A, 0x4E, 0x56, 0x57, 0x66, 0x6C`** | `SCMD` (`106436–107164`) | Return command ID only (`0x66` falls through to `Ones`) | No-op stubs. |
| **`0x1F`** | `SCMD` (`106448–106472`) | `ECMD([0x02, 0x00, 0xA4, ARGS?1:0])` | BIOS/EC power/fan flag. |
| **`0x20, 0x21, 0x22, 0x2A, 0x4C, 0x5E, 0x65`** | `SCMD` (`106474–106869`) | `ECMD([0x03, 0x00, 0xB8, ARGS?0xC2:0xC3, 0xA1..0xA9])` | Toggle FlightMode (`0x20`/`0xA2`), BT (`0x21`/`0xA3`), Webcam (`0x22`/`0xA1`), Touchpad (`0x2A`/`0xA5`), WiFi (`0x4C`/`0xA4`), `0xA6`, `0xA9`. |
| **`0x27`** | `SCMD` (`106552–106566`) | `ECMD([0x03, 0x00, 0xCA, 0x00, ARGS])` | White-only kbd brightness (`CLEVO_CMD_SET_KB_WHITE_LEDS`). |
| **`0x46`** | `SCMD` (`106607–106630`) | Sets `HKDR = 1`, `PRM0=0x12, SSMP=0xC0`, `ECMD 0xC4 0x05 0x01`, `AIRP \|= 0x10`; returns `PSF3` | **Enable hotkey ACPI Notify events** (`CLEVO_CMD_SET_EVENTS_ENABLED`). |
| **`0x48, 0x49, 0x4F, 0x55, 0x5A, 0x5B, 0x6D`** | `SCMD` (`106638–107175`) | dGPU bus check (`0x48`), `PWRB`/`SLPB`/`LID0` notify (`0x49`,`0x5A`), `PSF1`/dGPU battery boost (`0x4F`), `INF2 \|= 2` (`0x55`), SMI `0x07` (`0x5B`), `HIDD.HPEM(8)` (`0x6D`) | Platform power/hotkey/GPU helpers. |
| **`0x67`** | `SCMD` (`106872–107047`) | `ECMD 0xC4` / `0xC2` / **`0xCA`** (see §3.1) | **Keyboard RGB color (`0xF0`), brightness (`0xF4`), power/sleep (`0xE0`), effects.** |
| **`0x68`** | `SCMD` (`107049–107082`) | `ECMD 0xC1 0x01..0x04` with `ARGS[7:0], [15:8], [23:16], [31:24]` | **Set manual fan duties (0–255 per fan, `CLEVO_CMD_SET_FANSPEED_VALUE`).** |
| **`0x69`** | `SCMD` (`107084–107124`) | `ECMD 0xC1 0xFF 0x01..0x04` for each bit `0..3` set in `ARGS` | **Restore fan(s) to EC auto (`ARGS = 0x0F`, `CLEVO_CMD_SET_FANSPEED_AUTO`).** |
| **`0x6A`** | `SCMD` (`107126–107143`) | `ECMD([0x03, 0x00, 0xBA, (ARGS>>8)&0xFF, ARGS&0xFF])` | EC `0xBA` command. |
| **`0x6B`** | `SCMD` (`107145–107150`) | Sets `DCHU.INDX = ARGS` | Set EC `RAM` offset/width for `0x73`/`0x75`. |
| **`0x74`** | `SCMD` (`107177–107210`) | `ECMD([0x02, 0x00, 0xC6, vol])` | Beep/audio volume mute (`0xC6`). |
| **`0x75`** | `SCMD` (`107212–107308`) | Writes 1/2/4 bytes to `0xFE0B0100 + INDX` (triggers `FCMD` if `0xF8`) | Write EC `RAM` at `INDX`. |
| **`0x76`** | `SCMD` (`107310–107480`) | Subcmd `(ARGS>>24)`: `1..4` -> `ECMD 0xC6/C7/C8`; `5..7` -> `ECMD 0xCB` (`FlexiCharger`) | **FlexiCharger charge start/end/enable (`0x05`/`0x06`/`0x07`).** |
| **`0x79`** | `SCMD` (`107482–108017`) | Subcmd `(ARGS>>24)`: **`0x01`** -> `ECMD 0xD7` (`0→2` balanced, `1→0x10` max, `2→8`, `5→1` quiet, `6→4`, `7→0x20` perf, `8→0x40`); `0x05` -> `ECKS\|=0x10`; `0x07` -> `ECMD 0xCC`; `0x0E` -> `GFOF`; `0x15` -> `ECMD 0xD3`; `0x18` -> `ECMD 0xD4`; **`0x19`** -> `ECMD 0xD8` + `CPCM` + `SMI 0x11` + `Notify(IETM,0x88)` + `Notify(TCPU,0x83)` + `Notify(NPCF,0xC0)`; `0x1A` -> `AIRP\|=0x40`; `0x1C` -> `ECMD 0xBD`; `0x1D` -> `INF2`; `0x1E` -> `ECMD 0xB8 0xAC`; `0x22` -> `ECMD 0xD9`; `0x26` -> `ECMD 0xDB` | **Thermal/fan profile (`0x01`) & DPTF/power profile (`0x19`) (`CLEVO_CMD_OPT`).** |

---

## 5. EC OperationRegion, Memory-Mapped EC RAM, and Hotkey `_Qxx` Behavior

### 5.1 EC Regions in `dsdt.dsl` (`\_SB.PC00.LPCB.EC`)
1. **`RAM` (`OperationRegion (RAM, SystemMemory, 0xFE0B0100, 0x0100)`, `dsdt.dsl:100632–100793`):**
   - `0x07`: `TMP` (ACPI thermal zone temp, °C — matched `0x31 = 49 °C` in `recon/ec_dump_idle.hex`)
   - `0xCE`: `DUT1` (Fan 1 duty `0..255` — matched `0x47` in `ec_dump_idle.hex`)
   - `0xCF`: `DUT2` (Fan 2 duty `0..255` — matched `0x47` in `ec_dump_idle.hex`)
   - `0xD0..0xD1`: `RPM1` (16-bit LE tach period — matched `0x03 0xD8` in `ec_dump_idle.hex`)
   - `0xD2..0xD3`: `RPM2` (16-bit LE tach period — matched `0x03 0xDB` in `ec_dump_idle.hex`)
   - `0xD4..0xD5`: `RPM4`, `0xE0..0xE1`: `RPM3` (0 in `ec_dump_idle.hex`)
   - `0xD7..0xDF`: `DTHL, DTBP, AIRP, WINF, RINF, INF2`, `0xE2`: `ECKS`
   - `0x14..0x66`: Battery info/status (`BPU0`, `BDC0`, `BFC0`, `BPV0`, `BPR0`, `BRC0`, `BRS0`, etc.)
2. **`EC81` (`OperationRegion (EC81, EmbeddedControl, Zero, 0xFF)`, `dsdt.dsl:100795–100805`):**
   - `Offset (0xF8)`: `FCMD` (`0xF8`), `FDAT` (`0xF9`), `FBUF` (`0xFA`), `FBF1` (`0xFB`), `FBF2` (`0xFC`), `FBF3` (`0xFD`) — used exclusively by `ECMD`.
3. **`RAM2` / `RAM3` (`OperationRegion (RAM2/RAM3, SystemMemory, 0xFE0B0300, 0x0100)`, `dsdt.dsl:100807–100887` & `102252–102301`):**
   - `0x80..0x8A`: `KLCR..KRCB` (3-zone/1-zone RGB defaults), `KBBH` (`0x89`), `FANQ` (`0x8A`)
   - `0x8B`: `KBTY` / `KBTP` (keyboard backlight type reported by `PK0D[0x0F]`)
   - `0x8C..`: `F1T1..F3R3` (EC fan curve tables written by `PK0E`).

### 5.2 Why `Fn+Backlight` Hotkey Did Nothing in Phase 1
- In `DCHU._INI` (`dsdt.dsl:102563–102566`) and `WMI._INI` (`dsdt.dsl:96069–96072`), **`HKDR` is initialized to `Zero`**.
- EC query **`_Q50`** (`dsdt.dsl:101630–101856`) processes hotkey codes from `EC.OEM4`:
  - `0x81` / `0x20` -> `NEVT (Local0, Local0)` (`101676–101681`, brightness down)
  - `0x82` / `0x21` -> `NEVT (Local0, Local0)` (`101683–101688`, brightness up)
  - `0x9E` -> `NEVT (0x9E, 0x9E)` (`101726–101731`)
  - `0x9F` / `0x3F` -> `NEVT (Local0, Local0)` (`101733–101738`, backlight toggle)
  - `0x80` -> `NEVT (0x83, 0x83)` (`101669–101674`, RGB color cycle)
  - `0x8A` -> `NEVT (0x8A, 0x8A)` (`101696–101700`, white brightness cycle)
  - Notice that inside `_Q50`, even the `If ((OSYS == 0x03E8)){}` Linux fallback blocks are **empty**!
- **`NEVT` (`dsdt.dsl:100889–100901`):**
  ```asl
  Method (NEVT, 2, NotSerialized)
  {
      If (^^^^DCHU.HKDR) { ^^^^DCHU.EVNT = Arg0; Notify (DCHU, Arg1) }
      ElseIf (^^^^WMI.HKDR) { ^^^^WMI.EVNT = Arg0; Notify (WMI, 0xD0) }
  }
  ```
  Because no Linux driver has bound `CLV0001` or `ABBC0F6B/D` and called **`_DSM 0x46`** (`HKDR = One`), **`NEVT` silently discards every keyboard-backlight hotkey press**! Meanwhile standard keys (`Fn+F1..F12` volume/brightness/etc.) go via PS/2 AT scancodes, `_Q11`/`_Q12` (`Notify(GFX0.DD1F, 0x86/0x87)`), or `HIDD` (`INTC1051`), which is why all other `Fn` hotkeys already worked.

---

## 6. `_OSI` Gating & WMI BMOF (`WQBB` / `WQMX`) Check

### 6.1 Every `_OSI` Call in `dsdt.dsl` / `ssdt*.dsl`
Grep across all 42 `.dsl` files found `_OSI` **only** in `dsdt.dsl`:
1. **`dsdt.dsl:30743–30799`:** Sets `OSYS` (`0x03E8` default, `0x07D1`..`0x07DF` up to `_OSI ("Windows 2015") -> OSYS = 0x07DF`). There are **no** newer `_OSI` strings (`Windows 2018`/`2020`/`2022`).
2. **`dsdt.dsl:34840`:** `If (_OSI ("Processor Aggregator Device"))`.

**Impact assessment:**
- Linux kernels >= 4.x already return `TRUE` for `_OSI("Windows 2015")`, so `OSYS == 0x07DF` right now (independently confirmed by `CLV0001:00`, `CLV0002:00`, and `INTC1051:00` all evaluating `_STA == 0x0F`, which requires `OSYS >= 0x07DC`/`0x07DD`).
- Setting `acpi_osi=Linux` or `acpi_osi='!Windows 2015'` would **drop `OSYS` below `0x07DC`**, which would **hide `CLV0001`, `CLV0002`, and `INTC1051`** (`_STA` returns `0` at `dsdt.dsl:102570`, `108029`, `100229`).
- **Conclusion:** **NO `acpi_osi` GRUB kernel parameter change is warranted or beneficial.**

### 6.2 WMI BMOF (`WQBB` / `WQMX` / `05901221`)
- `WQBB`, `WQMX`, and the standard WMI MOF GUID (`05901221-D566-11D1-B2F0-00A0C9062910`) are **absent** across `dsdt.dsl` and all `ssdt*.dsl`.
- `_SB.WMI._WDG` (`dsdt.dsl:96055–96065`) defines only `ABBC0F6D` (`"BB"` method), `ABBC0F6B` (`0xD0` event), and `ABBC0F6C` (`0xD1` event).
- `ssdt7.dsl` `WMI1` (`OPT1`, lines `1550–1580`) defines only `F6CB5C3C-9CAE-4EBD-B577-931EA32A2CC0` (`"MX"` method -> `GFX0._DSM`).
- Therefore `/sys/bus/wmi/devices/*/bmof` is absent by firmware design; full method semantics are instead directly documented in `dsdt.dsl` above.

---

## 7. Evidence-Based Recommendation for Phase 3 Step 2

### 7.1 Interface Verdict for `BIOS 1.14RA1`
- **Primary Hardware Interface:** **`CLV0001` (`_SB.DCHU._DSM`, UUID `93f224e4-fbdc-4bbf-add6-db71bdc0afad`)** (Path B — clean ACPI control method interface; no raw `ec_sys write_support=1` needed, no `acpi_osi` GRUB edit needed).
- **Backup Equivalent:** `ABBC0F6D` (`WMBB` calls the exact same `SCMD`/`GCMD` logic).
- **Supported Capabilities Confirmed in DSDT:**
  1. **Keyboard RGB + Brightness:** `_DSM 0x67` (`0xE0` init/power, `0xF0` single-zone `0xFA=B, 0xFB=R, 0xFC=G`, `0xF4` brightness) -> `ECMD 0xCA`, plus `_DSM 0x46` to enable `Fn+backlight` hotkeys (`NEVT` `0x81`/`0x82`/`0x83`/`0x9F`). (Also check `PK0D[0x0F]` `KBTP` value at runtime.)
  2. **Fan Readout (RPM + Duty + Temps):** `_DSM 0x0C` (`PK0C`: `RPM1`/`RPM2` tach periods + duty + temps) and `_DSM 0x63`/`0x64` (`GET_FANINFO1/2`).
  3. **Fan Manual Duty & Auto Release:** `_DSM 0x68` (set fan 1/2 duty 0–255) and `_DSM 0x69` (`0x0F` return to EC auto).
  4. **Thermal/Performance Profiles:** `_DSM 0x79` subcmd `0x01` (`0`=balanced, `1`=max-fan, `5`=quiet, `7`=performance -> `ECMD 0xD7`) and subcmd `0x19` (DPTF/TDP profile `ECMD 0xD8`).
  5. **FlexiCharger Battery Limit (Optional):** `_DSM 0x76`/`0x77` (and `0x04` `0x1E`/`0x1F`).

### 7.2 Recommended Driver Strategy for Step 2 (Requires Explicit User Approval)
1. **Test Patched `tuxedo-drivers` First (`nick42d/clevo-drivers` / `Atul977` patch: `tuxedo_is_compatible() -> true`, built locally in `control-center/driver/`):**
   - **Why first:** Directly binds `CLV0001` (`clevo_acpi.ko`), calls `_DSM 0x0D` (`PK0D` to reveal `KBTP`), `_DSM 0x46` (enables hotkeys), `_DSM 0x67` (`0xE0`/`0xF0`/`0xF4` -> `rgb:kbd_backlight`), `_DSM 0x76`/`0x77` (battery thresholds), and exposes `/dev/tuxedo_io` for `_DSM 0x63/0x64/0x68/0x69/0x79`.
   - **Watch-out:** Verify on load what `PK0D[0x0F]` (`KBTP`) returns; if `KBTP == 0x00` or `0x01`, `tuxedo-drivers` could misclassify as white-only/none (`0x52` fallback doesn't know 1-zone RGB), and `tuxedo_io` lacks an in-kernel fan watchdog or `hwmon` sysfs.
2. **Preferred Production Driver Architecture (if `tuxedo-drivers` misdetects `KBTP` or for `hwmon` + 15s watchdog):**
   - Adapt **`clevo-acpi-dkms`** (add `Aspire A715-79G` DMI match, use `_DSM 0x67` `0xF0`/`0xF4` or verified `ECMD 0xCA`, add `PK0C` `RPM1/RPM2` `hwmon` readout inspired by **`opendchu`** `dchu_hwmon.c`, and keep `clevo-acpi-dkms`'s **15s in-kernel dead-man's-switch fan watchdog** calling `_DSM 0x69 0x0F`).
   - `opendchu` alone is **not** recommended as the sole driver because `dchu_leds.c` calls white-only `_DSM 0x3D`/`0x27` instead of `_DSM 0x67` and `dchu_hwmon.c` lacks `_DSM 0x68`/`0x69` continuous fan control and watchdog.
   - `the3rdchild`'s `acer-ec` raw `ECMD 0xCA` workaround is **not** needed as primary path on `BIOS 1.14RA1` (since `_DSM 0x67` is fully implemented), though its `0xFE0B0100` EC map (`0x07`, `0xCE/0xCF`, `0xD0..0xD3`) is 100% confirmed.
