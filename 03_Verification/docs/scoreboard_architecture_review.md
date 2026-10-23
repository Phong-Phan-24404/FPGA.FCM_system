# Scoreboard architecture — đánh giá lại

Rà soát lại ba điểm mà architecture review nêu về scoreboard, cộng những thứ
tìm thấy khi đọc lại code. Mỗi kết luận kèm bằng chứng từ chính source hoặc
từ một lần chạy sim, không phải suy đoán.

Tóm tắt: **một lỗ hổng thật đã được sửa** (mức SoC không có kế toán giao dịch),
**một mục trong traceability là nhận định sai** đã được đính chính, và hai
giới hạn còn lại nhỏ hơn mức review ngụ ý — nhưng vẫn có một vùng mù thật ở
mức SoC.

---

## 1. "Scoreboard phụ thuộc vào transaction do driver công bố"

### Ở mức IP: rủi ro nhỏ hơn mô tả chung

Lập luận chung là: scoreboard tin driver, nên nó kiểm cái driver ĐỊNH gửi chứ
không phải cái DUT THẬT SỰ nhận. Ở đây lập luận đó yếu đi một bậc, vì **giá
trị kỳ vọng không đến từ quan sát của driver**. Chúng đọc thẳng từ file vector
của `01_Reference`; driver chỉ chở chúng qua `stimulus_ap`.

Hệ quả cụ thể: nếu driver nạp sai histogram — sai địa chỉ, `hist_wr_en` hụt
một nhịp, bỏ sót bin — thì DUT tính trên dữ liệu khác với dữ liệu reference đã
dùng, nên `centers_q` sẽ lệch và `fcm_core_scoreboard` báo `MISMATCH`. Lỗi của
driver vẫn bị bắt, chỉ là bị bắt dưới nhãn sai.

Thêm hai hàng rào đã có sẵn:

- `K_MISMATCH` — so `k` driver gửi với `num_clusters` monitor đọc từ bus;
- `CASE_ID` — so thứ tự ghép cặp.

Kết luận: chuyển sang lấy stimulus từ input monitor ở mức IP sẽ cải thiện
**chẩn đoán** (lỗi hiện đúng nhãn), không cải thiện **khả năng phát hiện**.
Chưa đáng làm bây giờ.

### Ở mức SoC: đây mới là chỗ có vùng mù thật

`fcm_stream_pipeline` có backpressure thật (`pixel_ready`), và
`fcm_soc_monitor` **không quan sát luồng pixel chút nào** — nó chỉ lấy mẫu ở
sườn lên của `done`/`error`. Không có chỗ nào kiểm "DUT đã nhận đúng 202500
pixel".

Kịch bản lọt lưới: DUT đánh rơi một số ít pixel khi backpressure. Histogram
lệch vài đếm trên tổng ~202500; tâm sau khi quy đổi về 8-bit nhiều khả năng
vẫn tròn ra đúng giá trị cũ, nên scoreboard vẫn xanh.

**Đã sửa.** `fcm_soc_monitor` nay chạy một task song song đếm beat
`pixel_valid && pixel_ready`, gán vào `fcm_soc_item.observed_beats`, và
`fcm_soc_scoreboard` so nó với `exp_item.pixels.size()` (R-SOC-6).

Bằng chứng — tiêm lỗi cho driver bỏ đúng một pixel:

```
UVM_ERROR [BEATS] DUT nhan 202499 beat, driver gui 202500 pixel (demo_k02 k=2 pixels=202500)
```

Chạy sạch thì không báo gì: `2/2 cases match reference`, 0 UVM_ERROR.

Lưu ý về sức mạnh của bằng chứng này: đột biến trên cũng làm lệch `eof` nên
centroid cũng sai theo. Nó chứng minh cơ chế hoạt động và **nêu đúng nguyên nhân
trước hệ quả**, nhưng chưa chứng minh trường hợp mất pixel mà tâm 8-bit vẫn
tròn ra đúng — đó mới là kịch bản lọt lưới thật sự.

**Còn lại:** monitor đếm được BAO NHIÊU beat nhưng không kiểm NỘI DUNG từng
pixel trên bus. Một DUT nhận đủ 202500 beat nhưng đọc nhầm giá trị vẫn lọt
qua chỗ này (tuy sẽ bị bắt bởi histogram/centroid). `tb_fcm_system` thì có
kiểm từng pixel — xem R-SYS-4.

---

## 2. "Ghép cặp expected/observed theo thứ tự FIFO"

Đúng, và với DUT hiện tại thì không sao: cả ba DUT xử lý tuần tự, một giao
dịch một lúc, không có outstanding.

Điều quan trọng hơn thứ tự là **kế toán**: FIFO order chỉ an toàn khi có gì đó
bảo đảm không mất giao dịch. Đây là chỗ tìm ra lỗi thật.

### Lỗi đã tìm thấy và đã sửa: mức SoC không có kế toán giao dịch

`fcm_core_scoreboard` và `fcm_member_scoreboard` đều có `planned` /
`received_expected` / `received_observed` / `pending_expected` và báo
`INCOMPLETE` khi lệch. `fcm_soc_scoreboard` **không có**: `report_phase` của
nó chỉ báo lỗi khi `checked == 0`.

Hệ quả: sequence gửi 6 case, monitor chỉ công bố 4 → scoreboard ghép 4 cặp,
`failed == 0`, và report in **"4/4 cases match reference"**. Một lần chạy mất
hai case trông y hệt một lần chạy sạch.

Đã sửa: thêm đúng bộ đếm như hai scoreboard mức IP, và
`fcm_soc_base_test` nay đặt `env.scoreboard.planned` từ `seq.sent_count`
(sequence mức SoC trước đó không hề công bố số item đã gửi).

Bằng chứng — tiêm lỗi vào `fcm_soc_monitor` để bỏ qua giao dịch đầu tiên,
chạy `+FCM_MAX_ITEMS=2`:

```
UVM_ERROR [INCOMPLETE] soc planned=2 checked=1 pending=1 exp_q=0 obs_q=0
FAIL: tb_fcm_stream_pipeline_uvm
```

Trước khi sửa, đúng lần chạy đó báo `1/1 cases match reference` và PASS.
Chạy sạch sau khi sửa: `2/2 cases match reference`, không có `INCOMPLETE`.

---

## 3. "Transaction gộp stimulus và expected"

Đúng. `fcm_core_item` giữ cùng lúc `hist`/`init_centers` (stimulus),
`expected_*` (prediction) và `actual_*` (observed). Có một chỗ phải lách vì
điều này:

```systemverilog
// Latency is observed, not expected, so carry it across
exp_item.actual_cycles = obs_item.actual_cycles;
checked_ap.write(exp_item);
```

Scoreboard phải chép một trường observed sang item expected trước khi đẩy cho
coverage, vì chỉ có một kiểu transaction cho cả ba vai trò.

Đánh giá: đây là nợ kỹ thuật về độ rõ ràng, không phải lỗ hổng phát hiện lỗi.
Tách thành ba kiểu sẽ đụng vào cả driver, monitor, scoreboard, coverage và perf
của cả ba agent — chi phí lớn, lợi ích là dễ đọc. **Chưa làm**; làm khi có nhu
cầu thật (ví dụ khi thêm predictor độc lập).

---

## 4. Thêm: monitor mức core phụ thuộc vào driver để đọc LUT

Phát hiện khi viết `fcm_core_passive_test`. `fcm_core_monitor` lấy LUT bằng
cách lấy mẫu `vif.labels_lut_data` theo từng nhịp — nhưng **driver** mới là
thứ lái `labels_lut_addr`:

```systemverilog
// Driver applies labels_lut_addr at each falling edge ...
```

Nghĩa là một `fcm_core_agent` ở chế độ `UVM_PASSIVE` **không tự đọc được LUT**;
nó chỉ chép lại những gì một driver ở nơi khác đang quét. Trong
`fcm_core_passive_test` điều đó vẫn đúng vì agent ACTIVE ở cùng env đang quét,
nên hai monitor quan sát 5/5 giao dịch như nhau.

Đây là giới hạn cần biết trước khi tái sử dụng agent này ở một env cấp cao
hơn: ở đó sẽ không có ai quét LUT, và `actual_lut` sẽ là rác. Ghi lại thay vì
sửa, vì cách sửa đúng (cho monitor tự lái địa chỉ đọc) biến monitor thành một
thứ chủ động lái bus — trái với vai trò của nó.

---

## 5. Đính chính traceability: R-SOC-5 chưa được kiểm

`test_traceability.md` và `verification_plan.md` ghi:

> R-SOC-5 | `eof` lệch nhịp ⇒ `error_o` | sequence đẩy đủ khung, monitor quan sát

Đọc lại `fcm_soc_driver::stream_image`, `pixel_eof` **luôn** đi cùng pixel cuối:

```systemverilog
vif.pixel_eof <= (i == total - 1);
```

Không có test nào đẩy `eof` lệch nhịp. Comment trong driver ("lệch một nhịp là
DUT báo error_o, và đó chính là hành vi cần kiểm") mô tả ý định, không mô tả
thứ đang chạy.

**Đã sửa.** Đọc lại RTL thì `fcm_stream_pipeline` bắt HAI nhánh riêng biệt
(`eof` sớm, và đủ `IMG_PIXELS` mà thiếu `eof`), nên requirement tách thành
R-SOC-5a và R-SOC-5b. `fcm_soc_eof_error_sequence` sinh cả hai;
`fcm_soc_item.expect_error` cho scoreboard so `saw_error` **hai chiều**; và
`fcm_soc_full_test` đưa chúng vào tier `regression`. Đột biến lật
`expect_error` ⇒ 2 UVM_ERROR, chứng minh DUT thật sự bật `error_o`.

Muốn kiểm thật thì cần một sequence lỗi cố ý (`fcm_soc_eof_error_sequence`) và
một test chấp nhận `error_o` là kết quả ĐÚNG — hiện `fcm_soc_scoreboard` coi
mọi `saw_error` là `UVM_ERROR`, nên cần thêm trường "kỳ vọng lỗi" vào
transaction trước đã.

---

## 6. Việc nên làm tiếp, theo thứ tự

| # | Việc | Lý do | Chi phí |
| --- | --- | --- | --- |
| 1 | ~~Đếm beat `pixel_valid && pixel_ready`~~ | **ĐÃ LÀM** — R-SOC-6 | — |
| 2 | ~~`fcm_soc_eof_error_sequence` + trường "kỳ vọng lỗi"~~ | **ĐÃ LÀM** — R-SOC-5a/5b, trong tier `regression` | — |
| 3 | Tách stimulus / observed / prediction thành ba kiểu transaction | độ rõ ràng (§3) | lớn |
| 4 | Lấy stimulus từ input monitor ở mức IP | chẩn đoán, không phải phát hiện (§1) | lớn |

Mục 1 và 2 đáng làm; mục 3 và 4 chỉ nên làm khi có nhu cầu kéo theo, không
phải vì tài liệu review nói vậy.
