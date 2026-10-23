# File: 5_tests/check_numerical_acceptance.py
# Description: Checks numerical accuracy limits using the DSE report.

import argparse,csv,sys
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import refpkg  # noqa: F401  - registers the reference packages
from workspace_paths import MODELS, FIXTURES, VECTORS, CPP_DIR, SPECS, REPORTS, HW_EVIDENCE
ROOT=MODELS


# Function: main
# Description: Checks whether all reported cases meet both accuracy limits.
def main():
    p=argparse.ArgumentParser()
    p.add_argument('--max-optimal-label-mismatch-pct',type=float,required=True)
    p.add_argument('--max-extra-objective-per-pixel',type=float,required=True)
    p.add_argument('--profile',default='precision',choices=('precision','compact'))
    args=p.parse_args()
    path=REPORTS/'dse_v4_cases.csv'
    if not path.exists():
        raise SystemExit('DSE report missing; historical DSE data is not shipped; obtain the original report from 06_Docs')
    with path.open() as file:rows=[r for r in csv.DictReader(file) if r['profile']==args.profile]
    # require results for the full sweep before accepting the report
    if len(rows)!=210:
        raise SystemExit('expected 210-case DSE; do not claim numerical signoff from a partial sweep')
    # use the worst result instead of the average
    top_labels=max(rows,key=lambda r:float(r['optimal_label_mismatch_pct']))
    top_j=max(rows,key=lambda r:float(r['objective_gap_per_pixel']))
    worst_labels=float(top_labels['optimal_label_mismatch_pct'])
    worst_gap=float(top_j['objective_gap_per_pixel'])
    good=worst_labels<=args.max_optimal_label_mismatch_pct and worst_gap<=args.max_extra_objective_per_pixel
    print(f'{"PASS" if good else "FAIL"} numerical decision gate ({args.profile}); worst optimal-label-mismatch={worst_labels:.6f}% '
          f'[{top_labels["case"]} K{top_labels["K"]}], worst positive J gap / pixel={worst_gap:.7f} '
          f'[{top_j["case"]} K{top_j["K"]}]')
    sys.exit(0 if good else 1)


if __name__=='__main__':main()
