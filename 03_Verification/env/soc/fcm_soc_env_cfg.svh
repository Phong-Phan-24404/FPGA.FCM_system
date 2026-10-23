// File: fcm_soc_env_cfg.svh
// Description: Sets up the soc env cfg component.

  // The test prepares the environment config and supplies it to the agent.
  // Class: fcm_soc_env_cfg
  // Description: Stores the environment settings and vector paths.
  class fcm_soc_env_cfg extends uvm_object;
    `uvm_object_utils(fcm_soc_env_cfg)

    fcm_soc_agent_cfg agent_cfg;

    // Vector directories parsed from +FCM_VECTORS.
    string       vector_dirs [$];
    // Zero means run all cases.
    int unsigned max_items = 0;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name = "fcm_soc_env_cfg");
      super.new(name);
      agent_cfg = fcm_soc_agent_cfg::type_id::create("agent_cfg");
    endfunction
  endclass
