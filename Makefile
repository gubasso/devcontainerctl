BIN_DIR ?= $(HOME)/.local/bin
CONFIG_DIR ?= $(HOME)/.config/dctl
DATA_DIR ?= $(HOME)/.local/share/dctl
SYSTEMD_DIR ?= $(HOME)/.local/share/systemd/user

INSTALL := install

CONFIG_IMAGES := agents python-dev rust-dev zig-dev
TEMPLATE_DIRS := python rust zig

.PHONY: install uninstall install-systemd uninstall-systemd test lint

install:
	$(INSTALL) -d "$(BIN_DIR)"
	$(INSTALL) -m 755 bin/dctl "$(BIN_DIR)/dctl"
	for image in $(CONFIG_IMAGES); do \
		$(INSTALL) -d "$(CONFIG_DIR)/$$image"; \
		$(INSTALL) -m 644 ".config/dctl/$$image/Dockerfile" "$(CONFIG_DIR)/$$image/Dockerfile"; \
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
	for image in $(CONFIG_IMAGES); do \
		rm -f "$(CONFIG_DIR)/$$image/Dockerfile"; \
		rmdir "$(CONFIG_DIR)/$$image" 2>/dev/null || true; \
	done
	rmdir "$(CONFIG_DIR)" 2>/dev/null || true
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

test:
	bats tests

lint:
	shellcheck bin/dctl install.sh uninstall.sh
