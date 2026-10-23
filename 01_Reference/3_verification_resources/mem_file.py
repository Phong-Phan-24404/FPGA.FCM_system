# File: 3_verification_resources/mem_file.py
# Description: Reads and writes hexadecimal Verilog memory files.

from pathlib import Path


# Function: write_mem
# Description: Writes integer values as fixed-width hexadecimal words.
def write_mem(path: str | Path, values, width: int, signed: bool = False):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    if not 1 <= width <= 64:
        raise ValueError('memory word width must be 1..64')
    vals = list(values)
    # check that each value fits the chosen word width
    for x in vals:
        lo, hi = (-(1<<(width-1)), (1<<(width-1))-1) if signed else (0, (1<<width)-1)
        if not lo <= x <= hi:
            raise ValueError(f'{p}: value {x} does not fit {width} bits')
    p.write_text(''.join(f'{x & ((1<<width)-1):0{(width+3)//4}X}\n' for x in vals))


# Function: read_mem
# Description: Reads the hexadecimal words from a memory file.
def read_mem(path: str | Path, width: int, signed: bool = False) -> list[int]:
    vals = []
    at = 0
    for linenum, line in enumerate(Path(path).read_text().splitlines(), 1):
    # remove comments before reading the data words
        code = line.split('//', 1)[0].split('#', 1)[0].strip()
        if not code:
            continue
        for token in code.split():
    # accept an address marker only at the expected next position
            if token.startswith('@'):
                at = int(token[1:], 16)
                continue
            x = int(token.replace('_',''), 16)
            if x >= 1<<width:
                raise ValueError(f'value too large at {path}:{linenum}')
            if at != len(vals):
                raise ValueError('sparse @-address files not supported by scoreboard')
            vals.append(x-(1<<width) if signed and x >= 1<<(width-1) else x)
            at += 1
    return vals
