// File: fcm_core_base_test.svh
// Description: Configures and runs the core base test UVM test.

  // Set up the core UVM environment and run reference histogram cases.
  // Class: fcm_core_base_test
  // Description: Sets up the UVM environment and runs the saved cases.
  class fcm_core_base_test extends uvm_test;
    `uvm_component_utils(fcm_core_base_test)

    fcm_core_env     env;
    fcm_core_env_cfg cfg;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    // Function: configure
    // Description: Sets the vector directories and number of cases.
    virtual function void configure(fcm_core_env_cfg c);
      void'(fcm_split_dirs(fcm_vector_spec(), c.vector_dirs));
      c.max_items = fcm_max_items();
    endfunction

    // Function: build_phase
    // Description: Builds the UVM components and reads their settings.
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      cfg = fcm_core_env_cfg::type_id::create("cfg");

      if (!uvm_config_db #(virtual fcm_core_if)::get(this, "", "vif", cfg.agent_cfg.vif))
        `uvm_fatal("NOVIF", "fcm_core_if not set for uvm_test_top")

      configure(cfg);
      if (cfg.vector_dirs.size() == 0)
        `uvm_fatal("NOVECTORS", "+FCM_VECTORS khong co duong dan nao")

      uvm_config_db #(fcm_core_env_cfg)::set(this, "env", "cfg", cfg);
      env = fcm_core_env::type_id::create("env", this);
    endfunction

    // Task: run_phase
    // Description: Handles transactions during the UVM run phase.
    task run_phase(uvm_phase phase);
      fcm_core_case_sequence seq;
      int unsigned planned_total;

      phase.raise_objection(this);
      planned_total = 0;
      // Run vector folders in order and keep case IDs continuous.
      foreach (cfg.vector_dirs[i]) begin
        seq = fcm_core_case_sequence::type_id::create($sformatf("seq%0d", i));
        seq.vector_dir   = cfg.vector_dirs[i];
        seq.max_items    = cfg.max_items;
        seq.case_id_base = planned_total;
        seq.start(env.core_agent.sequencer);
        planned_total += seq.sent_count;
      end
      env.scoreboard.planned = planned_total;
      // Allow the scoreboard to process the last transaction.
      #1us;
      phase.drop_objection(this);
    endtask
  endclass
