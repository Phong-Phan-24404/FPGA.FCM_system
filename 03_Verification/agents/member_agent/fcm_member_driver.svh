// File: fcm_member_driver.svh
// Description: Drives DUT inputs for the member UVM agent.

  // Class: fcm_member_driver
  // Description: Sends test inputs to the DUT.
  class fcm_member_driver extends uvm_driver #(fcm_member_item);
    `uvm_component_utils(fcm_member_driver)

    fcm_member_agent_cfg       cfg;
    virtual fcm_member_if vif;
    uvm_analysis_port #(fcm_member_item) stimulus_ap;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name, uvm_component parent);
      super.new(name, parent);
      stimulus_ap = new("stimulus_ap", this);
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
      fcm_member_item item;

      vif.start <= 1'b0;
      vif.num_clusters <= '0;
      vif.gray <= '0;
      for (int i = 0; i < MAX_C; i++) vif.centers_q[i] <= '0;

      wait (vif.rst_n === 1'b1);

      forever begin
        seq_item_port.get_next_item(item);

        @(negedge vif.clk);
        vif.num_clusters <= item.k;
        vif.gray         <= item.gray;
        for (int i = 0; i < MAX_C; i++) vif.centers_q[i] <= item.centers[i];
        vif.start <= 1'b1;

        @(negedge vif.clk);
        vif.start <= 1'b0;

        // Send the input and expected values to the scoreboard in transaction order.
        stimulus_ap.write(item);

        @(posedge vif.done);
        @(negedge vif.clk);

        seq_item_port.item_done();
      end
    endtask
  endclass
