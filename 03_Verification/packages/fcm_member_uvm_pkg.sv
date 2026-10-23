// File: fcm_member_uvm_pkg.sv
// Description: Includes the UVM agents, sequences and tests.

// This package includes the membership UVM agent, sequences, tests, and scoreboard. Reference values
// come from vector files. Keep this include order for class dependencies.

// Package: fcm_member_uvm_pkg
// Description: Keeps the related verification helpers together.
package fcm_member_uvm_pkg;

  import uvm_pkg::*;
  import fcm_pkg::*;
  import fcm_vector_pkg::*;   // use shared vector helpers
  `include "uvm_macros.svh"

  localparam int MAX_C = MAX_CLUSTERS;

  `include "fcm_member_item.svh"            //  agents/member_agent
  `include "fcm_member_agent_cfg.svh"       //  agents/member_agent
  `include "fcm_member_env_cfg.svh"         //  env/ip
  `include "fcm_member_sequencer.svh"       //  agents/member_agent
  `include "fcm_member_driver.svh"          //  agents/member_agent
  `include "fcm_member_monitor.svh"         //  agents/member_agent
  `include "fcm_member_coverage.svh"        //  env/ip
  `include "fcm_member_scoreboard.svh"      //  env/ip
  `include "fcm_member_agent.svh"           //  agents/member_agent
  `include "fcm_member_env.svh"             //  env/ip
  `include "fcm_member_trace_sequence.svh"  //  sequences/ip
  `include "fcm_member_base_test.svh"       //  tests/ip

endpackage
