// File: fcm_core_uvm_pkg.sv
// Description: Includes the UVM agents, sequences and tests.

// This package includes the core UVM agent, sequences, tests, and scoreboard. Reference values come
// from vector files. Keep this include order for class dependencies.

// Package: fcm_core_uvm_pkg
// Description: Keeps the related verification helpers together.
package fcm_core_uvm_pkg;

  import uvm_pkg::*;
  import fcm_pkg::*;
  import fcm_vector_pkg::*;   // use shared vector helpers
  `include "uvm_macros.svh"

  localparam int MAX_C = MAX_CLUSTERS;

  `include "fcm_core_item.svh"           //  agents/core_agent
  `include "fcm_core_agent_cfg.svh"      //  agents/core_agent
  `include "fcm_core_env_cfg.svh"        //  env/ip
  `include "fcm_core_sequencer.svh"      //  agents/core_agent
  `include "fcm_core_driver.svh"         //  agents/core_agent
  `include "fcm_core_monitor.svh"        //  agents/core_agent
  `include "fcm_core_coverage.svh"       //  env/ip
  `include "fcm_core_perf.svh"           //  env/ip
  `include "fcm_core_scoreboard.svh"     //  env/ip
  `include "fcm_core_agent.svh"          //  agents/core_agent
  `include "fcm_core_env.svh"            //  env/ip
  `include "fcm_core_case_sequence.svh"  //  sequences/ip
  `include "fcm_core_base_test.svh"      //  tests/ip
  `include "fcm_core_smoke_test.svh"     //  tests/ip
  `include "fcm_core_passive_test.svh"   //  tests/ip

endpackage
