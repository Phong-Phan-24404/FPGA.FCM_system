// File: fcm_profile.sv
// Description: Measures the cycle counts of the membership unit and core engine.

// Measure how many cycles each part of the FCM core spends processing data. The profiler is bound to
// RTL for simulation only and reports results when +FCM_PROFILE is set.

`timescale 1ns/1ps

// Profiler for the membership datapath.
// Module: fcm_member_profile
// Description: Counts cycles spent in the selected processing stages.
module fcm_member_profile import fcm_pkg::*; #(
    parameter int MAX_C = MAX_CLUSTERS
)(
    input logic             clk,
    input logic             rst_n,
    input logic [4:0]       state_i,        // member FSM state as bits
    input logic [MAX_C-1:0] ratio_busy_i,
    input logic             recip_busy_i,
    input logic             split_busy_i
);

  localparam int N_STATES = 19;

  longint unsigned state_cycles [N_STATES];
  longint unsigned ratio_busy   [MAX_C];
  longint unsigned recip_busy;
  longint unsigned split_busy;
  longint unsigned member_active;
  longint unsigned member_runs;

  string state_name [N_STATES];

  initial begin
    foreach (state_cycles[i]) state_cycles[i] = 0;
    foreach (ratio_busy[i])   ratio_busy[i]   = 0;
    recip_busy    = 0;
    split_busy    = 0;
    member_active = 0;
    member_runs   = 0;
    state_name[0]  = "S_IDLE";
    state_name[1]  = "S_DIST";
    state_name[2]  = "S_SQUARE";
    state_name[3]  = "S_SQUARE_COMMIT";
    state_name[4]  = "S_SQUARE_REDUCE";
    state_name[5]  = "S_SPLIT_DIV";
    state_name[6]  = "S_SPLIT_WAIT";
    state_name[7]  = "S_SPLIT_ASSIGN";
    state_name[8]  = "S_RATIO_DIV";
    state_name[9]  = "S_RATIO_WAIT";
    state_name[10] = "S_RATIO_REDUCE";
    state_name[11] = "S_RATIO_REDUCE2";
    state_name[12] = "S_RECIP_DIV";
    state_name[13] = "S_RECIP_WAIT";
    state_name[14] = "S_SCALE";
    state_name[15] = "S_SCALE_SHIFT";
    state_name[16] = "S_SCALE_SUM";
    state_name[17] = "S_RESIDUAL";
    state_name[18] = "S_DONE";
  end

  // S_IDLE = 0 and S_DONE = 15 in fcm_member's state_t. Encoded positionally
  // Here because the enum is local to that module.
  localparam logic [4:0] ST_IDLE = 5'd0;
  localparam logic [4:0] ST_DONE = 5'd18;

  // Use always because these simulation counters are also reset in initial.
  // always_ff would report multiple drivers.
  always @(posedge clk) begin
    if (rst_n) begin
      state_cycles[int'(state_i)]++;
      if (state_i != ST_IDLE) member_active++;
      if (state_i == ST_DONE) member_runs++;
      if (recip_busy_i) recip_busy++;
      if (split_busy_i) split_busy++;
      for (int i = 0; i < MAX_C; i++)
        if (ratio_busy_i[i]) ratio_busy[i]++;
    end
  end

  final begin
    real pct;
    if ($test$plusargs("FCM_PROFILE")) begin
      $display("");
      $display("--- fcm_member state breakdown (active cycles = %0d, runs = %0d) ---",
               member_active, member_runs);
      $display("    %-18s %14s %8s", "state", "cycles", "%active");
      for (int i = 0; i < N_STATES; i++) begin
        if (state_cycles[i] == 0) continue;
        pct = (member_active != 0)
              ? 100.0 * real'(state_cycles[i]) / real'(member_active) : 0.0;
        $display("    %-18s %14d %7.2f", state_name[i], state_cycles[i], pct);
      end
      if (member_runs != 0)
        $display("    cycles per membership computation: %0d",
                 member_active / member_runs);

      $display("");
      $display("--- divider busy cycles (%% of fcm_member active cycles) ---");
      for (int i = 0; i < MAX_C; i++) begin
        pct = (member_active != 0)
              ? 100.0 * real'(ratio_busy[i]) / real'(member_active) : 0.0;
        $display("    ratio_divider[%0d]  %14d %7.2f", i, ratio_busy[i], pct);
      end
      pct = (member_active != 0)
            ? 100.0 * real'(recip_busy) / real'(member_active) : 0.0;
      $display("    %-18s %14d %7.2f", "recip_divider", recip_busy, pct);
      pct = (member_active != 0)
            ? 100.0 * real'(split_busy) / real'(member_active) : 0.0;
      $display("    %-18s %14d %7.2f", "split_divider", split_busy, pct);
      $display("");
    end
  end

endmodule


// Profiler for the core engine.
// Module: fcm_engine_profile
// Description: Counts cycles spent in the selected processing stages.
module fcm_engine_profile import fcm_pkg::*; #(
    parameter int MAX_C = MAX_CLUSTERS
)(
    input logic              clk,
    input logic              rst_n,
    input logic [4:0]        state_i,       // engine FSM state as bits
    input logic [COUNT_W-1:0] hist_rd_data_i,
    input logic              center_busy_i,
    input logic [MAX_C-1:0]  accum_busy_i
);

  localparam int N_STATES = 26;

  longint unsigned state_cycles [N_STATES];
  longint unsigned center_busy;
  longint unsigned accum_busy_any;
  longint unsigned engine_active;
  longint unsigned iterations;
  longint unsigned nonzero_bins;
  longint unsigned zero_bins;

  string state_name [N_STATES];

  initial begin
    foreach (state_cycles[i]) state_cycles[i] = 0;
    center_busy    = 0;
    accum_busy_any = 0;
    engine_active  = 0;
    iterations     = 0;
    nonzero_bins   = 0;
    zero_bins      = 0;
    state_name[0]  = "E_IDLE";
    state_name[1]  = "E_ITER_START";
    state_name[2]  = "E_BIN_ADDR";
    state_name[3]  = "E_BIN_FETCH";
    state_name[4]  = "E_MEMBER_START";
    state_name[5]  = "E_MEMBER_WAIT";
    state_name[6]  = "E_ACCUM_START";
    state_name[7]  = "E_BIN_NEXT";
    state_name[8]  = "E_DRAIN";
    state_name[9]  = "E_CENTER_START";
    state_name[10] = "E_CENTER_WAIT";
    state_name[11] = "E_CENTER_NEXT";
    state_name[12] = "E_RS_SETUP";
    state_name[13] = "E_RS_ADDR";
    state_name[14] = "E_RS_FETCH";
    state_name[15] = "E_RS_DIST";
    state_name[16] = "E_RS_SQUARE";
    state_name[17] = "E_RS_MIN";
    state_name[18] = "E_RS_SCORE_MUL";
    state_name[19] = "E_RS_SCORE";
    state_name[20] = "E_RS_NEXT_BIN";
    state_name[21] = "E_RS_COMMIT";
    state_name[22] = "E_DELTA_CALC";
    state_name[23] = "E_DELTA";
    state_name[24] = "E_CHECK";
    state_name[25] = "E_DONE";
  end

  // Positional encoding of fcm_core_engine's state_t.
  localparam logic [4:0] ST_IDLE       = 5'd0;
  localparam logic [4:0] ST_ITER_START = 5'd1;
  localparam logic [4:0] ST_BIN_FETCH  = 5'd3;

  // Use always because the simulation counters are also reset in initial.
  // always_ff would report multiple drivers.
  always @(posedge clk) begin
    if (rst_n) begin
      state_cycles[int'(state_i)]++;
      if (state_i != ST_IDLE)       engine_active++;
      if (state_i == ST_ITER_START) iterations++;
      // E_BIN_FETCH is where the zero/non-zero branch is decided.
      if (state_i == ST_BIN_FETCH) begin
        if (hist_rd_data_i == '0) zero_bins++;
        else                      nonzero_bins++;
      end
      if (center_busy_i)   center_busy++;
      if (|accum_busy_i)   accum_busy_any++;
    end
  end

  final begin
    real pct;
    if ($test$plusargs("FCM_PROFILE")) begin
      $display("");
      $display("================= FCM DATAPATH PROFILE =================");
      $display("engine active cycles      : %0d", engine_active);
      $display("iterations                : %0d", iterations);
      $display("non-zero bins processed   : %0d", nonzero_bins);
      $display("zero bins skipped         : %0d", zero_bins);
      if (iterations != 0)
        $display("cycles / iteration        : %0d", engine_active / iterations);
      // nonzero_bins counts bin VISITS across all iterations, so this is
      // Cycles per bin visit -- the figure the per-bin budget refers to.
      if (nonzero_bins != 0)
        $display("cycles / non-zero bin     : %0d", engine_active / nonzero_bins);
      $display("");
      $display("--- fcm_core_engine state breakdown ---");
      $display("    %-18s %14s %8s", "state", "cycles", "%active");
      for (int i = 0; i < N_STATES; i++) begin
        if (state_cycles[i] == 0) continue;
        pct = (engine_active != 0)
              ? 100.0 * real'(state_cycles[i]) / real'(engine_active) : 0.0;
        $display("    %-18s %14d %7.2f", state_name[i], state_cycles[i], pct);
      end
      $display("");
      $display("--- engine-level unit busy (%% of engine active cycles) ---");
      pct = (engine_active != 0)
            ? 100.0 * real'(center_busy) / real'(engine_active) : 0.0;
      $display("    %-18s %14d %7.2f", "center_divider", center_busy, pct);
      pct = (engine_active != 0)
            ? 100.0 * real'(accum_busy_any) / real'(engine_active) : 0.0;
      $display("    %-18s %14d %7.2f", "accum lanes (any)", accum_busy_any, pct);
      $display("========================================================");
    end
  end

endmodule


// Bind the profiler modules to their matching RTL modules.
// Module: fcm_profile_bind
// Description: Binds the checks to their DUT modules.
module fcm_profile_bind;
  bind fcm_member fcm_member_profile u_member_profile (
      .clk(clk),
      .rst_n(rst_n),
      .state_i(state),
      .ratio_busy_i({gen_ratio[6].ratio_divider.busy,
                     gen_ratio[5].ratio_divider.busy,
                     gen_ratio[4].ratio_divider.busy,
                     gen_ratio[3].ratio_divider.busy,
                     gen_ratio[2].ratio_divider.busy,
                     gen_ratio[1].ratio_divider.busy,
                     gen_ratio[0].ratio_divider.busy}),
      .recip_busy_i(recip_divider.busy),
      .split_busy_i(split_divider.busy)
  );

  bind fcm_core_engine fcm_engine_profile u_engine_profile (
      .clk(clk),
      .rst_n(rst_n),
      .state_i(state),
      .hist_rd_data_i(hist_rd_data),
      .center_busy_i(center_divider.busy),
      .accum_busy_i({gen_accum[6].u_accum.busy,
                     gen_accum[5].u_accum.busy,
                     gen_accum[4].u_accum.busy,
                     gen_accum[3].u_accum.busy,
                     gen_accum[2].u_accum.busy,
                     gen_accum[1].u_accum.busy,
                     gen_accum[0].u_accum.busy})
  );
endmodule
