// File: fcm_soc_case_sequence.svh
// Description: Loads and sends soc case sequence verification scenarios.

  // Run image-based SoC verification cases using saved pixel and reference data.
  // Class: fcm_soc_case_sequence
  // Description: Reads saved vectors and sends the test cases.
  class fcm_soc_case_sequence extends uvm_sequence #(fcm_soc_item);
    `uvm_object_utils(fcm_soc_case_sequence)

    string       vector_dir = FCM_DEFAULT_VECTOR_DIR;  // set by the UVM test
    int unsigned max_items  = 0;
    // Count sent transactions so the scoreboard can detect missing results.
    int unsigned sent_count = 0;

    // Function: new
    // Description: Creates the component with default values.
    function new(string name = "fcm_soc_case_sequence");
      super.new(name);
    endfunction

    // Task: body
    // Description: Loads and sends the selected verification cases.
    task body();
      int unsigned sent;
      int k, iterations;
      string dir;
      longint unsigned pixels [$];
      longint unsigned golden [$];
      fcm_soc_item item;
      int n;

      sent = 0;
      `uvm_info("SEQ", $sformatf("vector dir: %s", vector_dir), UVM_LOW)

      for (int kk = MIN_CLUSTERS; kk <= MAX_CLUSTERS; kk++) begin
        dir = fcm_case_dir(vector_dir, kk);
        if (!fcm_read_contract({dir, "/vector_contract.txt"}, k, iterations)) begin
          `uvm_warning("NOCASE", $sformatf("bo qua case: %s", dir))
          continue;
        end

        n = fcm_read_mem({dir, "/pixels_u8.mem"}, pixels);
        if (n != IMG_PIXELS) begin
          `uvm_error("BADMEM",
                     $sformatf("%s/pixels_u8.mem: co %0d word, can %0d",
                               dir, n, IMG_PIXELS))
          continue;
        end
        n = fcm_read_mem({dir, "/golden_centers.mem"}, golden);
        if (n != k) begin
          `uvm_error("BADMEM",
                     $sformatf("%s/golden_centers.mem: co %0d word, can %0d",
                               dir, n, k))
          continue;
        end

        item = fcm_soc_item::type_id::create("item");
        item.case_name = {"demo_k", fcm_pad(kk, 2)};
        item.pixels = new[IMG_PIXELS];
        for (int unsigned i = 0; i < IMG_PIXELS; i++)
          item.pixels[i] = pixels[i][7:0];

        // Convert Q-format cluster centers to 8-bit gray using the specified rounding rule.
        for (int i = 0; i < MAX_C; i++) begin
          if (i < k) begin
            longint unsigned rounded;
            rounded = golden[i] + (longint'(1) << (CENTER_FRAC - 1));
            item.expected_centroids[i] = (rounded >> CENTER_FRAC) > 255
                                         ? 8'hFF
                                         : 8'((rounded >> CENTER_FRAC));
          end else begin
            item.expected_centroids[i] = '0;
          end
        end

        start_item(item);
        item.k = k[NUMC_W-1:0];
        finish_item(item);

        sent++;
        if (max_items != 0 && sent >= max_items) break;
      end

      if (sent == 0)
        `uvm_fatal("NOVECTORS",
                   $sformatf("khong doc duoc case nao tu %s", vector_dir))
      sent_count = sent;
      `uvm_info("SEQ", $sformatf("sent %0d cases", sent), UVM_LOW)
    endtask
  endclass
