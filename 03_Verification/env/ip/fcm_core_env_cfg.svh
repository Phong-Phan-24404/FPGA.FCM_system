// File: fcm_core_env_cfg.svh
// Description: Sets up the core env cfg component.

  // The test sets up this environment config and passes the agent settings to the environment.
  // Class: fcm_core_env_cfg
  // Description: Stores the environment settings and vector paths.
  class fcm_core_env_cfg extends uvm_object;
    `uvm_object_utils(fcm_core_env_cfg)

    fcm_core_agent_cfg agent_cfg;

    // An optional passive agent observes the same DUT interface without driving it.
    fcm_core_agent_cfg passive_agent_cfg;

    // Vector directories parsed from +FCM_VECTORS.
    string       vector_dirs [$];
    // Zero means run all cases.
    int unsigned max_items = 0;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name = "fcm_core_env_cfg");
      super.new(name);
      agent_cfg = fcm_core_agent_cfg::type_id::create("agent_cfg");
    endfunction
  endclass
