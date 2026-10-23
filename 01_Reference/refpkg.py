# File: refpkg.py
# Description: Registers numbered source folders as regular Python packages.

# Python cannot import folder names that start with a number directly.
# Register each folder under its plain package name so normal and relative
# imports work inside the reference project.
# Entry scripts import this module before using the registered packages.
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent

# load packages in dependency order: golden, fixed-point, then verification
_PACKAGES = (
    ('1_golden_algorithm', 'golden_algorithm'),
    ('2_bit_exact_algorithm', 'bit_exact_algorithm'),
    ('3_verification_resources', 'verification'),
)


# Function: _register
# Description: Loads one source folder under its Python package name.
def _register(dir_name: str, module_name: str):
    existing = sys.modules.get(module_name)
    if existing is not None:
        return existing

    package_dir = _HERE / dir_name
    init_file = package_dir / '__init__.py'
    if not init_file.is_file():
        raise ImportError(
            f"Reference package '{dir_name}' thiếu __init__.py: {init_file}"
        )

    # create an import spec for the folder with a numbered name
    spec = importlib.util.spec_from_file_location(
        module_name,
        init_file,
        submodule_search_locations=[str(package_dir)],
    )
    if spec is None or spec.loader is None:
        raise ImportError(f"Không tạo được spec cho {dir_name}")

    module = importlib.util.module_from_spec(spec)
    # register the module first so its submodules can import it
    sys.modules[module_name] = module
    try:
        spec.loader.exec_module(module)
    except BaseException:
        sys.modules.pop(module_name, None)
        raise
    return module


# Function: register_all
# Description: Registers all the source packages without repeating imports.
def register_all() -> dict:
    return {name: _register(dir_name, name) for dir_name, name in _PACKAGES}


register_all()
