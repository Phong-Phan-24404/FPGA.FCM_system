# File: 4_tools/generate_corner_vectors.py
# Description: Generates vectors that test unusual clustering and hardware cases.

# The module description is also used in the command-line help.
"""Targeted corner-case vectors for RTL paths the demo/stress sets never reach.

Companion to generate_stress_vectors.py. That tool samples *natural* histogram
families; by construction none of its seeds has ever produced a reseed event
(every scenario_suite.json reports reseeds=0), so the fcm_core_engine E_RS_*
states and the fcm_member exact-match split branch ship untested.

This tool constructs scenarios that provably hit those paths:

  reseed_single  exactly one dead cluster per reseed iteration
  reseed_multi   the maximum reachable number of simultaneously dead clusters
  coincident     >=2 clusters sitting exactly on an occupied gray bin, which is
                 the `_split_one` branch with len(indices) >= 2
  deep_iter      longest convergence run found, to exercise the iteration loop

Like every other vector tool here, this is STIMULUS CONSTRUCTION ONLY. Every
golden value comes from bit_exact_algorithm.fcm.run. Output layout is
demo_k02..demo_k07 so the existing UVM sequence consumes it unchanged.
"""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import refpkg  # noqa: F401  - registers the reference packages
from bit_exact_algorithm.fcm import run
from bit_exact_algorithm.profiles import PROFILES
from verification.histogram_cases import distribute
from verification.mem_exporter import export_case
from workspace_paths import VECTORS

FAMILIES = ('reseed_single', 'reseed_multi', 'coincident', 'deep_iter')
P = PROFILES['precision']
F = P.center_frac


# Function: _hist
# Description: Makes a full-frame histogram from grayscale weights.
def _hist(weights: list[float]) -> list[int]:
    h = distribute(weights)
    if sum(h) != 202500:
        raise AssertionError('invalid frame count')
    return h


# Function: _spike
# Description: Creates a histogram with all pixels at the same gray value.
def _spike(gray: int) -> list[int]:
    w = [0.0] * 256
    w[gray] = 1.0
    return _hist(w)


# Function: _reseed_count
# Description: Counts all cluster reseed events in a result.
def _reseed_count(result) -> int:
    return sum(len(t['dead_clusters']) for t in result.trace)


# Function: _max_coincident
# Description: Counts the most centers sharing an occupied gray value.
def _max_coincident(hist: list[int], result) -> int:
    worst = 0
    for t in result.trace:
        for g, count in enumerate(hist):
            if count:
                worst = max(worst, sum(1 for c in t['centers_in_q'] if c == (g << F)))
    return worst


# Each corner case provides a histogram and optional starting centers.
# Single-gray cases can cause zero contributions and trigger reseeding.
# RESEED_MULTI_GRAY tests multiple clusters needing a reseed at once.
# RESEED_SINGLE_PAIR uses two close gray values to trigger one reseed.
# For K=2, a single reseed is also the maximum possible reseed count.
RESEED_MULTI_GRAY = {2: 85, 3: 63, 4: 51, 5: 42, 6: 36, 7: 31}
RESEED_SINGLE_PAIR = {3: (4, 2), 4: (0, 2), 5: (0, 3), 6: (0, 4), 7: (0, 2)}

# These seeds create cases with longer convergence times.
# They test the iteration limit using repeatable starting centers and histograms.
# The cases are meant to converge, not to force a non-converging run.
DEEP_ITER_SEED = {2: 60, 3: 165, 4: 2713, 5: 850, 6: 209, 7: 1688}


# Function: _deep_case
# Description: Makes a sparse histogram and starting centers for a long run.
def _deep_case(k: int, seed: int):
    # the same seed and cluster count always give the same case
    import random
    r = random.Random((seed << 8) ^ (k << 2) ^ 0xD33B)
    w = [0.0] * 256
    for g in r.sample(range(256), 8):
        w[g] = r.random() + 0.02
    h = _hist(w)
    init = sorted(r.sample(range(0, (255 << F) + 1), k))
    return h, init


# Function: _scenario
# Description: Selects the histogram and starting centers for a corner case.
def _scenario(family: str, k: int):
    if family == 'reseed_multi':
        return _spike(RESEED_MULTI_GRAY[k]), None

    if family == 'reseed_single':
        if k not in RESEED_SINGLE_PAIR:
            return _spike(RESEED_MULTI_GRAY[k]), None
        gray, delta = RESEED_SINGLE_PAIR[k]
        w = [0.0] * 256
        w[gray] = 1.0
        w[gray + delta] = 1.0
        return _hist(w), None

    if family == 'coincident':
        # put two centers on the same occupied gray value
        # this checks how an exact-match membership is shared between them
        grays = [20 + 30 * i for i in range(k)]
        w = [0.0] * 256
        for i, g in enumerate(grays):
            w[g] = 1.0 + 0.1 * i
        init = [grays[0] << F, grays[0] << F]
        init += [grays[i] << F for i in range(1, k - 1)]
        return _hist(w), init[:k]

    if family == 'deep_iter':
        return _deep_case(k, DEEP_ITER_SEED[k])

    raise ValueError('unknown corner family')


# Function: main
# Description: Writes corner-case vectors and checks their expected conditions.
def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--family', choices=FAMILIES, required=True)
    parser.add_argument('--out', type=Path, default=None)
    a = parser.parse_args()

    base = a.out or (VECTORS / 'corner' / a.family)
    entries = []
    for k in range(2, 8):
        hist, init = _scenario(a.family, k)
        pixels = [g for g, n in enumerate(hist) for _ in range(n)]
        result = run(hist, k, P, lanes=2, init_q=init)

        reseeds = _reseed_count(result)
        coincident = _max_coincident(hist, result)

        folder = export_case(base, f'demo_k{k:02d}', pixels, k, result)
        # record the case settings and results in the manifest
        manifest_path = folder / 'manifest.json'
        manifest = json.loads(manifest_path.read_text())
        manifest['scenario'] = {
            'family': a.family,
            'raster_order': 'sorted_by_gray',
            'reseed_events': reseeds,
            'max_coincident_clusters': coincident,
            'custom_init_centers': init is not None,
            'source': '01_Reference/4_tools/generate_corner_vectors.py',
        }
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')

        entries.append({'K': k, 'active_bins': result.active_bins,
                        'iterations': result.iterations,
                        'converged': result.converged,
                        'reseeds': reseeds,
                        'max_coincident_clusters': coincident})
        print(f'{a.family} K={k} bins={result.active_bins} '
              f'iterations={result.iterations} converged={result.converged} '
              f'reseeds={reseeds} coincident={coincident}', flush=True)

    # reject a case if it does not reach its required condition
    if a.family.startswith('reseed') and not all(e['reseeds'] for e in entries):
        print('ERROR: a reseed family case produced no reseed event', file=sys.stderr)
        return 1
    if a.family == 'reseed_single' and not all(
            e['reseeds'] == 1 for e in entries if e['K'] in RESEED_SINGLE_PAIR):
        print('ERROR: reseed_single must have exactly one dead cluster per case',
              file=sys.stderr)
        return 1
    if a.family == 'coincident' and not all(
            e['max_coincident_clusters'] >= 2 for e in entries):
        print('ERROR: coincident family did not reach 2 coincident clusters',
              file=sys.stderr)
        return 1

    (base / 'scenario_suite.json').write_text(json.dumps(
        {'family': a.family, 'profile': 'precision', 'cases': entries},
        indent=2) + '\n')
    print('For UVM: +FCM_VECTORS=' + str(base))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
