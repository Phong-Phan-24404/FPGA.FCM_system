// File: fcm_core_env.svh
// Description: Sets up the core env component.

  // Class: fcm_core_env
  // Description: Builds and connects the components of this UVM environment.
  class fcm_core_env extends uvm_env;
    `uvm_component_utils(fcm_core_env)

    fcm_core_env_cfg      cfg;
    fcm_core_agent        core_agent;
    fcm_core_agent        passive_agent;   // Null unless enabled in the config
    fcm_core_scoreboard   scoreboard;
    fcm_core_coverage     coverage;
    fcm_core_perf         perf;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    // Function: build_phase
    // Description: Builds the UVM components and reads their settings.
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(fcm_core_env_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "fcm_core_env_cfg not set for this env")

      // Give the agent a clear instance name for logs and configuration.
      uvm_config_db #(fcm_core_agent_cfg)::set(this, "core_agent", "cfg", cfg.agent_cfg);
      core_agent = fcm_core_agent::type_id::create("core_agent", this);

      // Build a passive agent on the same interface with its own config.
      if (cfg.passive_agent_cfg != null) begin
        uvm_config_db #(fcm_core_agent_cfg)::set(this, "passive_agent", "cfg", cfg.passive_agent_cfg);
        passive_agent = fcm_core_agent::type_id::create("passive_agent", this);
      end

      scoreboard = fcm_core_scoreboard::type_id::create("scoreboard", this);
      coverage   = fcm_core_coverage::type_id::create("coverage", this);
      perf       = fcm_core_perf::type_id::create("perf", this);
    endfunction

    // Function: connect_phase
    // Description: Connects the driver, sequencer and analysis ports.
    function void connect_phase(uvm_phase phase);
      // Only the active driver sends stimulus to the scoreboard.
      if (core_agent.get_is_active() == UVM_ACTIVE)
        core_agent.driver.stimulus_ap.connect(scoreboard.stimulus_fifo.analysis_export);
      core_agent.monitor.ap.connect(scoreboard.observed_fifo.analysis_export);
      scoreboard.checked_ap.connect(coverage.analysis_export);
      scoreboard.checked_ap.connect(perf.analysis_export);

      // Keep the passive monitor separate from the scoreboard to avoid duplicate results.
    endfunction
  endclass
