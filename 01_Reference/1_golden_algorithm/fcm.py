# File: 1_golden_algorithm/fcm.py
# Description: Runs floating-point FCM clustering on grayscale histograms.

# Uses floating-point values to measure accuracy, not bit-exact hardware behavior.
from __future__ import annotations
from dataclasses import dataclass
from typing import Sequence

PIXELS = 450 * 450


# Function: histogram_from_pixels
# Description: Counts the pixels at each of the 256 grayscale levels.
def histogram_from_pixels(pixels: Sequence[int]) -> list[int]:
    if len(pixels) != PIXELS:
        raise ValueError(f'expected {PIXELS} pixels, received {len(pixels)}')
    hist = [0] * 256
    for px in pixels:
        if not (0 <= px <= 255):
            raise ValueError(f'invalid 8-bit grayscale pixel: {px}')
        hist[px] += 1
    return hist


# Function: check_histogram
# Description: Checks that the histogram contains one valid 450x450 frame.
def check_histogram(hist: Sequence[int]) -> None:
    if len(hist) != 256 or any(x < 0 or x > PIXELS or int(x) != x for x in hist):
        raise ValueError('histogram must have 256 nonnegative integer counts <=202500')
    if sum(hist) != PIXELS:
        raise ValueError('histogram must represent precisely 450x450 pixels')


# Function: initial_centers
# Description: Sets evenly spaced starting centers for K clusters.
def initial_centers(k: int) -> list[float]:
    if not (2 <= k <= 7):
        raise ValueError('K must be 2..7')
    # place the starting centers at integer grayscale values
    return [float((idx * 255) // (k + 1)) for idx in range(1, k + 1)]


# Function: memberships
# Description: Calculates how strongly a gray value belongs to each cluster.
def memberships(gray: int, centers: Sequence[float]) -> list[float]:
    # scale by the smallest squared distance to keep the ratios in range
    # if a gray matches multiple centers, split its membership equally
    distances = [abs(gray - c) for c in centers]
    zeros = [i for i, d in enumerate(distances) if d == 0.0]
    if zeros:
        return [(1.0 / len(zeros)) if i in zeros else 0.0 for i in range(len(centers))]
    dmin_sq = min(distances) ** 2
    ratios = [dmin_sq / (d * d) for d in distances]
    total = sum(ratios)
    return [v / total for v in ratios]


# Function: label_lut
# Description: Maps each grayscale value to the closest cluster.
def label_lut(centers: Sequence[float]) -> list[int]:
    # use the lower cluster index when two centers are equally close
    return [min(range(len(centers)), key=lambda k: (abs(gray - centers[k]), k)) for gray in range(256)]


# Class: GoldenResult
# Description: Stores the centers, labels, and iteration results.
@dataclass
class GoldenResult:
    centers: list[float]
    lut: list[int]
    iterations: int
    converged: bool
    trace: list[dict]


# Function: run
# Description: Runs the floating-point clustering steps until convergence or the limit.
def run(hist: Sequence[int], k: int, *, max_iter: int = 200,
        epsilon: float = 0.1, init: Sequence[float] | None = None) -> GoldenResult:
    check_histogram(hist)
    if not (2 <= k <= 7 and max_iter == 200 and epsilon >= 0):
        raise ValueError('contract: K=2..7, max_iter=200, nonnegative epsilon')
    centers = list(initial_centers(k) if init is None else init)
    if len(centers) != k or not all(0.0 <= c <= 255.0 for c in centers):
        raise ValueError('initial centers must lie in [0,255]')
    trace = []
    converged = False
    # skip histogram bins that contain no pixels
    active = [(g, h) for g, h in enumerate(hist) if h]
    for iteration in range(1, max_iter + 1):
        numer = [0.0] * k
        denom = [0.0] * k
        before = list(centers)
        # add the weighted contribution from each occupied gray value
        for gray, count in active:
            u = memberships(gray, before)
            for j in range(k):
                h_u2 = count * u[j] * u[j]
                numer[j] += h_u2 * gray
                denom[j] += h_u2
        centers = [numer[j] / denom[j] if denom[j] > 0.0 else before[j] for j in range(k)]
        delta = max(abs(centers[j] - before[j]) for j in range(k))
        trace.append(dict(iteration=iteration, centers_in=before, centers_out=list(centers),
                          numerator=numer, denominator=denom, delta=delta))
        # stop when every center moves by at most epsilon
        if delta <= epsilon:
            converged = True
            break
    return GoldenResult(centers, label_lut(centers), len(trace), converged, trace)
