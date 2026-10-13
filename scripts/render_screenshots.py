"""
Renders the raw psql text output captured in screenshots/*_output.txt into
clean terminal-style PNG images for the README. This is real output from
the live database, not fabricated numbers - just styled for readability.
"""
import matplotlib.pyplot as plt
from pathlib import Path

SS_DIR = Path(__file__).resolve().parent.parent / "screenshots"

FILES = {
    "q01_output.txt": "Q1 — Top 10 Best-Selling Products by Revenue",
    "q03_output.txt": "Q3 — Month-over-Month Revenue Growth % (LAG window function)",
    "q17_output.txt": "Q17 — Repeat-Purchase Rate by First-Purchase Cohort (CTEs, FILTER)",
    "q27_output.txt": "Q27 — Second-Best-Selling Product per Category (DENSE_RANK)",
}

for fname, title in FILES.items():
    path = SS_DIR / fname
    text = path.read_text()
    lines = [l for l in text.split("\n") if l.strip() != "" and "rows)" not in l]

    fig_height = 0.32 * len(lines) + 0.9
    fig, ax = plt.subplots(figsize=(11, fig_height))
    ax.axis("off")
    fig.patch.set_facecolor("#1e1e1e")
    ax.set_facecolor("#1e1e1e")

    ax.text(0.01, 1.0, f"psql (16.x)  retail_analytics=#", fontsize=10,
             color="#8fce00", family="monospace", va="top", transform=ax.transAxes)
    ax.text(0.01, 0.93, title, fontsize=11, color="#61afef", weight="bold",
             family="monospace", va="top", transform=ax.transAxes)

    body = "\n".join(lines)
    ax.text(0.01, 0.82, body, fontsize=10, color="#d4d4d4", family="monospace",
             va="top", transform=ax.transAxes)

    out_path = SS_DIR / fname.replace("_output.txt", ".png")
    plt.savefig(out_path, dpi=150, facecolor=fig.get_facecolor(), bbox_inches="tight", pad_inches=0.25)
    plt.close(fig)
    print(f"wrote {out_path}")
