// File: fcm_soc_monitor.svh
// Description: Observes DUT outputs for the soc UVM agent.

  // Class: fcm_soc_monitor
  // Description: Reads the DUT results and sends them to the scoreboard.
  class fcm_soc_monitor extends uvm_monitor;
    `uvm_component_utils(fcm_soc_monitor)

    fcm_soc_agent_cfg       cfg;
    virtual fcm_soc_if vif;
    uvm_analysis_port #(fcm_soc_item) ap;

    // Count the transactions published by this monitor, even in passive mode.
    int unsigned observed_count;

    // Count accepted pixel beats for the current case.
    int unsigned beat_count;

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
      if (!uvm_config_db #(fcm_soc_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "fcm_soc_agent_cfg not set for this component")
      vif = cfg.vif;
    endfunction

    // Task: run_phase
    // Description: Watches the pixel stream and publishes the results.
    // Count accepted beats while streaming, then sample DONE or error separately.
    task count_beats();
      forever begin
        @(posedge vif.clk);
        if (vif.pixel_valid === 1'b1 && vif.pixel_ready === 1'b1)
          beat_count++;
      end
    endtask

    task run_phase(uvm_phase phase);
      fcm_soc_item obs;
      bit finished_seen;

      finished_seen = 1'b0;
      fork count_beats(); join_none

      forever begin
        @(posedge vif.clk);

        // Detect the rising edge of done_o so each case is reported only once.
        if (vif.done !== 1'b1 && vif.error !== 1'b1) begin
          finished_seen = 1'b0;
          continue;
        end
        if (finished_seen) continue;
        finished_seen = 1'b1;

        // Publish results on either DONE or error so the scoreboard receives every case.
        obs = fcm_soc_item::type_id::create("obs");
        obs.k = vif.num_clusters;
        for (int i = 0; i < MAX_C; i++) obs.actual_centroids[i] = vif.centroids[i];
        obs.actual_num_clusters = vif.active_num_clusters;
        obs.saw_error           = (vif.error === 1'b1);
        obs.saw_contract_error  = (vif.contract_error === 1'b1);
        obs.observed_beats      = beat_count;
        beat_count              = 0;   // reset before the next case
        observed_count++;
        ap.write(obs);
      end
    endtask
  endclass
