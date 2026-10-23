// File: fcm_pkg.sv
// Description: Defines shared FCM parameters, number widths, and data types.
// Author: Phan Chau Phong
// Package: fcm_pkg
// Description: Holds the fixed-point constants used across the FCM modules.
// The widths follow the precision profile in the bit-exact algorithm.
// Membership uses unsigned ratio normalization, and accumulation multiplies
// by the histogram count before applying the fixed-point shift.

package fcm_pkg;

  // Image size and supported cluster settings.
  parameter int IMG_W      = 450;
  parameter int IMG_H      = 450;
  parameter int IMG_PIXELS = IMG_W * IMG_H;          // 202500

  parameter int GRAY_W     = 8;
  parameter int GRAY_BINS  = 1 << GRAY_W;            // 256

  parameter int MAX_CLUSTERS = 7;
  parameter int MIN_CLUSTERS = 2;
  parameter int NUMC_W       = $clog2(MAX_CLUSTERS + 1);   // 3
  parameter int LABEL_W      = $clog2(MAX_CLUSTERS);       // 3
  parameter int MAX_ITER     = 200;
  parameter int ITER_W       = $clog2(MAX_ITER + 1);       // 8

  // Fixed-point precision settings.
  parameter int CENTER_FRAC = 12;   // F
  parameter int MEMBER_FRAC = 16;   // M
  parameter int NORM_GUARD  = 18;   // G

  // Bit widths for the fixed-point calculations.
  parameter int COUNT_W   = 18;                          // histogram_count
  parameter int CENTER_W  = GRAY_W + CENTER_FRAC;        // 20  center/gray_q/distance/delta
  parameter int DSQ_W     = 2 * CENTER_W;                // 40  distance_square
  parameter int RATIO_W   = MEMBER_FRAC + 1;             // 17
  parameter int RATIO_SUM_W = 19;                        // needs 19 bits for 7 << M
  parameter int MEMBER_W  = MEMBER_FRAC + 1;             // 17
  parameter int RECIP_W   = NORM_GUARD + 1;              // 19
  parameter int ACC_DEN_W = 34;                          // (202500 << M)
  parameter int ACC_NUM_W = 42;                          // (202500 << M) * 255

  // Numerator widths for the divider operations.
  parameter int RATIO_NUM_W  = DSQ_W + MEMBER_FRAC;              // 56
  parameter int NORM_NUM_W   = MEMBER_FRAC + NORM_GUARD + 1;     // 35
  parameter int NORM_PROD_W  = MEMBER_FRAC + NORM_GUARD + 2;     // 36
  parameter int CENTER_NUM_W = ACC_NUM_W + CENTER_FRAC;          // 54
  parameter int CSQ_PROD_W   = 50;                               // count*u*u before shifting

  // Width of the score used when reseeding an empty cluster.
  parameter int RESEED_SCORE_W = COUNT_W + DSQ_W;                // 58

  // Fixed-point constants.
  // ONE_Q represents 1.0 and needs the extra membership bit.
  parameter logic [MEMBER_W-1:0] ONE_Q = MEMBER_W'(1) << MEMBER_FRAC;

  // Nearest integer representation of 0.1 in Q8.F format.
  // For F = 12, the rounded value is (4096 + 5) / 10 = 410.
  parameter logic [CENTER_W-1:0] EPSILON_Q = CENTER_W'(410);

  // Centers must stay within the grayscale range scaled by 2^F.
  parameter logic [CENTER_W-1:0] CENTER_MAX_Q = CENTER_W'(255) << CENTER_FRAC;

  // Common data types used by the FCM modules.
  typedef logic [CENTER_W-1:0] center_t;
  typedef logic [MEMBER_W-1:0] member_t;
  typedef logic [COUNT_W-1:0]  count_t;

endpackage
