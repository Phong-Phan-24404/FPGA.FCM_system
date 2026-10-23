# Python Reference Test Suite

This directory contains validation tests for the Python FCM reference model:

- `test_algorithm.py`: Unit and property tests verifying mathematical correctness, invariant properties, and algorithmic behavior for floating-point and bit-exact fixed-point implementations.
- `test_vectors.py`: Validates the generated `.mem` files, execution traces, and contract manifests across all cluster configurations (K=2 to K=7).
- `check_numerical_acceptance.py`: Optional mathematical acceptance gate evaluating clustering quality against floating-point ground truth.
