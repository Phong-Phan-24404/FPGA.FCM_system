# Verification plan — FCM

Phạm vi: FCM algorithmic core IP (`02_FCM_IP`) và tầng tích hợp luồng ảnh
(`04_SoC_Intergration/.../fcm_stream_pipeline`). Contract đang verify:
`FCM_UNSIGNED_RATIO_NORM_V4`, profile `precision`.

Tài liệu này nói **kiểm cái gì và bằng cách nào**. Cấu trúc nguồn nằm ở
[uvm_architecture.md](uvm_architecture.md); danh mục testbench và ánh xạ
requirement → test nằm ở [test_traceability.md](test_traceability.md).

## 1. Nguyên tắc nền

**Scoreboard không cài đặt lại thuật toán FCM.** Mọi giá trị kỳ vọng đọc từ
file vector do `01_Reference` sinh ra. Nếu viết lại contract bằng
SystemVerilog, một hiểu nhầm sẽ xuất hiện ở cả DUT lẫn scoreboard, và test
sẽ xanh trong khi RTL sai.

Hệ quả: chất lượng verification bị chặn trên bởi chất lượng bộ vector. Vì vậy
"bộ vector đã chạm tới nhánh nào" là một câu hỏi first-class, và có
subscriber riêng trả lời (mục 4).

## 2. Ba tầng kiểm thử và lý do tồn tại

| Tầng | DUT | Kiểm thứ mà tầng khác không kiểm được |
| --- | --- | --- |
| Unit directed | `fcm_divider`, `fcm_accum_update` | số học từng khối, kể cả các giá trị biên mà vector mức cao không bao giờ sinh ra |
| IP UVM — member | `fcm_member` | từng bước membership trên ĐÚNG các bộ tâm mà thuật toán thật sự đi qua (`bin_traces/*.jsonl`) |
| IP UVM — core | `fcm_core` | vòng lặp trọn vẹn trên histogram thật: tâm cuối, số vòng lặp, cờ hội tụ, bảng nhãn |
| SoC UVM | `fcm_stream_pipeline` | gom histogram từ 202500 pixel có bắt tay valid/ready, tính tâm khởi tạo trong phần cứng, quy đổi Q8.12 → 8-bit |
| SoC directed | SDRAM path, stream reader, board UI | đường dữ liệu và UI của board, không liên quan thuật toán |
| Hệ thống | `fcm_de10lite_integration` + `sdram_image_path` + Avalon slave | trọn đường đi của một khung ảnh: upload, đóng gói SDRAM, CDC, và đèn báo |

Lưu ý ranh giới: **không phải mọi test mức SoC đều là một UVM system-level
environment.** Chỉ `tb_fcm_stream_pipeline_uvm` dùng `fcm_soc_uvm_pkg`; các
testbench SDRAM/JTAG/board-UI là directed và độc lập.

## 3. Requirement → kiểm bằng gì

| ID | Requirement | Checker | Nơi kiểm |
| --- | --- | --- | --- |
| R-MEM-1 | Membership của mỗi bin khớp reference | scoreboard so từng `membership_q` | `fcm_member_scoreboard` |
| R-MEM-2 | Tổng membership = 1.0 ở scale của contract | scoreboard + SVA `a_sum_is_one` | `fcm_member_scoreboard`, `fcm_member_sva` |
| R-MEM-3 | Cluster không active phải bằng 0 | SVA `a_inactive_zero` | `fcm_member_sva` |
| R-MEM-4 | Membership nằm trong miền hợp lệ | SVA `a_member_in_range` | `fcm_member_sva` |
| R-CORE-1 | Tâm cuối khớp reference | scoreboard so `centers_q` | `fcm_core_scoreboard` |
| R-CORE-2 | Số vòng lặp hội tụ khớp reference | scoreboard so `iter_converged` | `fcm_core_scoreboard` |
| R-CORE-3 | Cờ `converged` khớp reference | scoreboard | `fcm_core_scoreboard` |
| R-CORE-4 | Bảng nhãn (label LUT) khớp reference | scoreboard quét toàn LUT | `fcm_core_scoreboard` |
| R-CORE-5 | Số vòng lặp bị chặn; không hội tụ ⇒ chạm MAX_ITER | SVA `a_iterations_bounded`, `a_not_converged_means_max` | `fcm_core_engine_sva` |
| R-CORE-6 | Tâm luôn nằm trong miền hợp lệ | SVA `a_centers_in_domain` | `fcm_core_engine_sva` |
| R-CORE-7 | `contract_error` không bao giờ bật ở input hợp lệ | SVA `a_no_contract_error` + scoreboard | `fcm_member_sva`, `fcm_core_engine_sva` |
| R-DIV-1 | Không chia cho 0, không tràn | SVA `a_no_div_by_zero`, `a_no_overflow` | `fcm_divider_sva` |
| R-DIV-2 | Thương đúng trên dải giá trị kiểm | so với mô hình trong TB | `tb_fcm_divider` |
| R-ACC-1 | Tích luỹ tử/mẫu không tràn | SVA `a_no_overflow` | `fcm_accum_update_sva` |
| R-PROTO-1 | `start` chỉ nhận khi idle; `done` là xung | SVA `a_no_start_while_busy`, `a_done_pulse` | mọi `*_sva` |
| R-PROTO-2 | Không ghi histogram khi đang tính | SVA `a_no_write_during_compute` | `fcm_core_protocol_sva` |
| R-RST-1 | Reset giữa chừng đưa DUT về idle và lần chạy sau vẫn đúng | directed, reset tại 4 điểm | `tb_fcm_core_reset` |
| R-SOC-1 | Tâm hiển thị 8-bit khớp reference | scoreboard mức SoC | `fcm_soc_scoreboard` |
| R-SOC-2 | `done` và `error` loại trừ nhau | SVA `a_done_xor_error` | `fcm_stream_pipeline_sva` |
| R-SOC-3 | `pixel_ready` chỉ bật trong cửa sổ streaming | SVA `a_ready_only_when_streaming` | `fcm_stream_pipeline_sva` |
| R-SOC-4 | `num_clusters` được latch đúng | SVA `a_numc_latched` | `fcm_stream_pipeline_sva` |
| R-SOC-5a | `eof` đến SỚM (trước pixel cuối) ⇒ `error_o` | sequence đặt `eof` giữa khung; scoreboard so `saw_error` với `expect_error` | `fcm_soc_eof_error_sequence` |
| R-SOC-5b | Đủ `IMG_PIXELS` mà THIẾU `eof` ⇒ `error_o` | sequence không bao giờ phát `eof` | `fcm_soc_eof_error_sequence` |
| R-SOC-6 | DUT nhận đúng số pixel đã gửi, kể cả dưới backpressure | monitor đếm beat `pixel_valid && pixel_ready`, scoreboard so với `pixels.size()` | `fcm_soc_monitor`, `fcm_soc_scoreboard` |
| R-SYS-1 | Avalon slave báo protocol error khi `byteenable` không hợp lệ | đọc thanh ghi trạng thái sau một ghi sai | `tb_fcm_system` |
| R-SYS-2 | Upload commit đúng `PADDED_WORDS` word vào SDRAM | đếm word đã commit | `tb_fcm_system` |
| R-SYS-3 | Đóng gói pixel → word 16-bit đúng thứ tự byte thấp trước; phần đệm bằng 0 | quét toàn bộ mảng SDRAM | `tb_fcm_system` |
| R-SYS-4 | Luồng đọc ngược trả đúng pixel và marker `sof`/`eol`/`eof` | so từng pixel với ảnh nguồn | `tb_fcm_system` |
| R-SYS-5 | CDC FIFO 50→25 MHz không mất và không đổi pixel | so nội dung FIFO ở phía `clk_fcm` | `tb_fcm_system` |
| R-SYS-6 | Histogram, centroid cuối và đèn báo của board khớp reference | so với `hist_counts_u18.mem`, `golden_centers.mem`, `ledr` | `tb_fcm_system` |
| R-AVM-1 | Không `read` và `write` cùng chu kỳ | SVA `a_no_read_and_write` | `fcm_avalon_mm_sva` |
| R-AVM-2 | Master giữ lệnh ổn định khi bị `waitrequest` chặn | SVA `a_cmd_stable_while_waited`, `a_writedata_stable_while_waited` | `fcm_avalon_mm_sva` |
| R-AVM-3 | Lệnh không bị rút về giữa lúc bị chặn | SVA `a_cmd_not_dropped` | `fcm_avalon_mm_sva` |
| R-AVM-4 | `byteenable` có ít nhất một lane | SVA `a_byteenable_nonzero` | `fcm_avalon_mm_sva` |
| R-AVM-5 | `waitrequest` không treo vô hạn | SVA `a_waitrequest_bounded` | `fcm_avalon_mm_sva` |
| R-AVM-6 | `readdata` không có X/Z khi master lấy | SVA `a_readdata_known` | `fcm_avalon_mm_sva` |
| R-CDC-1 | Nguồn giữ dữ liệu khi `dcfifo` chặn | SVA `a_hold_data_when_backpressured` | `fcm_cdc_sva` |
| R-CDC-2 | Không báo `ready` khi FIFO đầy | SVA `a_no_fifo_overflow` | `fcm_cdc_sva` |
| R-CDC-3 | Không đọc FIFO khi đang rỗng | SVA `a_no_fifo_underflow` | `fcm_cdc_sva` |
| R-CDC-4 | `stream_request` đủ rộng để phía `clk_50` lấy mẫu ≥ 2 lần | SVA `a_stream_request_wide_enough` | `fcm_cdc_sva` |
| R-CDC-5 | Tầng đồng bộ thứ hai bám theo tầng thứ nhất | SVA `a_sync_follows_meta` | `fcm_cdc_sva` |

Bảng này là **đề nghị ban đầu**: ID được đặt khi viết lại tài liệu, chưa có
trong một tài liệu requirement có sẵn. Khi dự án có spec chính thức, thay cột
ID bằng ID của spec đó.

## 4. Coverage

Không có license `svverification` ⇒ không `covergroup`. Thay bằng bộ đếm
thuần trong `uvm_subscriber`, chỉ đếm trên các case **đã được scoreboard kiểm
xong** (`checked_ap`), nên con số coverage không bao giờ lớn hơn con số đã
kiểm.

| Subscriber | Đếm gì | Dùng để trả lời |
| --- | --- | --- |
| `fcm_member_coverage` | case theo K, số tâm trùng pixel (0/1/nhiều), gray biên | bộ vector có chạm nhánh chia đều `2^M` không |
| `fcm_core_coverage` | case theo K, theo số bin active, hội tụ / chạm trần | bộ vector có case không hội tụ không |
| `fcm_core_perf` | chu kỳ `start`→`done` | hồi quy hiệu năng, không phải pass/fail |
| `fcm_soc_coverage` | case theo K | |

Coverage ở đây là **stimulus inventory**, không phải structural coverage của
DUT. Hai thứ đó khác nhau và `regression/scripts/coverage_matrix.py` giữ
chúng tách biệt — đừng gộp lại trong báo cáo.

Hiện trạng đã biết: bộ `precision` không bao giờ chạm nhánh reseed hay nhánh
trùng tâm, nên `fcm_core_base_test` chạy kèm các bộ corner
(`reseed_single`, `reseed_multi`, `coincident`, `deep_iter`). Nếu chỉ chạy
`precision`, các trạng thái `E_RS_*` và `_split_one` nhiều index không hề
được kiểm — `fcm_member_coverage` sẽ phát `UVM_WARNING` khi điều đó xảy ra.

## 5. Tiêu chí coi là đạt

Một tier được coi là xanh khi tất cả các điều sau đúng:

1. mọi testbench trong tier `PASS` (exit code 0 **và** log không có
   `** Error`, `FAIL`, `UVM_ERROR : <khác 0>`, `UVM_FATAL`);
2. scoreboard báo `checked == planned` — không case nào im lặng bị bỏ qua
   (`UVM_ERROR("INCOMPLETE")` bắt đúng trường hợp này);
3. không có `UVM_WARNING` coverage mới so với lần chạy trước.

Điều 2 quan trọng hơn vẻ ngoài của nó: một sequence đọc nhầm thư mục sẽ gửi 0
item, và nếu không có nó thì "0/0 cases match" trông vẫn như PASS.

## 6. Giới hạn đã biết của kiến trúc hiện tại

Ghi lại để không bị phát hiện lại như lỗi mới:

- **Scoreboard lấy kích thích từ driver, không từ input monitor.** Ở mức IP
  điều này ít nghiêm trọng hơn vẻ ngoài, vì giá trị kỳ vọng đọc từ file vector
  chứ không từ quan sát của driver. Ở mức SoC, vùng mù đã được thu hẹp:
  monitor nay đếm beat `pixel_valid && pixel_ready` (R-SOC-6), nên số pixel
  DUT THẬT SỰ nhận được kiểm độc lập với số driver ĐỊNH gửi. Nội dung từng
  pixel thì vẫn chưa. Xem
  [scoreboard_architecture_review.md](scoreboard_architecture_review.md).
- **Ghép cặp expected/observed theo thứ tự FIFO**, có kiểm chéo `case_id`.
  Không mở rộng được cho DUT cho phép nhiều giao dịch outstanding hoặc hoàn
  thành out-of-order.
- **Transaction gộp stimulus và expected.** Về lâu dài nên tách thành
  stimulus / observed / prediction để giảm coupling.
- **PHY JTAG không được mô phỏng.** `tb_fcm_system` bắt đầu từ Avalon slave,
  tức bỏ qua `altera_jtag_sld_node` → `bytes_to_packets` → `packets_to_master`.
  Đây là IP của vendor, và mô phỏng nó thật tốn thêm ~28 phút mỗi case. Việc
  chuỗi JTAG có đấu đúng không hiện chỉ được chứng minh bằng bring-up trên board.
- **Không có model SDRAM mức chip.** `tb_fcm_system` mô hình bộ nhớ ở giao diện
  client của controller, có bơm backpressure. Chân `DRAM_*` và bản thân
  `Sdram_Control` chưa bao giờ được mô phỏng.
