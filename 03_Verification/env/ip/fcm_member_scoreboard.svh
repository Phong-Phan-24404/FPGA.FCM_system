// File: fcm_member_scoreboard.svh
// Description: Sets up the member scoreboard component.

  // Class: fcm_member_scoreboard
  // Description: Checks the DUT results against the reference vectors.
  class fcm_member_scoreboard extends uvm_component;
    `uvm_component_utils(fcm_member_scoreboard)

    uvm_tlm_analysis_fifo #(fcm_member_item) stimulus_fifo;
    uvm_tlm_analysis_fifo #(fcm_member_item) observed_fifo;

    int unsigned checked;
    int unsigned failed;
    int unsigned planned;
    int unsigned received_expected;
    int unsigned received_observed;
    int unsigned pending_expected;
    uvm_analysis_port #(fcm_member_item) checked_ap;

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
      fcm_member_item exp_item, obs_item;
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

    // Function: compare
    // Description: Compares a DUT transaction with its expected values.
    function void compare(fcm_member_item exp_item, fcm_member_item obs_item);
      bit ok = 1'b1;
      longint unsigned sum = 0;

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
                   $sformatf("fcm_member asserted contract_error: %s", exp_item.convert2string()))
      end

      for (int i = 0; i < MAX_C; i++) begin
        sum += obs_item.actual[i];
        if (obs_item.actual[i] !== exp_item.expected[i]) begin
          ok = 1'b0;
          `uvm_error("MISMATCH",
                     $sformatf("u[%0d]: DUT=%0d reference=%0d  (%s)",
                               i, obs_item.actual[i], exp_item.expected[i],
                               exp_item.convert2string()))
        end
      end

      // Also check that the membership values add up to exactly 2^M.
      if (sum != (longint'(1) << MEMBER_FRAC)) begin
        ok = 1'b0;
        `uvm_error("SUM",
                   $sformatf("sum(u)=%0d, must be %0d  (%s)",
                             sum, longint'(1) << MEMBER_FRAC,
                             exp_item.convert2string()))
      end

      if (!ok) failed++;
      else checked_ap.write(obs_item);
    endfunction

    // Function: report_phase
    // Description: Prints the final check results.
    function void report_phase(uvm_phase phase);
      if (planned == 0 || checked != planned || received_expected != planned ||
          received_observed != planned || pending_expected != 0 ||
          stimulus_fifo.used() != 0 || observed_fifo.used() != 0)
        `uvm_error("INCOMPLETE", $sformatf("member planned=%0d checked=%0d pending=%0d exp_q=%0d obs_q=%0d",
                   planned, checked, pending_expected, stimulus_fifo.used(), observed_fifo.used()))
      if (failed == 0)
        `uvm_info("SCOREBOARD",
                  $sformatf("fcm_member: %0d/%0d cases match reference", checked, checked),
                  UVM_NONE)
      else
        `uvm_error("SCOREBOARD",
                   $sformatf("fcm_member: %0d/%0d cases MISMATCH", failed, checked))
    endfunction
  endclass
