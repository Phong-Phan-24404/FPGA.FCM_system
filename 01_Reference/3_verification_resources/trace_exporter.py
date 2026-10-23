# File: 3_verification_resources/trace_exporter.py
# Description: Saves selected fixed-point bin calculations as JSONL traces.

from pathlib import Path
import json
from bit_exact_algorithm.fcm import FixedResult, compute_bin


# Function: export_trace
# Description: Writes a per-bin trace for the selected iterations.
def export_trace(path: str | Path, hist: list[int], result: FixedResult,
                 *, iterations: str = 'first,last', lanes: int = 2):
    # accept 'first', 'last', or a comma-separated list of iteration numbers
    selected = set()
    for token in iterations.split(','):
        token = token.strip().lower()
        selected.add(1 if token == 'first' else result.iterations if token == 'last' else int(token))
    if any(i < 1 or i > result.iterations for i in selected):
        raise ValueError('selected trace iteration was not executed')
    root = Path(path)
    root.mkdir(parents=True, exist_ok=True)
    active = [(g,c) for g,c in enumerate(hist) if c]
    files = []
    for iteration in sorted(selected):
        # use the centers from the start of this iteration for each bin
        centers = result.trace[iteration-1]['centers_in_q']
        f = root/f'iter_{iteration:03d}_bin_trace.jsonl'
        with f.open('w') as out:
            for idx, (g,c) in enumerate(active):
                checkpoint = compute_bin(g,c,centers,result.profile,lane=idx%lanes)
                checkpoint.update(iteration=iteration, active_bin_ordinal=idx, centers_in_q=centers,
                                  note='combinational per-bin checkpoint; lane scheduling is not cycle-accurate')
                out.write(json.dumps(checkpoint, separators=(',',':'))+'\n')
        files.append(str(f))
    return files
