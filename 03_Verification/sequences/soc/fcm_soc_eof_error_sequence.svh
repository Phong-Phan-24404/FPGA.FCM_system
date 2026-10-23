  // Class: fcm_soc_eof_error_sequence
  // Description: Sends early-EOF and missing-EOF frames to check error_o.
  // Both cases test the error branches in the P_STREAM state.
  class fcm_soc_eof_error_sequence extends uvm_sequence #(fcm_soc_item);
    `uvm_object_utils(fcm_soc_eof_error_sequence)

    string       vector_dir = FCM_DEFAULT_VECTOR_DIR;  // test sets this path
    int unsigned sent_count = 0;

    function new(string name = "fcm_soc_eof_error_sequence");
      super.new(name);
    endfunction

    // Use a saved image with the expected number of pixels.
    // Only the EOF protocol matters for these tests, not the pixel values.
    function automatic bit load_image(int k, ref byte unsigned pixels []);
      longint unsigned words [$];
      string dir;
      int n;
      dir = fcm_case_dir(vector_dir, k);
      n = fcm_read_mem({dir, "/pixels_u8.mem"}, words);
      if (n <= 0) begin
        `uvm_warning("NOCASE", $sformatf("khong doc duoc %s/pixels_u8.mem", dir))
        return 1'b0;
      end
      pixels = new [n];
      foreach (pixels[i]) pixels[i] = byte'(words[i]);
      return 1'b1;
    endfunction

    task body();
      byte unsigned pixels [];
      fcm_soc_item  item;
      int           k = MIN_CLUSTERS;

      `uvm_info("SEQ", $sformatf("vector dir: %s", vector_dir), UVM_LOW)
      if (!load_image(k, pixels))
        `uvm_fatal("NOVECTORS", $sformatf("khong doc duoc case nao tu %s", vector_dir))

      // Put EOF in the middle of the frame.
      // The DUT should raise error_o after eof_index + 1 accepted beats.
      item = fcm_soc_item::type_id::create("eof_som");
      item.case_name    = "eof_som";
      item.pixels       = pixels;
      item.eof_index    = pixels.size() / 2;
      item.expect_error = 1'b1;
      start_item(item);
      item.k = k[NUMC_W-1:0];
      finish_item(item);
      sent_count++;

      // Set eof_index to pixels.size() so no pixel carries EOF.
      // The DUT should report an error after IMG_PIXELS beats.
      item = fcm_soc_item::type_id::create("thieu_eof");
      item.case_name    = "thieu_eof";
      item.pixels       = pixels;
      item.eof_index    = pixels.size();
      item.expect_error = 1'b1;
      start_item(item);
      item.k = k[NUMC_W-1:0];
      finish_item(item);
      sent_count++;

      `uvm_info("SEQ", $sformatf("sent %0d cases", sent_count), UVM_LOW)
    endtask
  endclass
