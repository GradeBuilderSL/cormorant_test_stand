# cormorant_test_stand

Vivado test harnesses for the HLS kernels (`ConvKernel`, and the others as they come online). Each kernel sits in its
own Vivado project under `kernels/<name>_test/` with a Zynq-UltraScale+ PS VIP
driving the AXI-Lite control port and DDR slave; a SystemVerilog OOP testbench
programs the registers, asserts `ap_start`, and back-door verifies the output
buffer against a closed-form reference for every transaction in a manifest.

The repo's main job is to make those projects scriptable: build/synth/impl
runs and behavioural simulations are driven by the wrappers under `scripts/`,
and the top-level `Makefile` exposes uniform `make hw-<kernel>` /
`make tb-<kernel>` entry points generated from a single registry file.

Test fixtures (`manifest.txt` + `test_*.hex`) are produced **outside** this
repo by whatever pipeline owns the kernel under test. You point the testbench
at them per-run with a `DATA_DIR` knob — each kernel can have its own.

The kernel's HLS IP catalogue (the directory the .xpr's `ip_repo_paths`
references) is also external. You can repoint it per-run with `--ip-repo` /
`IP_REPO_<k>=` so the test stand picks up freshly-rebuilt kernel sources
without editing the project file. Whether or not the override is supplied,
both `build_hw.sh` and `run_tb.sh` upgrade any locked IPs and regenerate the
BD wrapper before launching synth or simulation, so the test always reflects
the current kernel revision.

## Layout

```
cormorant_test_stand/
├── Makefile                       — entry points; rules generated from registry
├── kernels/
│   └── conv_test/                 — Vivado project for ConvKernel
│       ├── conv_test.xpr
│       └── conv_test.srcs/
│           ├── sources_1/bd/design_conv/   — block design (PS VIP + IP)
│           └── sim_1/new/conv_tb.sv         — OOP testbench
└── scripts/
    ├── registry.sh                — kernel table (single source of truth)
    ├── lib.sh                     — Vivado discovery + registry helpers
    ├── build_hw.sh                — synth + impl + bitstream wrapper
    ├── run_tb.sh                  — xsim wrapper
    ├── clean.sh                   — wipe Vivado scratch dirs
    └── tcl/
        ├── lib.tcl                — shared Tcl: ip-repo override + locked-IP / BD refresh
        ├── build_hw.tcl
        └── run_sim.tcl
```

## Prerequisites

- **Vivado 2025.2** (or any 2023.2+; the discovery logic walks
  `/mnt/data/xilinx`, `/tools/Xilinx`, `/opt/Xilinx`). Either source
  `settings64.sh` first, set `VIVADO=/path/to/bin/vivado`, or just put
  `vivado` on `PATH` — the scripts handle all three.
- **A fixtures directory per kernel** containing `manifest.txt` and the
  `test_*.hex` files the testbench reads. Generated however the kernel's
  upstream pipeline generates them; not produced here.

## Quick start

```bash
# Hardware build (synth + impl + bitstream)
make hw-conv

# Hardware build, no bitstream, 8 parallel jobs
make hw-conv BIT=0 VIVADO_JOBS=8

# Behavioural xsim test — DATA_DIR is mandatory
make tb-conv DATA_DIR_conv=/path/to/conv/fixtures

# Single-kernel shorthand: bare DATA_DIR works too
make tb-conv DATA_DIR=/path/to/conv/fixtures

# Custom JSON report destination
make tb-conv DATA_DIR_conv=/path/to/conv/fix REPORT_conv=/tmp/conv.json

# Repoint the IP repo at a freshly-rebuilt kernel catalogue
make hw-conv IP_REPO_conv=/path/to/kernels/build
make tb-conv DATA_DIR_conv=/path/to/conv/fix IP_REPO_conv=/path/to/kernels/build

# Wipe Vivado scratch dirs (.cache .gen .runs .sim .hw .ip_user_files)
make clean-conv

# Run all registered kernels — each one needs its own DATA_DIR_<k>
make all-tb DATA_DIR_conv=/path/to/conv/fix DATA_DIR_matmul=/path/to/matmul/fix
```

The wrappers can also be invoked directly:

```bash
scripts/build_hw.sh conv --jobs 8 --no-bitstream --ip-repo /path/to/kernels/build
scripts/run_tb.sh   conv --data-dir /path/to/conv/fix --report /tmp/conv.json --ip-repo /path/to/kernels/build
scripts/clean.sh    conv
```

`make help` and `scripts/*.sh --help` print full option lists.

## Reading test results

The testbench writes a JSON report to
`kernels/<kernel>_test/<kernel>_test_report.json` (the project directory the
wrapper `cd`s into before invoking Vivado). Override with `--report` /
`REPORT_<k>=` / `REPORT=`. The fixtures directory is treated as read-only,
so the report deliberately lands next to the project, not next to the
inputs. `run_tb.sh` parses it at the end and prints a one-line summary:

```
[ts] kernel=conv  total=18  passed=18  failed=0  all_passed=True
```

The wrapper exits non-zero if `all_passed` is false, so it composes cleanly in
CI.

## Adding a new kernel

The scripts are deliberately data-driven — adding a kernel is one row of
`scripts/registry.sh` and a Vivado project under `kernels/<name>_test/`:

1. Create `kernels/<name>_test/<name>_test.xpr` containing a block design
   `design_<name>` with a Zynq UltraScale+ PS VIP and the kernel IP, plus a
   wrapper module `design_<name>_wrapper`.
2. Drop a SystemVerilog testbench at the project's `sim_1` fileset
   (`<name>_tb.sv` is the convention) that reads its fixtures from
   `+DATA_DIR=<dir>` (manifest.txt + .hex live there) and writes
   `+REPORT=<file>`.
3. Append one row to `KERNELS_TABLE` in `scripts/registry.sh` (five fields):
   ```bash
   "matmul: kernels/matmul_test: matmul_test.xpr: design_matmul_wrapper: matmul_tb"
   ```
4. `make hw-matmul`, `make tb-matmul DATA_DIR_matmul=<dir>`, and
   `make clean-matmul` are now available — no Makefile or script edits
   needed.

See `scripts/registry.sh` for a description of each field and the conventions
the Tcl drivers assume.

## Environment overrides

| Variable | Meaning |
|---|---|
| `VIVADO` | Pin a specific `vivado` binary (skips PATH/install search) |
| `VIVADO_JOBS` | Default parallelism for synth/impl (overridden by `--jobs`/`VIVADO_JOBS=`) |
| `DATA_DIR_<k>` | Fixtures directory for kernel `<k>` (required for `tb-<k>`) |
| `DATA_DIR` | Single-kernel shorthand for `DATA_DIR_<k>` |
| `REPORT_<k>` | JSON report path for kernel `<k>` (default `kernels/<k>_test/<k>_test_report.json`) |
| `REPORT` | Single-kernel shorthand for `REPORT_<k>` |
| `IP_REPO_<k>` | Override the HLS IP repository path stored in kernel `<k>`'s `.xpr` |
| `IP_REPO` | Single-kernel shorthand for `IP_REPO_<k>` |
