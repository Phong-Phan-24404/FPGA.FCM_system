# File: 2_bit_exact_algorithm/fcm.py
# Description: Runs integer FCM calculations using the hardware fixed-point rules.

# Centers and memberships use fixed-point arithmetic with defined rounding.
# The floating-point model is used for accuracy comparisons, not bit-level matching.
from __future__ import annotations
from dataclasses import dataclass
from typing import Sequence
from golden_algorithm.fcm import check_histogram, initial_centers
from .profiles import Profile


# Function: _split_one
# Description: Splits a full membership across centers with the same gray value.
def _split_one(indices: list[int], k: int, one: int) -> list[int]:
    q, r = divmod(one, len(indices))
    out = [0] * k
    # give any extra units to the lowest cluster indices
    for j, i in enumerate(indices):
        out[i] = q + (j < r)
    return out


# Function: compute_memberships
# Description: Calculates fixed-point memberships for one grayscale value.
def compute_memberships(gray: int, centers_q: Sequence[int], p: Profile) -> tuple[list[int], dict]:
    # square the fixed-point distances, then scale by the smallest square
    # divide again to normalize the membership values
    # add leftover units to keep their total exactly equal to 2^M
    # hardware dividers must give the same integer quotient
    f, m, guard = p.center_frac, p.member_frac, p.norm_guard
    one = 1 << m
    if not 0 <= gray <= 255 or not (2 <= len(centers_q) <= 7):
        raise ValueError('invalid grayscale or cluster count')
    if any(c < 0 or c > (255<<f) for c in centers_q):
        raise ValueError('center outside legal grayscale domain')
    distances = [abs((gray<<f)-c) for c in centers_q]
    squares = [d*d for d in distances]
    zero = [i for i, sq in enumerate(squares) if sq == 0]
    # matching centers share the membership without division
    if zero:
        out = _split_one(zero, len(centers_q), one)
        return out, dict(distance_q=distances, square=squares, ratio_q=[one if i in zero else 0 for i in range(len(centers_q))],
                         sum_ratio=one*len(zero), reciprocal_q=0, membership_q=out, exact_match=True)
    minimum = min(squares)
    ratio = [(minimum<<m)//sq for sq in squares]
    total = sum(ratio)
    assert one <= total <= len(centers_q)*one
    recip = (1 << (m+guard)) // total
    members = [(r*recip)>>guard for r in ratio]
    remaining = one - sum(members)
    assert 0 <= remaining <= len(centers_q)+1, (ratio, recip, members, remaining)
    # assign the remaining units to the largest ratio, breaking ties by index
    best = max(range(len(ratio)), key=lambda k: (ratio[k], -k))
    members[best] += remaining
    assert sum(members) == one and all(0 <= u <= one for u in members)
    return members, dict(distance_q=distances, square=squares, ratio_q=ratio,
                         sum_ratio=total, reciprocal_q=recip,
                         membership_q=members, exact_match=False)


# Function: label_lut
# Description: Assigns each gray value to its nearest fixed-point center.
def label_lut(centers_q: Sequence[int], p: Profile) -> list[int]:
    return [min(range(len(centers_q)), key=lambda k: (abs((g<<p.center_frac)-centers_q[k]), k))
            for g in range(256)]


# Class: FixedResult
# Description: Stores the fixed-point centers and clustering results.
@dataclass
class FixedResult:
    centers_q: list[int]
    lut: list[int]
    iterations: int
    converged: bool
    trace: list[dict]
    profile: Profile
    active_bins: int

    # Function: centers
    # Description: Converts the fixed-point centers to regular numbers.
    @property
    def centers(self):
        return [c/(1<<self.profile.center_frac) for c in self.centers_q]


# Function: weighted_contribution
# Description: Calculates one weighted contribution using the selected profile.
def weighted_contribution(count: int, membership_q: int, p: Profile) -> int:
    # precision multiplies the count before shifting; compact shifts U squared first
    # the two policies can give different integer results
    if not (0 <= count <= 202500 and 0 <= membership_q <= (1<<p.member_frac)):
        raise ValueError('invalid histogram count or membership')
    if p.accumulation_policy == 'multiply_before_shift':
        return (count*membership_q*membership_q) >> p.member_frac
    return count*((membership_q*membership_q) >> p.member_frac)


# Function: compute_bin
# Description: Calculates one histogram bin's contributions to each cluster.
def compute_bin(gray: int, count: int, centers_q: Sequence[int], p: Profile, *, lane: int = 0) -> dict:
    members, dbg = compute_memberships(gray, centers_q, p)
    m = p.member_frac
    u2 = [(u*u)>>m for u in members]  # stores U squared for checking the calculations
    den = [weighted_contribution(count,u,p) for u in members]
    num = [v*gray for v in den]
    return dict(gray=gray, count=count, lane=lane, **dbg,
                membership_square_q=u2, contribute_den=den, contribute_num=num)


# Function: run
# Description: Runs fixed-point FCM on a histogram and returns the results.
def run(hist: Sequence[int], k: int, p: Profile, *, lanes: int = 1,
        max_iter: int = 200, init_q: Sequence[int] | None = None) -> FixedResult:
    check_histogram(hist)
    if not (2 <= k <= 7 and max_iter == 200 and 1 <= lanes <= 16):
        raise ValueError('K=2..7; max_iter=200; 1<=P<=16')
    f = p.center_frac
    centers = ([(int(x)<<f) for x in initial_centers(k)] if init_q is None else list(init_q))
    if len(centers) != k or any(not 0 <= c <= (255<<f) for c in centers):
        raise ValueError('initial centers must fit Q8.F grayscale range')
    active = [(g, count) for g, count in enumerate(hist) if count]
    trace = []
    converged = False
    w = p.widths
    for iteration in range(1, max_iter+1):
        old = list(centers)
        # split bins between lanes and combine their sums in a fixed order
        # this gives the same result for every supported lane count
        lane_n = [[0]*k for _ in range(lanes)]
        lane_d = [[0]*k for _ in range(lanes)]
        for bin_index, (g, count) in enumerate(active):
            lane = bin_index % lanes
            b = compute_bin(g, count, old, p, lane=lane)
            for j in range(k):
                lane_n[lane][j] += b['contribute_num'][j]
                lane_d[lane][j] += b['contribute_den'][j]
        num = [sum(lane_n[lane][j] for lane in range(lanes)) for j in range(k)]
        den = [sum(lane_d[lane][j] for lane in range(lanes)) for j in range(k)]
        # check that the sums fit within the profile bit widths
        assert max(den) < (1<<w['accumulator_den'])
        assert max(num) < (1<<w['accumulator_num'])
        centers = [(num[j]<<f)//den[j] if den[j] else old[j] for j in range(k)]
        dead = [j for j, d in enumerate(den) if d == 0]
        reseed_gray = {}
        if dead:
            # rounding can leave a cluster with no weighted contributions
            # give it a gray value that is poorly represented by the centers
            # rank bins by count times nearest squared distance
            # break equal scores by gray value and avoid reusing bins when possible
            reseed_scores = [(count * min(abs((g<<f)-c)**2 for c in old), g)
                             for g, count in active]
            candidates = sorted(reseed_scores, key=lambda x: (-x[0], x[1]))
            used = set()
            for j in dead:
                g = next((g for score, g in candidates if g not in used), candidates[0][1])
                centers[j] = g << f
                reseed_gray[j] = g
                used.add(g)
        assert all(0 <= c <= (255<<f) for c in centers), 'weighted-average center escaped grayscale domain'
        delta = max(abs(centers[j]-old[j]) for j in range(k))
        trace.append(dict(iteration=iteration, centers_in_q=old, centers_out_q=list(centers),
                          numerator=num, denominator=den, delta_q=delta,
                          converged=delta<=p.epsilon_raw, active_bins=len(active),
                          dead_clusters=dead, reseed_gray=reseed_gray))
        # stop when the largest change is within the fixed-point threshold
        if delta <= p.epsilon_raw:
            converged = True
            break
    return FixedResult(centers, label_lut(centers, p), len(trace), converged, trace, p, len(active))
