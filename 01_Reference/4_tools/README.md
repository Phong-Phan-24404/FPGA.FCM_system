# Reference Tools

This directory contains standalone tools for vector generation and integrity verification:

- `generate_vectors.py`: Produces bit-exact golden vectors, intermediate simulation traces, and memory fixtures for both `precision` and `compact` profiles (K=2 through K=7). Output is written directly to `03_Verification/vectors/`.
- `check_reference_lock.py`: Validates mathematical model integrity by checking SHA-256 signatures of arithmetic implementations and frozen K=2–7 fixtures.
