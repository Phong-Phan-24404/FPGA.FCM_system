// File: fcm_soc_env.svh
// Description: Sets up the soc env component.

  // Class: fcm_soc_env
  // Description: Builds and connects the components of this UVM environment.
  class fcm_soc_env extends uvm_env;
    `uvm_component_utils(fcm_soc_env)

    fcm_soc_env_cfg      cfg;
    fcm_soc_agent        stream_agent;
    fcm_soc_scoreboard   scoreboard;
    fcm_soc_coverage     coverage;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    // Function: build_phase
    // Description: Builds the UVM components and reads their settings.
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(fcm_soc_env_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "fcm_soc_env_cfg not set for this env")

      // Use a clear agent instance name in logs and configuration.
      uvm_config_db #(fcm_soc_agent_cfg)::set(this, "stream_agent", "cfg", cfg.agent_cfg);

      stream_agent     = fcm_soc_agent::type_id::create("stream_agent", this);
      scoreboard = fcm_soc_scoreboard::type_id::create("scoreboard", this);
      coverage   = fcm_soc_coverage::type_id::create("coverage", this);

    endfunction

    // Function: connect_phase
    // Description: Connects the driver, sequencer and analysis ports.
    function void connect_phase(uvm_phase phase);
      // Only active agents publish input stimulus.
      if (stream_agent.get_is_active() == UVM_ACTIVE) begin
        stream_agent.driver.stimulus_ap.connect(scoreboard.stimulus_fifo.analysis_export);
        stream_agent.driver.stimulus_ap.connect(coverage.analysis_export);
      end
      stream_agent.monitor.ap.connect(scoreboard.observed_fifo.analysis_export);
    endfunction
  endclass
