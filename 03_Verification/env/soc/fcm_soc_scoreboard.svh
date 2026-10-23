// File: fcm_soc_scoreboard.svh
// Description: Sets up the soc scoreboard component.

  // Class: fcm_soc_scoreboard
  // Description: Checks the DUT results against the reference vectors.
  class fcm_soc_scoreboard extends uvm_component;
    `uvm_component_utils(fcm_soc_scoreboard)

    uvm_tlm_analysis_fifo #(fcm_soc_item) stimulus_fifo;
    uvm_tlm_analysis_fifo #(fcm_soc_item) observed_fifo;

    int unsigned checked;
    int unsigned failed;

    // Track the planned and checked transaction counts so missing results do not look like a pass.
    int unsigned planned;
    int unsigned received_expected;
    int unsigned received_observed;
    int unsigned pending_expected;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name, uvm_component parent);
      super.new(name, parent);
      stimulus_fifo = new("stimulus_fifo", this);
      observed_fifo = new("observed_fifo", this);
    endfunction

    // Task: run_phase
    // Description: Handles transactions during the UVM run phase.
    task run_phase(uvm_phase phase);
      fcm_soc_item exp_item, obs_item;
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
    function void compare(fcm_soc_item exp_item, fcm_soc_item obs_item);
      bit ok = 1'b1;

      checked++;

      // Invalid EOF cases must raise error_o; normal cases must not.
      // Check both outcomes instead of skipping the error check.
      if (obs_item.saw_error !== exp_item.expect_error) begin
        ok = 1'b0;
        `uvm_error("ERRORFLAG",
                   $sformatf("error_o=%0b nhung ky vong %0b: %s",
                             obs_item.saw_error, exp_item.expect_error,
                             exp_item.convert2string()))
      end
      if (obs_item.saw_contract_error) begin
        ok = 1'b0;
        `uvm_error("CONTRACT",
                   $sformatf("pipeline bat contract_error_o: %s",
                             exp_item.convert2string()))
      end

      // Check the accepted beat count because a missing pixel may not change a rounded center.
      // Use planned_beats() since an early-EOF case sends only part of the image.
      if (obs_item.observed_beats != exp_item.planned_beats()) begin
        ok = 1'b0;
        `uvm_error("BEATS",
                   $sformatf("DUT nhan %0d beat, driver gui %0d (%s)",
                             obs_item.observed_beats, exp_item.planned_beats(),
                             exp_item.convert2string()))
      end

      // An error case stops before the FCM result is valid.
      // Do not compare centers or cluster count for that case.
      if (exp_item.expect_error) begin
        if (!ok) failed++;
        return;
      end

      if (obs_item.actual_num_clusters !== exp_item.k) begin
        ok = 1'b0;
        `uvm_error("NUMC",
                   $sformatf("active_num_clusters: DUT=%0d expected=%0d (%s)",
                             obs_item.actual_num_clusters, exp_item.k,
                             exp_item.convert2string()))
      end

      // Compare only active clusters, because other lanes have no expected values.
      for (int i = 0; i < MAX_C; i++) begin
        if (i >= int'(exp_item.k)) continue;
        if (obs_item.actual_centroids[i] !== exp_item.expected_centroids[i]) begin
          ok = 1'b0;
          `uvm_error("MISMATCH",
                     $sformatf("centroid[%0d]: DUT=%02X reference=%02X (%s)",
                               i, obs_item.actual_centroids[i],
                               exp_item.expected_centroids[i],
                               exp_item.convert2string()))
        end
      end

      if (!ok) failed++;
    endfunction

    // Function: report_phase
    // Description: Prints the final check results.
    function void report_phase(uvm_phase phase);
      if (planned == 0 || checked != planned || received_expected != planned ||
          received_observed != planned || pending_expected != 0 ||
          stimulus_fifo.used() != 0 || observed_fifo.used() != 0)
        `uvm_error("INCOMPLETE",
                   $sformatf("soc planned=%0d checked=%0d pending=%0d exp_q=%0d obs_q=%0d",
                             planned, checked, pending_expected,
                             stimulus_fifo.used(), observed_fifo.used()))
      if (checked == 0)
        `uvm_error("SCOREBOARD", "fcm_stream_pipeline: no case was checked")
      else if (failed == 0)
        `uvm_info("SCOREBOARD",
                  $sformatf("fcm_stream_pipeline: %0d/%0d cases match reference",
                            checked, checked), UVM_NONE)
      else
        `uvm_error("SCOREBOARD",
                   $sformatf("fcm_stream_pipeline: %0d/%0d cases MISMATCH",
                             failed, checked))
    endfunction
  endclass
