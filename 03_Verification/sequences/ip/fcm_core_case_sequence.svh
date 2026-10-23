// File: fcm_core_case_sequence.svh
// Description: Loads and sends core case sequence verification scenarios.

  // Run core test cases using the saved histogram, starting centers, final centers, iteration count,
  // convergence flag, and label LUT.
  // Class: fcm_core_case_sequence
  // Description: Reads saved vectors and sends the test cases.
  class fcm_core_case_sequence extends uvm_sequence #(fcm_core_item);
    `uvm_object_utils(fcm_core_case_sequence)

    string       vector_dir = FCM_DEFAULT_VECTOR_DIR;  // set by the UVM test
    int unsigned max_items  = 0;   // zero runs all cases
    int unsigned sent_count = 0;
    // Keep case IDs in order when running several vector directories.
    int unsigned case_id_base = 0;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name = "fcm_core_case_sequence");
      super.new(name);
    endfunction

    // Require the expected number of words so incomplete vector files fail the test.
    // Function: load
    // Description: Reads the values needed for one verification case.
    function automatic bit load(string path, int expect_n,
                                ref longint unsigned values[$]);
      int n;
      n = fcm_read_mem(path, values);
      if (n < 0) begin
        `uvm_error("NOFILE", $sformatf("khong mo duoc: %s", path))
        return 1'b0;
      end
      if (n != expect_n) begin
        `uvm_error("BADMEM",
                   $sformatf("%s: co %0d word, can %0d", path, n, expect_n))
        return 1'b0;
      end
      return 1'b1;
    endfunction

    // Task: body
    // Description: Loads and sends the selected verification cases.
    task body();
      int unsigned sent;
      int k, iterations;
      string dir;
      longint unsigned hist   [$];
      longint unsigned init   [$];
      longint unsigned golden [$];
      longint unsigned lut    [$];
      longint unsigned iters  [$];
      longint unsigned conv   [$];
      fcm_core_item item;

      sent = 0;
      `uvm_info("SEQ", $sformatf("vector dir: %s", vector_dir), UVM_LOW)

      for (int kk = MIN_CLUSTERS; kk <= MAX_CLUSTERS; kk++) begin
        dir = fcm_case_dir(vector_dir, kk);
        if (!fcm_read_contract({dir, "/vector_contract.txt"}, k, iterations)) begin
          `uvm_warning("NOCASE", $sformatf("bo qua case: %s", dir))
          continue;
        end

        if (!load({dir, "/hist_counts_u18.mem"},   GRAY_BINS, hist))   continue;
        if (!load({dir, "/initial_centers.mem"},   k,         init))   continue;
        if (!load({dir, "/golden_centers.mem"},    k,         golden)) continue;
        if (!load({dir, "/golden_lut_u3.mem"},     GRAY_BINS, lut))    continue;
        if (!load({dir, "/golden_iteration_count_u8.mem"}, 1,  iters)) continue;
        if (!load({dir, "/golden_converged_u1.mem"},       1,  conv))  continue;

        item = fcm_core_item::type_id::create("item");
        item.case_id = case_id_base + sent;
        // Include the vector directory in each case name to identify a mismatch.
        item.case_name = {vector_dir, "/demo_k", fcm_pad(kk, 2)};
        item.n_active  = 0;
        for (int g = 0; g < GRAY_BINS; g++) begin
          item.hist[g] = int'(hist[g]);
          if (hist[g] != 0) item.n_active++;
          item.expected_lut[g] = lut[g][LABEL_W-1:0];
        end
        for (int i = 0; i < MAX_C; i++) begin
          item.init_centers[i]     = (i < k) ? center_t'(init[i])   : '0;
          item.expected_centers[i] = (i < k) ? center_t'(golden[i]) : '0;
        end

        start_item(item);
        item.k                   = k[NUMC_W-1:0];
        item.expected_iterations = int'(iters[0]);
        item.expected_converged  = conv[0][0];
        finish_item(item);

        sent++;
        if (max_items != 0 && sent >= max_items) break;
      end

      if (sent == 0)
        `uvm_fatal("NOVECTORS",
                   $sformatf("khong doc duoc case nao tu %s", vector_dir))
      sent_count = sent;
      `uvm_info("SEQ", $sformatf("sent %0d cases", sent), UVM_LOW)
    endtask
  endclass
