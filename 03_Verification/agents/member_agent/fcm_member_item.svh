// File: fcm_member_item.svh
// Description: Defines the transaction data for member verification.

  // Class: fcm_member_item
  // Description: Stores the input and expected values for one membership case.
  class fcm_member_item extends uvm_sequence_item;
    int unsigned case_id;
    logic [NUMC_W-1:0] k;
    bit [GRAY_W-1:0] gray;
    center_t centers [MAX_C];
    member_t expected [MAX_C];
    member_t actual   [MAX_C];
    logic    saw_contract_error;

    `uvm_object_utils(fcm_member_item)

    // Function: new
    // Description: Creates the component with default values.
    function new(string name = "fcm_member_item");
      super.new(name);
    endfunction

    // Function: convert2string
    // Description: Formats the item values for printing in the log.
    function string convert2string();
      string s;
      s = $sformatf("k=%0d gray=%0d", k, gray);
      for (int i = 0; i < MAX_C; i++) s = {s, $sformatf(" c%0d=%0d", i, centers[i])};
      for (int i = 0; i < MAX_C; i++) s = {s, $sformatf(" exp%0d=%0d", i, expected[i])};
      return s;
    endfunction
  endclass
