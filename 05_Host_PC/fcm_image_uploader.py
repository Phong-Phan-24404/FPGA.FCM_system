"""Desktop tool to prepare a grayscale image and upload it to the DE10-Lite."""

from __future__ import annotations

import os
import multiprocessing as mp
import queue
import shutil
import subprocess
import sys
import threading
from pathlib import Path
from typing import Any, Callable

import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext, ttk

from PIL import Image, ImageTk


FRAME_WIDTH = 450
FRAME_HEIGHT = 450
FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT
PREVIEW_SIZE = (420, 420)
SCRIPT_DIR = Path(__file__).resolve().parent
WORKSPACE_DIR = SCRIPT_DIR.parent

# Mô hình tham chiếu của workspace. Preview trên PC phải chạy đúng contract mà
# RTL hiện thực, nếu không nó chỉ là một con số thứ hai không ai đối chiếu được.
REFERENCE_DIR = WORKSPACE_DIR / "01_Reference"
REFERENCE_PROFILE = "precision"
PROJECT_MARKER = Path("host") / "upload_grayscale_mem.tcl"
PROJECT_CANDIDATES = (
    WORKSPACE_DIR / "04_SoC_Intergration" / "de10_lite_fcm_sdram",
    SCRIPT_DIR / "de10_lite_fcm_sdram",
)


def project_dir() -> Path:
    """project_dir: Find and return the path to the FCM project directory."""
    configured = os.environ.get("FCM_PROJECT_DIR")
    candidates = (Path(configured).expanduser(),) if configured else PROJECT_CANDIDATES
    searched: list[str] = []
    for candidate in candidates:
        resolved = candidate.resolve()
        searched.append(str(resolved))
        if (resolved / PROJECT_MARKER).is_file():
            return resolved
    locations = "\n".join(f"  - {path}" for path in searched)
    raise FileNotFoundError(
        "Không tìm thấy project FCM. Giữ thư mục 05_Host_PC cạnh thư mục "
        "04_SoC_Intergration, hoặc đặt biến môi trường FCM_PROJECT_DIR.\n"
        f"Đã tìm tại:\n{locations}"
    )


def mem_file_path() -> Path:
    """mem_file_path: Return the file path for saving input grayscale memory data."""
    return project_dir() / "mem" / "input_grayscale.mem"


def find_system_console() -> Path:
    """find_system_console: Locate and return the Quartus System Console executable path."""
    names = ("system-console.exe", "system-console")
    for name in names:
        found = shutil.which(name)
        if found:
            return Path(found)

    roots = [Path(r) for r in (os.environ.get("ALTERA_ROOT"), r"C:\altera_lite", r"C:\intelFPGA_lite", r"C:\intelFPGA") if r]
    for root in roots:
        if not root.is_dir():
            continue
        for version_dir in sorted(root.iterdir(), reverse=True):
            candidate = version_dir / "quartus" / "sopc_builder" / "bin" / "system-console.exe"
            if candidate.is_file():
                return candidate
    raise FileNotFoundError(
        "Không tìm thấy Quartus System Console. Cài Intel/Altera Quartus Prime, "
        "hoặc thêm thư mục chứa system-console.exe vào PATH."
    )


def crop_square(source: Image.Image) -> Image.Image:
    """crop_square: Crop the center square area of an input image."""
    side = min(source.width, source.height)
    left = (source.width - side) // 2
    top = (source.height - side) // 2
    return source.crop((left, top, left + side, top + side))


def to_luma(cropped: Image.Image) -> Image.Image:
    """to_luma: Convert an image to grayscale using custom integer luma formula."""
    if cropped.mode == "L":
        return cropped.copy()
    rgb = cropped.convert("RGB")
    grayscale = Image.new("L", rgb.size)
    grayscale.putdata([(77 * r + 150 * g + 29 * b + 128) >> 8 for r, g, b in rgb.getdata()])
    return grayscale


def preprocess(source: Image.Image) -> tuple[Image.Image, Image.Image]:
    """preprocess: Preprocess image into aligned grayscale and color frames of target dimensions."""
    cropped = crop_square(source)
    grayscale = to_luma(cropped).resize((FRAME_WIDTH, FRAME_HEIGHT), Image.Resampling.NEAREST)
    color = cropped.convert("RGB").resize((FRAME_WIDTH, FRAME_HEIGHT), Image.Resampling.NEAREST)
    return grayscale, color


def write_mem(image: Image.Image, path: Path) -> None:
    """write_mem: Write grayscale pixel values in hexadecimal format to a memory file."""
    if image.mode != "L" or image.size != (FRAME_WIDTH, FRAME_HEIGHT):
        raise ValueError("Ảnh chưa được resize về đúng 450 x 450 grayscale.")
    pixels = list(image.getdata())
    if len(pixels) != FRAME_PIXELS:
        raise ValueError("Số pixel sau xử lý không đúng 202500.")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="\n") as mem_file:
        mem_file.writelines(f"{value:02X}\n" for value in pixels)


def read_mem(path: Path) -> list[int]:
    """read_mem: Read grayscale byte values from a memory file."""
    try:
        tokens = path.read_text(encoding="ascii").split()
    except OSError as exc:
        raise ValueError(f"Không đọc được {path}: {exc}") from exc
    if len(tokens) != FRAME_PIXELS:
        raise ValueError(f"{path} phải có đúng {FRAME_PIXELS} byte, đang có {len(tokens)}.")
    return [int(token, 16) for token in tokens]


def run_reference_worker(mem_path: str, cluster_count: int, result_queue: mp.Queue) -> None:
    """run_reference_worker: Run the reference FCM algorithm in a separate process and queue results.

    Dùng CHÍNH mô hình tham chiếu của workspace (01_Reference), profile
    'precision' — đúng contract mà RTL trong 02_FCM_IP hiện thực. Trước đây
    chỗ này nạp 04_SoC_Intergration/.../reference_model, một mô hình Q16.16
    riêng; sau khi RTL chuyển sang V4 thì preview và board tính ra hai kết quả
    khác nhau mà không có gì báo hiệu.
    """
    try:
        sys.path.insert(0, str(REFERENCE_DIR))
        import refpkg  # noqa: F401  - đăng ký các package của reference

        from bit_exact_algorithm.fcm import run as run_fixed
        from bit_exact_algorithm.profiles import PROFILES
        from golden_algorithm.fcm import histogram_from_pixels

        profile = PROFILES[REFERENCE_PROFILE]
        pixels = read_mem(Path(mem_path))
        histogram = histogram_from_pixels(pixels)
        result = run_fixed(histogram, cluster_count, profile)

        # Làm tròn Q8.F về mức xám 8-bit, cùng cách mà fcm_stream_pipeline.sv
        # làm trên board.
        half = 1 << (profile.center_frac - 1)
        centers_u8 = [
            min(max((center + half) >> profile.center_frac, 0), 255)
            for center in result.centers_q
        ]
        result_queue.put({
            "kind": "result",
            "clusters": cluster_count,
            "centers_u8": centers_u8,
            "centers_q": result.centers_q,
            "labels_lut": result.lut,
            "converged": result.converged,
            "iter_converged": result.iterations,
        })
    except Exception as exc:
        result_queue.put({"kind": "error", "message": repr(exc)})


class UploaderApp(ttk.Frame):
    def __init__(self, master: tk.Tk) -> None:
        """__init__: Initialize the GUI layout, controls, and application state."""
        super().__init__(master, padding=12)
        self.master = master
        self.source_path: Path | None = None
        self.source_image: Image.Image | None = None
        self.processed_image: Image.Image | None = None
        self.color_image: Image.Image | None = None
        self.preview: ImageTk.PhotoImage | None = None
        self.upload_result: queue.Queue[dict[str, Any]] = queue.Queue()
        self.reference_lines: mp.Queue = mp.Queue()
        self.reference_process: mp.Process | None = None
        self.reference_callback: Callable[[], None] | None = None
        self.upload_running = False
        self.reference_running = False
        self.busy_text = ""
        self.busy_tick = 0
        self.busy_job: str | None = None
        self.centers_u8: list[int] | None = None
        self.centers_q: list[int] | None = None
        self.labels_lut: list[int] | None = None
        self.centers_k: int | None = None
        self.converged = False
        self.iter_converged = 0

        master.title("FCM Image Uploader for DE10-Lite")
        master.minsize(760, 780)
        self.grid(sticky="nsew")
        master.columnconfigure(0, weight=1)
        master.rowconfigure(0, weight=1)
        self.columnconfigure(0, weight=1)
        self.rowconfigure(5, weight=1)

        controls = ttk.Frame(self)
        controls.grid(row=0, column=0, sticky="ew")
        ttk.Button(controls, text="Chọn ảnh...", command=self.choose_image).grid(row=0, column=0, padx=(0, 8))
        self.resize_button = ttk.Button(controls, text="Resize về 450 × 450", command=self.resize_image, state="disabled")
        self.resize_button.grid(row=0, column=1, padx=8)
        self.push_button = ttk.Button(controls, text="Push lên FPGA", command=self.push_image, state="disabled")
        self.push_button.grid(row=0, column=2, padx=8)
        ttk.Separator(controls, orient="vertical").grid(row=0, column=3, sticky="ns", padx=14)
        ttk.Label(controls, text="K:").grid(row=0, column=4, padx=(0, 4))
        self.cluster_var = tk.IntVar(value=7)
        ttk.Spinbox(controls, from_=2, to=7, textvariable=self.cluster_var, width=4, state="readonly").grid(row=0, column=5)
        self.reference_button = ttk.Button(
            controls, text="Tính tâm cụm", command=self.compute_reference, state="disabled")
        self.reference_button.grid(row=0, column=6, padx=(8, 0))

        rebuild = ttk.Frame(self)
        rebuild.grid(row=1, column=0, sticky="ew", pady=(8, 0))
        self.rebuild_gray_button = ttk.Button(
            rebuild, text="Tái tạo ảnh grayscale", command=self.rebuild_grayscale, state="disabled")
        self.rebuild_gray_button.grid(row=0, column=0, padx=(0, 8))
        self.rebuild_color_button = ttk.Button(
            rebuild, text="Tái tạo ảnh màu", command=self.rebuild_color, state="disabled")
        self.rebuild_color_button.grid(row=0, column=1, padx=8)
        self.clear_button = ttk.Button(rebuild, text="Xóa console", command=self.clear_console)
        self.clear_button.grid(row=0, column=2, padx=8)

        status = ttk.Frame(self)
        status.grid(row=2, column=0, sticky="ew", pady=(10, 0))
        status.columnconfigure(1, weight=1)
        self.progress = ttk.Progressbar(status, mode="indeterminate", length=180)
        self.progress.grid(row=0, column=0, sticky="w")
        self.progress.grid_remove()
        self.status_var = tk.StringVar(value="")
        ttk.Label(status, textvariable=self.status_var).grid(row=0, column=1, sticky="w", padx=(10, 0))

        self.info_var = tk.StringVar(value="Chọn một ảnh để bắt đầu.")
        ttk.Label(self, textvariable=self.info_var, justify="left").grid(row=3, column=0, sticky="w", pady=(8, 6))

        self.image_label = ttk.Label(self, anchor="center", text="Chưa có ảnh xem trước", relief="sunken")
        self.image_label.grid(row=4, column=0, sticky="nsew")

        self.log = scrolledtext.ScrolledText(self, height=11, state="disabled", wrap="word")
        self.log.grid(row=5, column=0, sticky="nsew", pady=(10, 0))
        ascii_lines = [
                r"                                  |\    /|               ",
                r"                               ___| \,,/_/               ",
                r"                            ---__/ \/    \               ",
                r"                           __--/     (D)  \              ",
                r"                           _ -/    (_      \             ",
                r"                          // /       \_ /  -\            ",
                r"    __-------_____--___--/           / \_ O o)           ",
                r"   /                                 /   \__/            ",
                "  /            Fuzzy C-Means        /                    ",
                r" ||          )                   \_/\                    ",
                " ||         /              _      /  |                   ",
                r" | |      /--______      ___\    /\  :                   ",
                r" | /   __-  - _/   ------    |  |   \ \                  ",
                r"  |   -  -   /                | |     \ )                ",
                "  |  |   -  |                 | )     | |                ",
                "   | |    | |                 | |    | |                 ",
                "   | |    < |                 | |   |_/                  ",
                r"   < |    /__\                <  \                       ",
                r"   /__\                       /___\                      ",
                ""         
        ]
        self.append_log("\n".join(ascii_lines))


    def append_log(self, text: str) -> None:
        """append_log: Append text to the GUI log output area."""
        self.log.configure(state="normal")
        self.log.insert("end", text)
        self.log.see("end")
        self.log.configure(state="disabled")

    def clear_console(self) -> None:
        """clear_console: Clear all content from the GUI log console."""
        self.log.configure(state="normal")
        self.log.delete("1.0", "end")
        self.log.configure(state="disabled")

    def start_busy(self, text: str) -> None:
        """start_busy: Display progress bar and start busy status animation."""
        self.busy_text = text
        self.busy_tick = 0
        self.status_var.set(text)
        self.progress.grid()
        self.progress.start(60)
        if self.busy_job is None:
            self.animate_busy()

    def animate_busy(self) -> None:
        """animate_busy: Update busy status text with animated dots periodically."""
        self.busy_job = None
        if not (self.upload_running or self.reference_running):
            return
        self.busy_tick = (self.busy_tick + 1) % 4
        self.status_var.set(f"{self.busy_text}{'.' * self.busy_tick}")
        self.busy_job = self.after(350, self.animate_busy)

    def stop_busy(self) -> None:
        """stop_busy: Stop busy status animation and hide the progress bar."""
        if self.upload_running or self.reference_running:
            return
        if self.busy_job is not None:
            self.after_cancel(self.busy_job)
            self.busy_job = None
        self.progress.stop()
        self.progress.grid_remove()
        self.status_var.set("")

    def show_image(self, image: Image.Image) -> None:
        """show_image: Render an image thumbnail onto the preview label."""
        preview = image.copy()
        preview.thumbnail(PREVIEW_SIZE, Image.Resampling.NEAREST)
        self.preview = ImageTk.PhotoImage(preview)
        self.image_label.configure(image=self.preview, text="")

    def refresh_buttons(self) -> None:
        """refresh_buttons: Update enabled/disabled state of GUI buttons based on state."""
        busy = self.upload_running or self.reference_running
        self.resize_button.configure(
            state="normal" if not busy and self.source_image is not None else "disabled")
        ready = not busy and self.processed_image is not None
        for button in (self.push_button, self.reference_button,
                       self.rebuild_gray_button, self.rebuild_color_button):
            button.configure(state="normal" if ready else "disabled")

    def invalidate_results(self) -> None:
        """invalidate_results: Reset stored cluster centers and result metadata."""
        self.centers_u8 = None
        self.centers_q = None
        self.labels_lut = None
        self.centers_k = None
        self.converged = False
        self.iter_converged = 0

    def choose_image(self) -> None:
        """choose_image: Open file dialog to choose an image file and display preview."""
        chosen = filedialog.askopenfilename(
            title="Chọn ảnh đầu vào",
            filetypes=[("Image files", "*.png *.jpg *.jpeg *.bmp *.tif *.tiff"), ("All files", "*.*")],
        )
        if not chosen:
            return
        try:
            with Image.open(chosen) as opened:
                opened.load()
                self.source_image = opened.copy()
            self.source_path = Path(chosen)
        except Exception as exc:
            messagebox.showerror("Không thể mở ảnh", str(exc))
            return
        self.processed_image = None
        self.color_image = None
        self.invalidate_results()
        self.show_image(self.source_image)
        self.refresh_buttons()
        self.info_var.set(f"Ảnh gốc: {self.source_path.name} — {self.source_image.width} × {self.source_image.height} px")
        self.append_log(f"[FILE] {self.source_path.name} — {self.source_image.width} × {self.source_image.height} px\n")

    def resize_image(self) -> None:
        """resize_image: Preprocess current input image into 450x450 grayscale and color formats."""
        if self.source_image is None:
            return
        self.processed_image, self.color_image = preprocess(self.source_image)
        self.invalidate_results()
        self.show_image(self.processed_image)
        self.refresh_buttons()
        self.info_var.set("Ảnh đã xử lý: crop giữa ảnh → grayscale → 450 × 450 (nearest-neighbor).")
        self.append_log("[PREP] Crop giữa → grayscale → 450 × 450 nearest, 202500 pixel.\n")

    def write_current_mem(self) -> Path:
        """write_current_mem: Save processed image to memory file and return path."""
        assert self.processed_image is not None
        path = mem_file_path()
        write_mem(self.processed_image, path)
        return path

    def push_image(self) -> None:
        """push_image: Initiate background thread to upload image data to FPGA board."""
        if self.processed_image is None:
            messagebox.showwarning("Chưa resize", "Hãy bấm Resize trước khi Push.")
            return
        try:
            root = project_dir()
            console = find_system_console()
            script_path = root / "host" / "upload_grayscale_mem.tcl"
            mem_path = self.write_current_mem()
        except Exception as exc:
            messagebox.showerror("Không thể chuẩn bị upload", str(exc))
            return

        self.upload_running = True
        self.refresh_buttons()
        self.start_busy("Đang push ảnh 450×450 lên FPGA")
        self.append_log(f"[PUSH] Bắt đầu upload {mem_path.name} qua JTAG/USB-Blaster...\n")
        threading.Thread(target=self.run_upload, args=(console, script_path, mem_path, root), daemon=True).start()
        self.after(120, self.poll_upload_output)

    def run_upload(self, console: Path, script_path: Path, mem_path: Path, root: Path) -> None:
        """run_upload: Execute System Console command script for memory upload."""
        command = [str(console), "--script", str(script_path), str(mem_path)]
        captured: list[str] = []
        result: dict[str, Any] = {
            "ok": False, "reason": "Upload kết thúc bất thường.", "output": captured}
        try:
            process = subprocess.Popen(
                command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, encoding="utf-8", errors="replace",
            )
            assert process.stdout is not None
            for line in process.stdout:
                captured.append(line.rstrip("\n"))
            code = process.wait()
            if code == 0 and any("PASS" in line for line in captured):
                result = {"ok": True, "reason": "", "output": captured}
            else:
                result = {"ok": False,
                          "reason": f"System Console thoát với mã {code}.",
                          "output": captured}
        except Exception as exc:
            result = {"ok": False,
                      "reason": f"Không chạy được System Console: {exc}",
                      "output": captured}
        finally:
            self.upload_result.put(result)

    def poll_upload_output(self) -> None:
        """poll_upload_output: Check upload result queue and update log output."""
        try:
            result = self.upload_result.get_nowait()
        except queue.Empty:
            self.after(120, self.poll_upload_output)
            return

        self.upload_running = False
        self.stop_busy()
        self.refresh_buttons()
        if result["ok"]:
            self.append_log("[PUSH] SUCCESS — ảnh đã nằm trong SDRAM.\n")
            self.append_log("       Đặt SW[2:0] = K rồi nhấn KEY1 để board chạy FCM.\n")
        else:
            self.append_log(f"[PUSH] FAIL — {result['reason']}\n")
            for line in [text for text in result["output"] if text.strip()][-12:]:
                self.append_log(f"       {line}\n")

    def compute_reference(self) -> None:
        """compute_reference: Trigger reference FCM computation for selected K value."""
        if self.processed_image is None:
            messagebox.showwarning("Chưa resize", "Hãy chọn ảnh và bấm Resize trước.")
            return
        cluster_count = self.cluster_var.get()
        if self.labels_lut is not None and self.centers_k == cluster_count:
            self.append_log(f"[REF] Đã có tâm cụm cho K={cluster_count}, in lại kết quả.\n")
            self.log_centers()
            return
        self.ensure_centers(None)

    def ensure_centers(self, on_ready: Callable[[], None] | None) -> None:
        """ensure_centers: Ensure cluster centers are calculated before running callback."""
        cluster_count = self.cluster_var.get()
        if self.labels_lut is not None and self.centers_k == cluster_count:
            if on_ready is not None:
                on_ready()
            return
        try:
            mem_path = self.write_current_mem()
        except Exception as exc:
            messagebox.showerror("Không thể chuẩn bị dữ liệu", str(exc))
            return
        self.start_reference(mem_path, cluster_count, on_ready)

    def start_reference(self, mem_path: Path, cluster_count: int,
                        on_ready: Callable[[], None] | None = None) -> None:
        """start_reference: Start reference FCM calculation process in background."""
        if self.reference_running:
            return
        self.reference_callback = on_ready
        self.reference_running = True
        self.refresh_buttons()
        self.start_busy(f"Đang tính tâm cụm bằng reference FCM, K={cluster_count}")
        self.append_log(f"[REF] Chạy reference FCM trong process riêng, K={cluster_count}...\n")
        self.reference_process = mp.Process(
            target=run_reference_worker,
            args=(str(mem_path), cluster_count, self.reference_lines),
            daemon=True,
        )
        self.reference_process.start()
        self.after(100, self.poll_reference_output)

    def poll_reference_output(self, grace: int = 0) -> None:
        """poll_reference_output: Poll output queue from reference FCM process."""
        try:
            message = self.reference_lines.get_nowait()
        except queue.Empty:
            alive = self.reference_process is not None and self.reference_process.is_alive()
            if alive or grace < 5:
                self.after(100, lambda: self.poll_reference_output(0 if alive else grace + 1))
            else:
                self.finish_reference("[REF] FAIL — kết thúc mà không trả về kết quả.\n")
            return

        if message["kind"] == "error":
            self.finish_reference(f"[REF] FAIL — {message['message']}\n")
            return

        self.centers_u8 = message["centers_u8"]
        self.centers_q = message["centers_q"]
        self.labels_lut = message["labels_lut"]
        self.centers_k = message["clusters"]
        self.converged = message["converged"]
        self.iter_converged = message["iter_converged"]
        self.finish_reference(None, ok=True)
        self.log_centers()

    def finish_reference(self, message: str | None, ok: bool = False) -> None:
        """finish_reference: Clean up reference process state and invoke callback if successful."""
        if message:
            self.append_log(message)
        if self.reference_process is not None:
            self.reference_process.join(timeout=0.1)
            self.reference_process = None
        callback = self.reference_callback
        self.reference_callback = None
        self.reference_running = False
        self.stop_busy()
        self.refresh_buttons()
        if ok and callback is not None:
            callback()

    def log_centers(self) -> None:
        """log_centers: Format and print calculated cluster centers to log console."""
        assert self.centers_u8 is not None and self.centers_q is not None
        self.append_log(f"[REF] SUCCESS — tâm cụm cuối, K={self.centers_k}:\n")
        for index, (center_u8, center_q) in enumerate(zip(self.centers_u8, self.centers_q)):
            self.append_log(
                f"       C{index} = {center_u8:02X}  ({center_u8:3d} dec, Q8.12: {center_q})\n"
            )
        self.append_log(
            f"       Converged: {int(self.converged)}, iteration đầu tiên: {self.iter_converged:02d}\n"
            "       Đối chiếu: đặt SW[5:3] = chỉ số C muốn xem trên board.\n"
        )

    def label_and_quantize(self) -> tuple[list[int], list[int]]:
        """label_and_quantize: Map pixel memory bytes to cluster labels and center values."""
        assert self.labels_lut is not None and self.centers_u8 is not None
        pixels = read_mem(mem_file_path())
        labels = [self.labels_lut[value] for value in pixels]
        return labels, [self.centers_u8[label] for label in labels]

    def log_label_counts(self, labels: list[int]) -> None:
        """log_label_counts: Count and log pixel allocation for each cluster center."""
        assert self.centers_u8 is not None and self.centers_k is not None
        for index in range(self.centers_k):
            self.append_log(
                f"       C{index} = {self.centers_u8[index]:02X}: {labels.count(index):6d} pixel\n"
            )

    def rebuild_grayscale(self) -> None:
        """rebuild_grayscale: Trigger reconstruction of grayscale image using cluster centers."""
        if self.processed_image is None:
            return
        self.ensure_centers(self.render_grayscale)

    def render_grayscale(self) -> None:
        """render_grayscale: Render and display reconstructed grayscale image."""
        try:
            labels, quantized = self.label_and_quantize()
        except Exception as exc:
            messagebox.showerror("Không thể tái tạo ảnh", str(exc))
            return
        result = Image.new("L", (FRAME_WIDTH, FRAME_HEIGHT))
        result.putdata(quantized)
        self.show_image(result)
        self.info_var.set(
            f"Ảnh grayscale tái tạo: mỗi pixel thay bằng centroid gần nhất (K={self.centers_k})."
        )
        self.append_log(
            f"[GRAY] Tái tạo từ .mem + {self.centers_k} tâm cụm (khoảng cách ngắn nhất, Q8.12):\n"
        )
        self.log_label_counts(labels)

    def rebuild_color(self) -> None:
        """rebuild_color: Trigger reconstruction of color image using YCbCr color space."""
        if self.color_image is None:
            return
        self.ensure_centers(self.render_color)

    def render_color(self) -> None:
        """render_color: Render and display reconstructed color image keeping original chroma."""
        if self.color_image is None:
            return
        try:
            labels, quantized = self.label_and_quantize()
        except Exception as exc:
            messagebox.showerror("Không thể tái tạo ảnh", str(exc))
            return

        _luma, blue_diff, red_diff = self.color_image.convert("YCbCr").split()
        value = Image.new("L", (FRAME_WIDTH, FRAME_HEIGHT))
        value.putdata(quantized)
        result = Image.merge("YCbCr", (value, blue_diff, red_diff)).convert("RGB")

        self.show_image(result)
        self.info_var.set(
            f"Ảnh màu tái tạo: giữ Cb/Cr của ảnh sau resize, Y = {self.centers_k} mức FCM."
        )
        self.append_log(
            f"[COLOR] Tái tạo YCbCr: Y = {self.centers_k} mức FCM, Cb/Cr giữ nguyên:\n"
        )
        self.log_label_counts(labels)


def main() -> None:
    """main: Entry point to check requirements and launch the GUI application."""
    try:
        project_dir()
    except FileNotFoundError as exc:
        root = tk.Tk()
        root.withdraw()
        messagebox.showerror("FCM Image Uploader", str(exc))
        root.destroy()
        raise SystemExit(1)
    root = tk.Tk()
    UploaderApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
