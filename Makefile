BIN_DIR ?= $(HOME)/.local/bin
DATA_DIR ?= $(HOME)/.local/share/dctl
LIB_DIR ?= $(HOME)/.local/lib/dctl
SYSTEMD_DIR ?= $(HOME)/.local/share/systemd/user

INSTALL := install

IMAGE_NAMES := agents python-dev rust-dev zig-dev
TEMPLATE_DIRS := python rust zig
LIB_FILES := common.sh ws.sh image.sh init.sh test.sh auth.sh

.PHONY: install uninstall install-systemd uninstall-systemd test test-unit test-integration lint check

install:
	$(INSTALL) -d "$(BIN_DIR)"
	$(INSTALL) -m 755 bin/dctl "$(BIN_DIR)/dctl"
	$(INSTALL) -d "$(LIB_DIR)"
	for lib in $(LIB_FILES); do \
		$(INSTALL) -m 644 "lib/dctl/$$lib" "$(LIB_DIR)/$$lib"; \
	done
	for image in $(IMAGE_NAMES); do \
		$(INSTALL) -d "$(DATA_DIR)/images/$$image"; \
		$(INSTALL) -m 644 "images/$$image/Dockerfile" "$(DATA_DIR)/images/$$image/Dockerfile"; \
	done
	$(INSTALL) -d "$(DATA_DIR)/templates"
	for template in $(TEMPLATE_DIRS); do \
		$(INSTALL) -d "$(DATA_DIR)/templates/$$template"; \
		$(INSTALL) -m 644 "templates/$$template/devcontainer.json" "$(DATA_DIR)/templates/$$template/devcontainer.json"; \
	done
	$(INSTALL) -m 644 templates/README.md "$(DATA_DIR)/templates/README.md"
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
	rmdir "$(LIB_DIR)" 2>/dev/null || true
	for image in $(IMAGE_NAMES); do \
		rm -f "$(DATA_DIR)/images/$$image/Dockerfile"; \
		rmdir "$(DATA_DIR)/images/$$image" 2>/dev/null || true; \
	done
	rmdir "$(DATA_DIR)/images" 2>/dev/null || true
	for template in $(TEMPLATE_DIRS); do \
		rm -f "$(DATA_DIR)/templates/$$template/devcontainer.json"; \
		rmdir "$(DATA_DIR)/templates/$$template" 2>/dev/null || true; \
	done
	rm -f "$(DATA_DIR)/templates/README.md"
	rmdir "$(DATA_DIR)/templates" 2>/dev/null || true
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
