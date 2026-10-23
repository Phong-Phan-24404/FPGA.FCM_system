# File: conftest.py
# Description: Makes the reference packages available during pytest runs.

# Importing refpkg lets pytest find the numbered reference packages.
import refpkg  # noqa: F401  - registers the reference packages
