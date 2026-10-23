// File: fcm_member_env.svh
// Description: Sets up the member env component.

  // Class: fcm_member_env
  // Description: Builds and connects the components of this UVM environment.
  class fcm_member_env extends uvm_env;
    `uvm_component_utils(fcm_member_env)

    fcm_member_env_cfg      cfg;
    fcm_member_agent        member_agent;
    fcm_member_scoreboard   scoreboard;
    fcm_member_coverage     coverage;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    // Function: build_phase
    // Description: Builds the UVM components and reads their settings.
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(fcm_member_env_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "fcm_member_env_cfg not set for this env")

      // Use a clear agent instance name in logs and configuration.
      uvm_config_db #(fcm_member_agent_cfg)::set(this, "member_agent", "cfg", cfg.agent_cfg);

      member_agent     = fcm_member_agent::type_id::create("member_agent", this);
      scoreboard = fcm_member_scoreboard::type_id::create("scoreboard", this);
      coverage   = fcm_member_coverage::type_id::create("coverage", this);

    endfunction

    // Function: connect_phase
    // Description: Connects the driver, sequencer and analysis ports.
    function void connect_phase(uvm_phase phase);
      // Only active agents publish input stimulus.
      if (member_agent.get_is_active() == UVM_ACTIVE)
        member_agent.driver.stimulus_ap.connect(scoreboard.stimulus_fifo.analysis_export);
      member_agent.monitor.ap.connect(scoreboard.observed_fifo.analysis_export);
      scoreboard.checked_ap.connect(coverage.analysis_export);
    endfunction
  endclass
