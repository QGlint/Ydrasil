import tkinter as tk
from tkinter import ttk


def _bit_width(value: int) -> int:
	return max(1, value.bit_length())


def _leading_zeros(value: int, width: int) -> int:
	if width <= 0:
		return 0
	if value == 0:
		return width
	return max(0, width - value.bit_length())


def _format_bin(value: int, width: int) -> str:
	mask = (1 << width) - 1
	return format(value & mask, f"0{width}b")


def non_restoring_division(
	dividend: int,
	divisor: int,
	width: int | None = None,
	signed_mode: bool = False,
):
	if divisor == 0:
		raise ValueError("divisor cannot be zero")
	if not signed_mode and (dividend < 0 or divisor < 0):
		raise ValueError("unsigned mode does not allow negative values")

	abs_dividend = abs(dividend)
	abs_divisor = abs(divisor)

	if width is None:
		base_width = max(_bit_width(abs_dividend), _bit_width(abs_divisor))
		if signed_mode:
			base_width += 1
		n = base_width
	else:
		n = width

	if n <= 0:
		raise ValueError("bit width must be positive")

	leading_diff = _leading_zeros(abs_divisor, n) - _leading_zeros(abs_dividend, n)
	shift = max(0, leading_diff)
	if shift > 0:
		normalized_dividend = abs_dividend << shift
		normalize_action = f"Normalize (display only): dividend << {shift}"
	else:
		normalized_dividend = abs_dividend
		normalize_action = "Normalize (display only): none"

	q = 0
	a = abs_dividend
	m = abs_divisor

	steps = []
	steps.append(
		{
			"step": 0,
			"a": a,
			"q": normalized_dividend & ((1 << n) - 1),
			"action": normalize_action,
			"q_bit": "-",
			"m": m << max(0, _bit_width(abs(a)) - _bit_width(m)),
		}
	)
	if abs_divisor > abs_dividend:
		quotient = 0
		remainder = abs_dividend
		if signed_mode and dividend < 0:
			remainder = -remainder
		return {
			"width": n,
			"quotient": -quotient if signed_mode and (dividend < 0) ^ (divisor < 0) else quotient,
			"remainder": remainder,
			"abs_quotient": quotient,
			"abs_remainder": abs(remainder),
			"normalize_shift": shift,
			"normalize_action": normalize_action,
			"normalized_dividend": normalized_dividend,
			"iter_count": 1,
			"steps": steps,
			"signed": signed_mode,
		}

	iter_count = shift + 1
	for i in range(iter_count):
		k = shift - i
		m_shift = m << k
		if a >= 0:
			a = a - m_shift
			action = f"A = A - (M << {k})"
		else:
			a = a + m_shift
			action = f"A = A + (M << {k})"

		if a >= 0:
			q = q | (1 << k)
			q_bit = "1"
		else:
			q_bit = "0"

		steps.append(
			{
				"step": i + 1,
				"a": a,
				"q": q,
				"action": action,
				"q_bit": q_bit,
				"m": m_shift,
			}
		)

	if a < 0:
		a = a + m

	quotient = q
	remainder = a
	if signed_mode:
		if (dividend < 0) ^ (divisor < 0):
			quotient = -quotient
		if dividend < 0:
			remainder = -remainder

	return {
		"width": n,
		"quotient": quotient,
		"remainder": remainder,
		"abs_quotient": q,
		"abs_remainder": a,
		"normalize_shift": shift,
		"normalize_action": normalize_action,
		"normalized_dividend": normalized_dividend,
		"iter_count": iter_count,
		"steps": steps,
		"signed": signed_mode,
	}


def srt_radix4_division(
	dividend: int,
	divisor: int,
	width: int | None = None,
	signed_mode: bool = False,
):
	if divisor == 0:
		raise ValueError("divisor cannot be zero")
	if not signed_mode and (dividend < 0 or divisor < 0):
		raise ValueError("unsigned mode does not allow negative values")

	abs_dividend = abs(dividend)
	abs_divisor = abs(divisor)

	if width is None:
		base_width = max(_bit_width(abs_dividend), _bit_width(abs_divisor))
		if signed_mode:
			base_width += 1
		n = base_width
	else:
		n = width

	if n <= 0:
		raise ValueError("bit width must be positive")

	# Radix-4 digit recurrence (non-redundant) for stable results.
	# Convert dividend to base-4 digits from MSB.
	tmp = abs_dividend
	if tmp == 0:
		digits = [0]
	else:
		digits = []
		while tmp > 0:
			digits.append(tmp & 0x3)
			tmp >>= 2
		digits.reverse()

	steps = []
	q = 0
	rem = 0
	for i, digit in enumerate(digits, start=1):
		rem = (rem << 2) + digit
		q_digit = rem // abs_divisor
		if q_digit > 3:
			q_digit = 3
		rem = rem - q_digit * abs_divisor
		q = (q << 2) + q_digit

		steps.append(
			{
				"step": i,
				"p": rem,
				"d": abs_divisor,
				"q_digit": int(q_digit),
				"q": q,
				"in_digit": digit,
			}
		)

	quot = q

	if signed_mode:
		if (dividend < 0) ^ (divisor < 0):
			quot = -quot
		if dividend < 0:
			rem = -rem

	return {
		"width": n,
		"quotient": quot,
		"remainder": rem,
		"steps": steps,
		"digit_count": len(steps),
		"signed": signed_mode,
		"scaled_divisor": abs_divisor,
		"scaled_dividend": abs_dividend,
		"scale_shift": 0,
	}


class DivisionGui:
	def __init__(self, root: tk.Tk) -> None:
		self.root = root
		self.root.title("Non-Restoring Division Simulator")

		self.dividend_var = tk.StringVar()
		self.divisor_var = tk.StringVar()
		self.width_var = tk.StringVar()
		self.mode_var = tk.StringVar(value="unsigned")
		self.status_var = tk.StringVar(value="Ready")

		self._build_ui()

	def _build_ui(self) -> None:
		main = ttk.Frame(self.root, padding=12)
		main.grid(row=0, column=0, sticky="nsew")
		self.root.columnconfigure(0, weight=1)
		self.root.rowconfigure(0, weight=1)

		inputs = ttk.LabelFrame(main, text="Inputs", padding=10)
		inputs.grid(row=0, column=0, sticky="ew")
		inputs.columnconfigure(1, weight=1)

		ttk.Label(inputs, text="Dividend (decimal):").grid(row=0, column=0, sticky="w")
		ttk.Entry(inputs, textvariable=self.dividend_var).grid(row=0, column=1, sticky="ew")

		ttk.Label(inputs, text="Divisor (decimal):").grid(row=1, column=0, sticky="w")
		ttk.Entry(inputs, textvariable=self.divisor_var).grid(row=1, column=1, sticky="ew")

		ttk.Label(inputs, text="Bit width (optional):").grid(row=2, column=0, sticky="w")
		ttk.Entry(inputs, textvariable=self.width_var).grid(row=2, column=1, sticky="ew")

		mode_frame = ttk.Frame(inputs)
		mode_frame.grid(row=3, column=0, columnspan=2, sticky="w", pady=(6, 0))
		ttk.Label(mode_frame, text="Mode:").grid(row=0, column=0, sticky="w")
		ttk.Radiobutton(
			mode_frame,
			text="Unsigned",
			value="unsigned",
			variable=self.mode_var,
		).grid(row=0, column=1, sticky="w", padx=(6, 0))
		ttk.Radiobutton(
			mode_frame,
			text="Signed (two's complement)",
			value="signed",
			variable=self.mode_var,
		).grid(row=0, column=2, sticky="w", padx=(6, 0))

		ttk.Button(inputs, text="Simulate", command=self.run).grid(row=4, column=0, columnspan=2, pady=(8, 0))

		self.summary = ttk.Label(main, text="", font=("TkDefaultFont", 10, "bold"))
		self.summary.grid(row=1, column=0, sticky="w", pady=(10, 6))

		self.srt_summary = ttk.Label(main, text="")
		self.srt_summary.grid(row=2, column=0, sticky="w", pady=(0, 6))

		self.help_text = ttk.Label(
			main,
			text=(
				"A is the remainder register; final remainder is A (after correction if A < 0). "
				"Final quotient is Q. Negative A appears as leading 1s (two's complement)."
			),
		)
		self.help_text.grid(row=3, column=0, sticky="w", pady=(0, 6))

		self.table = ttk.Treeview(
			main,
			columns=("step", "a", "m", "action", "adec", "mdec"),
			show="headings",
			height=12,
		)
		self.table.grid(row=4, column=0, sticky="nsew")
		main.rowconfigure(4, weight=1)

		self.table.heading("step", text="Step")
		self.table.heading("a", text="A (bin)")
		self.table.heading("m", text="M (bin)")
		self.table.heading("action", text="Action")
		self.table.heading("adec", text="A (dec)")
		self.table.heading("mdec", text="M (dec)")

		self.table.column("step", width=60, anchor="center")
		self.table.column("a", width=180, anchor="center")
		self.table.column("m", width=180, anchor="center")
		self.table.column("action", width=160, anchor="center")
		self.table.column("adec", width=80, anchor="center")
		self.table.column("mdec", width=80, anchor="center")

		self.srt_table = ttk.Treeview(
			main,
			columns=("step", "p", "d", "qd", "pdec"),
			show="headings",
			height=8,
		)
		self.srt_table.grid(row=5, column=0, sticky="nsew", pady=(6, 0))
		main.rowconfigure(5, weight=1)

		self.srt_table.heading("step", text="SRT Step")
		self.srt_table.heading("p", text="P (bin)")
		self.srt_table.heading("d", text="D (bin)")
		self.srt_table.heading("qd", text="q_digit")
		self.srt_table.heading("pdec", text="P (dec)")

		self.srt_table.column("step", width=70, anchor="center")
		self.srt_table.column("p", width=180, anchor="center")
		self.srt_table.column("d", width=180, anchor="center")
		self.srt_table.column("qd", width=70, anchor="center")
		self.srt_table.column("pdec", width=90, anchor="center")

		ttk.Label(main, textvariable=self.status_var).grid(row=6, column=0, sticky="w", pady=(8, 0))

	def run(self) -> None:
		self._clear_table()
		try:
			dividend = int(self.dividend_var.get().strip(), 10)
			divisor = int(self.divisor_var.get().strip(), 10)
			width_text = self.width_var.get().strip()
			width = int(width_text, 10) if width_text else None
			signed_mode = self.mode_var.get() == "signed"

			if width is not None and width <= 0:
				raise ValueError("bit width must be positive")

			result = non_restoring_division(dividend, divisor, width, signed_mode=signed_mode)
			srt_result = srt_radix4_division(dividend, divisor, width, signed_mode=signed_mode)
		except ValueError as exc:
			self.status_var.set(f"Error: {exc}")
			self.summary.config(text="")
			self.srt_summary.config(text="")
			return

		n = result["width"]
		q = result["quotient"]
		r = result["remainder"]
		normalized_dividend = result["normalized_dividend"]

		shift = n - _bit_width(abs(divisor))
		shift = max(0, shift)
		aligned_divisor = abs(divisor) << shift

		r_bin = _format_bin(r, n + 1)
		q_bin = _format_bin(q, n)

		iter_count = result.get("iter_count", n)
		self.summary.config(
			text=(
				f"Aligned M = {aligned_divisor} (bin { _format_bin(aligned_divisor, n) }), "
				f"Normalized dividend = {normalized_dividend}, "
				f"Cycles = {iter_count}, "
				f"Quotient = {q} (bin { q_bin }), "
				f"Remainder = {r} (bin { r_bin })"
			)
		)

		srt_q = srt_result["quotient"]
		srt_r = srt_result["remainder"]
		srt_cycles = srt_result["digit_count"]
		srt_r_bin = _format_bin(srt_r, n + 1)
		srt_q_bin = _format_bin(srt_q, n)
		self.srt_summary.config(
			text=(
				f"SRT radix-4: Cycles = {srt_cycles}, "
				f"Quotient = {srt_q} (bin { srt_q_bin }), "
				f"Remainder = {srt_r} (bin { srt_r_bin })"
			)
		)

		for step in result["steps"]:
			a_val = step["a"]
			m_val = step.get("m", abs(divisor))
			self.table.insert(
				"",
				"end",
				values=(
					step["step"],
					_format_bin(a_val, n + 1),
					_format_bin(m_val, n + 1),
					step["action"],
					a_val,
					m_val,
				),
			)

		for step in srt_result["steps"]:
			p_val = step["p"]
			d_val = step["d"]
			self.srt_table.insert(
				"",
				"end",
				values=(
					step["step"],
					_format_bin(p_val, n + 2),
					_format_bin(d_val, n + 2),
					step["q_digit"],
					p_val,
				),
			)

		self.status_var.set("Done")

	def _clear_table(self) -> None:
		for row in self.table.get_children():
			self.table.delete(row)
		for row in self.srt_table.get_children():
			self.srt_table.delete(row)


def main() -> None:
	root = tk.Tk()
	app = DivisionGui(root)
	root.minsize(820, 420)
	root.mainloop()


if __name__ == "__main__":
	main()
