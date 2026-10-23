# Golden Verification Vectors

This directory contains pre-generated golden vectors and intermediate execution traces produced by `01_Reference/4_tools/generate_vectors.py` using contract `FCM_UNSIGNED_RATIO_NORM_V4`.

## Directory Structure

- `precision/`: Golden vectors for the **precision** profile (`CENTER_FRAC=12`, `MEMBER_FRAC=16`, `NORM_GUARD=18`), matching the RTL implementation in `02_FCM_IP` and `04_SoC_Intergration`. Contains test suites `demo_k02` through `demo_k07`.
- `compact/`: Golden vectors for the **compact** profile (`CENTER_FRAC=6`, `MEMBER_FRAC=12`, `NORM_GUARD=16`), maintained for resource-constrained profile comparison. Contains test suites `demo_k02` through `demo_k07`.
- `stress/`: Constrained-random scenario families from `01_Reference/4_tools/generate_stress_vectors.py`, keyed by seed and family. Reference-validated; not part of the automatic RTL regression.
- `corner/`: Targeted vectors from `01_Reference/4_tools/generate_corner_vectors.py` for RTL paths the natural histograms never reach. **These are in the default `tb_fcm_core_uvm` run** (see `TbPlusArgs` in `07_Scripts/config/fcm_ip.psd1`):
  - `reseed_single/`: exactly one dead cluster, so `fcm_core_engine`'s `E_RS_*` reseed scan runs.
  - `reseed_multi/`: K-1 dead clusters, the maximum reachable — exercises `gray_used` exhaustion and the `rs_global` fallback.
  - `coincident/`: crafted duplicate initial centers on an occupied gray, so `compute_memberships` takes its exact-match branch with 2 or more indices.
  - `deep_iter/`: 39..160 iterations, covering the upper half of the iteration range that the precision demos (9..62) leave empty.

  No stress or corner seed has ever produced a reseed event, which is why the
  `corner/` families exist: before them, the reseed and coincident-center logic
  shipped with zero coverage.

## Vector Bundle Contents (per `demo_k*`)

Each `demo_k*` test folder contains:
- `vector_contract.txt`: Machine-readable metadata specifying cluster count $K$, iteration count, profile parameters, and file inventory.
- `pixels_u8.mem`: 202,500 unsigned 8-bit input pixels (450×450 grayscale image).
- `sdram_proposed_u16.mem`: 101,250 16-bit packed SDRAM words (2 pixels per word).
- `hist_counts_u18.mem`: 256-bin histogram counts (18-bit unsigned).
- `initial_centers.mem`: Initial cluster centroids (Q8.F fixed-point format).
- `golden_centers.mem`: Final expected cluster centroids.
- `golden_lut_u3.mem`: 256-entry classification look-up table.
- `golden_converged_u1.mem`: Expected convergence flag (1 bit).
- `golden_iteration_count_u8.mem`: Expected total iteration count.
- `trace_*.mem`: Cycle-by-cycle / iteration-by-iteration golden traces for centers, accumulator numerators/denominators, max delta, and reseed events.
- `manifest.json`: for `stress/` and `corner/` bundles, the `scenario` block records the family, the reseed-event count and the maximum number of coincident clusters, so what a vector is supposed to exercise is checkable without rerunning it.

**`initial_centers.mem` is part of the vector, not a convention.** The
`coincident` and `deep_iter` families start from crafted centers rather than
the default `initial_centers(k)` policy. Anything that recomputes expected
values must read this file — `03_Verification/regression/scripts/validate_stress_vectors.py`
passes it as `init_q`.
- `bin_traces/*.jsonl`: Fine-grained membership calculation traces per histogram bin.
