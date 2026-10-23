# File: 4_tools/generate_stress_vectors.py
# Description: Builds repeatable stress-test vectors for fixed-point FCM.

# The module description is used as command-line help text.
"""Reproducible constrained scenario vectors for the frozen Precision reference.

Produces demo_k02..demo_k07 for existing UVM sequence compatibility. This is
stimulus generation, NOT an implementation of FCM arithmetic. All golden values
are calculated by bit_exact_algorithm.fcm.run.
"""
from __future__ import annotations
import argparse, json, random, sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import refpkg  # noqa: F401  - registers the reference packages
from bit_exact_algorithm.fcm import run
from bit_exact_algorithm.profiles import PROFILES
from verification.histogram_cases import distribute
from verification.mem_exporter import export_case
from workspace_paths import VECTORS

FAMILIES=('constant','boundary','adjacent','sparse','bimodal','uniform','random_weighted')

# Function: make_hist
# Description: Creates a histogram for the chosen scenario, seed, and K.
def make_hist(family: str, seed: int, k: int) -> list[int]:
    if family not in FAMILIES:
        raise ValueError('unknown scenario family')
    # combine the seed and cluster count for repeatable test data
    r=random.Random((seed << 8) ^ (k << 2) ^ 0xFCE1)
    weights=[0.0]*256
    if family=='constant':
        weights[r.choice([0,1,127,128,254,255])]=1.0
    elif family=='boundary':
        for g in (0,1,2,253,254,255): weights[g]=1.0+r.random()
    elif family=='adjacent':
    # use neighboring gray values so some centers become close
        first=r.randrange(0,256-(k+1))
        for g in range(first,first+k+1):weights[g]=0.1+r.random()
    elif family=='sparse':
        for g in r.sample(range(256),r.randint(k,min(16,k+9))): weights[g]=r.random()**2+1e-4
    elif family=='bimodal':
        c1=r.randint(8,85);c2=r.randint(175,247)
        for g in range(256):weights[g]=1e-4+1.5/(1+((g-c1)/10)**4)+1/(1+((g-c2)/14)**4)
    elif family=='uniform':
        weights=[1.0]*256
    else:
        weights=[r.random()**3+1e-4 for _ in range(256)]
    h=distribute(weights)
    if sum(h)!=202500:raise AssertionError('invalid frame count')
    return h

# Function: main
# Description: Exports the stress cases for K=2 through K=7.
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seed',type=int,required=True)
    parser.add_argument('--family',choices=FAMILIES,required=True)
    parser.add_argument('--out',type=Path,default=None)
    a=parser.parse_args()
    base=a.out or (VECTORS/'stress'/f'seed_{a.seed:08d}'/a.family)
    entries=[]
    for k in range(2,8):
        hist=make_hist(a.family,a.seed,k)
        # pixel order does not affect FCM, so build a fixed raster for exports
        pixels=[g for g,n in enumerate(hist) for _ in range(n)]
        result=run(hist,k,PROFILES['precision'],lanes=2)
        folder=export_case(base,f'demo_k{k:02d}',pixels,k,result)
        # save the stress-case settings in the manifest
        manifest_path=folder/'manifest.json'
        manifest=json.loads(manifest_path.read_text())
        manifest['scenario']={'family':a.family,'seed':a.seed,'raster_order':'sorted_by_gray',
                              'reseed_events':sum(len(x['dead_clusters']) for x in result.trace),
                              'source':'01_Reference/4_tools/generate_stress_vectors.py'}
        manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
        entries.append({'K':k,'active_bins':result.active_bins,'iterations':result.iterations,
                        'converged':result.converged,
                        'reseeds':manifest['scenario']['reseed_events']})
        print(f'{a.family} seed={a.seed} K={k} bins={result.active_bins} iterations={result.iterations} '
              f'reseeds={entries[-1]["reseeds"]}',flush=True)
    (base/'scenario_suite.json').write_text(json.dumps({'family':a.family,'seed':a.seed,'profile':'precision',
                                                         'cases':entries},indent=2)+'\n')
    print('For UVM: +FCM_VECTORS='+str(base))
if __name__=='__main__':main()
