SHELL := /bin/bash
APP ?= $(CURDIR)/build/ThermalScope.app
PERF_OUT ?= $(CURDIR)/performance-results/$(shell TZ=Asia/Shanghai date +%Y%m%d-%H%M%S)

.PHONY: build check perf-smoke perf-standard perf-soak

build:
	bash scripts/build.sh "$(APP)"

check:
	bash scripts/check.sh

perf-smoke:
	python3 scripts/perf_suite.py --profile smoke --out "$(PERF_OUT)-smoke"

perf-standard:
	python3 scripts/perf_suite.py --profile standard --out "$(PERF_OUT)-standard"

perf-soak:
	python3 scripts/perf_suite.py --profile soak --out "$(PERF_OUT)-soak"
