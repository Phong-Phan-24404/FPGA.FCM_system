// File: fcm_soc_driver.svh
// Description: Drives DUT inputs for the soc UVM agent.

  // Class: fcm_soc_driver
  // Description: Sends test inputs to the DUT.
  class fcm_soc_driver extends uvm_driver #(fcm_soc_item);
    `uvm_component_utils(fcm_soc_driver)

    fcm_soc_agent_cfg       cfg;
    virtual fcm_soc_if vif;
    uvm_analysis_port #(fcm_soc_item) stimulus_ap;

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
      if (!uvm_config_db #(fcm_soc_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "fcm_soc_agent_cfg not set for this component")
      vif = cfg.vif;
    endfunction

    // Send the full image through valid/ready and mark EOF with the last pixel.
    // Task: stream_image
    // Description: Sends image pixels through the stream interface.
    task stream_image(fcm_soc_item item);
      int unsigned total;
      int unsigned eof_at;

      total = item.pixels.size();
      // The default '1 puts EOF on the last pixel.
      // Error sequences change eof_index to test the EOF position.
      eof_at = (item.eof_index == '1) ? total - 1 : item.eof_index;

      // Wait until the DUT can receive the pixel stream.
      do @(posedge vif.clk); while (vif.pixel_ready !== 1'b1);

      for (int unsigned i = 0; i < total; i++) begin
        @(negedge vif.clk);
        vif.pixel_data  <= item.pixels[i];
        vif.pixel_valid <= 1'b1;
        vif.pixel_eof   <= (i == eof_at);

        // Keep the pixel data stable until the DUT accepts it.
        @(posedge vif.clk);
        while (vif.pixel_ready !== 1'b1) @(posedge vif.clk);

        // Stop sending pixels after EOF; the frame is already complete.
        if (i == eof_at) break;
      end

      @(negedge vif.clk);
      vif.pixel_valid <= 1'b0;
      vif.pixel_eof   <= 1'b0;
    endtask

    // Task: run_phase
    // Description: Handles transactions during the UVM run phase.
    task run_phase(uvm_phase phase);
      fcm_soc_item item;

      vif.start        <= 1'b0;
      vif.num_clusters <= '0;
      vif.pixel_data   <= '0;
      vif.pixel_valid  <= 1'b0;
      vif.pixel_eof    <= 1'b0;

      wait (vif.rst_n === 1'b1);

      forever begin
        seq_item_port.get_next_item(item);

        @(negedge vif.clk);
        vif.num_clusters <= item.k;
        @(negedge vif.clk);
        vif.start <= 1'b1;
        @(negedge vif.clk);
        vif.start <= 1'b0;

        stream_image(item);

        stimulus_ap.write(item);

        do @(posedge vif.clk); while (vif.done !== 1'b1 && vif.error !== 1'b1);
        @(negedge vif.clk);

        seq_item_port.item_done();
      end
    endtask
  endclass
