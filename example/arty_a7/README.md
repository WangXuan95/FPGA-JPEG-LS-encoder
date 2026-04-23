<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 Leonardo Capossio - bard0 design - hello@bard0.com -->

# Arty A7-100T example — hardware JPEG-LS encoder demo

End-to-end hardware demo of the JPEG-LS encoder on a [Digilent Arty A7-100T](https://digilent.com/reference/programmable-logic/arty-a7/) (`xc7a100tcsg324-1`). Pixels and compressed bytes move over JTAG using the [fpgacapZero](https://github.com/lcapossio/fpgacapZero) EJTAG-AXI bridge — no UART, no extra cables, just the onboard USB-JTAG.

## Architecture

```
┌─────────────────────┐  JTAG (Arty USB) ┌───────────────────────────────┐
│ run_demo.py (host)  │ ←─────────────→ │ arty_jls_top                   │
│  - load .pgm        │                 │  ├─ MMCM 100 → 50 MHz          │
│  - AXI writes pix   │                 │  ├─ fcapz_ejtagaxi_xilinx7     │
│  - AXI reads .jls   │                 │  │    (AXI4 master)            │
│  - JPEGLSdec verify │                 │  └─ axi_jls_ctrl               │
└─────────────────────┘                 │       ├─ in_fifo (1024×8b)     │
                                        │       ├─ jls_encoder (NEAR=0)  │
                                        │       └─ out_fifo (256×17b)    │
                                        └───────────────────────────────┘
```

Clocking: 100 MHz board clock is divided by an MMCM to 50 MHz for the entire fabric, well below the encoder's measured ~63.8 MHz Fmax (see top-level README). JTAG TCK and fabric clock are declared asynchronous.

## Register map

Byte addresses (32-bit regs, little-endian):

| Addr      | Reg       | R/W | Bits                                                                   |
| --------- | --------- | --- | ---------------------------------------------------------------------- |
| 0x0000    | CTRL      | W   | [0]=soft_reset  [1]=sof_strobe  [2]=done_clear                         |
| 0x0004    | WIDTH     | R/W | [13:0] image width                                                     |
| 0x0008    | HEIGHT    | R/W | [13:0] image height                                                    |
| 0x000C    | STATUS    | R   | [0]=busy  [1]=done  [2]=in_full  [3]=out_empty  [18:8]=in_count  [27:16]=out_count |
| 0x0010    | NEAR      | R   | [2:0] compile-time NEAR                                                |
| 0x1000+   | PIX_IN    | W   | write wdata[7:0] with wstrb=0x1; pushes 1 pixel per AXI beat           |
| 0x2000+   | OUT_DATA  | R   | read pops one word: [15:0]=data, [16]=o_last                           |

The input FIFO back-pressures via `s_wready` when full. The encoder's i_e is gated when the output FIFO approaches full (JTAG readback is much slower than the encoder, so without this the out FIFO would overflow).

NEAR is a synthesis parameter — rebuild the bitstream to change it. The default is **0 (lossless)**, which enables the host-side roundtrip verification.

## Prerequisites

- Vivado 2020+ (tested with 2025.2), in `PATH` or pointed at via `$VIVADO`
- Xilinx `hw_server` running (auto-started by Vivado Lab Tools)
- `fcapz/` git submodule initialized: `git submodule update --init --recursive`
- fpgacapZero Python host installed: `python -m pip install -e fcapz`
- optional override for a different checkout: set `FCAPZ_ROOT`
- Arty A7-100T connected via USB

## Build

```bash
cd example/arty_a7
python run_demo.py --build
```

Outputs:
- `arty_jls_top.bit` — bitstream
- `vivado_out/timing_summary.rpt`
- `vivado_out/utilization.rpt`

## Run

End-to-end (programs FPGA, encodes, decodes, byte-compares):

```bash
python run_demo.py --image ../../SIM/images/test001.pgm
```

Options:

- `--build` — build first, then run
- `--no-program` — assume FPGA is already loaded
- `--no-verify` — skip roundtrip check
- `--out path.jls` — override default `<image>.jls`

Combined one-shot:

```bash
python run_demo.py --build --image ../../SIM/images/test001.pgm
```

## Throughput expectations

JTAG is the bottleneck. Typical observed speeds with the onboard FT2232H at 30 MHz TCK are a few hundred kB/s for AXI bursts. A 256×256 image (64 kB) takes on the order of a second to push in + a second to drain out.

## LEDs

- LD4 `busy` — encoder running
- LD5 `done` — last word emitted (sticky)
- LD6 `in_empty` — input FIFO empty
- LD7 `out_nonempty` — output FIFO has unread data

## Known limitations

- Single NEAR value per bitstream (compile-time parameter)
- One pixel per AXI beat (wstrb=0x1); 4-pixel packing would quadruple ingress bandwidth but complicates the slave FSM
- No CRC / protocol framing — the host and FPGA agree on (W, H) via register writes; mismatched values will produce garbage output

## Files

| Path                               | Role                                                    |
| ---------------------------------- | ------------------------------------------------------- |
| `rtl/arty_jls_top.v`               | Top, MMCM, EJTAG-AXI wrapper                           |
| `rtl/axi_jls_ctrl.v`               | AXI4 slave + FIFOs + jls_encoder instantiation          |
| `rtl/sync_fifo.v`                  | Minimal BRAM-friendly sync FIFO                         |
| `constraints/arty_jls.xdc`         | Pinout + clock constraints                              |
| `build.tcl`                        | Vivado batch build                                      |
| `run_demo.py`                      | One-script host driver                                  |
