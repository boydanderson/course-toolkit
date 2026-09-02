# Test fixture -- dummy course identity, not a real course. Used to
# verify core/course-lib.sh and exercise the schedule engine against a
# "studio + two lectures + reflection" weekly shape.

COURSE_CODE = DEMO101
COURSE_NAME = Introduction to Demo Studies
HOSTING_ORG = demo-org
CANVAS_HOST = canvas.example.edu
RENDERER = latex-beamer

SEMESTER_START_MONDAY = 2026-08-10
NUM_WEEKS = 13
RECESS_AFTER_WEEK = 6
PDF_BASE_URL = https://demo-org.example.edu/pdfs
