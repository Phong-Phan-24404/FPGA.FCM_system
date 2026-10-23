# Change log — tái cấu trúc 03_Verification (2026-10-21)

Thực hiện theo ba pha, mỗi pha chạy regression và so với baseline. Không sửa
RTL, không sửa reference model, không sửa bộ vector.

Baseline trước khi đụng vào gì (Questa 2025.2, Starter FPGA Edition):

| Tier | Kết quả |
| --- | --- |
| IP `regression` (5 tb) | 5/5 PASS |
| SoC `unit` (4 tb) | 4/4 PASS |

---

## Pha 1 (P0) — tách file, dựng lại cây thư mục

Giữ nguyên tên class, quan hệ kế thừa, interface, transaction và hành vi.

**Tách package.** `fcm_uvm_pkg.sv` (1214 dòng, 21 class) và
`fcm_soc_uvm_pkg.sv` (467 dòng, 10 class) tách thành một file `.svh` cho mỗi
class. Tách thuần văn bản: ghép lại các `.svh` theo thứ tự `` `include `` cho
ra đúng thân package cũ, đã kiểm bằng script so từng dòng.

**Cây thư mục mới** — phân vùng theo verification target trước, vai trò UVM
sau (`common/`, `agents/`, `env/`, `sequences/`, `tests/`, `tb/`,
`assertions/`, `packages/`, `regression/`, `docs/`).

**Di chuyển**

| Cũ | Mới |
| --- | --- |
| `fcm_ip/uvm/fcm_uvm_pkg.sv` | `packages/` + `.svh` theo vai trò |
| `fcm_ip/tb/fcm_if.sv` | `agents/member_agent/fcm_member_if.sv`, `agents/core_agent/fcm_core_if.sv` (một interface một file) |
| `fcm_ip/tb/fcm_sva.sv` | `assertions/ip/` |
| `fcm_ip/tb/tb_*.sv`, `fcm_profile.sv` | `tb/ip/` |
| `soc/uvm/fcm_soc_uvm_pkg.sv` | `packages/` + `.svh` theo vai trò |
| `soc/tb/fcm_soc_if.sv` | `agents/stream_agent/` |
| `soc/tb/fcm_soc_sva.sv` | `assertions/soc/` |
| `soc/tb/tb_*.sv` | `tb/soc/` |
| `soc/fixtures/` | `tb/soc/fixtures/` |
| `tools/*.py` | `regression/scripts/` |

**Build** — `07_Scripts/config/{fcm_ip,project}.psd1`: `TbSources` trỏ đường
dẫn mới; `IncludeDirs` thêm các thư mục `.svh` để `vlog` nhận `+incdir+`.
File `.svh` không nằm trong `TbSources`.

**Kết quả.** IP 5/5, SoC unit 4/4. So log với baseline: mọi timestamp, số case
(`3000/3000`, `30/30`) và tổng chu kỳ (`4145766`) **giống hệt**; chỉ `file(line)`
trong UVM message đổi.

---

## Pha 2 (P1) — naming, ownership, gỡ coupling, configuration

**Tách `fcm_uvm_pkg` thành hai package.** `fcm_member_uvm_pkg` và
`fcm_core_uvm_pkg`.

> Khác với đề xuất trong feedback (một `fcm_ip_uvm_pkg`). Lý do: Questa phân
> giải mọi kiểu virtual interface được nhắc tới trong package lúc elaborate,
> nên khi hai agent chung package, `tb_fcm_core_uvm` phải instantiate một
> `fcm_member_if` nó không dùng (`unused_member_vif`) chỉ để tránh
> `vsim-8451`, và `tb_fcm_member_uvm` phải instantiate `unused_core_vif`.
> Một package cho mỗi agent xoá hẳn hai hack đó. Cả hai instance giả đã bị gỡ.

**Configuration object.** Thêm `<x>_agent_cfg` (giữ vif) và `<x>_env_cfg`
(giữ `agent_cfg`, `vector_dirs`, `max_items`) cho cả ba agent. Luồng:
tb top → test → env → agent → driver/monitor, mỗi bước dùng **đường dẫn
instance tường minh**.

**Bỏ wildcard `config_db`.** `set(null, "*", "vif", vif)` → `set(null,
"uvm_test_top", "vif", vif)`. Driver và monitor không còn tự lấy vif từ
`config_db`; chúng nhận `cfg` từ agent cha.

**Một nơi duy nhất đọc plusarg.** `+FCM_VECTORS` / `+FCM_MAX_ITEMS` đọc ở
`configure()` của base test. Hằng đường dẫn mặc định — trước đây chép ở 8 chỗ —
gom về `fcm_vector_pkg::FCM_DEFAULT_VECTOR_DIR`, kèm
`fcm_vector_spec()`, `fcm_vector_dir()`, `fcm_max_items()`,
`fcm_split_dirs()` dùng chung cho cả testbench directed.

**Đổi tên instance.** `env.agent` → `env.member_agent` / `env.core_agent` /
`env.stream_agent`. Tên class **không** đổi.

**Kết quả.** IP 5/5 (`3000/3000`, `30/30`, `4145766` chu kỳ — giống baseline);
SoC unit 4/4; `tb_fcm_stream_pipeline_uvm` với `+FCM_MAX_ITEMS=1` cho
`1/1 cases match reference`. Khác biệt duy nhất trong log là đường dẫn
hierarchy (do đổi tên instance) và tên sequence `seq` → `seq0` ở mức member
(test mức member giờ lặp theo danh sách thư mục, giống mức core).

---

## Pha 3 (P2) — agent tái sử dụng, regression layer, tài liệu

**Active / passive.** `<x>_agent_cfg.is_active` (mặc định `UVM_ACTIVE`). Ở
`UVM_PASSIVE` agent chỉ dựng monitor; env bỏ qua kết nối xuất phát từ driver.
`get_is_active()` override để đọc từ cfg, không để lệch với field của
`uvm_agent`.

**Base / derived test.** `fcm_core_base_test` có hook `virtual function
configure()`. `fcm_core_smoke_test` là test dẫn xuất đầu tiên: dùng đúng env,
agent, scoreboard, sequence, chỉ giới hạn một case cho mỗi bộ vector. Mọi
scenario mới nên đi đường này thay vì chép `build_phase`/`run_phase`.

**Regression layer.** `regression/scripts/Invoke-Regression.ps1` chạy tier
tương ứng ở **cả hai** config, gom log và ghi
`regression/reports/<timestamp>/summary.md`. Định nghĩa tier vẫn chỉ có một
nguồn — khoá `Tiers` trong `.psd1`; script không chép lại.

**Tài liệu.** `docs/uvm_architecture.md`, `docs/verification_plan.md`,
`docs/test_traceability.md`, `docs/onboarding.md`, và file này.

**Kết quả.** `Invoke-Regression.ps1 -Tier regression -Clean`: **10/10 PASS**
(IP 5, SoC 5). Số liệu khớp baseline từng điểm — `fcm_member` 3000/3000,
`fcm_core` 30/30 với 4145766 chu kỳ, `fcm_stream_pipeline` 6/6.
`fcm_core_smoke_test` chạy riêng: 5/5 case (một case cho mỗi bộ vector), hết
vài giây thay vì ~3 phút.

---

## Pha 4 — kiểm thử UVM_PASSIVE, kiểm cơ chế báo lỗi, rà lại scoreboard

### 4.1 UVM_PASSIVE giờ có bài chạy thật

`fcm_core_env_cfg.passive_agent_cfg` (mặc định null) cho phép dựng một agent
thứ hai, chỉ quan sát, trên CÙNG interface. `fcm_core_passive_test` bật nó lên
và tự kiểm trong `check_phase`: agent PASSIVE không có driver và sequencer, có
monitor, và quan sát ĐÚNG số giao dịch mà agent ACTIVE sinh ra. Monitor của cả
ba agent thêm trường `observed_count` để trả lời được câu hỏi đó.

Kết quả: `agent PASSIVE quan sat 5/5 giao dich, khong co driver/sequencer`,
`5/5 cases match reference`, 0 UVM_ERROR.

**Kiểm chính bài kiểm.** Đổi `is_active` của agent passive thành `UVM_ACTIVE`
rồi chạy lại: 3 UVM_ERROR (sai chế độ, vẫn dựng driver, vẫn dựng sequencer),
exit 1. Một bài kiểm không bao giờ đỏ được thì không chứng minh được gì.

Giới hạn còn lại: `fcm_core_monitor` đọc LUT bằng cách lấy mẫu
`labels_lut_data` trong khi **driver** mới là thứ quét `labels_lut_addr`, nên
một agent PASSIVE đứng một mình sẽ không đọc được LUT. Xem
[scoreboard_architecture_review.md](scoreboard_architecture_review.md) §4.

### 4.2 Cơ chế báo lỗi của regression — ba lỗ hổng, đã sửa

Tiêm lỗi thật để xem báo cáo có đỏ không. Cả ba lỗ hổng đều cho **màu xanh
giả**, và đều xuất hiện đúng lúc đang có lỗi thật.

| # | Lỗ hổng | Triệu chứng | Sửa |
| --- | --- | --- | --- |
| 1 | Lỗi compile làm `Invoke-Sim.ps1` ném exception; `Invoke-Regression.ps1` chết theo | Không có `summary.md`; tầng SoC không bao giờ chạy — một lỗi cú pháp mức IP giấu luôn trạng thái mức SoC | `try/catch` theo từng tầng, cộng một dòng `(compile/elaborate) FAIL` trong báo cáo |
| 2 | Báo cáo đọc log cũ của lần chạy trước | `Invoke-Sim` chỉ xoá log của testbench nó sắp chạy; chết ở testbench đầu thì những testbench sau vẫn còn log cũ và được báo **PASS** dù chưa hề chạy | Bỏ qua mọi log có `LastWriteTime` trước lúc bắt đầu lần chạy; báo `NO LOG` |
| 3 | Luật dò lỗi chỉ bắt bảng tổng kết UVM | Mẫu `'UVM_FATAL @'` KHÔNG BAO GIỜ khớp (giữa chúng luôn có tên file), nên phát hiện phụ thuộc hoàn toàn vào việc `uvm_report_server` kịp in bảng. Sim chết trước đó ⇒ log đầy UVM_ERROR vẫn PASS | Thêm `UVM_(ERROR\|FATAL)(?!\s*:)` ở **cả** `Invoke-Sim.ps1` và `Invoke-Regression.ps1` |

Lỗ hổng 3 nằm trong `07_Scripts/questa/Invoke-Sim.ps1` — ngoài `03_Verification`,
nhưng nó chính là cơ chế quyết định PASS/FAIL nên phải sửa cùng chỗ.

Thêm `-PlusArgs` cho `Invoke-Regression.ps1`, và dòng Note của testbench FAIL
giờ mang lỗi ĐẦU TIÊN (ưu tiên fatal) thay vì dòng "x/y cases match".

Bằng chứng:

```
# lỗi compile ở mức IP
ip  | (compile/elaborate) | FAIL   | vlog (SystemVerilog) thất bại (exit code 2).
ip  | tb_fcm_divider      | NO LOG | khong co log tu lan chay nay
ip  | tb_fcm_accum_update | NO LOG | khong co log tu lan chay nay
soc | tb_sdram_mock_status| PASS            <- tầng SoC vẫn chạy
EXIT=1

# lỗi lúc chạy: trỏ FCM_VECTORS vào thư mục không tồn tại
ip | tb_fcm_member_uvm | FAIL | UVM_FATAL ... [NOVECTORS] khong doc duoc case nao
ip | tb_fcm_core_uvm   | FAIL | UVM_FATAL ... [NOVECTORS] khong doc duoc case nao
EXIT=1
```

### 4.3 Scoreboard — một lỗ hổng thật, đã sửa

`fcm_soc_scoreboard` không có kế toán giao dịch (`planned` /
`received_*` / `pending_*`) như hai scoreboard mức IP; nó chỉ báo lỗi khi
`checked == 0`. Sequence gửi 6 case mà monitor chỉ công bố 4 ⇒ scoreboard ghép
4 cặp rồi in **"4/4 cases match reference"**. Đã thêm đủ bộ đếm và
`INCOMPLETE`; `fcm_soc_case_sequence` nay công bố `sent_count` và
`fcm_soc_base_test` đặt `env.scoreboard.planned`.

Bằng chứng — tiêm lỗi cho monitor bỏ qua giao dịch đầu:
`UVM_ERROR [INCOMPLETE] soc planned=2 checked=1 pending=1` và FAIL. Trước khi
sửa, đúng lần chạy đó báo `1/1 cases match reference` và PASS.

**Đính chính tài liệu.** R-SOC-5 (`eof` lệch nhịp ⇒ `error_o`) trước đây được
ghi là đã kiểm. Đọc lại driver: `pixel_eof` LUÔN đi với pixel cuối, nên chưa
có test nào sinh ra tình huống đó. `verification_plan.md` và
`test_traceability.md` đã sửa thành chưa kiểm.

Phân tích đầy đủ ba điểm review nêu, kèm việc nên làm tiếp theo thứ tự:
[scoreboard_architecture_review.md](scoreboard_architecture_review.md).

### 4.4 Regression sau Pha 4

`Invoke-Regression.ps1 -Tier regression -Clean`: **10/10 PASS**, số liệu vẫn
khớp baseline từng điểm (3000/3000, 30/30 với 4145766 chu kỳ, 6/6). Luật dò
lỗi chặt hơn không tạo ra FAIL giả nào.

---

## Chưa làm — ghi lại để không mất dấu

- R-SOC-5 (`eof` lệch nhịp) chưa có sequence nào sinh ra.
- Ghép cặp expected/observed vẫn theo thứ tự FIFO (có kiểm chéo `case_id` và,
  từ Pha 4, có kế toán `planned` ở cả ba scoreboard).
- Transaction vẫn gộp stimulus, expected và observed.
- Agent PASSIVE của mức member và mức SoC chưa có env nào dựng; chỉ
  `fcm_core_agent` có bài chạy qua đường passive.
- Chưa có cột owner trong `test_traceability.md`, và ID requirement là ID
  mới đặt, chưa nối với một tài liệu spec chính thức.

Chi tiết và lý do: [verification_plan.md](verification_plan.md) §6.

---

## Pha 5 — dọn file ngoài luồng chính (chuẩn bị public release)

Repo là public repository và là bản release của dự án, nên tiêu chí là **chỉ
giữ file nằm trong luồng chính**. Quét toàn bộ 74 file nguồn của
`03_Verification` xem file nào không ai tham chiếu, rồi đọc từng ứng viên.

### Đã xoá

| File | Lý do |
| --- | --- |
| `tb/soc/tb_fcm_fullflow_dump.sv` (282 dòng) | viết cho số học Q16.16; tự định nghĩa stub `div_q16`/`div_17_4`/`div_12_5` cho megafunction đã gỡ; giá trị kỳ vọng SAI so với contract V4; **không nằm trong `TbSources` nên chưa từng được compile** |
| `tb/soc/tb_jtag_sdram_fcm_system.sv` (398 dòng) | cùng lý do, cộng stub `dcfifo` riêng |
| `regression/scripts/run_fcm_fullflow_dump.ps1` (29 dòng) | script chạy TB đầu tiên; **cả 11 đường dẫn source đều không còn tồn tại** (`rtl/fcm/*.sv`, `rtl/tb/*.sv`); `$projectRoot` tính nhầm thành `03_Verification`; thư mục output là `..\xyz`; dựng 203 thư mục dump mỗi lần chạy |

Dấu vết cho thấy ba file này là một thí nghiệm bỏ dở: `tb_fcm_fullflow_dump.sv`
có `localparam ROOT = "rtl/xyz"`, đúng cái tên placeholder mà script dùng.

Lý do xoá thay vì giữ làm "mẫu tham khảo": một testbench cho **giá trị kỳ vọng
sai** mà vẫn nằm trong repo public thì nguy hiểm hơn là không có gì. Người đọc
mới không có cách nào biết nó sai nếu không đọc hết chú thích trong
`project.psd1`.

Mọi tham chiếu đã được dọn theo: `07_Scripts/config/project.psd1`,
`README.md`, `test_traceability.md`, `verification_plan.md`, và luật
`.gitignore` cho `regression/xyz/` (không còn lý do tồn tại).

### Hệ quả cần biết

Dự án **không còn** testbench full-system JTAG → SDRAM → FCM nào. Trước đây
thực chất cũng không có — hai file kia không hề được compile — nhưng giờ điều
đó hiện rõ trong cây nguồn thay vì bị che bởi hai file trông như testbench.

### Giữ lại, có lý do

| File | Vì sao vẫn thuộc luồng chính |
| --- | --- |
| `tb/ip/fcm_profile.sv`, `tb/ip/tb_fcm_core_profile.sv` | nằm trong `TbSources` nên được compile mỗi lần chạy; là nguồn số liệu của `06_Docs/ip/FCM_IP_DATAPATH_PROFILE.md` |
| `vectors/compact/` | `01_Reference/5_tests/test_vectors.py` assert đúng 12 case = compact + precision |
| `vectors/stress/` | `regression/scripts/validate_stress_vectors.py` đọc, và `06_Docs` dẫn chiếu |

---

## Pha 6 — bổ sung tầng kiểm thử hệ thống cho 04_SoC_Intergration

### Nguồn gốc

Dự án tiền nhiệm (`de10_lite_fcm_sdram`, đã bring-up thành công trên board) có
sẵn một testbench hệ thống. Tên cũ `tb_jtag_sdram_fcm_system` gây hiểu nhầm:
nó **không** dùng PHY JTAG và **không** dùng SDRAM thật — nó đẩy dữ liệu thẳng
vào `image_upload_avalon_slave` bằng task `avalon_write()`, và mô hình bộ nhớ ở
giao diện client của controller.

Đối chiếu RTL hai dự án (bỏ comment và dòng trống):

| Module | Kết quả |
| --- | --- |
| `image_upload_avalon_slave`, `sdram_image_path`, `sdram_image_store`, `sdram_grayscale_stream_reader`, `terasic_sdram_controller`, `sdram_init_guard`, `image_stream_reader`, `sdram_mock_status`, `fcm_power_on_reset` | **giống hệt** |
| `fcm_stream_pipeline` | khác 46 dòng — thêm đúng một port `contract_error_o` |
| `fcm_de10lite_integration` | khác 26 dòng — đổi tên tín hiệu, nối `contract_error`. **Port list giống hệt** |
| `fcm_board_ui` | khác 2 dòng — thêm `contract_error_i` và `ledr_o[5]` |

Vì toàn bộ đường dữ liệu upload → SDRAM → stream không đổi, testbench cũ vẫn
còn giá trị. Nó compile vào RTL V4 với **0 lỗi** mà không sửa dòng nào.

### Ba lần chạy để tìm ra cái gì thật sự cần sửa

| Lần | Kết quả | Nguyên nhân |
| --- | --- | --- |
| 1 | timeout sau 823 s, `loaded=1 words=101376 stage=0` | `DEBOUNCE_CYCLES` đổi 250_000 → 500_000 trên `clk_fcm`; TB giữ phím đúng `250_010` chu kỳ — con số tune cho bản cũ |
| 2 | `FCM histogram bin 0 mismatch`, 50 s | ảnh dùng sai: `tb/soc/fixtures/input_grayscale.mem` **không phải** ảnh sinh ra golden vector |
| 3 | **PASS**, 70 s | dùng `vectors/precision/demo_k07/pixels_u8.mem` |

Lần 1 chứng minh nửa đầu đường dữ liệu đã đúng trên V4 ngay từ đầu: upload
commit đủ `101376` word, và hai vòng kiểm đóng gói + padding đều qua.

### Phát hiện: fixture lệch reference

`03_Verification/tb/soc/fixtures/input_grayscale.mem` là một **ảnh khác** với
`01_Reference/fixtures/input_grayscale.mem`. Cùng 202500 pixel nhưng histogram
lệch ngay bin 0 (2 so với 10).

Ảnh khớp golden vector: `01_Reference/fixtures/`, `vectors/*/demo_kNN/pixels_u8.mem`.
Ảnh không khớp: chỉ mỗi file trong `tb/soc/fixtures/`.

Nó vô hại ở `tb_sdram_image_path` (bài đó chỉ đòi đọc ra đúng thứ đã ghi vào),
nhưng là cái bẫy cho bất kỳ testbench mức hệ thống nào — tôi đã sập bẫy đó ở
lần chạy 2. Đã xoá thư mục `fixtures/` và trỏ `tb_sdram_image_path` sang
`vectors/precision/demo_k07/pixels_u8.mem`: một nguồn ảnh duy nhất cho cả repo,
và bớt 600 KB trùng lặp.

### `tb_fcm_system` — những gì đã đổi khi port

| Việc | Lý do |
| --- | --- |
| `repeat (250_010)` → `KEY_HOLD_CYCLES = 500_010` | theo `DEBOUNCE_CYCLES` mới, có comment buộc hai số đi cùng nhau |
| `golden_center_u8()`: Q16.16 → Q8.12 | contract V4, `CENTER_FRAC = 12` |
| Đường dẫn vector dựng từ `fcm_vector_dir()` + `fcm_case_dir()` | dùng chung hạ tầng với phần còn lại của `03_Verification` |
| K lấy từ `+FCM_CASE_K` thay vì cố định 7 | chạy được mọi case `demo_kNN` |
| Bỏ stub `div_q16`/`div_17_4`/`div_12_5` | megafunction đã gỡ khỏi RTL V4 |
| **Bỏ stub `dcfifo`** | dùng model thật của `altera_mf_ver`; đây là lần đầu cầu CDC thật được mô phỏng trong repo |
| Thêm check `ledr[5]` | `contract_error_o` là tín hiệu mới của V4 |

### Nó kiểm những gì

Sáu requirement mới, `R-SYS-1..6` trong [verification_plan.md](verification_plan.md) §3:
Avalon protocol error, số word commit, đóng gói byte thấp trước + padding 0,
pixel và marker `sof`/`eol`/`eof` của luồng đọc ngược, nội dung CDC FIFO, và
histogram + centroid + đèn báo so với reference.

Đã vào `TbSources`, tier `regression`, và `TbPlusArgs` của
`07_Scripts/config/project.psd1`.

### Tài liệu

Thêm [verification_audit.md](verification_audit.md): đối chiếu toàn bộ hệ
thống với tiêu chuẩn ASIC, tách rõ khoảng trống **bị chặn bởi license** (không
có `covergroup`, không constrained random, không code coverage) với khoảng
trống **làm được nhưng chưa làm**, có xếp ưu tiên.

---

## Pha 7 — đóng vùng mù phát hiện ở mức SoC (R-SOC-6)

`fcm_soc_monitor` trước đây chỉ lấy mẫu tại sườn lên của `done`/`error`; nó
không hề quan sát luồng pixel. Nghĩa là "DUT thật sự nhận bao nhiêu pixel" chỉ
được suy ra gián tiếp qua centroid — mà với 202500 pixel, mất vài pixel có thể
không làm đổi tâm 8-bit sau khi làm tròn.

Thêm:

- `fcm_soc_monitor` chạy một task song song đếm beat `pixel_valid && pixel_ready`;
- `fcm_soc_item.observed_beats` chở con số đó sang scoreboard;
- `fcm_soc_scoreboard` so với `exp_item.pixels.size()`, báo `BEATS` khi lệch.

Đếm song song chứ không gộp vào vòng lấy mẫu kết quả, vì hai thứ xảy ra ở hai
thời điểm khác nhau: beat trong suốt pha streaming, kết quả tại `done`.

**Kiểm bằng đột biến.** Cho driver bỏ đúng một pixel:

```
UVM_ERROR [BEATS] DUT nhan 202499 beat, driver gui 202500 pixel (demo_k02 k=2 pixels=202500)
```

Chạy sạch: `2/2 cases match reference`, 0 UVM_ERROR — không có báo lỗi giả.

Đột biến này cũng làm lệch `eof` nên centroid sai theo; nó chứng minh cơ chế
chạy và **nêu đúng nguyên nhân trước hệ quả**, nhưng chưa chứng minh trường hợp
mất pixel mà tâm vẫn tròn ra đúng. Ghi nhận giới hạn đó thay vì tuyên bố quá
lời.

Còn lại: monitor đếm được BAO NHIÊU beat nhưng không kiểm NỘI DUNG từng pixel
trên bus. `tb_fcm_system` thì có (R-SYS-4).

Tiện thể: dòng Note của báo cáo regression nay nhận cả dòng `PASS` của các
testbench directed, nên `tb_fcm_system` không còn hiện ô trống.

---

## Pha 8 — R-SOC-5: `eof` lệch nhịp (requirement cuối chưa có test)

Đọc `fcm_stream_pipeline.sv` trước khi viết test, và phát hiện RTL bắt **hai**
trường hợp riêng biệt chứ không phải một:

```systemverilog
P_STREAM:
  if (pixel_eof_i)
      if (pixel_count_q == IMG_PIXELS-1)  // hết khung, hợp lệ
      else                                 // eof SỚM      -> error_o
  else if (pixel_count_q == IMG_PIXELS-1)  // THIẾU eof    -> error_o
```

Nên requirement tách thành **R-SOC-5a** (`eof` sớm) và **R-SOC-5b** (thiếu
`eof`). Viết một test chung cho cả hai sẽ bỏ sót một nhánh.

### Thay đổi

| File | Việc |
| --- | --- |
| `fcm_soc_item.svh` | thêm `eof_index`, `expect_error`, và `planned_beats()` |
| `fcm_soc_driver.svh` | đặt `eof` theo `eof_index` rồi dừng ngay; `'1` nghĩa là "pixel cuối" |
| `fcm_soc_scoreboard.svh` | so `saw_error` với `expect_error` **hai chiều**; case lỗi thì dừng trước khi so tâm; beat so với `planned_beats()` thay vì `pixels.size()` |
| `fcm_soc_eof_error_sequence.svh` | mới — hai case: `eof` giữa khung, và không bao giờ phát `eof` |
| `fcm_soc_base_test.svh` | tách `run_sequences()` khỏi `run_phase()` để test dẫn xuất thêm stimulus mà không chép lại phần objection |
| `fcm_soc_eof_error_test.svh` | mới — `fcm_soc_eof_error_test` (chỉ case lỗi) và `fcm_soc_full_test` (bình thường + lỗi) |

Scoreboard so **hai chiều** là điểm quan trọng: một case lỗi có chủ ý mà DUT im
lặng cũng là thất bại, nên không thể chỉ bỏ qua check khi đang chờ lỗi.

### Vào regression, không để chạy tay

`Invoke-Sim` chỉ nhận một `uvm_test` cho mỗi testbench, nên `UvmTests` của
`tb_fcm_stream_pipeline_uvm` trỏ sang `fcm_soc_full_test` — bài gộp cả case
bình thường lẫn hai case lỗi. Một requirement chỉ được chạy bằng tay thì không
tính là đã kiểm.

### Kiểm bằng đột biến

Lật `expect_error` từ 1 sang 0 ở cả hai case:

```
UVM_ERROR [ERRORFLAG] error_o=1 nhung ky vong 0: eof_som k=2 pixels=202500
UVM_ERROR [ERRORFLAG] error_o=1 nhung ky vong 0: thieu_eof k=2 pixels=202500
```

Đây mới là bằng chứng R-SOC-5 thật sự được kiểm: DUT **có** bật `error_o`
trong cả hai trường hợp, chứ không phải test pass vì bỏ qua check.

Chạy sạch: `2/2 cases match reference`, 0 UVM_ERROR, và không có `BEATS` —
nghĩa là `planned_beats()` tính đúng cho cả case dừng giữa chừng (101251 beat)
lẫn case đẩy hết khung (202500 beat).

---

## Pha 9 — mục 8 (protocol checker Avalon-MM) và mục 11 (CDC)

### Mục 8 — `fcm_avalon_mm_sva`

Trước đó giao thức Avalon chỉ được kiểm bằng **một** case viết tay trong
testbench. Thêm sáu assertion bind vào `image_upload_avalon_slave`, kiểm **cả
hai phía**:

- **phía master** (interconnect Qsys, hoặc task `avalon_write` của testbench):
  giữ `address`/`write`/`read`/`byteenable`/`writedata` ổn định khi bị
  `waitrequest` chặn, không rút lệnh về giữa chừng, `byteenable` khác 0;
- **phía slave**: `waitrequest` không treo vô hạn, `readdata` không có X/Z khi
  master lấy.

Kiểm phía master đáng giá riêng: nó xác nhận chính testbench tuân thủ giao
thức, thay vì giả định như vậy.

**Đột biến** — cho `avalon_write` buông `avs_write` một nhịp giữa lúc
`waitrequest` lên:

```
** Error: avalon: lenh bi rut ve trong khi dang bi chan
   Scope: tb_fcm_system.jtag_avalon_endpoint.u_sva.a_cmd_not_dropped
** Error: avalon: lenh doi khi dang bi waitrequest chan
   Scope: tb_fcm_system.jtag_avalon_endpoint.u_sva.a_cmd_stable_while_waited
```

### Mục 11 — CDC: làm được phần nào, và nói rõ phần không làm được

Kiểm công cụ trước: thư mục `questa_fse/win64/` **không có `qverify`** hay bất
kỳ công cụ CDC/formal nào. Mục 11 như đề ra — "bằng công cụ hình thức" — là
**không làm được**.

Đọc lại thiết kế thì phát hiện tiền đề của mục này cũng không chính xác. Hai
miền clock **không bất đồng bộ**: `MAX10_CLK1_50` và `fcm_clk` đều 50 MHz, cùng
tham chiếu (`PLL_IP`, `clk0_divide_by = 1`), và SDC **cố ý không cắt** chúng để
TimeQuest vẫn kiểm mọi đường giữa hai miền. Bằng chứng đúng đắn cho các
crossing này là STA đóng timing, không phải mô phỏng.

Phần thay thế đã làm: `fcm_cdc_sva` với năm assertion (R-CDC-1..5) bắt vi phạm
**giao thức** ở ranh giới crossing — loại lỗi mà STA cũng không bắt được, ví dụ
nguồn buông dữ liệu khi `dcfifo` đang chặn.

Ghi rõ trong [verification_audit.md](verification_audit.md) §7.1: mô phỏng
không mô hình metastability, nên các assertion này **không** chứng minh an toàn
metastability.

### Hai phát hiện kèm theo

**Code coverage: cờ được nhận im lặng, cho 0 bin.** Soát lại khẳng định của
chính mình vì `vcover.exe` có trong cài đặt. `vlog +cover` / `vopt +cover` /
`vsim -coverage` đều exit 0 không cảnh báo, nhưng `coverage report` cho
"Enabled Coverage" trống và `coverage save` không tạo ra `.ucdb`. Nguy hiểm hơn
báo lỗi thẳng — đừng thêm `+cover` vào script build.

**Testbench hệ thống chạy sai tỉ lệ clock.** `tb_fcm_system` kế thừa
`always #20 clk_fcm` (25 MHz) từ dự án tiền nhiệm, trong khi board chạy 50 MHz.
Cấu hình đang ship chưa bao giờ được mô phỏng, và metric sai gần gấp đôi.

| Tỉ lệ | `fcm_busy_to_done_ns` |
| --- | --- |
| 1:1 (50 MHz, board) — **mặc định mới** | 28,590,360 |
| 2:1 (25 MHz, cũ) — `+FCM_CLK_HALF=20` | 49,080,560 |

Giữ lại tỉ lệ 2:1 vì nó ép `dcfifo` nặng hơn, nhưng nó không phải thứ đang chạy
trên board. Cả hai đều PASS, không vi phạm R-AVM hay R-CDC nào.

### Mức tin cậy không đồng đều

R-AVM-1..6 đã kiểm bằng đột biến. **R-CDC-1..5 thì chưa** — vi phạm chúng đòi
sửa RTL, mà RTL không được đụng. Chúng chạy sạch ở cả hai tỉ lệ clock, nhưng đó
là bằng chứng yếu hơn, và tài liệu ghi rõ điều đó.
