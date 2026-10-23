  // Class: fcm_soc_eof_error_test
  // Description: Runs only the two incorrect-EOF cases for debugging.
  // The regression test also includes the normal image cases.
  class fcm_soc_eof_error_test extends fcm_soc_base_test;
    `uvm_component_utils(fcm_soc_eof_error_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual task run_sequences(ref int unsigned planned_total);
      fcm_soc_eof_error_sequence seq;
      foreach (cfg.vector_dirs[i]) begin
        seq = fcm_soc_eof_error_sequence::type_id::create($sformatf("eofseq%0d", i));
        seq.vector_dir = cfg.vector_dirs[i];
        seq.start(env.stream_agent.sequencer);
        planned_total += seq.sent_count;
      end
    endtask
  endclass


  // Class: fcm_soc_full_test
  // Description: Runs normal image cases and the two EOF error cases.
  // Keep both groups in one UVM test for the regression.
  class fcm_soc_full_test extends fcm_soc_base_test;
    `uvm_component_utils(fcm_soc_full_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual task run_sequences(ref int unsigned planned_total);
      fcm_soc_eof_error_sequence err_seq;

      // Run normal image cases first to check the main data path.
      // Then send the invalid EOF cases.
      super.run_sequences(planned_total);

      foreach (cfg.vector_dirs[i]) begin
        err_seq = fcm_soc_eof_error_sequence::type_id::create($sformatf("eofseq%0d", i));
        err_seq.vector_dir = cfg.vector_dirs[i];
        err_seq.start(env.stream_agent.sequencer);
        planned_total += err_seq.sent_count;
      end
    endtask
  endclass
