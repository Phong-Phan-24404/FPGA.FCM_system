// File: fcm_soc_uvm_pkg.sv
// Description: Includes the UVM agents, sequences and tests.

// This package includes the SoC UVM agent, sequences, tests, and scoreboard. Reference values come
// from vector files. Keep this include order for class dependencies.

// Package: fcm_soc_uvm_pkg
// Description: Keeps the related verification helpers together.
package fcm_soc_uvm_pkg;

  import uvm_pkg::*;
  import fcm_pkg::*;
  import fcm_vector_pkg::*;   // use shared vector helpers
  `include "uvm_macros.svh"

  localparam int MAX_C = MAX_CLUSTERS;

  `include "fcm_soc_item.svh"           //  agents/stream_agent
  `include "fcm_soc_agent_cfg.svh"      //  agents/stream_agent
  `include "fcm_soc_env_cfg.svh"        //  env/soc
  `include "fcm_soc_sequencer.svh"      //  agents/stream_agent
  `include "fcm_soc_driver.svh"         //  agents/stream_agent
  `include "fcm_soc_monitor.svh"        //  agents/stream_agent
  `include "fcm_soc_coverage.svh"       //  env/soc
  `include "fcm_soc_scoreboard.svh"     //  env/soc
  `include "fcm_soc_agent.svh"          //  agents/stream_agent
  `include "fcm_soc_env.svh"            //  env/soc
  `include "fcm_soc_case_sequence.svh"  //  sequences/soc
  `include "fcm_soc_eof_error_sequence.svh" //  sequences/soc
  `include "fcm_soc_base_test.svh"      //  tests/soc
  `include "fcm_soc_eof_error_test.svh"    //  tests/soc

endpackage
