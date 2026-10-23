# File: validate_stress_vectors.py
# Description: Checks stress vectors using the Python reference model.

"""Validate all generated stress vector expected outputs against frozen ref.
This checks expected-data integrity, not DUT behavior or UVM coverage.
"""
from pathlib import Path
import argparse,json,sys

HERE=Path(__file__).resolve()
ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'01_Reference'))
import refpkg  # Noqa: F401
from bit_exact_algorithm.fcm import run
from bit_exact_algorithm.profiles import PROFILES
from verification.mem_file import read_mem


# Function: validate
# Description: Checks a stress-vector case against the Python reference.
def validate(folder):
    m=json.loads((folder/'manifest.json').read_text())
    k=m['K'];p=PROFILES['precision']
    assert m['profile']['name']=='precision'
    h=read_mem(folder/'hist_counts_u18.mem',18)
    assert len(h)==256 and sum(h)==202500
    # Use the initial centers saved with each vector case.
    # Corner cases may start with matching centers, so the default centers would give a different result.
    init=read_mem(folder/'initial_centers.mem',p.widths['center'])
    assert len(init)==k
    expected=run(h,k,p,lanes=2,init_q=init)
    assert expected.centers_q==read_mem(folder/'golden_centers.mem',p.widths['center'])
    assert expected.lut==read_mem(folder/'golden_lut_u3.mem',3)
    assert expected.iterations==read_mem(folder/'golden_iteration_count_u8.mem',8)[0]
    assert int(expected.converged)==read_mem(folder/'golden_converged_u1.mem',1)[0]
    assert [v for t in expected.trace for v in t['numerator']]==read_mem(folder/'trace_acc_num.mem',42)
    assert [v for t in expected.trace for v in t['denominator']]==read_mem(folder/'trace_acc_den.mem',34)
    return k

# Function: main
# Description: Reads the arguments and starts the checks.
def main():
    a=argparse.ArgumentParser();a.add_argument('root',type=Path)
    args=a.parse_args();cases=sorted(args.root.glob('**/manifest.json'))
    if not cases:raise SystemExit('FAIL no stress vectors')
    for c in cases:
        k=validate(c.parent)
        print(f'PASS {c.parent}: K={k}',flush=True)
    print(f'PASS validated {len(cases)} scenarios against frozen Python reference')
if __name__=='__main__':main()
