# File: 3_verification_resources/mem_exporter.py
# Description: Saves clustering data as memory files and case information.

from __future__ import annotations
from pathlib import Path
import json
from golden_algorithm.fcm import histogram_from_pixels
from bit_exact_algorithm.fcm import FixedResult
from .mem_file import write_mem
from .sdram import pack_u16_low_byte_first,image_crc32


# Function: export_case
# Description: Writes memory vectors, a contract file, and a JSON manifest.
def export_case(root: str | Path, name: str, pixels: list[int], k: int, result: FixedResult):
    p = result.profile
    w = p.widths
    folder = Path(root) / name
    folder.mkdir(parents=True, exist_ok=True)
    h = histogram_from_pixels(pixels)
    if len(result.centers_q) != k:
        raise ValueError('K mismatch')
    wc, wd, wn = w['center'], w['accumulator_den'], w['accumulator_num']
    # store each filename together with its values and bit width
    definitions = [
        ('pixels_u8.mem', pixels, 8),
        ('sdram_proposed_u16.mem', pack_u16_low_byte_first(pixels), 16),
        ('hist_counts_u18.mem', h, 18),
        ('initial_centers.mem', result.trace[0]['centers_in_q'], wc),
        ('golden_centers.mem', result.centers_q, wc),
        ('golden_lut_u3.mem', result.lut, 3),
        ('golden_converged_u1.mem', [int(result.converged)], 1),
        ('golden_iteration_count_u8.mem', [result.iterations], 8),
        ('trace_centers_in.mem', [x for tr in result.trace for x in tr['centers_in_q']], wc),
        ('trace_centers_out.mem', [x for tr in result.trace for x in tr['centers_out_q']], wc),
        ('trace_acc_num.mem', [x for tr in result.trace for x in tr['numerator']], wn),
        ('trace_acc_den.mem', [x for tr in result.trace for x in tr['denominator']], wd),
        ('trace_delta.mem', [tr['delta_q'] for tr in result.trace], w['delta']),
        ('trace_reseed_u1.mem', [int(j in tr['dead_clusters']) for tr in result.trace for j in range(k)], 1),
        ('trace_reseed_gray_u8.mem', [tr['reseed_gray'].get(j,0) for tr in result.trace for j in range(k)], 8),
    ]
    mem_fields = {}
    for filename, data, width in definitions:
        write_mem(folder / filename, data, width)
        mem_fields[filename] = dict(width=width, signed=False, count=len(data),
                                    layout=('iteration_major_cluster_minor' if filename.startswith('trace_') and filename not in ('trace_delta.mem',) else 'linear'))
    # write a text contract so a C++ testbench can read it without JSON support
    contract_lines = ['FCM_UNSIGNED_RATIO_NORM_V4', f'K {k}',
                      f'ITERATIONS {result.iterations}', f'PROFILE {p.name}',
                      f'CENTER_FRAC {p.center_frac}', f'MEMBER_FRAC {p.member_frac}',
                      f'ACCUMULATION_POLICY {p.accumulation_policy}']
    for filename, spec in mem_fields.items():
        contract_lines.append(f'MEM {filename} {spec["width"]} {spec["count"]} 0')
    (folder/'vector_contract.txt').write_text('\n'.join(contract_lines)+'\n')
    manifest = dict(case=name, profile=p.describe(), K=k,
                    host_packaging=dict(status='PROPOSED_UNVERIFIED_BOARD_LAYOUT',
                                        format='row-major 16-bit words; pixel 2i low byte, pixel 2i+1 high byte',
                                        crc32_u8_pixels=image_crc32(pixels)),
                    iterations=result.iterations, converged=result.converged,
                    centers_real=result.centers, active_bins=result.active_bins,
                    mem_fields=mem_fields,
                    note='No packing: one unsigned word per line. trace arrays are iteration-major, cluster-minor; deltas iteration-major.',
                    contract='FCM_UNSIGNED_RATIO_NORM_V4',
                    phase='bit_exact_algorithm; do not compare these against legacy Q16.16 bit patterns')
    (folder/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    return folder
