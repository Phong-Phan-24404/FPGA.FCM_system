// File: fcm_member_trace_sequence.svh
// Description: Loads and sends member trace sequence verification scenarios.

  // Send per-bin membership inputs from the first and last saved iteration traces for each case.
  // Class: fcm_member_trace_sequence
  // Description: Reads saved vectors and sends the test cases.
  class fcm_member_trace_sequence extends uvm_sequence #(fcm_member_item);
    `uvm_object_utils(fcm_member_trace_sequence)

    string       vector_dir = FCM_DEFAULT_VECTOR_DIR;  // set by the UVM test
    int unsigned max_items  = 0;   // zero runs all cases
    int unsigned sent_count = 0;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name = "fcm_member_trace_sequence");
      super.new(name);
    endfunction

    // Send each record in the trace file and count the transactions.
    // Task: send_trace_file
    // Description: Reads a per-bin trace and sends its transactions.
    task send_trace_file(string path, int k, inout int unsigned sent);
      int fd;
      int code;
      string line;
      longint unsigned centers [$];
      longint unsigned members [$];
      longint unsigned gray;
      fcm_member_item item;

      fd = $fopen(path, "r");
      if (fd == 0) begin
        `uvm_warning("NOFILE", $sformatf("bo qua, khong mo duoc: %s", path))
        return;
      end

      forever begin
        code = $fgets(line, fd);
        if (code <= 0) break;
        if (fcm_json_seek(line, "membership_q") < 0) continue;

        gray = fcm_json_uint_field(line, "gray");
        fcm_json_uint_array(line, "centers_in_q", centers);
        fcm_json_uint_array(line, "membership_q", members);

        if (centers.size() != k || members.size() != k) begin
          `uvm_error("BADTRACE",
                     $sformatf("%s: K=%0d nhung centers=%0d members=%0d",
                               path, k, centers.size(), members.size()))
          break;
        end

        item = fcm_member_item::type_id::create("item");
        item.case_id = sent;
        start_item(item);
        item.k    = k[NUMC_W-1:0];
        item.gray = gray[GRAY_W-1:0];
        for (int i = 0; i < MAX_C; i++) begin
          item.centers[i]  = (i < k) ? center_t'(centers[i]) : '0;
          item.expected[i] = (i < k) ? member_t'(members[i]) : '0;
        end
        finish_item(item);

        sent++;
        if (max_items != 0 && sent >= max_items) break;
      end

      $fclose(fd);
    endtask

    // Task: body
    // Description: Loads and sends the selected verification cases.
    task body();
      int unsigned sent;
      int k, iterations;
      string dir;

      sent = 0;
      `uvm_info("SEQ", $sformatf("vector dir: %s", vector_dir), UVM_LOW)

      for (int kk = MIN_CLUSTERS; kk <= MAX_CLUSTERS; kk++) begin
        dir = fcm_case_dir(vector_dir, kk);
        if (!fcm_read_contract({dir, "/vector_contract.txt"}, k, iterations)) begin
          `uvm_warning("NOCASE", $sformatf("bo qua case: %s", dir))
          continue;
        end
        if (k != kk)
          `uvm_fatal("BADCASE",
                     $sformatf("%s: contract bao K=%0d, ten thu muc bao %0d",
                               dir, k, kk))

        // Avoid sending the same trace twice when a case finishes in one iteration.
        send_trace_file(fcm_trace_path(dir, 1), k, sent);
        if (iterations != 1)
          send_trace_file(fcm_trace_path(dir, iterations), k, sent);

        if (max_items != 0 && sent >= max_items) break;
      end

      if (sent == 0)
        `uvm_fatal("NOVECTORS",
                   $sformatf("khong doc duoc case nao tu %s", vector_dir))
      sent_count = sent;
      `uvm_info("SEQ", $sformatf("sent %0d cases", sent), UVM_LOW)
    endtask
  endclass
