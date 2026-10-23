// File: fcm_member_monitor.svh
// Description: Observes DUT outputs for the member UVM agent.

  // Class: fcm_member_monitor
  // Description: Reads the DUT results and sends them to the scoreboard.
  class fcm_member_monitor extends uvm_monitor;
    `uvm_component_utils(fcm_member_monitor)

    fcm_member_agent_cfg       cfg;
    virtual fcm_member_if vif;
    uvm_analysis_port #(fcm_member_item) ap;

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
      if (!uvm_config_db #(fcm_member_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "fcm_member_agent_cfg not set for this component")
      vif = cfg.vif;
    endfunction

    // Task: run_phase
    // Description: Handles transactions during the UVM run phase.
    task run_phase(uvm_phase phase);
      fcm_member_item obs;
      int unsigned monitor_id = 0;

      forever begin
        // Sample contract_error at DONE because the flag stays high until the next start.
        do @(posedge vif.clk); while (vif.done !== 1'b1);

        obs = fcm_member_item::type_id::create("obs");
        obs.case_id = monitor_id++;
        obs.k    = vif.num_clusters;
        obs.gray = vif.gray;
        for (int i = 0; i < MAX_C; i++) begin
          obs.centers[i] = vif.centers_q[i];
          obs.actual[i]  = vif.membership_q[i];
        end
        obs.saw_contract_error = vif.contract_error;
        observed_count++;
        ap.write(obs);
      end
    endtask
  endclass
