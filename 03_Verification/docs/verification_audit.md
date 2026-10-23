# Audit hệ thống verification — đối chiếu tiêu chuẩn ASIC

Soát toàn bộ `03_Verification` theo tiêu chí của một dự án ASIC, không phải
theo tiêu chí "chạy được trên board". Mỗi nhận định kèm bằng chứng từ source
hoặc từ một lần chạy sim.

Cập nhật: 2026-10-22, sau khi bổ sung tầng kiểm thử hệ thống.

---

## 1. Hiện trạng: bốn tầng kiểm thử

| Tầng | DUT | Kiểm thứ mà tầng khác không kiểm được | Testbench |
| --- | --- | --- | --- |
| Unit directed | `fcm_divider`, `fcm_accum_update` | số học từng khối ở giá trị biên | `tb_fcm_divider`, `tb_fcm_accum_update` |
| IP UVM | `fcm_member`, `fcm_core` | contract FCM trên tâm thật mà thuật toán đi qua | `tb_fcm_member_uvm`, `tb_fcm_core_uvm` |
| SoC UVM | `fcm_stream_pipeline` | gom histogram từ luồng pixel có backpressure | `tb_fcm_stream_pipeline_uvm` |
| **Hệ thống** | Avalon slave + `sdram_image_path` + `fcm_de10lite_integration` | **trọn đường đi một khung ảnh**: upload, đóng gói SDRAM, CDC 50→25 MHz, đèn báo | `tb_fcm_system` |

Tầng hệ thống là phần mới. Trước đó đường từ host xuống SDRAM rồi ngược lên
FCM **không có bài kiểm nào** — `tb_fcm_stream_pipeline_uvm` bắt đầu từ luồng
pixel đã có sẵn.

Nó cũng là nơi duy nhất `fcm_de10lite_integration` được mô phỏng, nghĩa là
`dcfifo` thật của `altera_mf_ver` (cầu CDC giữa hai miền clock) chỉ chạy ở đây.

## 2. Điểm mạnh — giữ nguyên

| Điểm | Bằng chứng |
| --- | --- |
| **Golden reference độc lập.** Scoreboard không cài đặt lại thuật toán; mọi giá trị kỳ vọng đọc từ file do mô hình Python bit-exact sinh ra | `fcm_core_scoreboard.svh`, `fcm_vector_pkg.sv` |
| **Kế toán giao dịch ở cả ba scoreboard.** `planned` vs `checked` vs `pending`, báo `INCOMPLETE` khi lệch | chứng minh bằng tiêm lỗi: bỏ một giao dịch ⇒ `planned=2 checked=1 pending=1` ⇒ FAIL |
| **Assertion bind, chạy ở cả hai tầng** | `fcm_sva_bind_member`/`_core` có mặt trong cả `tb_fcm_core_uvm` lẫn `tb_fcm_stream_pipeline_uvm` |
| **Agent tái sử dụng với config object, active/passive thật** | `fcm_core_passive_test` tự kiểm; đột biến `is_active` ⇒ 3 UVM_ERROR |
| **Regression gộp hai tầng, báo cáo một chỗ** | `Invoke-Regression.ps1` → `reports/<ts>/summary.md` |
| **Cơ chế báo lỗi đã được tự kiểm** | ba lỗ hổng màu-xanh-giả đã tìm và vá, xem [CHANGELOG](CHANGELOG_restructure.md) Pha 4 |

## 3. Khoảng trống bị chặn bởi license

Questa Intel FPGA Starter Edition **không có** license `svverification` và
không kèm code coverage. Đây là giới hạn công cụ, không phải lựa chọn
phương pháp — nêu rõ để không bị đánh giá nhầm là cẩu thả.

| Thiếu | Hệ quả | Đang thay bằng |
| --- | --- | --- |
| `covergroup` / functional coverage | không có bin, cross, hay coverage database | bộ đếm thuần trong `uvm_subscriber`, chỉ đếm case **đã kiểm xong** |
| `randomize()`, `randcase`, `randsequence` | **không có constrained random** — toàn bộ kích thích là directed hoặc đọc từ file | bộ vector corner sinh sẵn bằng Python (`reseed_single/multi`, `coincident`, `deep_iter`) |
| Code coverage (statement/branch/toggle/FSM) | không đo được dòng RTL nào chưa chạy | không có thay thế |

Hai mục đầu có đường thoát đã được thiết kế sẵn: coverage subscriber tách rời
agent và scoreboard, nên khi có license đầy đủ thì thay bằng `covergroup` thật
mà không đụng tới phần còn lại. Mục thứ ba thì không.

**Đây là khoảng trống lớn nhất giữa dự án này và một dự án ASIC thật.** Không
có code coverage nghĩa là không trả lời được câu hỏi "RTL còn dòng nào chưa
bao giờ chạy".

## 4. Khoảng trống làm được — theo thứ tự ưu tiên

| # | Việc | Vì sao đáng làm | Chi phí |
| --- | --- | --- | --- |
| 1 | `tb_fcm_system` chỉ chạy **K=7** trong tier | đường hệ thống phần lớn độc lập với K (upload, đóng gói, CDC, marker); chỉ phần chọn K của `fcm_board_ui` là phụ thuộc. Giá trị thực của một sweep đầy đủ **thấp hơn vẻ ngoài** | chạy tay: `-PlusArgs FCM_CASE_K=<2..7>` |
| 2 | ~~Đếm beat `pixel_valid && pixel_ready`~~ | **ĐÃ LÀM** — R-SOC-6, chứng minh bằng đột biến bỏ 1 pixel | — |
| 3 | ~~R-SOC-5: `eof` lệch nhịp~~ | **ĐÃ LÀM** — tách thành R-SOC-5a (`eof` sớm) và R-SOC-5b (thiếu `eof`), chạy trong regression qua `fcm_soc_full_test` | — |
| 4 | Mutation testing có hệ thống | làm ad-hoc 3 lần trong một phiên, cả 3 lần đều tìm ra lỗ hổng thật | vừa |
| 5 | Reset giữa chừng ở mức hệ thống | `tb_fcm_core_reset` chỉ làm ở mức IP; `KEY0` soft-reset của board chưa ai kiểm | vừa |
| 6 | Nhiều khung ảnh liên tiếp | mỗi sim chỉ chạy một khung; trạng thái còn sót giữa hai lần chạy chưa bị ép lộ | vừa |
| 7 | Backpressure ngẫu nhiên thay cho nhịp cố định | model SDRAM dùng `% 97`, `% 3`, `% 5` — một mẫu lặp, không phải stress thật | nhỏ |
| 8 | ~~Protocol checker cho Avalon-MM~~ | **ĐÃ LÀM** — `fcm_avalon_mm_sva`, R-AVM-1..6, chứng minh bằng đột biến buông lệnh giữa lúc bị chặn | — |
| 9 | CI tự động | regression chạy tay; không có gate trên pull request | vừa |
| 10 | Gate-level sim + SDF | chưa từng chạy; timing chỉ có STA | lớn |
| 11 | CDC/RDC bằng công cụ hình thức | **KHÔNG LÀM ĐƯỢC** — không có `qverify` trong Questa FSE. Đã làm phần thay thế: kiểm kê crossing + SVA giao thức (R-CDC-1..5). Xem §7 | — |
| 12 | X-propagation (`-xprop`) | hành vi khi reset chưa xác lập chưa được kiểm | vừa |

## 5. Giới hạn kiến trúc đã ghi nhận

Không phải lỗi, nhưng phải biết trước khi mở rộng:

- **PHY JTAG không được mô phỏng.** `tb_fcm_system` bắt đầu từ Avalon slave.
  Chuỗi `altera_jtag_sld_node` → `bytes_to_packets` → `packets_to_master` là IP
  vendor; mô phỏng thật tốn thêm ~28 phút mỗi case (đo được: TCK 20 MHz,
  8 TCK/byte, 202500 byte). Việc chuỗi đó đấu đúng chỉ được chứng minh bằng
  bring-up trên board.
- **Không có model SDRAM mức chip.** Bộ nhớ được mô hình ở giao diện client
  của controller. Chân `DRAM_*` và bản thân `Sdram_Control` chưa bao giờ chạy
  trong mô phỏng.
- **Scoreboard lấy kích thích từ driver**, không từ input monitor. Ở mức IP
  điều này ít nghiêm trọng vì giá trị kỳ vọng đến từ file vector chứ không từ
  quan sát của driver. Xem [scoreboard_architecture_review.md](scoreboard_architecture_review.md).
- **Ghép cặp expected/observed theo thứ tự FIFO**, có kiểm chéo `case_id` và
  kế toán `planned`. Không mở rộng được cho DUT có giao dịch outstanding.

## 6. Kết luận

Theo thang của một dự án ASIC:

| Khía cạnh | Đánh giá |
| --- | --- |
| Kiến trúc testbench phân tầng | **Đạt** |
| Self-checking với reference độc lập | **Tốt** — điểm mạnh nhất của dự án |
| Traceability requirement → test | **Đạt**, nhưng ID do tự đặt, chưa nối với spec chính thức |
| Độ phủ đường dữ liệu | **Đạt** sau khi thêm tầng hệ thống và R-SOC-6 |
| Functional coverage | **Không đạt** — chặn bởi license |
| Code coverage | **Không đạt** — chặn bởi license |
| Constrained random | **Không đạt** — chặn bởi license |
| Quản trị regression | **Đạt** |
| CDC | **Một phần** — SVA giao thức ở crossing (R-CDC-1..5) + STA đóng timing; công cụ hình thức không có |
| Gate-level sim | **Chưa làm** |

Hệ thống này đủ chặt cho một dự án FPGA có mô hình reference mạnh, và phần
phương pháp (phân tầng, self-checking, traceability, kế toán giao dịch, tự
kiểm cơ chế báo lỗi) đạt chuẩn ASIC. Phần **đo độ phủ** thì không, và không
thể đạt với license hiện tại — đó là điều cần nói thẳng trong bất kỳ bản đánh
giá nào, thay vì để người đọc suy ra từ việc thiếu báo cáo coverage.

---

## 7. Ghi chú bổ sung từ lần soát mục 8 và 11

### 7.1 CDC: hai miền clock là **đồng bộ có quan hệ pha**, không phải bất đồng bộ

`MAX10_CLK1_50` và `fcm_clk` đều 50 MHz và cùng tham chiếu — `PLL_IP` chạy
`clk0_divide_by = 1`. SDC **cố ý không cắt** chúng:

> They are deliberately NOT cut with `set_clock_groups -asynchronous`: cutting
> them would also stop checking any future unsynchronised signal added between
> the two domains.

Hệ quả cho verification:

- bằng chứng đúng đắn cho các crossing này là **STA đóng được timing**
  (hiện +2.322 ns setup, 0 đường fail), không phải mô phỏng;
- `dcfifo` và synchronizer ba tầng là lớp bảo vệ thêm, không phải điều kiện
  bắt buộc để đúng;
- **mô phỏng không mô hình metastability**, nên SVA ở `fcm_cdc_sva` không
  chứng minh được an toàn metastability. Chúng bắt vi phạm **giao thức** ở
  ranh giới crossing — loại lỗi mà STA cũng không bắt được, ví dụ nguồn buông
  dữ liệu khi FIFO đang chặn.

Một công cụ CDC hình thức sẽ bổ sung đúng phần còn thiếu: chứng minh cấu trúc
rằng mọi crossing đều có synchronizer phù hợp và không có logic tổ hợp xen
giữa. **`qverify` không có trong Questa FSE** — thư mục `win64/` chỉ có
simulator. Đây là khoảng trống không đóng được bằng cách viết thêm testbench.

### 7.2 Code coverage: cờ được nhận **im lặng** và cho 0 bin

Soát lại khẳng định "không có code coverage" bằng thực nghiệm, vì `vcover.exe`
có mặt trong cài đặt:

```
vlog +cover=sbcef   -> exit 0, không cảnh báo
vopt +cover=sbcef   -> exit 0, "Optimized design name is cov_opt"
vsim -coverage      -> exit 0, chạy bình thường
coverage report     -> "Enabled Coverage" TRỐNG, 0 bin, Total coverage 0.00%
coverage save       -> KHÔNG tạo ra file .ucdb
```

Nguy hiểm hơn là báo lỗi thẳng: toàn bộ luồng chạy sạch, không một dòng cảnh
báo, và người chạy có thể tin rằng mình đã bật coverage. **Đừng thêm `+cover`
vào script build** — nó chỉ tạo ảo giác.

### 7.3 Testbench hệ thống từng chạy sai tỉ lệ clock

`tb_fcm_system` kế thừa `always #20 clk_fcm` từ dự án tiền nhiệm, tức 25 MHz —
trong khi board chạy `fcm_clk` ở **50 MHz**. Nghĩa là cấu hình đang ship chưa
bao giờ được mô phỏng, và `METRIC: fcm_busy_to_done_ns` sai gần gấp đôi.

Đã sửa: mặc định `clk_fcm` = 50 MHz (đúng board), `+FCM_CLK_HALF=20` để quay
lại tỉ lệ 2:1. Giữ lại tỉ lệ cũ vì nó ép `dcfifo` nặng hơn tỉ lệ 1:1 — nhưng
nó **không** phải thứ đang chạy trên board.

| Tỉ lệ | `fcm_busy_to_done_ns` |
| --- | --- |
| 1:1 (50 MHz, cấu hình board) | 28,590,360 |
| 2:1 (25 MHz, cấu hình cũ) | 49,080,560 |

Cả hai đều PASS, không có vi phạm R-AVM hay R-CDC nào.

### 7.4 Mức tin cậy của từng nhóm assertion mới

Phải nói rõ vì hai nhóm không ngang nhau:

| Nhóm | Đã kiểm bằng đột biến | Ghi chú |
| --- | --- | --- |
| R-AVM-1..6 | **Có** — buông `avs_write` một nhịp giữa lúc `waitrequest` lên ⇒ `a_cmd_not_dropped` và `a_cmd_stable_while_waited` bắn đúng chu kỳ | |
| R-CDC-1..5 | **Chưa** | Vi phạm chúng đòi sửa RTL, mà RTL không được đụng. Chúng chạy sạch ở cả hai tỉ lệ clock, nhưng đó là bằng chứng yếu hơn. |

---

## 8. Trạng thái chốt (2026-10-22)

### Regression

`Invoke-Regression.ps1 -Tier regression -Clean` → **11 / 11 PASS**

| Tầng | Testbench | Số liệu |
| --- | --- | --- |
| IP | `tb_fcm_divider` | 2204 checks |
| IP | `tb_fcm_accum_update` | 125 operations |
| IP | `tb_fcm_member_uvm` | 3000/3000 case |
| IP | `tb_fcm_core_uvm` | 30/30 case, 4 145 766 chu kỳ |
| IP | `tb_fcm_core_reset` | 10 full-case, 4 điểm abort |
| SoC | `tb_sdram_mock_status`, `tb_image_stream_reader`, `tb_sdram_image_path`, `tb_fcm_board_ui` | directed |
| SoC | `tb_fcm_stream_pipeline_uvm` | 8/8 case (6 bình thường + 2 lỗi `eof`) |
| SoC | `tb_fcm_system` | K=7, 202500 pixel, 28.59 ms |

Mọi con số của IP không đổi so với baseline trước khi tái cấu trúc.

### Requirement

Không còn ID nào thiếu checker, và mọi checker đều chạy trong tier `regression`:

| Nhóm | ID |
| --- | --- |
| Membership | R-MEM-1..4 |
| Core | R-CORE-1..7 |
| Số học khối | R-DIV-1..2, R-ACC-1 |
| Giao thức IP | R-PROTO-1..2 |
| Reset | R-RST-1 |
| SoC | R-SOC-1..4, R-SOC-5a/5b, R-SOC-6 |
| Hệ thống | R-SYS-1..6 |
| Avalon-MM | R-AVM-1..6 |
| CDC | R-CDC-1..5 |

### Đã kiểm bằng đột biến

Bảy lần trong quá trình xây dựng, **cả bảy đều cho kết quả có ý nghĩa**:

| Đột biến | Bắt được bởi |
| --- | --- |
| `is_active` của agent passive → ACTIVE | `fcm_core_passive_test`, 3 UVM_ERROR |
| Monitor SoC bỏ một giao dịch | `INCOMPLETE`: `planned=2 checked=1 pending=1` |
| Lỗi cú pháp trong class | báo cáo regression: 3 đường màu-xanh-giả |
| Driver SoC bỏ một pixel | `BEATS`: nhận 202499, gửi 202500 |
| Lật `expect_error` | `ERRORFLAG` ×2, chứng minh DUT thật sự bật `error_o` |
| `avalon_write` buông lệnh khi bị chặn | `a_cmd_not_dropped`, `a_cmd_stable_while_waited` |
| Dùng sai ảnh nguồn | `FCM histogram bin 0 mismatch` |

Nhóm duy nhất **chưa** kiểm bằng đột biến là R-CDC-1..5 — xem §7.4.

### Người tiếp nhận nên làm gì tiếp

Theo thứ tự:

1. **Đưa repo vào git.** Toàn bộ công việc hiện chỉ nằm trên đĩa. `.gitignore`
   đã sẵn sàng và đã kiểm chứng: giữ đúng 75+ file nguồn, 17.3 MB thay vì
   70.7 MB.
2. **Mutation testing có hệ thống** (§4 mục 4). Làm ad-hoc bảy lần đã hiệu quả
   như bảng trên; làm có hệ thống sẽ còn hơn.
3. **Reset giữa chừng ở mức hệ thống** (§4 mục 5) — `KEY0` soft-reset chưa ai
   kiểm.
4. **Nhiều khung ảnh liên tiếp** (§4 mục 6) — mỗi sim chỉ chạy một khung, nên
   trạng thái còn sót giữa hai lần chạy chưa bị ép lộ.
5. **CI** (§4 mục 9).

### Thứ KHÔNG thể đóng bằng cách viết thêm testbench

- functional coverage, constrained random, code coverage — Questa FSE không có
  (§3, và bằng chứng thực nghiệm ở §7.2);
- CDC/RDC hình thức — không có `qverify` (§7.1);
- gate-level sim + SDF (§4 mục 10).

Ba nhóm này cần license hoặc công cụ khác. Bất kỳ bản đánh giá nào về dự án
cũng nên nói thẳng điều đó, thay vì để người đọc suy ra từ việc thiếu báo cáo
coverage.
