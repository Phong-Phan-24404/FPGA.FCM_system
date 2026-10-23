# SDRAM Image Upload & Board Operation

This directory contains the Quartus System Console scripts for uploading image data into SDRAM over JTAG.

## Workflow

1. Program the FPGA with `DE10_LITE_FCM_SDRAM.sof` on the DE10-Lite board.
2. Ensure the SDRAM initialization is complete (monitored via `sdram_init_guard`).
3. Execute the upload script through Quartus System Console:

```powershell
C:\altera_lite\25.1std\quartus\sopc_builder\bin\system-console.exe --script host\upload_grayscale_mem.tcl
```

The script transmits 50,625 32-bit Avalon-MM words containing the 450×450 grayscale image (`mem/input_grayscale.mem`). The hardware unpacks them into 202,500 8-bit pixels and stores them as 101,250 16-bit words (zero-padded to 101,376 words for SDRAM 256-word burst boundaries).

`LEDR0` turns ON once the frame has committed to SDRAM.

## Running FCM on Board

1. Set `SW[2:0]` to the desired cluster count $K \in [2, 7]$ (`010` = K2, `011` = K3, ..., `111` = K7). `LEDR1` illuminates when armed with a valid $K$.
2. Press `KEY1` to trigger FCM execution.
   - The FPGA clears the 256-bin histogram RAM.
   - Pixels stream from SDRAM into the histogram logic.
   - `LEDR2` illuminates while the FCM pipeline is active (`rUn` shown on HEX displays).
3. Upon completion, `LEDR3` turns ON.
4. Set `SW[5:3]` to inspect centroids 0 through 6. The seven-segment displays show `C i vv`, where `i` is the centroid index and `vv` is the 8-bit hexadecimal grayscale centroid value.
5. Press `KEY0` to soft-reset the FCM state machine. The uploaded image in SDRAM remains preserved, allowing another run with different $K$ without re-uploading.

## Standalone Host Script Verification

To test the script syntax and data-packing logic without physical hardware attached:

```powershell
C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe -t host\tb_upload_grayscale_mem.tcl
```
