// File: fcm_core_monitor.svh
// Description: Observes DUT outputs for the core UVM agent.

  // Class: fcm_core_monitor
  // Description: Reads the DUT results and sends them to the scoreboard.
  class fcm_core_monitor extends uvm_monitor;
    `uvm_component_utils(fcm_core_monitor)

    fcm_core_agent_cfg       cfg;
    virtual fcm_core_if vif;
    uvm_analysis_port #(fcm_core_item) ap;

    // Count the transactions published by this monitor, even in passive mode.
    int unsigned observed_count;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    // Function: build_phase
    // Description: Builds the UVM components and reads their settings.
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(fcm_core_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "fcm_core_agent_cfg not set for this component")
      vif = cfg.vif;
    endfunction

    // Task: run_phase
    // Description: Handles transactions during the UVM run phase.
    task run_phase(uvm_phase phase);
      fcm_core_item obs;
      int unsigned monitor_id = 0;
      int unsigned cycles;

      forever begin
        // Count cycles from START to DONE to measure the full core latency.
        do @(posedge vif.clk); while (vif.start !== 1'b1);
        cycles = 0;

        // Sample the results when DONE is high and the output signals are stable.
        do begin
          @(posedge vif.clk);
          cycles++;
        end while (vif.done !== 1'b1);

        obs = fcm_core_item::type_id::create("obs");
        obs.case_id = monitor_id++;
        obs.actual_cycles = cycles;
        obs.k = vif.num_clusters;
        for (int i = 0; i < MAX_C; i++) obs.actual_centers[i] = vif.centers_q[i];
        obs.actual_converged   = vif.converged;
        obs.actual_iterations  = vif.iter_converged;
        obs.saw_contract_error = vif.contract_error;
        // The driver sets each LUT address on a falling clock edge.
        // RAM updates its registered output on the next rising edge.
        // Read the value at the following falling edge.
        @(negedge vif.clk);
        for (int g = 0; g < GRAY_BINS; g++) begin
          @(negedge vif.clk);
          obs.actual_lut[g] = vif.labels_lut_data;
        end
        observed_count++;
        ap.write(obs);
      end
    endtask
  endclass
