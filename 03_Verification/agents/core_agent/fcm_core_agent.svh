// File: fcm_core_agent.svh
// Description: Builds the UVM agent for the core engine.

  // Class: fcm_core_agent
  // Description: Builds and connects the UVM driver, sequencer, and monitor.
  class fcm_core_agent extends uvm_agent;
    `uvm_component_utils(fcm_core_agent)

    fcm_core_agent_cfg   cfg;
    fcm_core_sequencer   sequencer;
    fcm_core_driver      driver;
    fcm_core_monitor     monitor;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    // Use the agent config to keep the active/passive mode consistent.
    // Function: get_is_active
    // Description: Reads the agent mode from its config.
    virtual function uvm_active_passive_enum get_is_active();
      return (cfg != null) ? cfg.is_active : UVM_ACTIVE;
    endfunction

    // Function: build_phase
    // Description: Builds the UVM components and reads their settings.
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(fcm_core_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "fcm_core_agent_cfg not set for this agent")

      // Pass each child its own config using the exact instance path.
      uvm_config_db #(fcm_core_agent_cfg)::set(this, "driver",  "cfg", cfg);
      uvm_config_db #(fcm_core_agent_cfg)::set(this, "monitor", "cfg", cfg);

      // Always build the monitor; build the driver and sequencer for active agents.
      monitor = fcm_core_monitor::type_id::create("monitor", this);
      if (get_is_active() == UVM_ACTIVE) begin
        sequencer = fcm_core_sequencer::type_id::create("sequencer", this);
        driver    = fcm_core_driver::type_id::create("driver", this);
      end
    endfunction

    // Function: connect_phase
    // Description: Connects the driver, sequencer and analysis ports.
    function void connect_phase(uvm_phase phase);
      if (get_is_active() == UVM_ACTIVE)
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass
