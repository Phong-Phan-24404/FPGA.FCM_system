// File: fcm_core_coverage.svh
// Description: Sets up the core coverage component.

  // Use simple counters to track the core scenarios checked by the scoreboard.
  // Class: fcm_core_coverage
  // Description: Counts the scenarios covered by checked transactions.
  class fcm_core_coverage extends uvm_subscriber #(fcm_core_item);
    `uvm_component_utils(fcm_core_coverage)

    int unsigned n_total;
    int unsigned n_by_k [8];
    // Low-overhead portable cross-counter: observed-and-scoreboard-checked
    // K x active-bin class. Not equivalent to universal coverage closure.
    int unsigned n_k_x_active [8][5];
    int unsigned n_converged;
    int unsigned n_not_converged;
    int unsigned n_iter_min;        // Converged on the first iteration
    int unsigned n_iter_max;        // Reached the MAX_ITER limit
    int unsigned min_bins;
    int unsigned max_bins;
    int unsigned min_iters;
    int unsigned max_iters;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name, uvm_component parent);
      super.new(name, parent);
      min_bins  = 32'hFFFF_FFFF;
      min_iters = 32'hFFFF_FFFF;
    endfunction

    // Function: write
    // Description: Records data from a checked transaction.
    function void write(fcm_core_item t);
      int class_id;
      n_total++;
      if (t.k < 8) n_by_k[t.k]++;
      class_id = (t.n_active == 1) ? 0 : (t.n_active <= 7) ? 1 :
                 (t.n_active <= 63) ? 2 : (t.n_active < 256) ? 3 : 4;
      if (t.k < 8) n_k_x_active[t.k][class_id]++;
      if (t.expected_converged) n_converged++;
      else                      n_not_converged++;
      if (t.expected_iterations == 1)        n_iter_min++;
      if (t.expected_iterations == MAX_ITER) n_iter_max++;
      if (t.n_active < min_bins) min_bins = t.n_active;
      if (t.n_active > max_bins) max_bins = t.n_active;
      if (t.expected_iterations < min_iters) min_iters = t.expected_iterations;
      if (t.expected_iterations > max_iters) max_iters = t.expected_iterations;
    endfunction

    // Function: report_phase
    // Description: Prints the final check results.
    function void report_phase(uvm_phase phase);
      string s;
      s = $sformatf("ran %0d cases\n", n_total);
      for (int k = MIN_CLUSTERS; k <= MAX_CLUSTERS; k++)
        s = {s, $sformatf("    K=%0d                  : %0d\n", k, n_by_k[k])};
      s = {s, $sformatf("    converged / not       : %0d / %0d\n",
                        n_converged, n_not_converged)};
      s = {s, $sformatf("    iterations range      : %0d .. %0d\n",
                        min_iters, max_iters)};
      s = {s, $sformatf("    active bins range     : %0d .. %0d\n",
                        min_bins, max_bins)};
      s = {s, $sformatf("    iter==1 / iter==%0d   : %0d / %0d",
                        MAX_ITER, n_iter_min, n_iter_max)};
      for (int k = MIN_CLUSTERS; k <= MAX_CLUSTERS; k++) begin
        s = {s, $sformatf("\n    checked K=%0d x bins{1,2..7,8..63,64..255,256}: ",k)};
        for (int binclass=0; binclass<5; binclass++)
          s = {s, $sformatf("%0d ",n_k_x_active[k][binclass])};
      end
      `uvm_info("COVERAGE", s, UVM_NONE)

      for (int k = MIN_CLUSTERS; k <= MAX_CLUSTERS; k++)
        if (n_by_k[k] == 0)
          `uvm_warning("COVERAGE", $sformatf("no run case with K=%0d", k))
      if (n_converged == 0)
        `uvm_warning("COVERAGE", "no converging run case in vector set")
    endfunction
  endclass
