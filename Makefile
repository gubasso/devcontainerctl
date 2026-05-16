BIN_DIR ?= $(HOME)/.local/bin
DATA_DIR ?= $(HOME)/.local/share/dctl
LIB_DIR ?= $(HOME)/.local/lib/dctl
SYSTEMD_DIR ?= $(HOME)/.local/share/systemd/user

INSTALL := install

IMAGE_NAMES := agents python-dev rust-dev zig-dev
DEVCONTAINER_DIRS := agents python rust zig general coordinator base
DEVCONTAINER_MANIFESTS := general coordinator python rust zig
LIB_FILES := lifecycle.sh

.PHONY: install uninstall install-systemd uninstall-systemd test test-unit test-integration lint check gate-no-eval gate-no-raw-ansi gate-one-public-fn-per-file

install:
	$(INSTALL) -d "$(BIN_DIR)"
	$(INSTALL) -m 755 bin/dctl "$(BIN_DIR)/dctl"
	$(INSTALL) -d "$(LIB_DIR)"
	for lib in $(LIB_FILES); do \
		$(INSTALL) -m 644 "lib/dctl/$$lib" "$(LIB_DIR)/$$lib"; \
	done
	$(INSTALL) -d "$(LIB_DIR)/_lib"
	find lib/dctl/_lib -type f -name '*.sh' | while read -r file; do \
		dest="$(LIB_DIR)/$${file#lib/dctl/}"; \
		$(INSTALL) -d "$$(dirname "$$dest")"; \
		$(INSTALL) -m 644 "$$file" "$$dest"; \
	done
	$(INSTALL) -d "$(LIB_DIR)/commands"
	find lib/dctl/commands -type f -name '*.sh' | while read -r file; do \
		dest="$(LIB_DIR)/$${file#lib/dctl/}"; \
		$(INSTALL) -d "$$(dirname "$$dest")"; \
		$(INSTALL) -m 644 "$$file" "$$dest"; \
	done
	$(INSTALL) -d "$(LIB_DIR)/runtime"
	$(INSTALL) -m 644 "lib/dctl/runtime/common.sh" "$(LIB_DIR)/runtime/common.sh"
	$(INSTALL) -m 644 "lib/dctl/runtime/krun.sh" "$(LIB_DIR)/runtime/krun.sh"
	for image in $(IMAGE_NAMES); do \
		$(INSTALL) -d "$(DATA_DIR)/images/$$image"; \
		for file in images/$$image/*; do \
			if [ -x "$$file" ]; then mode=755; else mode=644; fi; \
			$(INSTALL) -m "$$mode" "$$file" "$(DATA_DIR)/images/$$image/$$(basename $$file)"; \
		done; \
	done
	$(INSTALL) -d "$(DATA_DIR)/devcontainers"
	for template in $(DEVCONTAINER_DIRS); do \
		$(INSTALL) -d "$(DATA_DIR)/devcontainers/$$template"; \
		for file in devcontainers/$$template/*; do \
			[ -f "$$file" ] || continue; \
			if [ -x "$$file" ]; then mode=755; else mode=644; fi; \
			$(INSTALL) -m "$$mode" "$$file" "$(DATA_DIR)/devcontainers/$$template/$$(basename $$file)"; \
		done; \
	done
	for manifest in $(DEVCONTAINER_MANIFESTS); do \
		$(INSTALL) -m 644 "devcontainers/$${manifest}.yaml" "$(DATA_DIR)/devcontainers/$${manifest}.yaml"; \
	done
	$(INSTALL) -m 644 devcontainers/README.md "$(DATA_DIR)/devcontainers/README.md"
	$(INSTALL) -d "$(DATA_DIR)/schemas"
	$(INSTALL) -m 644 schemas/compose.schema.yaml "$(DATA_DIR)/schemas/compose.schema.yaml"
	$(INSTALL) -m 644 schemas/projects.schema.yaml "$(DATA_DIR)/schemas/projects.schema.yaml"
	@printf '\n'
	@case ":$$PATH:" in *:"$(BIN_DIR)":*) ;; *) \
		printf '\033[1;33mWARN:\033[0m %s is not in PATH\n' "$(BIN_DIR)"; \
		printf '      Add to your shell profile: export PATH="%s:$$PATH"\n' "$(BIN_DIR)"; \
	;; esac

uninstall:
	rm -f "$(BIN_DIR)/dctl"
	for lib in $(LIB_FILES); do \
		rm -f "$(LIB_DIR)/$$lib"; \
	done
	rm -rf "$(LIB_DIR)/_lib"
	rm -rf "$(LIB_DIR)/commands"
	rm -f "$(LIB_DIR)/runtime/common.sh"
	rm -f "$(LIB_DIR)/runtime/krun.sh"
	rmdir "$(LIB_DIR)/runtime" 2>/dev/null || true
	rmdir "$(LIB_DIR)" 2>/dev/null || true
	for image in $(IMAGE_NAMES); do \
		for file in images/$$image/*; do \
			rm -f "$(DATA_DIR)/images/$$image/$$(basename $$file)"; \
		done; \
		rmdir "$(DATA_DIR)/images/$$image" 2>/dev/null || true; \
	done
	rmdir "$(DATA_DIR)/images" 2>/dev/null || true
	for template in $(DEVCONTAINER_DIRS); do \
		for file in devcontainers/$$template/*; do \
			rm -f "$(DATA_DIR)/devcontainers/$$template/$$(basename $$file)"; \
		done; \
		rmdir "$(DATA_DIR)/devcontainers/$$template" 2>/dev/null || true; \
	done
	for manifest in $(DEVCONTAINER_MANIFESTS); do \
		rm -f "$(DATA_DIR)/devcontainers/$${manifest}.yaml"; \
	done
	rm -f "$(DATA_DIR)/devcontainers/README.md"
	rmdir "$(DATA_DIR)/devcontainers" 2>/dev/null || true
	rm -f "$(DATA_DIR)/schemas/compose.schema.yaml"
	rm -f "$(DATA_DIR)/schemas/projects.schema.yaml"
	rmdir "$(DATA_DIR)/schemas" 2>/dev/null || true
	rmdir "$(DATA_DIR)" 2>/dev/null || true

install-systemd:
	$(INSTALL) -d "$(SYSTEMD_DIR)"
	sed "s|^ExecStart=.*|ExecStart=$(BIN_DIR)/dctl image build --all|" systemd/dctl-image-build.service \
		>"$(SYSTEMD_DIR)/dctl-image-build.service"
	chmod 644 "$(SYSTEMD_DIR)/dctl-image-build.service"
	$(INSTALL) -m 644 systemd/dctl-image-build.timer "$(SYSTEMD_DIR)/dctl-image-build.timer"
	@printf '%s\n' "Run: systemctl --user daemon-reload && systemctl --user enable --now dctl-image-build.timer"

uninstall-systemd:
	systemctl --user disable --now dctl-image-build.timer >/dev/null 2>&1 || true
	rm -f "$(SYSTEMD_DIR)/dctl-image-build.service"
	rm -f "$(SYSTEMD_DIR)/dctl-image-build.timer"
	systemctl --user daemon-reload >/dev/null 2>&1 || true

test-unit:
	bats --filter-tags 'unit,!integration' tests

test-integration:
	bats --filter-tags integration tests

test: test-unit test-integration

lint:
	pre-commit run shellcheck --all-files
	pre-commit run shfmt --all-files
	pre-commit run shellharden --all-files
	pre-commit run bashate --all-files
	pre-commit run typos --all-files

check:
	pre-commit run --all-files
	bash -O globstar -c 'shellcheck -x bin/* lib/**/*.sh'
	shfmt -d -i 2 -ci -bn -s bin/ lib/ hooks/ tests/
	bats -r tests/

gate-no-eval:
	! grep -rn --include='*.sh' -E '^[[:space:]]*eval\b' bin lib hooks | grep -v '# allow-eval'

gate-no-raw-ansi:
ifdef DCTL_ENFORCE_ANSI_GATE
	! grep -rn --include='*.sh' -F "\\033[" bin lib | grep -v 'lib/dctl/common.sh'
else
	@printf '%s\n' "gate-no-raw-ansi deferred until Phase 2 (set DCTL_ENFORCE_ANSI_GATE=1 to enable)"
endif

gate-one-public-fn-per-file:
ifdef DCTL_ENFORCE_ONEFN_GATE
	@find lib/dctl/commands lib/dctl/functions -type f -name '*.sh' 2>/dev/null | while read -r file; do \
		count=$$(grep -E -c '^dctl::(cmd|fn)::[A-Za-z0-9_]+[[:space:]]*\(\)' "$$file"); \
		if [ "$$count" -gt 1 ]; then \
			printf '%s\n' "$$file: $$count public functions"; \
			exit 1; \
		fi; \
	done
else
	@printf '%s\n' "gate-one-public-fn-per-file deferred until Phase 4 (set DCTL_ENFORCE_ONEFN_GATE=1 to enable)"
endif
