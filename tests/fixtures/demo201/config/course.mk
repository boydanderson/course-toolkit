# Test fixture -- dummy course identity, not a real course. Used to
# verify the schedule engine against a "lecture + recitation + lab"
# weekly shape -- a genuinely different session-kind vocabulary than
# demo101's, proving the engine doesn't assume a fixed kind set.

COURSE_CODE = DEMO201
COURSE_NAME = Applied Demo Practice
HOSTING_ORG = demo-org
CANVAS_HOST = canvas.example.edu
RENDERER = latex-beamer

SEMESTER_START_MONDAY = 2026-08-10
NUM_WEEKS = 13
RECESS_AFTER_WEEK = 6
PDF_BASE_URL = https://demo-org.example.edu/pdfs
