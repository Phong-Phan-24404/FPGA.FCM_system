// File: fcm_core_perf.svh
// Description: Sets up the core perf component.

  // Measure START-to-DONE latency in clock cycles. +FCM_CYCLE_BUDGET sets an optional per-case cycle
  // limit.
  // Class: fcm_core_perf
  // Description: Measures the number of cycles used by each checked case.
  class fcm_core_perf extends uvm_subscriber #(fcm_core_item);
    `uvm_component_utils(fcm_core_perf)

    int unsigned n_by_k   [8];
    int unsigned sum_by_k [8];
    int unsigned min_by_k [8];
    int unsigned max_by_k [8];
    int unsigned iters_by_k [8];
    int unsigned total_cycles;
    int unsigned budget;
    int unsigned over_budget;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name, uvm_component parent);
      super.new(name, parent);
      for (int k = 0; k < 8; k++) min_by_k[k] = 32'hFFFF_FFFF;
    endfunction

    // Function: build_phase
    // Description: Builds the UVM components and reads their settings.
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!$value$plusargs("FCM_CYCLE_BUDGET=%d", budget)) budget = 0;
    endfunction

    // Function: write
    // Description: Records data from a checked transaction.
    function void write(fcm_core_item t);
      int unsigned c = t.actual_cycles;
      total_cycles += c;
      if (t.k < 8) begin
        n_by_k[t.k]++;
        sum_by_k[t.k]   += c;
        iters_by_k[t.k] += t.expected_iterations;
        if (c < min_by_k[t.k]) min_by_k[t.k] = c;
        if (c > max_by_k[t.k]) max_by_k[t.k] = c;
      end
      if (budget != 0 && c > budget) begin
        over_budget++;
        `uvm_error("PERF",
                   $sformatf("%s: %0d cycles exceeds budget %0d",
                             t.convert2string(), c, budget))
      end
    endfunction

    // Function: report_phase
    // Description: Prints the final check results.
    function void report_phase(uvm_phase phase);
      string s;
      int unsigned per_iter;
      s = $sformatf("start->done latency, %0d cycles total\n", total_cycles);
      s = {s, "    K   cases      min        max       mean   cycles/iteration\n"};
      for (int k = MIN_CLUSTERS; k <= MAX_CLUSTERS; k++) begin
        if (n_by_k[k] == 0) continue;
        per_iter = (iters_by_k[k] != 0) ? (sum_by_k[k] / iters_by_k[k]) : 0;
        s = {s, $sformatf("    %0d   %5d  %9d  %9d  %9d  %9d\n",
                          k, n_by_k[k], min_by_k[k], max_by_k[k],
                          sum_by_k[k] / n_by_k[k], per_iter)};
      end
      if (budget != 0)
        s = {s, $sformatf("    budget %0d cycles/case, %0d over", budget, over_budget)};
      `uvm_info("PERF", s, UVM_NONE)
    endfunction
  endclass
