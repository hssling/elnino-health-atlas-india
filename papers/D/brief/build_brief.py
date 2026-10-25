"""Render the Paper D policy brief: policy_brief.md -> policy_brief.docx (pandoc) -> policy_brief.pdf (Word).

    python papers/D/brief/build_brief.py        (from <repo>)

pandoc writes the docx with a compact reference document built here from pandoc's default (Arial 10.5 pt, 1.7 cm
margins, A4), so the brief fits two pages. pandoc has no PDF engine on this machine (no LaTeX, wkhtmltopdf or
WeasyPrint), so the PDF is exported from the docx by Microsoft Word through docx2pdf (LibreOffice soffice as fallback; the
build stops if neither exists, so a stale PDF is never left silently). The page count is checked:
the build stops if the PDF has more than two pages.
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

BRIEF = Path(__file__).resolve().parent
MD = BRIEF / "policy_brief.md"
DOCX = BRIEF / "policy_brief.docx"
PDF = BRIEF / "policy_brief.pdf"
MAX_PAGES = 2


def reference_docx(path: Path) -> Path:
    from docx import Document
    from docx.oxml.ns import qn
    from docx.shared import Cm, Pt, RGBColor
    subprocess.run(["pandoc", "-o", str(path), "--print-default-data-file", "reference.docx"], check=True)
    doc = Document(str(path))
    for sec in doc.sections:
        sec.page_width, sec.page_height = Cm(21.0), Cm(29.7)
        sec.left_margin = sec.right_margin = Cm(1.7)
        sec.top_margin = sec.bottom_margin = Cm(1.5)

    def font(style, size, bold=None, color=None):
        rpr = style.element.get_or_add_rPr()
        rf = rpr.get_or_add_rFonts()
        for a in ("w:asciiTheme", "w:hAnsiTheme", "w:eastAsiaTheme", "w:cstheme"):
            if rf.get(qn(a)) is not None:
                del rf.attrib[qn(a)]
        for a in ("w:ascii", "w:hAnsi", "w:cs", "w:eastAsia"):
            rf.set(qn(a), "Arial")
        style.font.size = Pt(size)
        if bold is not None:
            style.font.bold = bold
        style.font.color.rgb = RGBColor(0x1D, 0x1F, 0x22) if color is None else color
    names = {s.name for s in doc.styles}
    for name in ("Normal", "Body Text", "First Paragraph", "Compact"):
        if name in names:
            st = doc.styles[name]
            font(st, 10.5)
            st.paragraph_format.space_before = Pt(0)
            st.paragraph_format.space_after = Pt(3)
            st.paragraph_format.line_spacing = 1.05
    for name, size in (("Title", 15), ("Subtitle", 10), ("Heading 2", 11.5)):
        if name in names:
            st = doc.styles[name]
            font(st, size, bold=name != "Subtitle", color=RGBColor(0x0B, 0x5F, 0x8A) if name != "Subtitle" else None)
            st.paragraph_format.space_before = Pt(6 if name == "Heading 2" else 0)
            st.paragraph_format.space_after = Pt(3)
            st.paragraph_format.alignment = 0
    doc.save(str(path))
    return path


def to_pdf(docx: Path, pdf: Path) -> None:
    """docx -> PDF with Microsoft Word (docx2pdf, Windows/macOS), else LibreOffice (`soffice --headless
    --convert-to pdf`). With neither, stop with an error rather than leave a stale committed PDF (review M7);
    tests/papers/test_d_atlas.py also checks that the PDF's numbers equal the markdown's."""
    try:
        from docx2pdf import convert
        convert(str(docx), str(pdf))
        return
    except ImportError:
        pass
    soffice = shutil.which("soffice") or shutil.which("libreoffice")
    if soffice:
        subprocess.run([soffice, "--headless", "--convert-to", "pdf", "--outdir", str(pdf.parent), str(docx)],
                       check=True)
        return
    sys.exit("no docx-to-PDF converter (Microsoft Word via docx2pdf, or LibreOffice soffice): "
             f"{pdf.name} NOT rebuilt and is now stale")


def page_count(pdf: Path) -> int:
    from pypdf import PdfReader
    return len(PdfReader(str(pdf)).pages)


def build() -> dict:
    if not shutil.which("pandoc"):
        sys.exit("pandoc not found")
    with tempfile.TemporaryDirectory() as tmp:
        ref = reference_docx(Path(tmp) / "reference_brief.docx")
        subprocess.run(["pandoc", str(MD), "-f", "markdown", "-t", "docx", "--reference-doc", str(ref),
                        "-o", str(DOCX)], check=True)
    to_pdf(DOCX, PDF)
    n = page_count(PDF)
    print(f"{PDF.name}: {n} page(s)")
    if n > MAX_PAGES:
        sys.exit(f"policy brief is {n} pages; the limit is {MAX_PAGES}")
    return {"docx": DOCX, "pdf": PDF, "pages": n}


if __name__ == "__main__":
    build()
