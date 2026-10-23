# Onboarding — DV engineer mới

Mục tiêu: trong một buổi, chạy được regression và biết phải sửa file nào.

## 1. Chạy thử trước khi đọc gì

```powershell
# Kiểm tra toolchain (Quartus, Questa, WSL/Python, fileset)
.\07_Scripts\Test-Toolchain.ps1

# Bài nhanh nhất, cả hai tầng
.\03_Verification\regression\scripts\Invoke-Regression.ps1 -Tier smoke
```

Báo cáo gộp nằm ở `03_Verification/regression/reports/<timestamp>/summary.md`.

**Chỉ chạy một sim một lúc.** Questa Intel FPGA Starter Edition có một
license `vsim`. Hai lần chạy song song sẽ hỏng và trông hệt như regression
RTL fail.

Chạy một testbench riêng:

```powershell
.\07_Scripts\questa\Invoke-Sim.ps1 -Top tb_fcm_core_uvm -ConfigPath .\07_Scripts\config\fcm_ip.psd1
```

Chạy nhanh khi debug (một case cho mỗi bộ vector):

```powershell
.\07_Scripts\questa\Invoke-Sim.ps1 -Top tb_fcm_core_uvm -ConfigPath .\07_Scripts\config\fcm_ip.psd1 -UvmTest fcm_core_smoke_test
```

## 2. Đọc theo thứ tự này

1. [verification_plan.md](verification_plan.md) §1–2 — kiểm cái gì và tại sao
   chia ba tầng.
2. [uvm_architecture.md](uvm_architecture.md) §2–3 — cây thư mục và package.
3. [test_traceability.md](test_traceability.md) — testbench nào kiểm gì, và
   requirement nào CHƯA có test.
4. Một đường dẫn trọn vẹn, từ test xuống driver:
   `tests/ip/fcm_core_base_test.svh` → `env/ip/fcm_core_env.svh` →
   `agents/core_agent/fcm_core_agent.svh` → `agents/core_agent/fcm_core_driver.svh`.

Đừng bắt đầu bằng `vectors/`: đó là dữ liệu do `01_Reference` sinh ra, không
phải nguồn để đọc.

## 3. "Tôi muốn sửa X thì sửa file nào"

| Muốn làm | Sửa ở |
| --- | --- |
| Đổi cách lái DUT | `agents/<x>_agent/fcm_<x>_driver.svh` |
| Đổi cách quan sát DUT | `agents/<x>_agent/fcm_<x>_monitor.svh` |
| Đổi điều kiện đúng/sai | `env/<level>/fcm_<x>_scoreboard.svh` |
| Thêm một con số coverage | `env/<level>/fcm_<x>_coverage.svh` |
| Thêm một scenario | `sequences/<level>/` + một test dẫn xuất ở `tests/<level>/` |
| Thêm một assertion | `assertions/<level>/` |
| Thêm class mới vào package | file `.svh` mới **và** một dòng `` `include `` trong `packages/<pkg>.sv` |
| Thêm testbench vào tier | `07_Scripts/config/*.psd1` (`TbSources`, `Tiers`, `UvmTests`) + một dòng ở `test_traceability.md` |
| Đổi đường dẫn vector mặc định | `common/fcm_vector_pkg.sv::FCM_DEFAULT_VECTOR_DIR` (một chỗ duy nhất) |

## 4. Năm cái bẫy đã có người vấp

1. **Thêm `.svh` mà quên `` `include ``.** File không được compile và cũng
   không có lỗi — class cũ vẫn dùng được. Package là nơi khai báo thứ tự, không
   phải thư mục.
2. **Đổi thứ tự `` `include ``.** Đó là thứ tự khai báo của package. Một class
   phải đứng sau mọi class nó tham chiếu.
3. **Quên instantiate module bind SVA trong testbench top.** Assertion im
   lặng và testbench vẫn báo PASS. Xem đầu `assertions/ip/fcm_sva.sv`.
4. **Dùng wildcard `"*"` trong `uvm_config_db::set`.** Nó phát cho mọi
   component có tên field trùng. Luồng cấu hình đi qua config object theo
   đường dẫn instance tường minh — xem
   [uvm_architecture.md](uvm_architecture.md) §5.
5. **Tin một con số "x/y cases match" mà không nhìn `planned`.** Scoreboard
   chỉ so được những cặp nó nhận được; `INCOMPLETE` mới là thứ nói rằng không
   có gì bị mất dọc đường. Xem
   [scoreboard_architecture_review.md](scoreboard_architecture_review.md) §2.
6. **Đọc plusarg trong env, agent hay sequence.** Chỉ `configure()` của base
   test được đọc. Nếu không, "lần chạy này dùng bộ vector nào" sẽ có nhiều câu
   trả lời khác nhau.

## 5. Trước khi gửi pull request

- chạy `Invoke-Regression.ps1 -Tier regression` và đính kèm `summary.md`;
- so với báo cáo của lần chạy trước: số case đã kiểm (`checked == planned`)
  phải không giảm, và không có `UVM_WARNING` coverage mới;
- nếu đổi hành vi scoreboard hoặc SVA, nói rõ requirement nào đổi theo —
  đó là lúc review cần kỹ nhất.
