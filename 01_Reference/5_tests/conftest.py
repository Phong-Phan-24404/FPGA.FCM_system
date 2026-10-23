# File: 5_tests/conftest.py
# Description: Provides shared image and histogram fixtures for tests.

# Both fixtures use the same 450x450 grayscale image file.
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import refpkg  # noqa: F401  - registers the reference packages

import pytest

from golden_algorithm.fcm import histogram_from_pixels
from verification.mem_file import read_mem
from workspace_paths import FIXTURES

PIXEL_FIXTURE = FIXTURES / 'input_grayscale.mem'


# Function: pixels
# Description: Loads the sample grayscale frame in raster order.
@pytest.fixture(scope='session')
def pixels():
    # load the image once for the whole test session
    if not PIXEL_FIXTURE.is_file():
        pytest.skip(f'thiếu fixture ảnh: {PIXEL_FIXTURE}')
    values = read_mem(PIXEL_FIXTURE, 8)
    if len(values) != 450 * 450:
        pytest.fail(
            f'{PIXEL_FIXTURE} phải có đúng 202500 giá trị, đang có {len(values)}'
        )
    return values


# Function: hist
# Description: Creates the histogram for the sample image.
@pytest.fixture(scope='session')
def hist(pixels):
    return histogram_from_pixels(pixels)
