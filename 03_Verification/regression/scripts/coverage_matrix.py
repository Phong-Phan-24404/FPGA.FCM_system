# File: coverage_matrix.py
# Description: Counts the test cases from saved vector manifests.

"""Stimulus coverage inventory only; never claim this proves DUT verification closure.

Use UVM scoreboard-checked counters, assertion logs, and RTL observations for
actual verification closure. --require-family verifies directed stimulus data.
"""
import argparse,json
from collections import Counter
from pathlib import Path


# Function: analyze
# Description: Counts the stress-vector scenarios described by the manifests.
def analyze(root:Path):
    manifests=list(root.glob('**/manifest.json'))
    counts=Counter();cases=[]
    for p in manifests:
        j=json.loads(p.read_text())
        if j.get('profile',{}).get('name') != 'precision':continue
        k=j['K'];family=j.get('scenario',{}).get('family','demo')
        active=j['active_bins'];iterations=j['iterations'];converged=j['converged']
        reseeds=j.get('scenario',{}).get('reseed_events',None)
        counts[f'K={k}']+=1
        counts[f'family={family}']+=1
        counts['converged' if converged else 'max_iterations']+=1
        counts['active_bins:1' if active==1 else 'active_bins:2..7' if active<=7 else
               'active_bins:8..63' if active<=63 else 'active_bins:64..255' if active<256 else
               'active_bins:256']+=1
        if reseeds is not None and reseeds:counts['reseed']+=1
        cases.append({'path':str(p.parent.relative_to(root)),'K':k,'family':family,
                      'active_bins':active,'iterations':iterations,'converged':converged,'reseeds':reseeds})
    return counts,cases

# Function: main
# Description: Reads the arguments and starts the checks.
def main():
    p=argparse.ArgumentParser();p.add_argument('vectors',type=Path)
    p.add_argument('--json-out',type=Path,default=None)
    p.add_argument('--require-family',action='append',default=[])
    a=p.parse_args();c,cases=analyze(a.vectors)
    obj={'classification':'STIMULUS_ONLY_NOT_DUT_COVERAGE','total_precision_cases':len(cases),
         'counts':dict(sorted(c.items())),'cases':cases,
         'not_covered':['UVM observed transaction correctness','SVA activity','reset/CDC','post-fit STA']}
    if a.json_out:
        a.json_out.parent.mkdir(parents=True,exist_ok=True)
        a.json_out.write_text(json.dumps(obj,indent=2)+'\n')
    print(json.dumps({'classification':obj['classification'],'cases':len(cases),'counts':obj['counts']},indent=2))
    missing=[x for x in a.require_family if not c[f'family={x}']]
    if missing:raise SystemExit('FAIL missing scenario families: '+','.join(missing))
if __name__=='__main__':main()
