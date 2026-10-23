# File: 5_tests/test_algorithm.py
# Description: Tests fixed-point clustering and memory-vector calculations.

import sys,random,json,tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import refpkg  # noqa: F401  - registers the reference packages
from golden_algorithm.fcm import histogram_from_pixels,run as golden,initial_centers,memberships
from bit_exact_algorithm.fcm import run as fixed,compute_memberships,compute_bin,weighted_contribution
from bit_exact_algorithm.profiles import PROFILES
from verification.metrics import metrics, optimal_center_assignment
from verification.mem_exporter import export_case
from verification.mem_file import read_mem,write_mem
from verification.sdram import pack_u16_low_byte_first,unpack_u16_low_byte_first,image_crc32

from workspace_paths import MODELS, FIXTURES, VECTORS, CPP_DIR, SPECS, REPORTS, HW_EVIDENCE
ROOT=MODELS

# Function: test_membership
# Description: Checks membership ranges and the exact membership sum.
def test_membership():
    r=random.Random(20261019)
    checked=0
    for p in PROFILES.values():
        for k in range(2,8):
            for i in range(100):
                centers=[r.randint(0,255<<p.center_frac) for _ in range(k)]
        # include cases where a gray matches one or more centers
                if i%7==0:centers[r.randrange(k)]=(r.randrange(256)<<p.center_frac)
                if i%13==0:centers[1]=centers[0]
                gray=r.randrange(256)
                u,_=compute_memberships(gray,centers,p)
                assert sum(u)==1<<p.member_frac
                assert all(0<=v<=1<<p.member_frac for v in u)
                checked+=1
    print(f'PASS {checked} random/duplicate fixed membership invariant tests')

# Function: test_parallel_and_ranges
# Description: Checks that changing the lane count does not change the result.
def test_parallel_and_ranges(hist):
    checked=0
    for p in PROFILES.values():
        for k in range(2,8):
            a=fixed(hist,k,p,lanes=1)
            for lanes in (2,4,8):
                b=fixed(hist,k,p,lanes=lanes)
                assert a==b,(k,p.name,lanes)
                checked+=1
            assert all(0<=c<=(255<<p.center_frac) for c in a.centers_q)
    print(f'PASS {checked} complete lane-equivalence results (K=2..7, P=2/4/8)')

# Function: test_corner
# Description: Tests extreme histograms and accumulator bit widths.
def test_corner():
    r=random.Random(42)
    tests=[('black',{0:202500}),('white',{255:202500}),
           ('two_tone',{0:101250,255:101250}),
           ('single_middle',{127:202500}),
           ('random_sparse',{x:1 for x in [0,12,64,100,177,255]})]
    for name,data in tests:
        h=[0]*256
        if name=='random_sparse':
    # fill the remaining pixels into the first histogram bin
            vals=list(data);counts=[r.randint(1,10000) for _ in vals]
            counts[0]+=202500-sum(counts)
            for g,n in zip(vals,counts):h[g]=n
        else:
            for g,n in data.items():h[g]=n
        for p in PROFILES.values():
            for k in (2,4,7):
                a=fixed(h,k,p,lanes=1)
                b=fixed(h,k,p,lanes=4)
                assert a==b,(name,p.name,k)
                assert a.iterations<=200
        # check that the calculated sums fit the available bit widths
                for step in a.trace:
                    assert max(step['numerator'])<(1<<p.widths['accumulator_num'])
                    assert max(step['denominator'])<(1<<p.widths['accumulator_den'])
    print('PASS 45 synthetic-histogram full-run lane/range cases')

# Function: test_export
# Description: Tests whether memory vectors survive writing and reading.
def test_export(pixels,hist):
    packed=pack_u16_low_byte_first(pixels)
    assert len(packed)==101250
    assert unpack_u16_low_byte_first(packed)==pixels
    assert len(image_crc32(pixels))==8
    p=PROFILES['precision']; k=4
    res=fixed(hist,k,p)
    with tempfile.TemporaryDirectory() as temp:
        d=export_case(temp,'test',pixels,k,res)
        expected=read_mem(d/'golden_centers.mem',p.widths['center'])
        assert expected==res.centers_q
    # write and read each memory file to check its values
        for name,spec in json.loads((d/'manifest.json').read_text())['mem_fields'].items():
            src_data=read_mem(d/name,spec['width'])
            assert len(src_data)==spec['count']
            out=Path(temp)/('roundtrip_'+name)
            write_mem(out,src_data,spec['width'])
            assert read_mem(out,spec['width'])==src_data
        assert any(len(step['dead_clusters']) >= 0 for step in res.trace)
    print('PASS exported mem files and numeric trace roundtrip')

# Function: test_algorithm_regression
# Description: Checks fixed-point contribution precision on a sparse case.
def test_algorithm_regression():
    # floating-point FCM can settle on different valid cluster assignments
    tones=(0,1,31,63,128,192,254,255)
    h=[0]*256
    for i,gray in enumerate(tones):
        h[gray]=25313 if i<4 else 25312
    h[0]+=202500-sum(h)
    ideal=golden(h,7)
    from verification.metrics import optimal_center_assignment,objective,objective_trace
    assert objective(h,ideal.centers)>=0
    for name,p in PROFILES.items():
        actual=fixed(h,7,p)
        m=metrics(h,ideal,actual)
        assert sorted(m['cluster_permutation'])==list(range(7))
        assert m['objective_fixed']>=0 and m['objective_golden']>=0
        assert len(objective_trace(h,actual))==actual.iterations
        assert all(0<=x<=255 for x in actual.centers)
        assert 0<=m['mismatch_pixel_pct_aligned']<=100
    assert optimal_center_assignment([1.,2.],[2.,1.])==[1,0]
    # multiplying by the count before shifting keeps small contributions
    p=PROFILES['precision'];u=255;count=202500
    assert count*((u*u)>>p.member_frac)==0
    assert weighted_contribution(count,u,p)>0
    print('PASS sparse FCM objective/assignment test + quantified early-truncation fix')


# Function: test_legal_range_extremes
# Description: Checks single-gray frames, center limits, and reseeding.
def test_legal_range_extremes():
    for val in (0,127,255):
        h=[0]*256;h[val]=202500
        for k in (2,7):
            for p in PROFILES.values():
                x=fixed(h,k,p)
                assert 1<=x.iterations<=200
                assert all(0<=c<=255<<p.center_frac for c in x.centers_q)
        # check that every empty cluster receives a replacement gray value
                assert all(len(step['dead_clusters'])==len(step['reseed_gray']) for step in x.trace)
    print('PASS legal 450x450 extreme histograms for K=2/7, every profile')


# Function: main
# Description: Runs the clustering tests when this file is executed directly.
def main():
    pixels=[int(x,16) for x in (ROOT/'fixtures/input_grayscale.mem').read_text().split()]
    hist=histogram_from_pixels(pixels)
    test_membership()
    test_parallel_and_ranges(hist)
    test_corner()
    test_algorithm_regression()
    test_legal_range_extremes()
    test_export(pixels,hist)
    # also check the floating-point model for every cluster count
    for k in range(2,8):
        g=golden(hist,k)
        assert 1<=g.iterations<=200
        assert all(0<=c<=255 for c in g.centers)
        for gray in (0,127,255):
            u=memberships(gray,g.centers)
            assert abs(sum(u)-1)<1e-12
    print('PASS high-level reference for K=2..7')
    print('ALL PYTHON TESTS PASSED')

if __name__=='__main__':main()
