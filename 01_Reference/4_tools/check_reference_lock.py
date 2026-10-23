# File: 4_tools/check_reference_lock.py
# Description: Checks source hashes and clustering results against saved signatures.

from __future__ import annotations
import sys, argparse, hashlib, json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import refpkg  # noqa: F401  - registers the reference packages
from golden_algorithm.fcm import histogram_from_pixels
from bit_exact_algorithm.fcm import run
from bit_exact_algorithm.profiles import PROFILES
from workspace_paths import MODELS, FIXTURES, VECTORS, CPP_DIR, SPECS, REPORTS, HW_EVIDENCE
ROOT=MODELS
FREEZE=SPECS/'FROZEN_VECTOR_SIGNATURES.json'
# pair each package name with the source file used for hashing
FILES={'bit_exact_algorithm/fcm.py':'2_bit_exact_algorithm/fcm.py',
       'bit_exact_algorithm/profiles.py':'2_bit_exact_algorithm/profiles.py',
       'golden_algorithm/fcm.py':'1_golden_algorithm/fcm.py'}

# Function: build
# Description: Creates the source and result signatures for all cluster counts.
def build():
    pixels=[int(x,16) for x in (ROOT/'fixtures/input_grayscale.mem').read_text().split()]
    hist=histogram_from_pixels(pixels)
    profile=PROFILES['precision']
    results={}
    for k in range(2,8):
        r=run(hist,k,profile,lanes=2)
        data={'K':k,'centers_q':r.centers_q,'lut':r.lut,'iterations':r.iterations,
              'converged':r.converged,'traces':r.trace}
    # sort JSON keys so the hash does not depend on dictionary order
        digest=hashlib.sha256(json.dumps(data,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        results[str(k)]={'sha256':digest,'iterations':r.iterations,'centers_q':r.centers_q}
    hashes={key:hashlib.sha256((ROOT/relative).read_bytes()).hexdigest()
            for key,relative in FILES.items()}
    return {'freeze_id':'FCM_V5_TIMING_FIRST_REF_FREEZE_1',
            'bit_exact_contract':'FCM_UNSIGNED_RATIO_NORM_V4',
            'profile':'precision','center_format':'Q8.12','membership_format':'Q0.16',
            'external_center_word_bits':32,'target_compute_fmax_mhz':200,
            'fmax_status':'NOT_MEASURED_FOR_V5',
            'model_file_sha256':hashes,'fixture_case_signatures':results}

if __name__=='__main__':
    built=build()
    saved=json.loads(FREEZE.read_text())
    # report a mismatch if the source or calculated results differ
    if saved!=built:
        print('FAIL: arithmetic source or golden values differ from frozen reference')
        sys.exit(1)
    print('PASS: frozen-reference signatures and source hashes match for K2..7')
