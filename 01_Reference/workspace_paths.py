# File: workspace_paths.py
# Description: Stores the paths used by the reference code and tests.

# Keep project folders in one place so tools use the same paths.
from pathlib import Path

WORKSPACE = Path(__file__).resolve().parent.parent

# the reference code and its models share this folder
REFERENCE = WORKSPACE / '01_Reference'
MODELS = REFERENCE
FIXTURES = REFERENCE / 'fixtures'

GOLDEN_ALGORITHM = REFERENCE / '1_golden_algorithm'
BIT_EXACT_ALGORITHM = REFERENCE / '2_bit_exact_algorithm'
VERIFICATION_RESOURCES = REFERENCE / '3_verification_resources'

# location of the verification workspace and exported vectors
TESTBENCH = WORKSPACE / '03_Verification'
VECTORS = TESTBENCH / 'vectors'
CPP_DIR = TESTBENCH / 'cpp'

DOCS = WORKSPACE / '06_Docs'
SPECS = DOCS / '01_reference_specs'
REPORTS = DOCS / '03_reports'
HW_EVIDENCE = DOCS / '02_hardware_evidence'

# location of the FCM hardware source files
FCM_IP = WORKSPACE / '02_FCM_IP'
FCM_IP_RTL = FCM_IP / 'rtl'

# paths for the board integration and host program
SOC_INTEGRATION = WORKSPACE / '04_SoC_Intergration' / 'de10_lite_fcm_sdram'
HOST_PC = WORKSPACE / '05_Host_PC'
