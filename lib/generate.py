# /// script
# requires-python = ">=3.12"
# dependencies = ["openpyxl==3.1.5", "python-docx==1.2.0", "python-pptx==1.0.2"]
# ///
"""Generate the demo dataset's four authored office files.

The files are a fictional unit's working share for a training exercise:
opord-26-03-v1.docx, a draft operation order; opord-26-03-v2.docx, its revision;
mission-analysis-brief.pptx, a mission analysis brief; and collection-plan.xlsx,
an information collection plan. The unit, places, and events in them are
fictional.

usage: uv run --script lib/generate.py <outdir>

Each file is written under its output name into outdir, which is created when
missing. Every core property (title, creator, created, modified, last modified
by, revision) is fixed, and each package is rewritten with its entries in the
library's order, stored uncompressed, under one fixed timestamp, so every run
writes the same bytes on any machine. Run it through `dataset source generate`.
"""

import datetime
import pathlib
import sys
import zipfile

import docx
import openpyxl
import pptx
from docx.shared import Pt
from openpyxl.styles import Alignment, Font
from openpyxl.writer.excel import ExcelWriter
from pptx.util import Inches
from pptx.util import Pt as PptxPt

MARKING = "UNCLASSIFIED // FOR TRAINING"
CREATOR = "TF LANTERN S3 Plans"
ZIP_TIME = (2026, 3, 2, 8, 0, 0)


def moment(day: int, hour: int) -> datetime.datetime:
    """A fixed moment in March 2026, the exercise's planning month."""
    return datetime.datetime(2026, 3, day, hour, 0, 0)


def set_core(properties, title: str, created: datetime.datetime, modified: datetime.datetime, revision: int) -> None:
    """Fixes a python-docx or python-pptx document's core properties."""
    properties.title = title
    properties.author = CREATOR
    properties.last_modified_by = CREATOR
    properties.created = created
    properties.modified = modified
    properties.revision = revision


def opord(version: int) -> list[tuple[str, list[str]]]:
    """OPORD 26-03's five paragraphs, as (heading, paragraphs), in the version given, 1 or 2."""
    v2 = version == 2
    return [
        (
            "1. Situation",
            [
                "a. Area of interest. The exercise area is the fictional coastal province of Varrow, "
                "including the port city of Kestrel Bay and the inland market towns along Route AMBER.",
                "b. Area of operations. Task Force LANTERN's area of operations is Kestrel Bay and the "
                "districts within 20 kilometers of it.",
                "c. Enemy forces. The opposing force, the Varrow Liberation Front (VLF), runs a network of "
                "social media accounts and two local radio programs that spread false reports of port "
                "closures and food shortages. Its most likely course of action is to amplify those reports "
                "during the harbor festival to draw crowds away from distribution points.",
                "d. Friendly forces. 3rd Brigade, the higher headquarters, conducts stability operations in "
                "Varrow. The Provincial Information Office publishes official notices in print and online.",
                "e. Civil considerations. Most residents get news from two radio stations and a community "
                "message board. Trust in provincial notices is moderate and falls after each false report.",
            ],
        ),
        (
            "2. Mission",
            [
                "Task Force LANTERN conducts information operations in Kestrel Bay "
                + (
                    "from 14 March to 28 March 2026"
                    if v2
                    else "from 16 March to 27 March 2026"
                )
                + " to counter VLF false reporting and keep residents informed of verified distribution "
                "points, in order to sustain public confidence in provincial services during the festival.",
            ],
        ),
        (
            "3. Execution",
            [
                "a. Commander's intent. Residents of Kestrel Bay can tell verified notices from false "
                "reports, and turnout at distribution points stays at or above its pre-festival level. "
                "The task force answers each false report within six hours with a verified correction.",
                "b. Concept of operations. Phase I (Assess) maps the VLF's channels and audiences. Phase II "
                "(Inform) pushes verified notices through the radio stations and the message board. "
                "Phase III (Transition) hands monitoring to the Provincial Information Office.",
                "c. Tasks to subordinate units.",
                "(1) Team ANVIL: monitor open-source channels in Kestrel Bay and report each new false "
                "report to the task force operations center "
                + ("within two hours of first sighting." if v2 else "within four hours of first sighting."),
                "(2) Team BEACON: "
                + (
                    "prepare corrections with the Provincial Information Office and deliver them through "
                    "both radio stations and the community message board."
                    if v2
                    else "prepare corrections and deliver them through both radio stations."
                ),
                "(3) Analysis cell: produce a daily assessment of the VLF's reach and of resident "
                "sentiment, due to the commander by 1800 each day.",
                "d. Coordinating instructions. Commander's critical information requirements are listed "
                "in the collection plan. "
                + (
                    "Rehearsal is at 1000 on 12 March at the task force operations center."
                    if v2
                    else "Rehearsal is at 1400 on 14 March at the task force operations center."
                ),
            ],
        ),
        (
            "4. Sustainment",
            [
                "a. Logistics. Teams draw radio airtime and printing support through the brigade "
                "support operations office. Each team carries three days of supplies.",
                "b. Personnel. Teams report personnel status to the S1 daily by 0900.",
                "c. Medical. The brigade aid station in Kestrel Bay supports all teams.",
            ],
        ),
        (
            "5. Command and Signal",
            [
                "a. Command. The task force commander is at the operations center in Kestrel Bay. "
                "The deputy commander is the alternate.",
                "b. Signal. "
                + (
                    "Primary communication is the task force secure chat; alternate is FM radio on the "
                    "task force net; contingency is cell phone; emergency is runner. Brevity codes change "
                    "daily at 0001."
                    if v2
                    else "Primary communication is FM radio on the task force net; alternate is cell "
                    "phone; emergency is runner."
                ),
            ],
        ),
    ]


def write_opord(path: pathlib.Path, version: int) -> None:
    """Writes OPORD 26-03 in the version given as a Word document."""
    doc = docx.Document()
    section = doc.sections[0]
    section.header.paragraphs[0].text = MARKING
    section.footer.paragraphs[0].text = MARKING
    doc.styles["Normal"].font.size = Pt(11)
    doc.add_paragraph("Copy 1 of 4 copies\nTask Force LANTERN\nKestrel Bay, Varrow\n"
                      + ("10 March 2026" if version == 2 else "6 March 2026"))
    doc.add_heading(
        "OPERATION ORDER 26-03 (EXERCISE QUIET HARBOR)" + (" REVISION 1" if version == 2 else " DRAFT"),
        level=1,
    )
    doc.add_paragraph("References: Map, Varrow Province, 1:50,000; 3rd Brigade OPORD 26-01.")
    doc.add_paragraph("Time zone used throughout the order: local.")
    for heading, paragraphs in opord(version):
        doc.add_heading(heading, level=2)
        for text in paragraphs:
            doc.add_paragraph(text)
    doc.add_paragraph("ACKNOWLEDGE.")
    doc.add_paragraph("OFFICIAL: TF LANTERN S3")
    doc.add_paragraph("Annexes: A (Task Organization), B (Intelligence), C (Collection Plan).")
    set_core(
        doc.core_properties,
        f"OPORD 26-03 v{version}",
        moment(6, 9),
        moment(10, 16) if version == 2 else moment(6, 17),
        version,
    )
    doc.save(path)


BRIEF = [
    (
        "Higher Headquarters Mission and Intent",
        [
            "3rd Brigade conducts stability operations in Varrow Province to maintain public order.",
            "Intent: provincial services keep running and residents trust official notices.",
            "Our role: counter false reporting in Kestrel Bay during the harbor festival.",
        ],
    ),
    (
        "Facts and Assumptions",
        [
            "Fact: two radio stations and one message board reach most residents.",
            "Fact: the VLF posted 14 false port-closure reports in February.",
            "Assumption: the VLF will increase posting during the festival.",
            "Assumption: the Provincial Information Office will co-sign corrections.",
        ],
    ),
    (
        "Specified Tasks",
        [
            "Counter VLF false reporting in Kestrel Bay.",
            "Keep residents informed of verified distribution points.",
            "Hand monitoring to the Provincial Information Office by 28 March.",
        ],
    ),
    (
        "Implied and Essential Tasks",
        [
            "Implied: map the VLF's channels and audiences.",
            "Implied: arrange airtime on both radio stations.",
            "Essential: deliver a verified correction within six hours of each false report.",
        ],
    ),
    (
        "Constraints",
        [
            "Must: coordinate every public notice with the Provincial Information Office.",
            "Must not: post through accounts that do not identify the task force.",
            "Limited to three teams and one analysis cell.",
        ],
    ),
    (
        "Risks",
        [
            "A late correction lets a false report spread; mitigate with a two-hour monitoring cycle.",
            "Residents may doubt corrections; mitigate by co-signing with the provincial office.",
            "Radio airtime may be unavailable on festival days; mitigate with message board posts.",
        ],
    ),
    (
        "Proposed Mission Statement",
        [
            "Task Force LANTERN conducts information operations in Kestrel Bay from 16 to 27 March 2026 "
            "to counter VLF false reporting and keep residents informed of verified distribution points, "
            "in order to sustain public confidence in provincial services during the festival.",
        ],
    ),
]


def write_brief(path: pathlib.Path) -> None:
    """Writes the mission analysis brief as a PowerPoint deck: a title slide and one slide a step."""
    deck = pptx.Presentation()
    title = deck.slides.add_slide(deck.slide_layouts[0])
    title.shapes.title.text = "Mission Analysis Brief"
    title.placeholders[1].text = "Task Force LANTERN, OPORD 26-03 (Exercise QUIET HARBOR)\n5 March 2026"
    slides = [title]
    for heading, bullets in BRIEF:
        slide = deck.slides.add_slide(deck.slide_layouts[1])
        slide.shapes.title.text = heading
        body = slide.placeholders[1].text_frame
        body.text = bullets[0]
        for bullet in bullets[1:]:
            body.add_paragraph().text = bullet
        slides.append(slide)
    for slide in slides:
        box = slide.shapes.add_textbox(Inches(0.5), Inches(7.0), Inches(9.0), Inches(0.4))
        box.text_frame.text = MARKING
        box.text_frame.paragraphs[0].runs[0].font.size = PptxPt(12)
    set_core(deck.core_properties, "Mission Analysis Brief, OPORD 26-03", moment(4, 9), moment(5, 7), 3)
    deck.save(path)


PLAN = [
    ("PIR 1", "Will the VLF post false reports of port closures during the festival?",
     "New posts naming the port on VLF-linked accounts", "CIA open-source intelligence articles", "Open"),
    ("PIR 1", "Will the VLF post false reports of port closures during the festival?",
     "Radio call-in segments repeating closure rumors", "Local radio monitoring", "Open"),
    ("PIR 2", "Where will residents look for distribution point notices?",
     "Message board traffic on distribution topics", "ODNI, The IC OSINT Strategy 2024-2026", "Open"),
    ("PIR 2", "Where will residents look for distribution point notices?",
     "Turnout counts at each distribution point", "Provincial Information Office reports", "Collecting"),
    ("PIR 3", "Do residents trust corrections from the provincial office?",
     "Share of replies citing the provincial office", "FM 2-0, Intelligence", "Collecting"),
    ("PIR 3", "Do residents trust corrections from the provincial office?",
     "Change in turnout after each correction", "Analysis cell daily assessment", "Planned"),
    ("PIR 4", "Will the VLF shift to new channels if its accounts are reported?",
     "New accounts reposting VLF material", "CIA open-source intelligence articles", "Planned"),
    ("PIR 4", "Will the VLF shift to new channels if its accounts are reported?",
     "Collection tasks and their priorities", "FM 2-0, Intelligence", "Answered"),
]


def write_plan(path: pathlib.Path) -> None:
    """Writes the information collection plan as an Excel workbook, one row an indicator."""
    book = openpyxl.Workbook()
    sheet = book.active
    sheet.title = "Collection Plan"
    sheet.append([MARKING])
    sheet.append(["Task Force LANTERN Information Collection Plan, OPORD 26-03 Annex C"])
    sheet.append([])
    header = ["PIR", "Requirement", "Indicator", "Source", "Status"]
    sheet.append(header)
    for cell in sheet[4]:
        cell.font = Font(bold=True)
    for row in PLAN:
        sheet.append(list(row))
    sheet.append([])
    sheet.append([MARKING])
    for column, width in zip("ABCDE", (8, 60, 48, 40, 12)):
        sheet.column_dimensions[column].width = width
    for row in sheet.iter_rows(min_row=5):
        for cell in row:
            cell.alignment = Alignment(wrap_text=True, vertical="top")
    props = book.properties
    props.title = "Information Collection Plan, OPORD 26-03"
    props.creator = CREATOR
    props.lastModifiedBy = CREATOR
    props.created = moment(5, 10)
    props.modified = moment(9, 15)
    props.revision = "2"
    ExcelWriter(book, zipfile.ZipFile(path, "w")).save()


def normalize(path: pathlib.Path) -> None:
    """Rewrites the package at path in its entries' order, each stored under the fixed timestamp."""
    with zipfile.ZipFile(path) as source:
        entries = [(info.filename, source.read(info)) for info in source.infolist()]
    with zipfile.ZipFile(path, "w") as target:
        for name, data in entries:
            info = zipfile.ZipInfo(name, date_time=ZIP_TIME)
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            target.writestr(info, data, compress_type=zipfile.ZIP_STORED)


def main() -> None:
    """Writes the four files into the directory the one argument names."""
    if len(sys.argv) != 2:
        sys.exit("usage: generate.py <outdir>")
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    writers = {
        "opord-26-03-v1.docx": lambda path: write_opord(path, 1),
        "opord-26-03-v2.docx": lambda path: write_opord(path, 2),
        "mission-analysis-brief.pptx": write_brief,
        "collection-plan.xlsx": write_plan,
    }
    for name, write in writers.items():
        path = out / name
        write(path)
        normalize(path)


if __name__ == "__main__":
    main()
