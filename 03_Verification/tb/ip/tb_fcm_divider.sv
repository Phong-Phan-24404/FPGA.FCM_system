// File: tb_fcm_divider.sv
// Description: Checks quotient, remainder and divider status flags.

// Check divider quotient, remainder, and status flags across the widths used by the FCM IP and SoC
// pipeline.

`timescale 1ns/1ps

// Module: tb_fcm_divider
// Description: Checks quotient, remainder and divider status flags.
module tb_fcm_divider;

  localparam int CLK_HALF = 5;

  logic clk = 1'b0;
  logic rst_n = 1'b0;

  always #CLK_HALF clk = ~clk;

  int unsigned errors = 0;
  int unsigned checks = 0;

  // Test the ratio, normalization, center update, and SoC initial-center divider widths.
  localparam int RATIO_NUM_W = 56;
  localparam int RATIO_DEN_W = 40;
  localparam int RATIO_Q_W   = 17;

  localparam int NORM_NUM_W = 35;
  localparam int NORM_DEN_W = 19;
  localparam int NORM_Q_W   = 19;

  localparam int CTR_NUM_W = 54;
  localparam int CTR_DEN_W = 34;
  localparam int CTR_Q_W   = 20;

  // 04_SoC_Intergration/de10_lite_fcm_sdram/rtl/src/fcm_stream_pipeline.sv
  localparam int INIT_NUM_W = 12;
  localparam int INIT_DEN_W = 5;
  localparam int INIT_Q_W   = 12;

  logic                     r_start, r_done, r_dz, r_ovf, r_busy;
  logic [RATIO_NUM_W-1:0]   r_num;
  logic [RATIO_DEN_W-1:0]   r_den;
  logic [RATIO_Q_W-1:0]     r_quot;
  logic [RATIO_DEN_W-1:0]   r_rem;

  fcm_divider #(.NUM_W(RATIO_NUM_W), .DEN_W(RATIO_DEN_W), .QUOT_W(RATIO_Q_W))
  dut_ratio (
      .clk(clk), .rst_n(rst_n), .start(r_start),
      .numerator(r_num), .denominator(r_den),
      .quotient(r_quot), .remainder(r_rem),
      .busy(r_busy), .done(r_done), .div_by_zero(r_dz), .overflow(r_ovf)
  );

  logic                    n_start, n_done, n_dz, n_ovf, n_busy;
  logic [NORM_NUM_W-1:0]   n_num;
  logic [NORM_DEN_W-1:0]   n_den;
  logic [NORM_Q_W-1:0]     n_quot;
  logic [NORM_DEN_W-1:0]   n_rem;

  fcm_divider #(.NUM_W(NORM_NUM_W), .DEN_W(NORM_DEN_W), .QUOT_W(NORM_Q_W))
  dut_norm (
      .clk(clk), .rst_n(rst_n), .start(n_start),
      .numerator(n_num), .denominator(n_den),
      .quotient(n_quot), .remainder(n_rem),
      .busy(n_busy), .done(n_done), .div_by_zero(n_dz), .overflow(n_ovf)
  );

  logic                   c_start, c_done, c_dz, c_ovf, c_busy;
  logic [CTR_NUM_W-1:0]   c_num;
  logic [CTR_DEN_W-1:0]   c_den;
  logic [CTR_Q_W-1:0]     c_quot;
  logic [CTR_DEN_W-1:0]   c_rem;

  fcm_divider #(.NUM_W(CTR_NUM_W), .DEN_W(CTR_DEN_W), .QUOT_W(CTR_Q_W))
  dut_center (
      .clk(clk), .rst_n(rst_n), .start(c_start),
      .numerator(c_num), .denominator(c_den),
      .quotient(c_quot), .remainder(c_rem),
      .busy(c_busy), .done(c_done), .div_by_zero(c_dz), .overflow(c_ovf)
  );

  // Run both radix-2 and radix-4 normalization dividers on the same inputs and compare their outputs.
  logic                  n4_start, n4_done, n4_dz, n4_ovf, n4_busy;
  logic [NORM_NUM_W-1:0] n4_num;
  logic [NORM_DEN_W-1:0] n4_den;
  logic [NORM_Q_W-1:0]   n4_quot;
  logic [NORM_DEN_W-1:0] n4_rem;

  fcm_divider #(.NUM_W(NORM_NUM_W), .DEN_W(NORM_DEN_W), .QUOT_W(NORM_Q_W),
                .RADIX(4))
  dut_norm_radix4 (
      .clk(clk), .rst_n(rst_n), .start(n4_start),
      .numerator(n4_num), .denominator(n4_den),
      .quotient(n4_quot), .remainder(n4_rem),
      .busy(n4_busy), .done(n4_done), .div_by_zero(n4_dz), .overflow(n4_ovf)
  );

  logic                   i_start, i_done, i_dz, i_ovf, i_busy;
  logic [INIT_NUM_W-1:0]  i_num;
  logic [INIT_DEN_W-1:0]  i_den;
  logic [INIT_Q_W-1:0]    i_quot;
  logic [INIT_DEN_W-1:0]  i_rem;

  fcm_divider #(.NUM_W(INIT_NUM_W), .DEN_W(INIT_DEN_W), .QUOT_W(INIT_Q_W))
  dut_init_center (
      .clk(clk), .rst_n(rst_n), .start(i_start),
      .numerator(i_num), .denominator(i_den),
      .quotient(i_quot), .remainder(i_rem),
      .busy(i_busy), .done(i_done), .div_by_zero(i_dz), .overflow(i_ovf)
  );

  // Helper tasks for result checking.
  // Task: expect_eq
  // Description: Compares an observed number with its expected value.
  task automatic expect_eq(input string what, input longint unsigned got,
                           input longint unsigned exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("[FAIL] %s: got %0d, expected %0d", what, got, exp);
    end
  endtask

  // Task: run_ratio
  // Description: Checks the ratio divider for a given numerator and denominator.
  task automatic run_ratio(input logic [RATIO_NUM_W-1:0] a,
                           input logic [RATIO_DEN_W-1:0] b);
    logic [RATIO_NUM_W-1:0] exp_q;
    logic [RATIO_DEN_W-1:0] exp_r;
    @(negedge clk);
    r_num = a; r_den = b; r_start = 1'b1;
    @(negedge clk);
    r_start = 1'b0;
    wait (r_done);
    @(posedge clk);
    if (b == 0) begin
      checks++;
      if (!r_dz) begin
        errors++;
        $display("[FAIL] ratio %0d/0: div_by_zero không được bật", a);
      end
    end else begin
      exp_q = a / b;
      exp_r = a % b;
      expect_eq($sformatf("ratio quot %0d/%0d", a, b), r_quot, exp_q[RATIO_Q_W-1:0]);
      expect_eq($sformatf("ratio rem  %0d/%0d", a, b), r_rem, exp_r);
      checks++;
      if (r_ovf !== (|exp_q[RATIO_NUM_W-1:RATIO_Q_W])) begin
        errors++;
        $display("[FAIL] ratio overflow %0d/%0d: got %0b", a, b, r_ovf);
      end
    end
  endtask

  // Task: run_norm
  // Description: Checks the normalization divider implementations.
  task automatic run_norm(input logic [NORM_NUM_W-1:0] a,
                          input logic [NORM_DEN_W-1:0] b);
    logic [NORM_NUM_W-1:0] exp_q;
    @(negedge clk);
    n_num = a; n_den = b; n_start = 1'b1;
    n4_num = a; n4_den = b; n4_start = 1'b1;
    @(negedge clk);
    n_start = 1'b0;
    n4_start = 1'b0;
    // DONE is a one-cycle pulse, so wait for both divider outputs at the same time.
    fork
      wait (n_done);
      wait (n4_done);
    join
    @(posedge clk);
    if (b != 0) begin
      exp_q = a / b;
      expect_eq($sformatf("norm quot %0d/%0d", a, b), n_quot, exp_q[NORM_Q_W-1:0]);
      expect_eq($sformatf("norm rem  %0d/%0d", a, b), n_rem, a % b);
      // Radix-4 against the reference...
      expect_eq($sformatf("norm4 quot %0d/%0d", a, b), n4_quot, exp_q[NORM_Q_W-1:0]);
      expect_eq($sformatf("norm4 rem  %0d/%0d", a, b), n4_rem, a % b);
      // ...and against radix-2, so a shared misunderstanding of the contract
      // Cannot hide by making both wrong in the same way.
      expect_eq($sformatf("norm4 vs norm2 quot %0d/%0d", a, b), n4_quot, n_quot);
      expect_eq($sformatf("norm4 vs norm2 rem  %0d/%0d", a, b), n4_rem, n_rem);
      checks++;
      if (n4_ovf !== n_ovf) begin
        errors++;
        $display("[FAIL] norm4 overflow %0d/%0d: radix4=%0b radix2=%0b",
                 a, b, n4_ovf, n_ovf);
      end
    end else begin
      checks++;
      if (!n4_dz) begin
        errors++;
        $display("[FAIL] norm4 %0d/0: div_by_zero khong duoc bat", a);
      end
    end
  endtask

  // Task: run_center
  // Description: Checks the center-update divider.
  task automatic run_center(input logic [CTR_NUM_W-1:0] a,
                            input logic [CTR_DEN_W-1:0] b);
    logic [CTR_NUM_W-1:0] exp_q;
    @(negedge clk);
    c_num = a; c_den = b; c_start = 1'b1;
    @(negedge clk);
    c_start = 1'b0;
    wait (c_done);
    @(posedge clk);
    if (b != 0) begin
      exp_q = a / b;
      expect_eq($sformatf("center quot %0d/%0d", a, b), c_quot, exp_q[CTR_Q_W-1:0]);
      expect_eq($sformatf("center rem  %0d/%0d", a, b), c_rem, a % b);
    end
  endtask

  // Task: run_init
  // Description: Checks the initial-center divider.
  task automatic run_init(input logic [INIT_NUM_W-1:0] a,
                          input logic [INIT_DEN_W-1:0] b);
    logic [INIT_NUM_W-1:0] exp_q;
    @(negedge clk);
    i_num = a; i_den = b; i_start = 1'b1;
    @(negedge clk);
    i_start = 1'b0;
    wait (i_done);
    @(posedge clk);
    if (b == 0) begin
      checks++;
      if (!i_dz) begin
        errors++;
        $display("[FAIL] init %0d/0: div_by_zero khong duoc bat", a);
      end
    end else begin
      exp_q = a / b;
      expect_eq($sformatf("init quot %0d/%0d", a, b), i_quot, exp_q[INIT_Q_W-1:0]);
      expect_eq($sformatf("init rem  %0d/%0d", a, b), i_rem, a % b);
    end
  endtask

  // Divider test scenarios.
  initial begin
    int unsigned seed;
    logic [RATIO_DEN_W-1:0] min_sq, sq;
    logic [NORM_DEN_W-1:0]  total;

    r_start = 1'b0; n_start = 1'b0; c_start = 1'b0; i_start = 1'b0;
    n4_start = 1'b0; n4_num = '0; n4_den = '0;
    r_num = '0; r_den = '0; n_num = '0; n_den = '0; c_num = '0; c_den = '0;
    i_num = '0; i_den = '0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    // Check zero, one, and maximum input values.
    run_ratio(56'd0, 40'd1);
    run_ratio(56'd1, 40'd1);
    run_ratio(56'd7, 40'd2);
    run_ratio({40'h7F_FFFF_FFFF, 16'd0}, 40'h7F_FFFF_FFFF);  //  exactly 2^16
    run_ratio(56'd12345678901, 40'd97);
    run_ratio(56'd5, 40'd0);        //  divide by zero

    run_norm(35'd0, 19'd1);
    run_norm(35'h4_0000_0000 >> 2, 19'd1);
    run_norm(35'd1 << 34, 19'd7);

    run_center(54'd0, 34'd1);
    run_center(54'd1044480, 34'd1024);
    run_center(54'h3F_FFFF_FFFF, 34'd202500);

    // Check quotient-width and numerator/denominator boundary values, including overflow.
    run_ratio(56'h80_0000_0000_0000, 40'd1);               //  smallest denominator
    run_ratio(56'hFF_FFFF_FFFF_FFFF, 40'd1);               //  maximum overflow case
    run_ratio(56'd1, 40'hFF_FFFF_FFFF);                    //  numerator smaller than denominator
    run_ratio(56'd0, 40'hFF_FFFF_FFFF);                    //  zero numerator
    run_ratio(56'hFF_FFFF_FFFF_FFFF, 40'h80_0000_0000);    //  denominator with the highest MSB
    run_ratio(56'hFF_FFFF_FFFF_FFFF, 40'hFF_FFFF_FFFF);    //  largest denominator
    run_ratio({40'd1, 16'd0}, 40'd1);                      //  quotient is exactly 2^16
    run_ratio({40'd2, 16'd0}, 40'd1);                      //  quotient is 2^17 and overflows RATIO_W
    run_ratio(56'd1 << 17, 40'd2);                         //  quotient is exactly 2^16
    for (int b = 0; b < 40; b++)                           //  check each denominator MSB
      run_ratio(56'hAAAA_AAAA_AAAA_AA, 40'd1 << b);
    for (int b = 0; b < 56; b++)                           //  check each numerator MSB
      run_ratio(56'd1 << b, 40'd3);

    run_norm(35'd0, 19'd1);
    run_norm(35'd12345, 19'd0);                            //  divide by zero
    run_norm(35'h7_FFFF_FFFF, 19'd1);                      //  smallest denominator
    run_norm(35'd1, 19'h7_FFFF);                           //  numerator smaller than denominator
    run_norm(35'h7_FFFF_FFFF, 19'h7_FFFF);                 //  largest denominator
    run_norm(35'h7_FFFF_FFFF, 19'h4_0000);                 //  denominator with the highest MSB
    for (int b = 0; b < 19; b++)
      run_norm(35'h5_5555_5555, 19'd1 << b);

    run_center(54'd0, 34'd1);
    run_center(54'h3F_FFFF_FFFF_FFFF, 34'd1);              //  smallest denominator
    run_center(54'd1, 34'h3_FFFF_FFFF);                    //  numerator smaller than denominator
    run_center(54'h3F_FFFF_FFFF_FFFF, 34'h3_FFFF_FFFF);    //  largest denominator
    run_center(54'h3F_FFFF_FFFF_FFFF, 34'h2_0000_0000);    //  denominator with the highest MSB
    for (int b = 0; b < 34; b++)
      run_center(54'h2A_AAAA_AAAA_AAAA, 34'd1 << b);

    // Use random values from the expected FCM input ranges. Ratio values should not overflow.
    seed = 20261020;
    for (int i = 0; i < 200; i++) begin
      sq     = {$urandom(seed), $urandom(seed)} & ((40'd1 << 40) - 1);
      if (sq == 0) sq = 40'd1;
      min_sq = sq / (($urandom(seed) % 1000) + 1);
      if (min_sq == 0) min_sq = 40'd1;
      run_ratio({min_sq, 16'd0}, sq);
    end

    // Normalization totals are between 2^16 and 7 * 2^16.
    for (int i = 0; i < 100; i++) begin
      total = 19'(65536 + ($urandom(seed) % (6 * 65536)));
      run_norm(35'd1 << (16 + 18), total);
    end

    // Center updates stay within the supported fixed-point range.
    for (int i = 0; i < 100; i++) begin
      logic [CTR_DEN_W-1:0] den;
      logic [CTR_NUM_W-1:0] num;
      den = {$urandom(seed), $urandom(seed)} & ((34'd1 << 34) - 1);
      if (den == 0) den = 34'd1;
      num = (CTR_NUM_W'(den) * CTR_NUM_W'($urandom(seed) % 256)) << 12;
      run_center(num, den);
    end

    // Check the SoC initial-center divider using its supported K values and width boundaries.
    for (int kk = 2; kk <= 7; kk++)
      for (int ii = 0; ii < kk; ii++)
        run_init(INIT_NUM_W'((ii + 1) * 255), INIT_DEN_W'(kk + 1));

    run_init(12'd0,    5'd3);                 //  zero numerator
    run_init(12'd1,    5'd31);                //  numerator smaller than denominator
    run_init(12'd4095, 5'd1);                 //  smallest denominator, largest quotient
    run_init(12'd4095, 5'd31);                //  largest denominator
    run_init(12'd4095, 5'd16);                //  denominator with the highest MSB
    run_init(12'd255,  5'd0);                 //  divide by zero
    for (int b = 0; b < 5; b++)               //  check each denominator MSB
      run_init(12'hAAA, INIT_DEN_W'(1 << b));
    for (int b = 0; b < 12; b++)              //  check each numerator MSB
      run_init(INIT_NUM_W'(1 << b), 5'd3);

    $display("----------------------------------------------------------");
    if (errors == 0)
      $display("PASS: fcm_divider %0d checks", checks);
    else
      $display("FAIL: fcm_divider %0d/%0d checks failed", errors, checks);
    $display("----------------------------------------------------------");
    $finish;
  end

  // Stop the simulation if the divider does not finish.
  initial begin
    #20ms;
    $display("FAIL: tb_fcm_divider timeout");
    $fatal(1, "timeout");
  end

endmodule
