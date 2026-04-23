#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design - hello@bard0.com

"""
Arty A7-100T JPEG-LS encoder demo runner.

End-to-end flow:
  1. (optional) build the bitstream via Vivado
  2. program the FPGA over JTAG (Xilinx hw_server)
  3. load a .pgm image
  4. push pixels into the encoder over EJTAG-AXI (fpgacapZero)
  5. drain the encoded JPEG-LS byte stream over EJTAG-AXI
  6. (optional) decode the .jls with ../SIM/JPEGLSdec.exe and byte-compare
     against the source .pgm (lossless roundtrip check for NEAR=0)

The single-binary bitstream has NEAR baked in via synthesis. For this demo
the compile-time value is 0 (lossless). See arty_jls_top.v to change it.

Usage:
    python run_demo.py --build                  # synth+impl+bitstream
    python run_demo.py --image test001.pgm      # end-to-end run
    python run_demo.py --image x.pgm --no-verify
    python run_demo.py --image x.pgm --build    # do everything
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

HERE           = Path(__file__).parent.resolve()
JLS_ROOT       = HERE.parent.parent
BITFILE        = HERE / "arty_jls_top.bit"
BUILD_TCL      = HERE / "build.tcl"
REF_DECODER    = JLS_ROOT / "SIM" / "JPEGLSdec.exe"
FCAPZ_ROOT     = Path(
    os.environ.get("FCAPZ_ROOT", str(JLS_ROOT / "fcapz"))
).resolve()

# -- Register map (must match axi_jls_ctrl.v) --
REG_CTRL    = 0x0000
REG_WIDTH   = 0x0004
REG_HEIGHT  = 0x0008
REG_STATUS  = 0x000C
REG_NEAR    = 0x0010
PIX_IN_BASE = 0x1000
OUT_BASE    = 0x2000

CTRL_SOFT_RESET = 1 << 0
CTRL_SOF        = 1 << 1
CTRL_DONE_CLEAR = 1 << 2

BATCH_MAX = 256  # chunk pushes/pulls this many words per JTAG batch


def sh(cmd, **kw):
    print(f"$ {' '.join(str(c) for c in cmd)}", flush=True)
    return subprocess.run(cmd, check=False, **kw)


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
def build_bitstream():
    vivado = os.environ.get("VIVADO", "vivado")
    cmd = [vivado, "-mode", "batch", "-source", str(BUILD_TCL)]
    r = sh(cmd, cwd=HERE)
    if r.returncode != 0:
        raise RuntimeError("Vivado build failed")
    if not BITFILE.exists():
        raise RuntimeError(f"Build completed but {BITFILE} not found")


# ---------------------------------------------------------------------------
# PGM load
# ---------------------------------------------------------------------------
def load_pgm(path: Path):
    """Return (width, height, bytes) for a P5 (binary) PGM with depth 255."""
    with open(path, "rb") as f:
        magic = f.readline().strip()
        if magic != b"P5":
            raise ValueError(f"{path}: not a P5 (binary) PGM")

        def read_int():
            while True:
                line = f.readline()
                if not line:
                    raise ValueError(f"{path}: unexpected EOF in header")
                line = line.split(b"#", 1)[0].strip()
                if line:
                    return line

        hdr = b""
        while hdr.count(b" ") + hdr.count(b"\n") < 2:
            hdr += read_int() + b" "
        parts = hdr.split()
        w, h = int(parts[0]), int(parts[1])

        depth_line = read_int()
        depth = int(depth_line.split()[0])
        if depth != 255:
            raise ValueError(f"{path}: depth {depth} unsupported (need 255)")

        data = f.read(w * h)
        if len(data) != w * h:
            raise ValueError(
                f"{path}: expected {w*h} pixel bytes, got {len(data)}"
            )
    return w, h, data


# ---------------------------------------------------------------------------
# AXI helpers
# ---------------------------------------------------------------------------
def decode_status(s: int):
    return dict(
        busy         = bool(s & 0x1),
        done         = bool(s & 0x2),
        in_full      = bool(s & 0x4),
        out_empty    = bool(s & 0x8),
        in_count     = (s >> 8)  & 0x7FF,   # 11 bits, 0..1024
        out_count    = (s >> 16) & 0x1FF,   # 9 bits, 0..256
        out_overflow = bool((s >> 28) & 0x1),
    )


def format_status(st: dict[str, int | bool]) -> str:
    return (
        "busy={busy} done={done} in_full={in_full} out_empty={out_empty} "
        "in_count={in_count} out_count={out_count} out_overflow={out_overflow}"
    ).format(**st)


def read_bridge_cfg(bridge, addr: int) -> int:
    from fcapz.ejtagaxi import CMD_CONFIG, CMD_NOP

    bridge._scan(CMD_CONFIG, addr=addr)
    _, _, rdata, _ = bridge._scan(CMD_NOP)
    return rdata


def dump_bridge_debug(bridge) -> str:
    regs = {
        "resp_wr_count": 0x01A0,
        "resp_wr0_data": 0x01A4,
        "resp_wr0_meta": 0x01A8,
        "resp_wr1_data": 0x01AC,
        "resp_wr1_meta": 0x01B0,
        "resp_wr2_data": 0x01B4,
        "resp_wr2_meta": 0x01B8,
        "resp_wr3_data": 0x01BC,
        "resp_wr3_meta": 0x01C0,
        "resp_cap_count": 0x01C4,
        "resp_cap0_data": 0x01C8,
        "resp_cap0_meta": 0x01CC,
        "resp_cap1_data": 0x01D0,
        "resp_cap1_meta": 0x01D4,
        "resp_cap2_data": 0x01D8,
        "resp_cap2_meta": 0x01DC,
        "resp_cap3_data": 0x01E0,
        "resp_cap3_meta": 0x01E4,
        "axi_deq_count": 0x01E8,
        "axi_deq0_addr": 0x01EC,
        "axi_deq0_meta": 0x01F0,
        "axi_deq1_addr": 0x01F4,
        "axi_deq1_meta": 0x01F8,
        "axi_deq2_addr": 0x01FC,
        "axi_deq2_meta": 0x0200,
        "axi_deq3_addr": 0x0204,
        "axi_deq3_meta": 0x0208,
    }
    parts = []
    for name, addr in regs.items():
        try:
            parts.append(f"{name}=0x{read_bridge_cfg(bridge, addr):08X}")
        except Exception as e:
            parts.append(f"{name}=<read failed: {e}>")
    return " ".join(parts)


# ---------------------------------------------------------------------------
# Encode flow
# ---------------------------------------------------------------------------
def encode_image(pgm_path: Path, out_jls: Path, no_program: bool):
    try:
        from fcapz.transport import XilinxHwServerTransport
        from fcapz.ejtagaxi import EjtagAxiController
    except ImportError:
        print("ERROR: fpgacapZero host stack not importable.", file=sys.stderr)
        print(f"  Install with: pip install -e {FCAPZ_ROOT}", file=sys.stderr)
        raise

    w, h, pix = load_pgm(pgm_path)
    print(f"[pgm] {pgm_path}: {w}x{h} ({len(pix)} bytes)")

    if w < 5 or w > 16384 or h < 1 or h > 16384:
        raise ValueError(f"Image size {w}x{h} outside encoder range")

    transport = XilinxHwServerTransport(
        fpga_name="xc7a100t",
        bitfile=str(BITFILE).replace("\\", "/") if not no_program else None,
        # Skip ELA/USER1 probe — this design only uses USER4 (EJTAG-AXI).
        ready_probe_addr=None,
    )
    bridge = EjtagAxiController(transport, chain=4)

    info = bridge.connect()
    print(f"[axi] connected: {info}")
    t0 = time.time()

    try:
        # -- Soft reset -----------------------------------------------------
        bridge.axi_write(REG_CTRL, CTRL_SOFT_RESET)
        time.sleep(0.01)
        bridge.axi_write(REG_CTRL, 0)

        # -- Width / height --------------------------------------------------
        bridge.axi_write(REG_WIDTH,  w)
        bridge.axi_write(REG_HEIGHT, h)
        rw = bridge.axi_read(REG_WIDTH)  & 0x3FFF
        rh = bridge.axi_read(REG_HEIGHT) & 0x3FFF
        if rw != w or rh != h:
            raise RuntimeError(f"W/H readback mismatch: {rw}x{rh} != {w}x{h}")

        # -- SOF strobe ------------------------------------------------------
        bridge.axi_write(REG_CTRL, CTRL_SOF)

        # -- Push pixels while draining output in-between -------------------
        out_bytes = bytearray()
        got_last  = False
        pix_idx   = 0
        N         = len(pix)

        def drain_some():
            """Drain everything currently in the out FIFO."""
            nonlocal got_last
            while not got_last:
                st = decode_status(bridge.axi_read(REG_STATUS))
                if st["out_overflow"]:
                    raise RuntimeError(
                        "Output FIFO overflow detected before drain: "
                        f"{format_status(st)}"
                    )
                n = st["out_count"]
                if n == 0:
                    return
                # Read words one at a time via WRITE_INC-style reads. burst_read
                # showed bridge-state issues at >9 beats on this slave; use
                # single-word reads which are proven reliable.
                for batch_idx in range(min(n, BATCH_MAX)):
                    out_word_idx = len(out_bytes) // 2
                    try:
                        w32 = bridge.axi_read(OUT_BASE)
                    except Exception as e:
                        try:
                            post_st = decode_status(bridge.axi_read(REG_STATUS))
                            post_status_msg = format_status(post_st)
                        except Exception as status_err:
                            post_status_msg = f"<status read failed: {status_err}>"
                        bridge_debug = dump_bridge_debug(bridge)
                        raise RuntimeError(
                            "OUT_BASE read failed at "
                            f"word={out_word_idx} byte_off={len(out_bytes)} "
                            f"batch_idx={batch_idx} "
                            f"pre_status=({format_status(st)}) "
                            f"post_status=({post_status_msg}) "
                            f"bridge_debug=({bridge_debug})"
                        ) from e
                    data = w32 & 0xFFFF
                    last = bool((w32 >> 16) & 1)
                    out_bytes.append(data & 0xFF)
                    out_bytes.append((data >> 8) & 0xFF)
                    if last:
                        got_last = True
                        break

        # Push pixels via write_block (AXI WRITE_INC; auto-increments address).
        # Every word lands in the 0x1000 pix-in window and pushes 1 pixel.
        while pix_idx < N:
            st = decode_status(bridge.axi_read(REG_STATUS))
            if st["out_overflow"]:
                raise RuntimeError(
                    "Output FIFO overflow detected during input push: "
                    f"{format_status(st)}"
                )
            free = 1024 - st["in_count"]
            if free <= 0:
                drain_some()
                continue
            batch = min(N - pix_idx, free, BATCH_MAX)
            chunk = [pix[pix_idx + i] for i in range(batch)]
            bridge.write_block(PIX_IN_BASE, chunk, wstrb=0x1)
            pix_idx += batch
            drain_some()

        # All pixels queued — wait for completion
        deadline = time.time() + 60.0  # generous; 256x256 over JTAG ~ minutes
        while not got_last and time.time() < deadline:
            drain_some()
            if got_last:
                break
            st = decode_status(bridge.axi_read(REG_STATUS))
            if st["out_overflow"]:
                raise RuntimeError(
                    "Output FIFO overflow detected while waiting for completion: "
                    f"{format_status(st)}"
                )
            if st["done"] and st["out_count"] == 0:
                got_last = True
                break
            time.sleep(0.005)

        if not got_last:
            raise RuntimeError("Timeout waiting for o_last")

        dt = time.time() - t0
        print(f"[axi] encoded {N}B -> {len(out_bytes)}B in {dt:.2f}s "
              f"({N/dt/1024:.1f} kB/s in)")
        out_jls.write_bytes(out_bytes)
        print(f"[jls] wrote {out_jls} ({len(out_bytes)} bytes)")
    finally:
        try:
            bridge.close()
        except Exception as e:
            print(f"[warn] bridge.close failed: {e}")


# ---------------------------------------------------------------------------
# Roundtrip verify
# ---------------------------------------------------------------------------
def verify_roundtrip(jls_path: Path, src_pgm: Path):
    if not REF_DECODER.exists():
        print(f"[verify] skipping, decoder not at {REF_DECODER}")
        return None

    decoded = jls_path.with_suffix(".decoded.pgm")
    # The reference decoder prints banners and can return a non-zero status
    # even on success; trust file existence instead.
    sh([str(REF_DECODER), f"-i{jls_path}", f"-o{decoded}"])
    if not decoded.exists():
        raise RuntimeError("Decoder did not produce an output file")

    # Compare pixels only (skip PGM header)
    _, _, ref_pix = load_pgm(src_pgm)
    _, _, got_pix = load_pgm(decoded)

    if ref_pix == got_pix:
        print(f"[verify] PASS: {len(ref_pix)} bytes match")
        return True
    diffs = sum(1 for a, b in zip(ref_pix, got_pix) if a != b)
    print(f"[verify] FAIL: {diffs}/{len(ref_pix)} bytes differ")
    return False


# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build",       action="store_true",
                    help="Synthesize and write bitstream before running")
    ap.add_argument("--image",       type=Path,
                    help=".pgm image to encode")
    ap.add_argument("--out",         type=Path, default=None,
                    help="output .jls (default: <image>.jls)")
    ap.add_argument("--no-program",  action="store_true",
                    help="Skip bitstream programming (assume FPGA already loaded)")
    ap.add_argument("--no-verify",   action="store_true",
                    help="Skip decode+compare roundtrip")
    args = ap.parse_args()

    if not args.build and not args.image:
        ap.error("supply --build, --image, or both")

    if args.build:
        build_bitstream()

    if args.image:
        if not args.image.is_file():
            ap.error(f"image not found: {args.image}")
        out = args.out if args.out else args.image.with_suffix(".jls")
        encode_image(args.image, out, args.no_program)
        if not args.no_verify:
            verify_roundtrip(out, args.image)


if __name__ == "__main__":
    main()
