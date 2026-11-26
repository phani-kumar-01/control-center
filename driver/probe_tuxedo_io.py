#!/usr/bin/env python3
"""
Phase 3 Step 2 probe & telemetry tool for /dev/tuxedo_io (tuxedo-drivers v0.3.9)
with read-only ec_sys cross-check and live CPU/ACPI/GPU temperature readout.
"""

import argparse
import ctypes
import fcntl
import glob
import os
import struct
import subprocess
import sys

# Linux ioctl encoding (x86_64: sizeof(void *) == 8)
_IOC_NRBITS = 8
_IOC_TYPEBITS = 8
_IOC_SIZEBITS = 14
_IOC_DIRBITS = 2

_IOC_NRSHIFT = 0
_IOC_TYPESHIFT = _IOC_NRSHIFT + _IOC_NRBITS
_IOC_SIZESHIFT = _IOC_TYPESHIFT + _IOC_TYPEBITS
_IOC_DIRSHIFT = _IOC_SIZESHIFT + _IOC_SIZEBITS

_IOC_NONE = 0
_IOC_WRITE = 1
_IOC_READ = 2

PTR_SIZE = ctypes.sizeof(ctypes.c_void_p)


def _ioc(direction: int, ioc_type: int, nr: int, size: int) -> int:
    return (
        (direction << _IOC_DIRSHIFT)
        | (ioc_type << _IOC_TYPESHIFT)
        | (nr << _IOC_NRSHIFT)
        | (size << _IOC_SIZESHIFT)
    )


def _ior(ioc_type: int, nr: int, size: int = PTR_SIZE) -> int:
    return _ioc(_IOC_READ, ioc_type, nr, size)


def _iow(ioc_type: int, nr: int, size: int = PTR_SIZE) -> int:
    return _ioc(_IOC_WRITE, ioc_type, nr, size)


# From driver/tuxedo-drivers/src/tuxedo_io/tuxedo_io_ioctl.h
IOCTL_MAGIC = 0xEC
MAGIC_READ_CL = IOCTL_MAGIC + 1   # 0xED
MAGIC_WRITE_CL = IOCTL_MAGIC + 2  # 0xEE

R_MOD_VERSION = _ior(IOCTL_MAGIC, 0x00, PTR_SIZE)
R_HWCHECK_CL = _ior(IOCTL_MAGIC, 0x05, PTR_SIZE)
R_HWCHECK_UW = _ior(IOCTL_MAGIC, 0x06, PTR_SIZE)

R_CL_HW_IF_STR = _ior(MAGIC_READ_CL, 0x00, PTR_SIZE)
R_CL_FANINFO1 = _ior(MAGIC_READ_CL, 0x10, PTR_SIZE)
R_CL_FANINFO2 = _ior(MAGIC_READ_CL, 0x11, PTR_SIZE)
R_CL_FANINFO3 = _ior(MAGIC_READ_CL, 0x12, PTR_SIZE)
R_CL_WEBCAM_SW = _ior(MAGIC_READ_CL, 0x13, PTR_SIZE)
R_CL_FLIGHTMODE_SW = _ior(MAGIC_READ_CL, 0x14, PTR_SIZE)
R_CL_TOUCHPAD_SW = _ior(MAGIC_READ_CL, 0x15, PTR_SIZE)

W_CL_FANSPEED = _iow(MAGIC_WRITE_CL, 0x10, PTR_SIZE)
W_CL_FANAUTO = _iow(MAGIC_WRITE_CL, 0x11, PTR_SIZE)
W_CL_PERF_PROFILE = _iow(MAGIC_WRITE_CL, 0x15, PTR_SIZE)

TUXEDO_IO_DEV = "/dev/tuxedo_io"
EC_IO_PATH = "/sys/kernel/debug/ec/ec0/io"
EC_WRITE_SUPPORT_PATH = "/sys/module/ec_sys/parameters/write_support"


def ioctl_read_str(fd: int, req: int, buf_len: int = 64) -> str:
    buf = bytearray(buf_len)
    fcntl.ioctl(fd, req, buf, True)
    return bytes(buf).split(b"\x00", 1)[0].decode("utf-8", errors="replace")


def ioctl_read_i32(fd: int, req: int) -> int:
    buf = bytearray(4)
    fcntl.ioctl(fd, req, buf, True)
    return struct.unpack("<i", buf)[0]


def ioctl_write_i32(fd: int, req: int, val: int) -> None:
    buf = struct.pack("<i", val)
    fcntl.ioctl(fd, req, buf)


def decode_faninfo(val: int) -> dict:
    raw = val & 0xFFFFFFFF
    duty = raw & 0xFF
    temp1 = (raw >> 8) & 0xFF
    temp2 = (raw >> 16) & 0xFF
    pct = round(duty * 100.0 / 255.0, 1)
    return {
        "raw": raw,
        "duty": duty,
        "pct": pct,
        "temp1": temp1,
        "temp2": temp2,
    }


def read_ec_ro() -> dict | None:
    if not os.path.exists(EC_IO_PATH):
        return None
    if os.path.exists(EC_WRITE_SUPPORT_PATH):
        with open(EC_WRITE_SUPPORT_PATH, "r", encoding="utf-8") as f:
            ws = f.read().strip()
        if ws != "N":
            print(f"[ec_sys] WARNING: write_support={ws} (expected N); refusing EC read.", file=sys.stderr)
            return None
    with open(EC_IO_PATH, "rb") as f:
        data = f.read(256)
    if len(data) < 0xD4:
        return None

    rpm1_le = struct.unpack_from("<H", data, 0xD0)[0]
    rpm2_le = struct.unpack_from("<H", data, 0xD2)[0]
    rpm1_be = struct.unpack_from(">H", data, 0xD0)[0]
    rpm2_be = struct.unpack_from(">H", data, 0xD2)[0]

    return {
        "tmp_c": data[0x07],
        "dut1": data[0xCE],
        "dut1_pct": round(data[0xCE] * 100.0 / 255.0, 1),
        "dut2": data[0xCF],
        "dut2_pct": round(data[0xCF] * 100.0 / 255.0, 1),
        "rpm1_bytes": data[0xD0:0xD2].hex(" "),
        "rpm2_bytes": data[0xD2:0xD4].hex(" "),
        "rpm1_le_60m": round(60_000_000 / rpm1_le) if rpm1_le else 0,
        "rpm2_le_60m": round(60_000_000 / rpm2_le) if rpm2_le else 0,
        "rpm1_be_2m": round(2_156_220 / rpm1_be) if rpm1_be else 0,
        "rpm2_be_2m": round(2_156_220 / rpm2_be) if rpm2_be else 0,
        "dthl": data[0xD7],
        "dtbp": data[0xD8],
        "airp": data[0xD9],
        "winf": data[0xDA],
        "rinf": data[0xDB],
    }


def read_temps() -> dict:
    temps: dict[str, float | None] = {
        "coretemp_pkg_c": None,
        "coretemp_max_c": None,
        "acpitz_c": None,
        "gpu_c": None,
        "max_c": None,
    }

    for hwmon in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
        name_path = os.path.join(hwmon, "name")
        if not os.path.exists(name_path):
            continue
        with open(name_path, "r", encoding="utf-8") as f:
            name = f.read().strip()
        if name == "coretemp":
            vals = []
            for inp in sorted(glob.glob(os.path.join(hwmon, "temp*_input"))):
                try:
                    with open(inp, "r", encoding="utf-8") as f:
                        c = int(f.read().strip()) / 1000.0
                    vals.append(c)
                    lbl_path = inp.replace("_input", "_label")
                    if os.path.exists(lbl_path):
                        with open(lbl_path, "r", encoding="utf-8") as lf:
                            if "Package" in lf.read():
                                temps["coretemp_pkg_c"] = c
                except OSError:
                    pass
            if vals:
                temps["coretemp_max_c"] = max(vals)
        elif name.startswith("acpitz"):
            inp = os.path.join(hwmon, "temp1_input")
            if os.path.exists(inp):
                try:
                    with open(inp, "r", encoding="utf-8") as f:
                        temps["acpitz_c"] = int(f.read().strip()) / 1000.0
                except OSError:
                    pass

    try:
        out = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader,nounits"],
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=3,
        ).strip()
        if out:
            temps["gpu_c"] = float(out.splitlines()[0].strip())
    except (OSError, subprocess.SubprocessError, ValueError):
        pass

    numeric = [v for k, v in temps.items() if k != "max_c" and v is not None]
    temps["max_c"] = max(numeric) if numeric else None
    return temps


def print_ec_summary(ec: dict | None) -> None:
    if ec is None:
        print("[ec_sys] /sys/kernel/debug/ec/ec0/io not available or unreadable (skipping EC cross-check)")
        return
    print(
        "[ec_sys RO] "
        f"0x07(TMP)={ec['tmp_c']}C | "
        f"0xCE(DUT1)={ec['dut1']}/255 ({ec['dut1_pct']}%) | "
        f"0xCF(DUT2)={ec['dut2']}/255 ({ec['dut2_pct']}%) | "
        f"0xD0..D1(RPM1)=[{ec['rpm1_bytes']}] -> {ec['rpm1_le_60m']} RPM (60M/LE) / {ec['rpm1_be_2m']} RPM (2.15M/BE) | "
        f"0xD2..D3(RPM2)=[{ec['rpm2_bytes']}] -> {ec['rpm2_le_60m']} RPM (60M/LE) / {ec['rpm2_be_2m']} RPM (2.15M/BE)"
    )


def cmd_telemetry() -> int:
    if not os.path.exists(TUXEDO_IO_DEV):
        print(f"ERROR: {TUXEDO_IO_DEV} does not exist.", file=sys.stderr)
        return 1
    with open(TUXEDO_IO_DEV, "rb+", buffering=0) as fd:
        fno = fd.fileno()
        mod_ver = ioctl_read_str(fno, R_MOD_VERSION)
        hw_cl = ioctl_read_i32(fno, R_HWCHECK_CL)
        hw_uw = ioctl_read_i32(fno, R_HWCHECK_UW)
        if_str = ioctl_read_str(fno, R_CL_HW_IF_STR)
        fan1 = decode_faninfo(ioctl_read_i32(fno, R_CL_FANINFO1))
        fan2 = decode_faninfo(ioctl_read_i32(fno, R_CL_FANINFO2))
        fan3 = decode_faninfo(ioctl_read_i32(fno, R_CL_FANINFO3))
        webcam = ioctl_read_i32(fno, R_CL_WEBCAM_SW)
        flight = ioctl_read_i32(fno, R_CL_FLIGHTMODE_SW)
        touchpad = ioctl_read_i32(fno, R_CL_TOUCHPAD_SW)

    print(f"[tuxedo_io] R_MOD_VERSION={mod_ver} R_HWCHECK_CL={hw_cl} R_HWCHECK_UW={hw_uw} R_CL_HW_IF_STR='{if_str}'")
    print(
        f"[tuxedo_io] R_CL_FANINFO1=0x{fan1['raw']:08x} "
        f"(duty={fan1['duty']}/255 {fan1['pct']}%, temp1={fan1['temp1']}C, temp2={fan1['temp2']}C)"
    )
    print(
        f"[tuxedo_io] R_CL_FANINFO2=0x{fan2['raw']:08x} "
        f"(duty={fan2['duty']}/255 {fan2['pct']}%, temp1={fan2['temp1']}C, temp2={fan2['temp2']}C)"
    )
    print(
        f"[tuxedo_io] R_CL_FANINFO3=0x{fan3['raw']:08x} "
        f"(duty={fan3['duty']}/255 {fan3['pct']}%, temp1={fan3['temp1']}C, temp2={fan3['temp2']}C)"
    )
    print(f"[tuxedo_io] switches: webcam={webcam} flightmode={flight} touchpad={touchpad}")
    print("[tuxedo_io] note: tuxedo_io v0.3.9 has no GET_SPEC (0x0D) or GET_AP_MODE ioctl; check dmesg for PK0D[0x0f] KBTP.")
    print_ec_summary(read_ec_ro())
    return 0


def cmd_fan_auto() -> int:
    with open(TUXEDO_IO_DEV, "rb+", buffering=0) as fd:
        ioctl_write_i32(fd.fileno(), W_CL_FANAUTO, 0x0F)
    print("[tuxedo_io] W_CL_FANAUTO(0x0F) sent -> fans returned to EC auto")
    return 0


def cmd_fan_set(duties: list[int]) -> int:
    for d in duties:
        if not 0 <= d <= 255:
            print(f"ERROR: duty {d} out of range 0..255", file=sys.stderr)
            return 2
    d1 = duties[0]
    d2 = duties[1]
    d3 = duties[2] if len(duties) > 2 else 0
    arg = d1 | (d2 << 8) | (d3 << 16)
    with open(TUXEDO_IO_DEV, "rb+", buffering=0) as fd:
        ioctl_write_i32(fd.fileno(), W_CL_FANSPEED, arg)
    print(f"[tuxedo_io] W_CL_FANSPEED(0x{arg:06x}) sent -> fan1={d1}/255 fan2={d2}/255 fan3={d3}/255")
    return 0


def cmd_set_profile(prof: int) -> int:
    if not 0 <= prof <= 3:
        print(f"ERROR: profile {prof} out of range 0..3 (0=quiet,1=powersave,2=perf,3=entertainment)", file=sys.stderr)
        return 2
    with open(TUXEDO_IO_DEV, "rb+", buffering=0) as fd:
        ioctl_write_i32(fd.fileno(), W_CL_PERF_PROFILE, prof)
    print(f"[tuxedo_io] W_CL_PERF_PROFILE({prof}) sent (_DSM 0x79 subcmd 0x19)")
    return 0


def cmd_temps(max_limit: float | None) -> int:
    t = read_temps()
    print(
        f"CPU_PKG={t['coretemp_pkg_c']}C CPU_MAX={t['coretemp_max_c']}C "
        f"ACPITZ={t['acpitz_c']}C GPU={t['gpu_c']}C MAX={t['max_c']}C"
    )
    if max_limit is not None and t["max_c"] is not None and t["max_c"] >= max_limit:
        print(f"ABORT: max temperature {t['max_c']}C >= limit {max_limit}C", file=sys.stderr)
        return 3
    return 0


def cmd_dry_run() -> int:
    print(f"[dry-run] x86_64 pointer size = {PTR_SIZE} bytes")
    print(f"[dry-run] R_MOD_VERSION     = 0x{R_MOD_VERSION:08x}")
    print(f"[dry-run] R_HWCHECK_CL      = 0x{R_HWCHECK_CL:08x}")
    print(f"[dry-run] R_CL_HW_IF_STR    = 0x{R_CL_HW_IF_STR:08x}")
    print(f"[dry-run] R_CL_FANINFO1     = 0x{R_CL_FANINFO1:08x}")
    print(f"[dry-run] R_CL_FANINFO2     = 0x{R_CL_FANINFO2:08x}")
    print(f"[dry-run] W_CL_FANSPEED     = 0x{W_CL_FANSPEED:08x}")
    print(f"[dry-run] W_CL_FANAUTO      = 0x{W_CL_FANAUTO:08x}")
    print(f"[dry-run] W_CL_PERF_PROFILE = 0x{W_CL_PERF_PROFILE:08x}")
    return cmd_temps(None)


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe /dev/tuxedo_io and read-only ec_sys telemetry.")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--dry-run", action="store_true", help="Print ioctl numbers and read sysfs temps without touching /dev/tuxedo_io")
    group.add_argument("--telemetry", action="store_true", help="Read /dev/tuxedo_io telemetry and RO ec_sys registers")
    group.add_argument("--ec-only", action="store_true", help="Read-only ec_sys register check (0x07, 0xCE..0xD3)")
    group.add_argument("--temps", action="store_true", help="Print live CPU/ACPI/GPU temperatures")
    group.add_argument("--fan-auto", action="store_true", help="Restore fans to EC auto (W_CL_FANAUTO 0x0F)")
    group.add_argument("--fan-set", nargs="+", type=int, metavar="DUTY", help="Set fan duties 0..255 (d1 d2 [d3])")
    group.add_argument("--set-profile", type=int, metavar="ID", help="Set DPTF/perf profile 0..3 via W_CL_PERF_PROFILE")
    parser.add_argument("--max-temp", type=float, default=None, help="With --temps, exit 3 if max temp >= threshold C")

    args = parser.parse_args()
    if args.dry_run:
        return cmd_dry_run()
    if args.telemetry:
        return cmd_telemetry()
    if args.ec_only:
        print_ec_summary(read_ec_ro())
        return 0
    if args.temps:
        return cmd_temps(args.max_temp)
    if args.fan_auto:
        return cmd_fan_auto()
    if args.fan_set:
        if len(args.fan_set) < 2 or len(args.fan_set) > 3:
            parser.error("--fan-set requires 2 or 3 duty values (0..255)")
        return cmd_fan_set(args.fan_set)
    if args.set_profile is not None:
        return cmd_set_profile(args.set_profile)
    return 0


if __name__ == "__main__":
    sys.exit(main())
