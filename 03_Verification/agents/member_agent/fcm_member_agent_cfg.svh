// File: fcm_member_agent_cfg.svh
// Description: Stores settings for the member UVM agent.

  // Agent settings come from the test and are passed to the agent components.
  // Class: fcm_member_agent_cfg
  // Description: Stores the virtual interface and agent mode.
  class fcm_member_agent_cfg extends uvm_object;
    `uvm_object_utils(fcm_member_agent_cfg)

    virtual fcm_member_if vif;

    // Active agents drive and monitor the DUT; passive agents only monitor it.
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name = "fcm_member_agent_cfg");
      super.new(name);
    endfunction
  endclass
