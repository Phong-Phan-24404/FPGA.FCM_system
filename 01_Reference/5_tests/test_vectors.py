# File: 5_tests/test_vectors.py
# Description: Tests memory vectors and traces against the fixed-point model.

import json
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import refpkg  # noqa: F401  - registers the reference packages
from bit_exact_algorithm.fcm import compute_bin, run as rerun
from bit_exact_algorithm.profiles import get_profile
from verification.sdram import pack_u16_low_byte_first,image_crc32
from verification.mem_file import read_mem
from workspace_paths import MODELS, FIXTURES, VECTORS, CPP_DIR, SPECS, REPORTS, HW_EVIDENCE
ROOT=MODELS

# Function: main
# Description: Recomputes each exported case and checks the saved values.
def main():
    cases=sorted((VECTORS).glob('*/demo_k*'))
    assert len(cases)==12, f'expected 12 Compact/Precision vector cases, found {len(cases)}'
    comparisons=0
    for d in cases:
        manifest=json.loads((d/'manifest.json').read_text())
        assert manifest['contract']=='FCM_UNSIGNED_RATIO_NORM_V4'
        assert (d/'vector_contract.txt').exists()
        k=manifest['K'];p=get_profile(manifest['profile']['name'])
        expected_iterations=manifest['iterations']
        # match the number of data words with the manifest
        for fn,spec in manifest['mem_fields'].items():
            raw=read_mem(d/fn,spec['width'],spec['signed'])
            assert len(raw)==spec['count'],(d,fn)
            comparisons+=len(raw)
        trace=read_mem(d/'trace_centers_in.mem',p.widths['center'])
        hist=read_mem(d/'hist_counts_u18.mem',18)
        assert sum(hist)==202500
        pixels=read_mem(d/'pixels_u8.mem',8)
        assert read_mem(d/'sdram_proposed_u16.mem',16)==pack_u16_low_byte_first(pixels)
        assert manifest['host_packaging']['crc32_u8_pixels']==image_crc32(pixels)
        assert manifest['profile']['accumulation_policy']==p.accumulation_policy
        # check the saved result against a fresh model calculation
        recomputed=rerun(hist,k,p)
        assert recomputed.centers_q==read_mem(d/'golden_centers.mem',p.widths['center'])
        assert recomputed.lut==read_mem(d/'golden_lut_u3.mem',3)
        assert recomputed.iterations==expected_iterations
        assert [v for tr in recomputed.trace for v in tr['numerator']]==read_mem(d/'trace_acc_num.mem',p.widths['accumulator_num'])
        assert [v for tr in recomputed.trace for v in tr['denominator']]==read_mem(d/'trace_acc_den.mem',p.widths['accumulator_den'])
        # check that the text contract agrees with the manifest
        for field in manifest['mem_fields']:
            spec=manifest['mem_fields'][field]
            assert f'MEM {field} {spec["width"]} {spec["count"]} 0' in (d/'vector_contract.txt').read_text().splitlines()

        for trace_path in sorted((d/'bin_traces').glob('iter_*_bin_trace.jsonl')):
            iteration=int(trace_path.name.split('_')[1]);assert 1<=iteration<=expected_iterations
            # calculate each trace bin using the iteration starting centers
            frozen=trace[(iteration-1)*k:iteration*k]
            seen=[]
            for line in trace_path.read_text().splitlines():
                x=json.loads(line)
                result=compute_bin(x['gray'],x['count'],frozen,p,lane=x['lane'])
                assert all(x[key]==result[key] for key in result), (d,iteration,x['gray'])
                seen.append(x['gray'])
                comparisons+=1
            # each occupied gray value should appear once in order
            assert seen==[g for g,h in enumerate(hist) if h]
    print(f'PASS {len(cases)} golden-vector cases, {comparisons} scalar/vector/bin-trace comparisons')

if __name__=='__main__':main()
