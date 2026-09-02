# toolkit.mk -- includable Make fragment, the renderer-agnostic build
# orchestration for a course repo consuming this toolkit as a submodule.
#
# A consuming course repo's own top-level Makefile does:
#
#   TOOLKIT_DIR := tooling
#   include $(TOOLKIT_DIR)/core/toolkit.mk
#
# Placeholder for now -- this is Stage 0 scaffolding only. The actual
# session-kind schedule engine, version tracking, and Canvas/README
# generation orchestration land here in Stages 1-2 of the extraction
# from cs1101s/course-materials. See that repo's course-toolkit
# extraction plan for the staged rollout.
