// File: fcm_core_scoreboard.svh
// Description: Sets up the core scoreboard component.

  // Class: fcm_core_scoreboard
  // Description: Checks the DUT results against the reference vectors.
  class fcm_core_scoreboard extends uvm_component;
    `uvm_component_utils(fcm_core_scoreboard)

    uvm_tlm_analysis_fifo #(fcm_core_item) stimulus_fifo;
    uvm_tlm_analysis_fifo #(fcm_core_item) observed_fifo;

    int unsigned checked;
    int unsigned failed;
    int unsigned planned;
    int unsigned received_expected;
    int unsigned received_observed;
    int unsigned pending_expected;
    uvm_analysis_port #(fcm_core_item) checked_ap;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name, uvm_component parent);
      super.new(name, parent);
      stimulus_fifo = new("stimulus_fifo", this);
      observed_fifo = new("observed_fifo", this);
      checked_ap = new("checked_ap", this);
    endfunction

    // Task: run_phase
    // Description: Handles transactions during the UVM run phase.
    task run_phase(uvm_phase phase);
      fcm_core_item exp_item, obs_item;
      forever begin
        stimulus_fifo.get(exp_item);
        received_expected++;
        pending_expected++;
        observed_fifo.get(obs_item);
        received_observed++;
        pending_expected--;
        compare(exp_item, obs_item);
      end
    endtask

    // Read expected results from vector files so the scoreboard does not repeat the FCM calculations.
    // Function: compare
    // Description: Compares a DUT transaction with its expected values.
    function void compare(fcm_core_item exp_item, fcm_core_item obs_item);
      bit ok = 1'b1;

      checked++;
      if (exp_item.case_id != obs_item.case_id) begin
        ok = 1'b0;
        `uvm_error("CASE_ID", $sformatf("expected id=%0d observed id=%0d",
                                     exp_item.case_id, obs_item.case_id))
      end
      if (exp_item.k !== obs_item.k) begin
        ok = 1'b0;
        `uvm_error("K_MISMATCH", "monitor K differs from driven K")
      end

      if (obs_item.saw_contract_error !== 1'b0) begin
        ok = 1'b0;
        `uvm_error("CONTRACT",
                   $sformatf("fcm_core asserted contract_error: %s",
                             exp_item.convert2string()))
      end

      for (int i = 0; i < MAX_C; i++) begin
        if (obs_item.actual_centers[i] !== exp_item.expected_centers[i]) begin
          ok = 1'b0;
          `uvm_error("MISMATCH",
                     $sformatf("center[%0d]: DUT=%0d reference=%0d  (%s)",
                               i, obs_item.actual_centers[i],
                               exp_item.expected_centers[i],
                               exp_item.convert2string()))
        end
      end

      if (obs_item.actual_iterations !== ITER_W'(exp_item.expected_iterations)) begin
        ok = 1'b0;
        `uvm_error("ITER",
                   $sformatf("iter_converged: DUT=%0d reference=%0d  (%s)",
                             obs_item.actual_iterations,
                             exp_item.expected_iterations,
                             exp_item.convert2string()))
      end

      if (obs_item.actual_converged !== exp_item.expected_converged) begin
        ok = 1'b0;
        `uvm_error("CONVERGED",
                   $sformatf("converged: DUT=%0b reference=%0b  (%s)",
                             obs_item.actual_converged,
                             exp_item.expected_converged,
                             exp_item.convert2string()))
      end

      // LUT observation is sampled independently by the passive monitor.
      // The driver only drives the read addresses after completion.
      begin
        int lut_errors = 0;
        for (int g = 0; g < GRAY_BINS; g++) begin
          if (obs_item.actual_lut[g] !== exp_item.expected_lut[g]) begin
            lut_errors++;
            // Show only the first few LUT mismatches to keep the report readable.
            if (lut_errors <= 4)
              `uvm_error("LUT",
                         $sformatf("lut[%0d]: DUT=%0d reference=%0d  (%s)",
                                   g, obs_item.actual_lut[g],
                                   exp_item.expected_lut[g],
                                   exp_item.convert2string()))
          end
        end
        if (lut_errors > 0) begin
          ok = 1'b0;
          `uvm_error("LUT",
                     $sformatf("%0d/%0d mục LUT sai (%s)",
                               lut_errors, GRAY_BINS, exp_item.convert2string()))
        end
      end

      if (!ok) failed++;
      else begin
        // Pass the measured latency along with the checked transaction.
        exp_item.actual_cycles = obs_item.actual_cycles;
        checked_ap.write(exp_item); // Coverage only on fully checked cases
      end
      if (ok)
        `uvm_info("SCOREBOARD",
                  $sformatf("case %0d matches reference (%s)",
                            checked, exp_item.convert2string()), UVM_HIGH)
    endfunction

    // Function: report_phase
    // Description: Prints the final check results.
    function void report_phase(uvm_phase phase);
      if (planned == 0 || checked != planned || received_expected != planned ||
          received_observed != planned || pending_expected != 0 ||
          stimulus_fifo.used() != 0 || observed_fifo.used() != 0)
        `uvm_error("INCOMPLETE", $sformatf("core planned=%0d checked=%0d pending=%0d exp_q=%0d obs_q=%0d",
                   planned, checked, pending_expected, stimulus_fifo.used(), observed_fifo.used()))
      if (checked == 0)
        `uvm_error("SCOREBOARD", "fcm_core: no case was checked")
      else if (failed == 0)
        `uvm_info("SCOREBOARD",
                  $sformatf("fcm_core: %0d/%0d cases match reference", checked, checked),
                  UVM_NONE)
      else
        `uvm_error("SCOREBOARD",
                   $sformatf("fcm_core: %0d/%0d cases MISMATCH", failed, checked))
    endfunction
  endclass
