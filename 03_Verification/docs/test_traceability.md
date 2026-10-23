# Test catalog & traceability

Một dòng cho mỗi testbench đang tồn tại. Thêm testbench mà không thêm dòng ở
đây nghĩa là không ai biết nó kiểm gì — xem
[`regression/testlists/README.md`](../regression/testlists/README.md).

ID requirement tham chiếu [verification_plan.md](verification_plan.md) §3.

## IP level — config `07_Scripts/config/fcm_ip.psd1`

| Testbench | Kiểu | uvm_test | Requirement | Checker | Tier |
| --- | --- | --- | --- | --- | --- |
| `tb_fcm_divider` | directed | — | R-DIV-1, R-DIV-2 | so với mô hình trong TB + `fcm_divider_sva` | smoke, unit, regression |
| `tb_fcm_accum_update` | directed | — | R-ACC-1 | so với mô hình trong TB + `fcm_accum_update_sva` | smoke, unit, regression |
| `tb_fcm_member_uvm` | UVM | `fcm_member_base_test` | R-MEM-1..4, R-PROTO-1 | `fcm_member_scoreboard`, `fcm_member_sva` | unit, regression |
| `tb_fcm_core_uvm` | UVM | `fcm_core_base_test` | R-CORE-1..7, R-PROTO-1, R-PROTO-2 | `fcm_core_scoreboard`, `fcm_core_engine_sva`, `fcm_core_protocol_sva` | unit, regression |
| `tb_fcm_core_uvm` | UVM | `fcm_core_smoke_test` | như trên, 1 case/bộ vector | như trên | chạy tay khi cần bản nhanh |
| `tb_fcm_core_uvm` | UVM | `fcm_core_passive_test` | cơ chế `UVM_PASSIVE` của agent, không phải RTL | tự kiểm trong `check_phase` | chạy tay |
| `tb_fcm_core_reset` | directed | — | R-RST-1 | so với vector reference sau mỗi lần reset | regression |
| `tb_fcm_core_profile` | đo đạc | — | — (không kiểm gì thêm) | `fcm_profile.sv` báo chu kỳ đi đâu | không nằm trong tier nào |

## SoC level — config `07_Scripts/config/project.psd1`

| Testbench | Kiểu | uvm_test | Requirement | Checker | Tier |
| --- | --- | --- | --- | --- | --- |
| `tb_sdram_mock_status` | directed | — | đường trạng thái SDRAM mock | assert trong TB | smoke, unit, regression |
| `tb_image_stream_reader` | directed | — | đọc luồng ảnh từ bộ nhớ | assert trong TB | smoke, unit, regression |
| `tb_sdram_image_path` | directed | — | ghi/đọc ảnh qua SDRAM path | so với `vectors/precision/demo_k07/pixels_u8.mem` | unit, regression |
| `tb_fcm_board_ui` | directed | — | hiển thị / nút bấm của board | assert trong TB | unit, regression |
| `tb_fcm_stream_pipeline_uvm` | UVM | `fcm_soc_full_test` | R-SOC-1..6 | `fcm_soc_scoreboard`, `fcm_stream_pipeline_sva` | regression |
| `tb_fcm_stream_pipeline_uvm` | UVM | `fcm_soc_base_test` | R-SOC-1..4, R-SOC-6 — chỉ case bình thường | như trên | chạy tay |
| `tb_fcm_stream_pipeline_uvm` | UVM | `fcm_soc_eof_error_test` | R-SOC-5a, R-SOC-5b — chỉ case lỗi | như trên | chạy tay |
| `tb_fcm_system` | directed | — | R-SYS-1..6, R-AVM-1..6, R-CDC-1..5 | tự kiểm trong TB + `fcm_avalon_mm_sva` + `fcm_cdc_sva` + `fcm_stream_pipeline_sva` | regression |

`tb_fcm_system` phủ trọn đường đi của một khung ảnh nhưng **không mô phỏng PHY
JTAG** và **không dùng model SDRAM mức chip** — xem
[verification_plan.md](verification_plan.md) §6 và
[verification_audit.md](verification_audit.md) §5.

## Chỗ chồng lấn cần biết

- **Reset** được kiểm ở `tb_fcm_core_reset` (directed, reset giữa chừng tại 4
  điểm) và *không* được kiểm trong `tb_fcm_core_uvm` (chỉ reset một lần lúc
  khởi động). Hai bài không trùng nhau.
- **Assertion mức IP chạy ở cả hai tầng.** `fcm_sva_bind_member` và
  `fcm_sva_bind_core` được instantiate trong cả `tb_fcm_core_uvm` lẫn
  `tb_fcm_stream_pipeline_uvm`, vì `fcm_core` nằm ngay trong DUT mức SoC. Một
  vi phạm contract mức IP sẽ bị bắt ở cả hai nơi.
- **`tb_fcm_core_profile` không thêm checking nào** so với `tb_fcm_core_uvm`;
  nó chỉ báo phân bố chu kỳ. Đừng tính nó vào coverage.

## Requirement chưa có test

Không còn. Mọi ID trong [verification_plan.md](verification_plan.md) §3 đều có
ít nhất một checker, và đều nằm trong tier `regression`.

## Cột còn thiếu

Chưa có cột **owner** và chưa có liên kết tới một tài liệu requirement chính
thức. Điền khi phân công thật; để trống còn hơn điền tên giả rồi không ai
biết hỏi ai.
