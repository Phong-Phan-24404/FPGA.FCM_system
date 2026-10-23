// File: fcm_core_smoke_test.svh
// Description: Configures and runs the core smoke test UVM test.

  // Run one case per vector folder using the base core UVM environment.
  // Class: fcm_core_smoke_test
  // Description: Runs a small set of core cases through the UVM environment.
  class fcm_core_smoke_test extends fcm_core_base_test;
    `uvm_component_utils(fcm_core_smoke_test)

    // Function: new
    // Description: Creates the component with default values.
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    // Function: configure
    // Description: Sets the vector directories and number of cases.
    virtual function void configure(fcm_core_env_cfg c);
      super.configure(c);
      // Use +FCM_MAX_ITEMS when a smaller set of cases is requested.
      if (c.max_items == 0) c.max_items = 1;
    endfunction
  endclass
