# File: 3_verification_resources/histogram_cases.py
# Description: Builds grayscale histograms for clustering tests.

# Stress histograms use difficult grayscale patterns to test the algorithm.
from __future__ import annotations
import math
import random
from pathlib import Path
from golden_algorithm.fcm import histogram_from_pixels

N=450*450


# Function: distribute
# Description: Turns grayscale weights into counts for one full frame.
def distribute(weights):
    if len(weights)!=256 or any(x<0 for x in weights) or sum(weights)<=0:
        raise ValueError('invalid histogram weights')
    total=sum(weights)
    raw=[N*w/total for w in weights]
    counts=[int(x) for x in raw]
    # add leftover pixels to bins with the largest fractional parts
    order=sorted(range(256),key=lambda g:(-(raw[g]-counts[g]),g))
    for g in order[:N-sum(counts)]:counts[g]+=1
    assert sum(counts)==N
    return counts


# Function: core_cases
# Description: Returns the basic histogram cases, including the sample image.
def core_cases(fixture: Path):
    rnd=random.Random(10337)
    pixels=[int(x,16) for x in fixture.read_text().split()]
    return {
       'demo':histogram_from_pixels(pixels),
       'uniform':distribute([1]*256),
       'bimodal':distribute([math.exp(-((g-55)/18)**2/2)+0.8*math.exp(-((g-198)/25)**2/2)+0.0001 for g in range(256)]),
       'random_weighted':distribute([0.1+rnd.random()**3 for g in range(256)]),
       'sparse_tones':distribute([1 if g in (0,1,31,63,128,192,254,255) else 0 for g in range(256)]),
    }


# Function: stress_cases
# Description: Creates stress cases with close or unevenly weighted gray values.
def stress_cases(per_k=30, seed=20261020):
    rng=random.Random(seed)
    out=[]
    for k in range(2,8):
        for i in range(per_k):
            n_tones=rng.randint(k,min(15,k+7))
            if i%5==0:
        # keep some gray values close together to make clustering harder
                start=rng.randrange(0,257-n_tones)
                tones=list(range(start,start+n_tones))
            else:
                tones=sorted(rng.sample(range(256),n_tones))
        # use different weight patterns to cover more input shapes
            mode=i%6
            if mode==0: weights=[1.0]*n_tones
            elif mode==1: weights=[1000.0]+[1.0]*(n_tones-1)
            elif mode==2: weights=[rng.random()**3+1e-5 for _ in tones]
            elif mode==3: weights=[float(rng.randint(1,5000)) for _ in tones]
            elif mode==4: weights=[100.0 if j in (0,n_tones-1) else 0.1 for j in range(n_tones)]
            else: weights=[1.0/(j+1) for j in range(n_tones)]
            w=[0.0]*256
            for tone, weight in zip(tones,weights):w[tone]=weight
            out.append((f'stress_k{k}_{i:02d}',k,distribute(w)))
    return out
