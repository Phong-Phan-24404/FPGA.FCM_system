// File: fcm_core_driver.svh
// Description: Drives DUT inputs for the core UVM agent.

  // Class: fcm_core_driver
  // Description: Sends test inputs to the DUT.
  class fcm_core_driver extends uvm_driver #(fcm_core_item);
    `uvm_component_utils(fcm_core_driver)

    fcm_core_agent_cfg       cfg;
    virtual fcm_core_if vif;
    uvm_analysis_port #(fcm_core_item) stimulus_ap;

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
      if (!uvm_config_db #(fcm_core_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "fcm_core_agent_cfg not set for this component")
      vif = cfg.vif;
    endfunction

    // Write all 256 histogram bins, including zeros, so data from another case is cleared.
    // Task: load_histogram
    // Description: Writes all histogram bins into the DUT.
    task load_histogram(fcm_core_item item);
      for (int g = 0; g < GRAY_BINS; g++) begin
        @(negedge vif.clk);
        vif.hist_wr_addr <= g[GRAY_W-1:0];
        vif.hist_wr_data <= item.hist[g][COUNT_W-1:0];
        vif.hist_wr_en   <= 1'b1;
      end
      @(negedge vif.clk);
      vif.hist_wr_en <= 1'b0;
    endtask

    // The driver only requests LUT addresses and does not read DUT data.
    // The passive monitor collects the LUT results.
    // Task: request_lut_read
    // Description: Sends the addresses used for the label LUT reads.
    task request_lut_read();
      for (int g = 0; g < GRAY_BINS; g++) begin
        @(negedge vif.clk);
        vif.labels_lut_addr <= GRAY_W'(g);
      end
      @(negedge vif.clk);
      vif.labels_lut_addr <= '0;
    endtask

    // Task: run_phase
    // Description: Handles transactions during the UVM run phase.
    task run_phase(uvm_phase phase);
      fcm_core_item item;

      vif.start           <= 1'b0;
      vif.num_clusters    <= '0;
      vif.hist_wr_en      <= 1'b0;
      vif.hist_wr_addr    <= '0;
      vif.hist_wr_data    <= '0;
      vif.labels_lut_addr <= '0;
      for (int i = 0; i < MAX_C; i++) vif.init_centers_q[i] <= '0;

      wait (vif.rst_n === 1'b1);

      forever begin
        seq_item_port.get_next_item(item);

        load_histogram(item);

        @(negedge vif.clk);
        vif.num_clusters <= item.k;
        for (int i = 0; i < MAX_C; i++) vif.init_centers_q[i] <= item.init_centers[i];

        @(negedge vif.clk);
        vif.start <= 1'b1;
        @(negedge vif.clk);
        vif.start <= 1'b0;

        do @(posedge vif.clk); while (vif.done !== 1'b1);

        // Drive the LUT read-address sequence only. Never sample DUT data
        // In the stimulus/driver path. The passive monitor captures it.
        request_lut_read();
        stimulus_ap.write(item);

        seq_item_port.item_done();
      end
    endtask
  endclass
