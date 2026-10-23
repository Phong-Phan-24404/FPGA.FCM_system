// File: fcm_soc_base_test.svh
// Description: Configures and runs the soc base test UVM test.

  // Set up the SoC stream environment and run image-based reference cases.
  // Class: fcm_soc_base_test
  // Description: Sets up the UVM environment and runs the saved cases.
  class fcm_soc_base_test extends uvm_test;
    `uvm_component_utils(fcm_soc_base_test)

    fcm_soc_env     env;
    fcm_soc_env_cfg cfg;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    // Function: configure
    // Description: Sets the vector directories and number of cases.
    virtual function void configure(fcm_soc_env_cfg c);
      void'(fcm_split_dirs(fcm_vector_spec(), c.vector_dirs));
      c.max_items = fcm_max_items();
    endfunction

    // Function: build_phase
    // Description: Builds the UVM components and reads their settings.
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      cfg = fcm_soc_env_cfg::type_id::create("cfg");

      if (!uvm_config_db #(virtual fcm_soc_if)::get(this, "", "vif", cfg.agent_cfg.vif))
        `uvm_fatal("NOVIF", "fcm_soc_if not set for uvm_test_top")

      configure(cfg);
      if (cfg.vector_dirs.size() == 0)
        `uvm_fatal("NOVECTORS", "+FCM_VECTORS khong co duong dan nao")

      uvm_config_db #(fcm_soc_env_cfg)::set(this, "env", "cfg", cfg);
      env = fcm_soc_env::type_id::create("env", this);
    endfunction

    // Task: run_phase
    // Description: Runs the selected SoC sequences and counts expected results.
    // Derived tests can add stimulus without repeating objection handling.
    virtual task run_sequences(ref int unsigned planned_total);
      fcm_soc_case_sequence seq;
      foreach (cfg.vector_dirs[i]) begin
        seq = fcm_soc_case_sequence::type_id::create($sformatf("seq%0d", i));
        seq.vector_dir = cfg.vector_dirs[i];
        seq.max_items  = cfg.max_items;
        seq.start(env.stream_agent.sequencer);
        planned_total += seq.sent_count;
      end
    endtask

    task run_phase(uvm_phase phase);
      int unsigned planned_total;

      phase.raise_objection(this);
      planned_total = 0;
      run_sequences(planned_total);
      // Tell the scoreboard how many results should be checked.
      env.scoreboard.planned = planned_total;
      // Allow the scoreboard to process the last transaction.
      #1us;
      phase.drop_objection(this);
    endtask
  endclass
