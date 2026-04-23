<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 Leonardo Capossio - bard0 design - hello@bard0.com -->

# TODO / Improvement Suggestions

## 1. Color (RGB) Support — Biggest Feature Gap
Currently hardwired to a single 8-bit grayscale pixel (`i_x`). JPEG-LS (ITU-T T.87)
defines interleaved color modes (ILV=0/1/2).
- **Full approach:** implement inter-channel prediction (ILV=2) for better compression, requiring a more coupled design.

## 2. AXI4-Stream Interface
The current interface is custom. Wrapping with AXI4-Stream (`TVALID`/`TREADY`/`TDATA`/`TLAST`)
would make it drop-in compatible with Xilinx/Intel IP ecosystems and standard DMA engines.

## 3. Output Backpressure / Flow Control
There is no `o_ready` signal — if the downstream consumer is slow, output data is lost.
- Add a small output FIFO + `o_ready` backpressure signal.
- Low effort, high impact for real system integration correctness.

## 4. Runtime NEAR Configuration
`NEAR` is currently a compile-time parameter, requiring re-synthesis to change compression quality.
- Make NEAR a runtime input port for flexibility.
- Requires reworking context memory initialization and arithmetic currently resolved at elaboration time.

## 5. Higher Clock Frequency
35 MHz is modest for Artix-7. Pipeline stage **e** is the bottleneck — it has combinational
dependency chains (context RAM read -> `func_get_q` -> `C_B_update`) in a single cycle.
- Break stage e into finer sub-stages to improve Fmax.
- Goal: reach ~55 MHz to enable 720p60 (55.3 Mpixel/s required).

## 6. Higher Bit Depth (10/12-bit)
Currently limited to 8-bit pixels. Medical imaging (X-ray, CT, MRI) commonly uses 12-bit.
- Widen `i_x`, adjust arithmetic, lookup tables, and context memory widths.
- Unlocks a much larger application space with relatively contained changes.
