// File: fcm_member_coverage.svh
// Description: Sets up the member coverage component.

  // Track membership scenarios with counters because this simulator edition does not provide
  // SystemVerilog covergroups.
  // Class: fcm_member_coverage
  // Description: Counts the scenarios covered by checked transactions.
  class fcm_member_coverage extends uvm_subscriber #(fcm_member_item);
    `uvm_component_utils(fcm_member_coverage)

    int unsigned n_by_k [8];          // Number of cases for each K
    int unsigned n_exact_none;        // No center matches the pixel
    int unsigned n_exact_single;      // One center matches the pixel
    int unsigned n_exact_multiple;    // Multiple matching centers share 2^M equally
    int unsigned n_gray_min;
    int unsigned n_gray_max;
    int unsigned n_total;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    // Function: write
    // Description: Records data from a checked transaction.
    function void write(fcm_member_item t);
      center_t gray_q;
      int unsigned zero_count;

      n_total++;
      if (t.k < 8) n_by_k[t.k]++;
      if (t.gray == 0)   n_gray_min++;
      if (t.gray == 255) n_gray_max++;

      zero_count = 0;
      gray_q = center_t'(t.gray) << CENTER_FRAC;
      for (int i = 0; i < MAX_C; i++)
        if (i < int'(t.k) && t.centers[i] == gray_q) zero_count++;

      case (zero_count)
        0:       n_exact_none++;
        1:       n_exact_single++;
        default: n_exact_multiple++;
      endcase
    endfunction

    // Keep UVM report messages in ASCII so the simulator logs display them correctly.
    // Function: report_phase
    // Description: Prints the final check results.
    function void report_phase(uvm_phase phase);
      string s;
      s = $sformatf("ran %0d cases\n", n_total);
      for (int k = MIN_CLUSTERS; k <= MAX_CLUSTERS; k++)
        s = {s, $sformatf("    K=%0d                  : %0d\n", k, n_by_k[k])};
      s = {s, $sformatf("    no coincident center  : %0d\n", n_exact_none)};
      s = {s, $sformatf("    exactly 1 coincident  : %0d\n", n_exact_single)};
      s = {s, $sformatf("    many coincident       : %0d\n", n_exact_multiple)};
      s = {s, $sformatf("    gray=0 / gray=255     : %0d / %0d", n_gray_min, n_gray_max)};
      `uvm_info("COVERAGE", s, UVM_NONE)

      // Report which scenarios were not exercised by the available vectors.
      if (n_exact_none == 0 || n_exact_single == 0 || n_exact_multiple == 0)
        `uvm_warning("COVERAGE",
                     "vector set does not reach all three coincident-center branches")
      for (int k = MIN_CLUSTERS; k <= MAX_CLUSTERS; k++)
        if (n_by_k[k] == 0)
          `uvm_warning("COVERAGE", $sformatf("no case with K=%0d", k))
    endfunction
  endclass
