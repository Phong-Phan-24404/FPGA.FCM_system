# File: 4_tools/generate_vectors.py
# Description: Exports fixed-point clustering vectors from the sample image.

# This script creates vectors for each supported cluster count.
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import refpkg  # noqa: F401  - registers the reference packages
import argparse
from golden_algorithm.fcm import histogram_from_pixels
from bit_exact_algorithm.fcm import run as fixed
from bit_exact_algorithm.profiles import PROFILES
from verification.mem_exporter import export_case
from verification.trace_exporter import export_trace

from workspace_paths import MODELS, FIXTURES, VECTORS, CPP_DIR, SPECS, REPORTS, HW_EVIDENCE
ROOT = MODELS


# Function: main
# Description: Runs clustering for K=2 through K=7 and exports the files.
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--profiles', nargs='+', choices=list(PROFILES), default=['precision'])
    parser.add_argument('--lanes', type=int, default=2)
    parser.add_argument('--bin-traces', default='first,last', help='first,last or comma-separated 1-based iterations')
    parser.add_argument('--skip-bin-traces', action='store_true')
    parser.add_argument('--out', type=Path, default=VECTORS)
    args = parser.parse_args()
    pixels = [int(x,16) for x in (ROOT/'fixtures/input_grayscale.mem').read_text().split()]
    hist = histogram_from_pixels(pixels)
    count = 0
    for k in range(2,8):
        for name in args.profiles:
            r = fixed(hist,k,PROFILES[name],lanes=args.lanes)
            folder = export_case(args.out, f'{name}/demo_k{k:02d}', pixels,k,r)
        # bin traces use more space, so they are optional
            if not args.skip_bin_traces:
                export_trace(folder/'bin_traces',hist,r,iterations=args.bin_traces,lanes=args.lanes)
            count += 1
            print(f'{name:9s} K={k} iterations={r.iterations:3d} '
                  f'reseeds={sum(len(x["dead_clusters"]) for x in r.trace):2d}', flush=True)
    print(f'Generated {count} golden-vector cases in {args.out}')


if __name__=='__main__':
    main()
