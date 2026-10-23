// File: fcm_core_item.svh
// Description: Defines the transaction data for core verification.

  // Class: fcm_core_item
  // Description: Stores the inputs and results for one test case.
  class fcm_core_item extends uvm_sequence_item;
    string                case_name;
    int unsigned          case_id;
    logic [NUMC_W-1:0]    k;
    int unsigned          n_active;

    // Read all 256 histogram bins from hist_counts_u18.mem.
    int unsigned          hist [GRAY_BINS];

    center_t              init_centers [MAX_C];
    center_t              expected_centers [MAX_C];
    center_t              actual_centers   [MAX_C];
    int unsigned          expected_iterations;
    bit                   expected_converged;
    logic [ITER_W-1:0]    actual_iterations;
    logic                 actual_converged;

    // Use golden_lut_u3.mem to check the label LUT.
    bit [LABEL_W-1:0]     expected_lut [GRAY_BINS];
    logic [LABEL_W-1:0]   actual_lut   [GRAY_BINS];

    logic                 saw_contract_error;

    // Record the observed START-to-DONE cycle count for performance reporting.
    int unsigned          actual_cycles;

    `uvm_object_utils(fcm_core_item)

    // Function: new
    // Description: Creates the component with default values.
    function new(string name = "fcm_core_item");
      super.new(name);
    endfunction

    // Function: convert2string
    // Description: Formats the item values for printing in the log.
    function string convert2string();
      return $sformatf("%s k=%0d active=%0d iters=%0d conv=%0b",
                       case_name, k, n_active, expected_iterations,
                       expected_converged);
    endfunction
  endclass
