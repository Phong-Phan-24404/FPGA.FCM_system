# Case số học — chính sách làm tròn của accumulator

> **Đính chính 2026-10-23.** Bản đầu của tài liệu này mô tả đây là "lỗi RTL
> lệch khỏi contract". **Sai.** Đối chiếu lại contract đương thời cho thấy RTL
> Q16.16 cài đặt **đúng** contract của nó. Thứ thay đổi là **chính sách**, không
> phải việc tuân thủ. Mục 2 có bằng chứng; mục 6 và 9 đã viết lại theo đó.

Hồ sơ một thay đổi số học thật trong FCM DUT: contract cũ, contract mới, RTL
hai bên, tác động đo được, và vì sao **không testbench nào có thể bắt được nó**.

---

## 1. Tóm tắt

| | |
| --- | --- |
| Module | `fcm_accum_update` — tích luỹ numerator/denominator cho cập nhật tâm cụm |
| Bản chất | **Đổi chính sách làm tròn**, không phải vi phạm contract |
| Vùng | Accumulator scheduling / centroid update |
| Trạng thái cũ | `post_square_shift` — đúng contract Q16.16 đương thời |
| Trạng thái mới | `multiply_before_shift` — profile `precision` của V4 |
| Phát hiện bởi | **Phân tích số học khi thiết kế lại contract cho V4** |
| Testbench có bắt được không | **Không, và về nguyên tắc là không thể** (mục 6) |
| RTL cũ | `backup.zip → backup/04_SoC_fcm_q16_2026-10-20/fcm/fcm_accum_update.sv` |

---

## 2. Hai contract nói gì

### Contract cũ (Q16.16)

`fcm_fixed_point_contract.md` của dự án tiền nhiệm:

> $\text{den}_k = \sum_b \text{count}_b \times W_b$ where the weight factor
> $W_b = u_b^2 \le 1.0$ (**expressed as 65536 in Q16.16**)
>
> $\text{den}_{max} = 230{,}400 \times 65{,}536 = 15{,}099{,}494{,}400$
> → $\lceil \log_2 \rceil = 34$ bits

Phép chứng minh bề rộng này là bằng chứng quyết định. `acc_den` 34 bit **chỉ
đủ nếu `W_b` đã bị cắt về Q16.16 trước khi nhân `count`**. Nếu nhân trước rồi
mới dịch, tích trước dịch cần `230400 × 65536²` ≈ **2⁵⁰**.

Contract cũ vì vậy quy định `post_square_shift`, dù không gọi tên nó.

### Contract mới (V4, profile `precision`)

```
ACCUMULATION_POLICY multiply_before_shift

den_bin = (count * u * u) >> M        # nhân hết rồi mới dịch MỘT lần
num_bin = den_bin * gray              # gray là số nguyên 0..255
```

Chính sách cũ **vẫn còn**, dưới tên profile `compact`:

```
ACCUMULATION_POLICY post_square_shift
```

Hai profile tồn tại song song chính là để so hai chính sách này với nhau.

---

## 3. RTL hai bên

### Cũ — `backup/04_SoC_fcm_q16_2026-10-20/fcm/fcm_accum_update.sv`

```systemverilog
u_square_q      = CENTER_W'((membership_q * membership_q) >>> Q_FRAC);  // cắt về Q16.16
weighted_gray_q = CENTER_W'((u_square_q * gray_q) >>> Q_FRAC);
den_add         = ACC_DEN_W'(bin_count) * ACC_DEN_W'($unsigned(u_square_q));
num_add         = $signed(ACC_NUM_W'(bin_count)) * weighted_gray_q;
```

Khớp contract cũ: `W_b` cắt trước, rồi nhân `count`.

### Mới — `02_FCM_IP/rtl/fcm_accum_update.sv`

```systemverilog
A_IDLE:    square_q       <= SQ_W'(membership_q) * SQ_W'(membership_q);
A_PRODUCT: count_square_q <= CSQ_PROD_W'(count_q) * CSQ_PROD_W'(square_q);   // 50 bit
A_WEIGHT:  den_add_q <= ACC_DEN_W'(count_square_q >> MEMBER_FRAC);           // dịch MỘT lần
           num_add_q <= ACC_NUM_W'(count_square_q >> MEMBER_FRAC) * ACC_NUM_W'(gray_q);
```

`CSQ_PROD_W` = 50 bit là dấu vân tay cấu trúc của chính sách mới — đúng con số
mà phép chứng minh của contract cũ loại trừ.

Việc tách bốn trạng thái là yêu cầu **timing** riêng
(`06_Docs/FCM_IP_50MHZ_AUDIT.md`), không liên quan tới chính sách làm tròn.

---

## 4. Vì sao chính sách cũ kém chính xác hơn

`u²` bị cắt về 16 bit thập phân **trước** khi nhân `count`. `count` lên tới
202 500 ≈ 2¹⁷·⁶. Sai số cắt khoảng 1 ulp do đó bị khuếch đại lên ~2¹⁷·⁶ lần
trước khi vào accumulator.

Trường hợp xấu nhất tường minh: `u` nhỏ ⇒ `(u×u) >> 16 = 0` ⇒ bin đó đóng góp
**đúng bằng không**, bất kể `count` lớn tới đâu.

Chính sách mới giữ nguyên 50 bit cho tới sau khi `count` đã nhân vào, nên sai
số cắt chỉ còn 1 ulp của tổng, không phải 1 ulp bị khuếch đại.

---

## 5. Tác động đo được

> Các log dưới đây là **TÁI HIỆN**, chạy 2026-10-23: đặt lại số học
> `post_square_shift` vào DUT V4 rồi chạy testbench hiện tại, vốn kỳ vọng
> `multiply_before_shift`. Không có log lịch sử nào còn lại. RTL đã khôi phục
> ngay sau đó (mục 7).

**Mức unit** — `tb_fcm_accum_update`:

```
** Fatal: ACCUM FAIL h=202500 g=255 u=255 observed=(0,0) exp=(200921,51234855)
```

`u=255` ⇒ `u² = 65 025` ⇒ `65025 >> 16 = 0`. Một bin 202 500 pixel đóng góp
bằng không, trong khi giá trị đúng là `(200921, 51234855)`.

**Mức hệ thống** — `tb_fcm_core_uvm`:

| Vector | Lệch centroid | `iter_converged` |
| --- | --- | --- |
| `precision/demo_k02` — 250 bin, 9 vòng | **3 LSB** (163870 vs 163873) | đúng |
| `corner/deep_iter/demo_k02` — 8 bin, 160 vòng | **61 LSB** (175848 vs 175787) | **159 vs 160** |

Trên ảnh thật sai số bị trung bình hoá qua 250 bin và chỉ còn ~0,002 % — mọi
phép kiểm dùng ngưỡng đều cho PASS. Trên `deep_iter` chỉ có 8 bin và 160 vòng
lặp, sai số không được trung bình hoá và còn tích luỹ, nên lệch cả số vòng hội
tụ. Đây là lý do `deep_iter` tồn tại.

---

## 6. Vì sao testbench không thể bắt được — hai tầng lý do

**Tầng 1 — contract đương thời quy định chính cách làm đó.** Một testbench
viết trung thực theo contract cũ sẽ tính `count × ((u²)>>16)` và **khớp với
RTL**. Nó PASS, và PASS đó là *đúng*: RTL tuân thủ đặc tả của nó. Không có
"lỗi" nào để bắt.

**Tầng 2 — reference model cũng cài đặt y hệt.**
`reference_model/rtl/stages.py` của dự án tiền nhiệm:

```python
den_add = wrap_unsigned(count * signed_to_unsigned(u2, cfg.center_w), ...)  # u2 đã cắt
num_add = wrap_signed(count * wg, cfg.acc_num_w)                            # wg dịch hai lần
```

Nên kể cả khi contract mơ hồ, hai phía vẫn hội tụ về cùng một cách đọc.

### Bảng quyết định

| Contract | Nguồn giá trị kỳ vọng | Kết quả |
| --- | --- | --- |
| Rõ ràng, đúng | Độc lập với RTL | Bắt được vi phạm |
| Rõ ràng, đúng | Cùng tác giả/cùng cách đọc | Có thể vẫn lọt |
| Mơ hồ | Độc lập | Ra **bất đồng** — tín hiệu để quay lại hỏi spec |
| Mơ hồ hoặc kém tối ưu | Không độc lập | **Xanh và sai** ← tình huống đã xảy ra |

**Và một loại không ô nào bắt được:** contract đúng theo nghĩa nhất quán, nhưng
*chọn sai về mặt số học*. Đó chính là case này. Phát hiện nó cần đối chiếu sơ
đồ fixed-point với thuật toán số thực và lượng hoá sai số khuếch đại — một
phân tích thiết kế, không phải một phép so trong testbench.

---

## 7. Regression sau khi khôi phục

RTL đã khôi phục về bản phát hành (khớp byte-for-byte với `fpga_fcm_v0.4.0`):

```
Invoke-Sim.ps1 -Tier regression -ConfigPath 07_Scripts/config/fcm_ip.psd1 -Clean
  5 / 5 testbench PASS
  fcm_core: 30/30 cases match reference
  [PERF] start->done latency, 4145766 cycles total
```

`4 145 766` chu kỳ khớp mọi lần chạy trước trong cây này.

---

## 8. Những lỗi mà verification THỰC SỰ bắt được

Theo ghi nhận của chính dự án tiền nhiệm
(`backup/pre_restructure_2026-10-19/de_10lite_fcm/docs/known_issues_and_waivers.md`):

| Lỗi | Bắt bởi | Nằm ở |
| --- | --- | --- |
| Assertion dùng `$error`, không làm Icarus fail; regression runner cũng không bắt được chuỗi đó | Debug một testbench mới | Hạ tầng verification |
| `E_INIT_ITER` chỉ cho phép tiền trạng thái `E_IDLE`, thiếu `E_CHECK` | Lộ ngay khi đổi sang `$fatal` | Assertion, vùng điều khiển FSM |
| `ENGINE_RT` là cận **dưới** chứ không phải cận trên của busy→done | Cùng lúc trên | Tham số trong `fcm_pkg` |
| `kit_show_modes_led` hiện chữ số nhãn trước `done_i`, lộ rác LUT | Code review | RTL ngoại vi |

Ba mục đầu nằm ở checker và tham số. **Không có bản ghi nào về một lỗi datapath
(divider, accumulator, centroid update, reseed FSM) bị testbench hoặc assertion
bắt được** trong workspace này.

---

## 9. Case này chứng minh được gì

**KHÔNG chứng minh:**

- khả năng debug từ symptom đỏ ngược về root cause — case này chưa bao giờ đỏ;
- khả năng của testbench trong việc tìm lỗi RTL — ở đây testbench không có vai
  trò nào, và không thể có.

**Chứng minh:**

1. **Đọc được một contract fixed-point ở mức bit và thấy nó chọn sai.** Manh
   mối quyết định là phép chứng minh bề rộng 34 bit — nó *ngụ ý* thứ tự dịch
   mà không nói ra. Đọc được điều đó từ một bất đẳng thức là kỹ năng cụ thể.
2. **Lượng hoá được tác động** thay vì phát biểu định tính: 1 ulp bị khuếch
   đại 2¹⁷·⁶ lần; 3 LSB trên ảnh thật, 61 LSB và lệch một vòng lặp ở corner
   thưa; trường hợp suy biến về 0.
3. **Hiểu giới hạn của chính phương pháp kiểm thử.** Biết được loại lỗi nào
   nằm ngoài tầm với của mọi testbench, và vì sao — đó là nội dung của bảng
   quyết định ở mục 6.
4. **Chuyển kết luận thành quyết định kiến trúc:** reference độc lập, đóng
   băng, sinh từ codebase riêng; và giữ chính sách cũ dưới dạng profile
   `compact` để so sánh được, thay vì xoá đi.

Nếu cần một case chứng minh kỹ năng *debugging* theo nghĩa hẹp, hồ sơ này
không phải thứ đó. Nó chứng minh *numerical design judgement* và hiểu biết về
giới hạn của verification.
