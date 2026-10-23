// File: fcm_sva.sv
// Description: Contains protocol and output assertions for the FCM IP.

// Bind these assertions to the FCM modules to check their handshake and output rules. The UVM
// scoreboard checks arithmetic results.

// Divider handshake checks.
// Module: fcm_divider_sva
// Description: Checks the handshake and output signals.
module fcm_divider_sva import fcm_pkg::*; (
    input logic clk,
    input logic rst_n,
    input logic start,
    input logic busy,
    input logic done,
    input logic div_by_zero,
    input logic overflow
);

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // Do not accept a new start while the divider is busy.
  a_no_start_while_busy: assert property (
      start |-> !busy
  ) else $error("fcm_divider: start trong khi busy");

  // DONE must be a one-cycle pulse.
  a_done_is_pulse: assert property (
      done |=> !done
  ) else $error("fcm_divider: done kéo dài hơn một chu kỳ");

  // Every accepted start must eventually produce DONE.
  a_start_leads_to_done: assert property (
      start |-> ##[1:$] done
  ) else $error("fcm_divider: start không bao giờ hoàn tất");

  // Division must not produce divide-by-zero or overflow flags.
  a_no_div_by_zero: assert property (
      !div_by_zero
  ) else $error("fcm_divider: chia cho 0");

  a_no_overflow: assert property (
      !overflow
  ) else $error("fcm_divider: thương không vừa QUOT_W bit");

endmodule


// Membership checks.
// Module: fcm_member_sva
// Description: Checks the handshake and output signals.
module fcm_member_sva import fcm_pkg::*; #(
    parameter int MAX_C = MAX_CLUSTERS
)(
    input logic              clk,
    input logic              rst_n,
    input logic              start,
    input logic              busy,
    input logic              done,
    input logic              contract_error,
    input logic [NUMC_W-1:0] num_clusters,
    input member_t           membership_q [0:MAX_C-1]
);

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // Function: member_sum
  // Description: Adds all membership values.
  function automatic longint unsigned member_sum();
    longint unsigned total = 0;
    for (int i = 0; i < MAX_C; i++) total += membership_q[i];
    return total;
  endfunction

  // Function: member_in_range
  // Description: Checks that membership values are within their allowed range.
  function automatic bit member_in_range();
    for (int i = 0; i < MAX_C; i++)
      if (membership_q[i] > member_t'(ONE_Q)) return 1'b0;
    return 1'b1;
  endfunction

  // The membership values must add up to exactly 2^M.
  a_sum_is_one: assert property (
      done |-> (member_sum() == (longint'(1) << MEMBER_FRAC))
  ) else $error("fcm_member: sum(u)=%0d, phải là %0d",
                member_sum(), longint'(1) << MEMBER_FRAC);

  // Each membership must be between zero and 2^M.
  a_member_in_range: assert property (
      done |-> member_in_range()
  ) else $error("fcm_member: có membership vượt 2^M");

  // Every lane outside active K must be zero, not just the final lane.
  // Function: all_inactive_zero
  // Description: Checks that unused membership lanes are zero.
  function automatic bit all_inactive_zero();
    for (int i = 0; i < MAX_C; i++)
      if (i >= int'(num_clusters) && membership_q[i] !== '0)
        return 1'b0;
    return 1'b1;
  endfunction

  a_inactive_zero: assert property (
      done |-> all_inactive_zero()
  ) else $error("fcm_member: inactive lane has nonzero or unknown membership");

  a_no_contract_error: assert property (
      !contract_error
  ) else $error("fcm_member: contract_error");

  a_no_start_while_busy: assert property (
      start |-> !busy
  ) else $error("fcm_member: start trong khi busy");

  a_k_in_range: assert property (
      start |-> (num_clusters >= NUMC_W'(MIN_CLUSTERS)) &&
                (num_clusters <= NUMC_W'(MAX_CLUSTERS))
  ) else $error("fcm_member: K=%0d ngoài dải 2..7", num_clusters);

endmodule


// Module: fcm_accum_update_sva
// Description: Checks accumulator update timing and outputs.
module fcm_accum_update_sva import fcm_pkg::*; (
    input logic clk,
    input logic rst_n,
    input logic start,
    input logic busy,
    input logic overflow
);

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  a_no_overflow: assert property (
      !overflow
  ) else $error("fcm_accum_update: accumulator tràn");

  a_no_start_while_busy: assert property (
      start |-> !busy
  ) else $error("fcm_accum_update: start trong khi lane đang bận");

endmodule


// Module: fcm_core_engine_sva
// Description: Checks the engine status and center values.
module fcm_core_engine_sva import fcm_pkg::*; #(
    parameter int MAX_C = MAX_CLUSTERS
)(
    input logic              clk,
    input logic              rst_n,
    input logic              start,
    input logic              busy,
    input logic              done,
    input logic              converged,
    input logic [ITER_W-1:0] iter_converged,
    input logic              contract_error,
    input logic [NUMC_W-1:0] num_clusters,
    input center_t           centers_q [0:MAX_C-1]
);

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // Function: centers_in_domain
  // Description: Checks that the cluster centers are inside the grayscale range.
  function automatic bit centers_in_domain();
    for (int i = 0; i < MAX_C; i++)
      if (i < int'(num_clusters) && centers_q[i] > CENTER_MAX_Q) return 1'b0;
    return 1'b1;
  endfunction

  // Keep all cluster centers inside the grayscale range.
  a_centers_in_domain: assert property (
      done |-> centers_in_domain()
  ) else $error("fcm_core_engine: tâm ra ngoài [0, 255<<F]");

  // The iteration count must stay within MAX_ITER.
  a_iterations_bounded: assert property (
      done |-> (iter_converged <= ITER_W'(MAX_ITER))
  ) else $error("fcm_core_engine: iter=%0d vượt MAX_ITER", iter_converged);

  // A run that does not converge must use the full iteration limit.
  a_not_converged_means_max: assert property (
      (done && !converged) |-> (iter_converged == ITER_W'(MAX_ITER))
  ) else $error("fcm_core_engine: dừng sớm mà không hội tụ (iter=%0d)",
                iter_converged);

  a_no_contract_error: assert property (
      !contract_error
  ) else $error("fcm_core_engine: contract_error");

  a_no_start_while_busy: assert property (
      start |-> !busy
  ) else $error("fcm_core_engine: start trong khi busy");

endmodule


// Module: fcm_core_protocol_sva
// Description: Checks the core start and histogram protocol.
module fcm_core_protocol_sva (
    input logic clk,
    input logic rst_n,
    input logic start,
    input logic hist_wr_en,
    input logic busy,
    input logic done
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  a_no_write_during_compute: assert property (
      hist_wr_en |-> !busy && !start
  ) else $error("fcm_core: illegal histogram write outside IDLE");

  a_start_only_idle: assert property (
      start |-> !busy && !hist_wr_en
  ) else $error("fcm_core: illegal start/busy/hist write overlap");

  a_done_pulse: assert property (
      done |=> !done
  ) else $error("fcm_core: done must be single-cycle pulse");
endmodule

// Bind the assertion groups inside modules so they are elaborated. Each testbench instantiates only
// the bind groups used by its DUT.
// Module: fcm_sva_bind_member
// Description: Binds the checks to their DUT modules.
module fcm_sva_bind_member;

  bind fcm_divider fcm_divider_sva u_sva (
      .clk(clk), .rst_n(rst_n), .start(start), .busy(busy), .done(done),
      .div_by_zero(div_by_zero), .overflow(overflow)
  );

  bind fcm_member fcm_member_sva #(.MAX_C(MAX_C)) u_sva (
      .clk(clk), .rst_n(rst_n), .start(start), .busy(busy), .done(done),
      .contract_error(contract_error), .num_clusters(k_active),
      .membership_q(member)
  );

endmodule


// Module: fcm_sva_bind_core
// Description: Binds the checks to their DUT modules.
module fcm_sva_bind_core;

  bind fcm_core fcm_core_protocol_sva u_sva (
      .clk(clk), .rst_n(rst_n), .start(start),
      .hist_wr_en(hist_wr_en), .busy(busy), .done(done)
  );

  bind fcm_accum_update fcm_accum_update_sva u_sva (
      .clk(clk), .rst_n(rst_n), .start(start), .busy(busy), .overflow(overflow)
  );

  bind fcm_core_engine fcm_core_engine_sva #(.MAX_C(MAX_C)) u_sva (
      .clk(clk), .rst_n(rst_n), .start(start), .busy(busy), .done(done),
      .converged(converged), .iter_converged(iter_converged),
      .contract_error(contract_error), .num_clusters(k_active),
      .centers_q(center_reg)
  );

endmodule
