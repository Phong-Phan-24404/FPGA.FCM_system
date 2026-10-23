# File: 3_verification_resources/metrics.py
# Description: Measures differences between floating-point and fixed-point clustering.

# Clusters can have different indices even when their centers match.
# Report both the original labels and the best matched labels for accuracy.
# Hardware checks still use the original indices.
from math import sqrt, fsum
from golden_algorithm.fcm import memberships


# Function: optimal_center_assignment
# Description: Matches fixed and floating-point centers with the lowest total error.
def optimal_center_assignment(fixed_centers, golden_centers):
    # try each valid cluster pairing and keep the lowest squared error
    k = len(fixed_centers)
    if k != len(golden_centers):
        raise ValueError('cluster mismatch')
    best = {0: (0.0, ())}
    for i, a in enumerate(fixed_centers):
        upcoming = {}
        for used, (cost, mapping) in best.items():
            for j, b in enumerate(golden_centers):
                if not (used >> j) & 1:
                    mask = used | (1 << j)
                    candidate = (cost + (a-b)**2, mapping + (j,))
                    if mask not in upcoming or candidate < upcoming[mask]:
                        upcoming[mask] = candidate
        best = upcoming
    return list(best[(1 << k)-1][1])


# Function: objective
# Description: Calculates the floating-point FCM objective for a histogram.
def objective(hist, centers):
    # use this value for accuracy checks, not exact hardware comparison
    return fsum(count * fsum((u*u)*((gray-c)**2)
                               for u,c in zip(memberships(gray,centers), centers))
                for gray,count in enumerate(hist) if count)


# Function: objective_trace
# Description: Calculates the objective after each fixed-point center update.
def objective_trace(hist, fixed):
    return [objective(hist, [c / (1<<fixed.profile.center_frac) for c in tr['centers_out_q']])
            for tr in fixed.trace]


# Function: optimal_label_assignment
# Description: Finds the cluster label mapping with the most matching pixels.
def optimal_label_assignment(hist, golden_lut, fixed_lut, k):
    # match labels using pixel counts instead of center distances
    # hardware output checks use the original cluster labels
    agreement=[[0]*k for _ in range(k)]
    for gray,count in enumerate(hist):
        if count:
            agreement[fixed_lut[gray]][golden_lut[gray]]+=count
    # find the assignment with the highest number of matching pixels
    best={0:(0,())}
    for i in range(k):
        nxt={}
        for used,(score,mapping) in best.items():
            for j in range(k):
                if not ((used>>j)&1):
                    mask=used|(1<<j)
                    cand=(score+agreement[i][j],mapping+(j,))
                    if mask not in nxt or cand[0]>nxt[mask][0] or (cand[0]==nxt[mask][0] and cand[1]<nxt[mask][1]):
                        nxt[mask]=cand
        best=nxt
    score,mapping=best[(1<<k)-1]
    return list(mapping),sum(hist)-score

# Function: metrics
# Description: Returns the accuracy measurements for one pair of FCM results.
def metrics(hist, gold, fixed):
    k = len(gold.centers)
    assert k == len(fixed.centers)
    mapping = optimal_center_assignment(fixed.centers, gold.centers)
    raw_e = [a-b for a,b in zip(fixed.centers, gold.centers)]
    aligned_e = [c-gold.centers[mapping[i]] for i,c in enumerate(fixed.centers)]
    raw_bins = [g for g in range(256) if gold.lut[g] != fixed.lut[g]]
    aligned_bins = [g for g in range(256) if gold.lut[g] != mapping[fixed.lut[g]]]
    pixels = sum(hist)
    optimal_label_map, optimal_pixel_errors=optimal_label_assignment(hist,gold.lut,fixed.lut,k)
    objective_golden=objective(hist,gold.centers)
    objective_fixed=objective(hist,fixed.centers)
    # skip the relative percentage when the reference objective is too small
    relative_objective_gap_pct=(100*(objective_fixed/objective_golden-1)
                               if objective_golden>=1.0 else None)
    return dict(objective_golden=objective_golden, objective_fixed=objective_fixed,
                objective_gap_per_pixel=(objective_fixed-objective_golden)/pixels,
                label_assignment_optimal=optimal_label_map,
                optimal_label_mismatch_pixels=optimal_pixel_errors,
                optimal_label_mismatch_pct=100*optimal_pixel_errors/pixels,
                relative_objective_gap_pct=relative_objective_gap_pct, K=k, profile=fixed.profile.name,
                golden_iters=gold.iterations, fixed_iters=fixed.iterations,
                golden_converged=gold.converged, fixed_converged=fixed.converged,
                center_rmse=sqrt(sum(e*e for e in raw_e)/k),
                center_rmse_aligned=sqrt(sum(e*e for e in aligned_e)/k),
                center_max_abs=max(abs(e) for e in raw_e),
                center_max_abs_aligned=max(abs(e) for e in aligned_e),
                mismatching_bins=len(raw_bins),
                mismatching_pixels=sum(hist[g] for g in raw_bins),
                mismatch_pixel_pct=100*sum(hist[g] for g in raw_bins)/pixels,
                mismatching_bins_aligned=len(aligned_bins),
                mismatching_pixels_aligned=sum(hist[g] for g in aligned_bins),
                mismatch_pixel_pct_aligned=100*sum(hist[g] for g in aligned_bins)/pixels,
                cluster_permutation=mapping,
                fixed_centers=fixed.centers, golden_centers=gold.centers,
                dead_reseeds=sum(len(step['dead_clusters']) for step in fixed.trace))
