// File: fcm_soc_item.svh
// Description: Defines the transaction data for soc verification.

  // Class: fcm_soc_item
  // Description: Stores pixels, expected results and stream status for one case.
  class fcm_soc_item extends uvm_sequence_item;
    string           case_name;
    bit [NUMC_W-1:0] k;

    // Load the full 450x450 image from pixels_u8.mem.
    byte unsigned    pixels [];

    // Convert the expected Q-format centers into 8-bit grayscale values.
    bit [7:0]        expected_centroids [MAX_C];
    bit [7:0]        actual_centroids   [MAX_C];

    // eof_index gives the pixel that carries EOF; the last pixel is the default.
    // An earlier index sends EOF too soon, while pixels.size() sends no EOF.
    int unsigned     eof_index;

    // Set expect_error when the DUT should raise error_o.
    // An invalid frame without an error is also a test failure.
    bit              expect_error;

    // Count the pixel beats the driver plans to send, including early EOF.
    function int unsigned planned_beats();
      return (eof_index < pixels.size()) ? eof_index + 1 : pixels.size();
    endfunction

    // Count accepted beats using pixel_valid and pixel_ready.
    // Compare this with the planned count to catch lost or extra pixels.
    // A few missing pixels may not change the rounded 8-bit centers.
    int unsigned     observed_beats;

    bit [NUMC_W-1:0] actual_num_clusters;
    bit              saw_error;
    bit              saw_contract_error;

    `uvm_object_utils(fcm_soc_item)

    // Function: new
    // Description: Creates the component with default values.
    function new(string name = "fcm_soc_item");
      super.new(name);
      eof_index    = '1;      // sequence may change this; '1 selects the last pixel
      expect_error = 1'b0;
    endfunction

    // Function: convert2string
    // Description: Formats the item values for printing in the log.
    function string convert2string();
      return $sformatf("%s k=%0d pixels=%0d", case_name, k, pixels.size());
    endfunction
  endclass
