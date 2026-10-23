// File: fcm_soc_coverage.svh
// Description: Sets up the soc coverage component.

  // Use counters to track checked SoC scenarios without covergroups.
  // Class: fcm_soc_coverage
  // Description: Counts the scenarios covered by checked transactions.
  class fcm_soc_coverage extends uvm_subscriber #(fcm_soc_item);
    `uvm_component_utils(fcm_soc_coverage)

    int unsigned n_by_k [8];
    int unsigned n_total;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    // Function: write
    // Description: Records data from a checked transaction.
    function void write(fcm_soc_item t);
      n_total++;
      if (t.k < 8) n_by_k[t.k]++;
    endfunction

    // Function: report_phase
    // Description: Prints the final check results.
    function void report_phase(uvm_phase phase);
      string s;
      s = $sformatf("ran %0d cases\n", n_total);
      for (int k = MIN_CLUSTERS; k <= MAX_CLUSTERS; k++)
        s = {s, $sformatf("    K=%0d : %0d\n", k, n_by_k[k])};
      `uvm_info("COVERAGE", s, UVM_NONE)
    endfunction
  endclass
