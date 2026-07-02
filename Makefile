NVIM ?= nvim

.PHONY: test test-unit test-e2e

# Full suite. test-e2e needs a working HOL4 (hol on PATH or $$HOLDIR set);
# test-unit runs anywhere.
test: test-unit test-e2e

test-unit:
	$(NVIM) --headless -u init.lua -l tests/unit.lua

test-e2e:
	$(NVIM) --headless -u init.lua -l tests/e2e.lua examples/TestScript.sml
