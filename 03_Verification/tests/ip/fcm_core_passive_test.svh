// File: fcm_core_passive_test.svh
// Description: Configures and runs the core passive test UVM test.

  // Check that an extra passive agent only monitors the DUT and observes the same transactions as the
  // active agent.
  // Class: fcm_core_passive_test
  // Description: Checks the passive agent setup and observed transaction counts.
  class fcm_core_passive_test extends fcm_core_base_test;
    `uvm_component_utils(fcm_core_passive_test)

    // Function: new
    // Description: Creates the component with default values.
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    // Function: configure
    // Description: Sets the vector directories and number of cases.
    virtual function void configure(fcm_core_env_cfg c);
      super.configure(c);

      // One case per vector folder is enough to check the passive agent setup.
      if (c.max_items == 0) c.max_items = 1;

      c.passive_agent_cfg           = fcm_core_agent_cfg::type_id::create("passive_agent_cfg");
      c.passive_agent_cfg.vif       = c.agent_cfg.vif;   // use the active agent interface
      c.passive_agent_cfg.is_active = UVM_PASSIVE;
    endfunction

    // Function: check_phase
    // Description: Checks the collected results at the end of the test.
    function void check_phase(uvm_phase phase);
      bit ok = 1'b1;

      super.check_phase(phase);

      if (env.passive_agent == null) begin
        `uvm_error("PASSIVE", "passive_agent khong duoc dung")
        return;
      end

      // Check the active and passive agent components.
      if (env.passive_agent.get_is_active() != UVM_PASSIVE) begin
        ok = 1'b0;
        `uvm_error("PASSIVE", "passive_agent khong o che do UVM_PASSIVE")
      end
      if (env.passive_agent.driver != null) begin
        ok = 1'b0;
        `uvm_error("PASSIVE", "agent PASSIVE van dung driver — se lai cung interface voi agent ACTIVE")
      end
      if (env.passive_agent.sequencer != null) begin
        ok = 1'b0;
        `uvm_error("PASSIVE", "agent PASSIVE van dung sequencer")
      end
      if (env.passive_agent.monitor == null) begin
        ok = 1'b0;
        `uvm_error("PASSIVE", "agent PASSIVE khong co monitor")
        return;
      end

      // Also check that the active agent has its driver and sequencer.
      if (env.core_agent.get_is_active() != UVM_ACTIVE) begin
        ok = 1'b0;
        `uvm_error("PASSIVE", "core_agent dang khong o che do UVM_ACTIVE")
      end
      if (env.core_agent.driver == null) begin
        ok = 1'b0;
        `uvm_error("PASSIVE", "core_agent ACTIVE nhung khong co driver")
      end

      // Compare the transaction counts reported by the two monitors.
      if (env.passive_agent.monitor.observed_count == 0) begin
        ok = 1'b0;
        `uvm_error("PASSIVE", "monitor PASSIVE khong quan sat duoc giao dich nao")
      end
      else if (env.passive_agent.monitor.observed_count !=
               env.core_agent.monitor.observed_count) begin
        ok = 1'b0;
        `uvm_error("PASSIVE",
                   $sformatf("so giao dich lech: passive=%0d active=%0d",
                             env.passive_agent.monitor.observed_count,
                             env.core_agent.monitor.observed_count))
      end

      // Report a pass only when all passive-agent checks succeed.
      if (ok)
        `uvm_info("PASSIVE",
                  $sformatf("agent PASSIVE quan sat %0d/%0d giao dich, khong co driver/sequencer",
                            env.passive_agent.monitor.observed_count,
                            env.core_agent.monitor.observed_count),
                  UVM_NONE)
    endfunction
  endclass
