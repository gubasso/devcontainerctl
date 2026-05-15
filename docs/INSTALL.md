# Install

Operator install guide for the libkrun + rootless Podman stack used by `dctl`.

## Supported distributions

openSUSE Tumbleweed is the primary target for this stack.

### openSUSE Leap 16

Leap 16 needs the `Virtualization:containers` and `Virtualization` repositories in
addition to the package steps below. The rest of the setup is the same.

## Enable the OBS Virtualization repo

Lead with this step on Tumbleweed. Without the OBS `Virtualization` repo, the
default Tumbleweed repos currently lag `libkrun` and may install a version
below the `dctl doctor` floor.

```bash
sudo zypper addrepo \
  https://download.opensuse.org/repositories/Virtualization/openSUSE_Tumbleweed/Virtualization.repo
sudo zypper refresh
sudo zypper install --from Virtualization libkrun libkrunfw
```

## Install host packages

Install the required host packages by their unversioned names. Do not pin
SONAME-specific package names such as `libkrun1` or `libkrunfw5`; `zypper`
resolves those automatically.

```bash
sudo zypper install podman crun libkrun libkrunfw
```

## Set up /dev/kvm access

Tumbleweed uses the `kvm` group for `/dev/kvm`. Group membership is not
retroactive in the current shell; run `newgrp kvm` or log out and back in.

```bash
sudo usermod -aG kvm "$USER"
newgrp kvm
```

## Set up rootless subuid/subgid

Rootless Podman needs subordinate UID and GID ranges for the current user.

```bash
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER"
podman system migrate
```

## Smoke-test the install

The canonical verification command is:

```bash
dctl doctor
```

If `dctl` is not installed yet, use a direct Podman smoke test first:

```bash
podman run --runtime krun --rm quay.io/quay/busybox:1.36 /bin/true
```

## Known limitations

- `libkrun` issue #674 remains open as of 2026-05: vsock TX `BufDescTooSmall`
  on guest kernels >= 6.2.
- `crun` issue #1894 can require an explicit POSIX ACL on `/dev/kvm` even when
  standard `kvm` group membership is present.
- The default Tumbleweed repos currently lag `libkrun`; use the OBS
  `Virtualization` repo so `dctl doctor` can satisfy `MIN_LIBKRUN_VER=1.18.0`.

## Leap 16 notes

Enable both repositories before installing packages:

```bash
sudo zypper addrepo \
  https://download.opensuse.org/repositories/Virtualization:containers/16.0/Virtualization:containers.repo
sudo zypper addrepo \
  https://download.opensuse.org/repositories/Virtualization/16.0/Virtualization.repo
sudo zypper refresh
sudo zypper install podman crun libkrun libkrunfw
```

## References

### crun + libkrun upstream

- crun handler source (`.feature_string = "LIBKRUN"`):
  <https://github.com/containers/crun/blob/main/src/libcrun/handlers/krun.c>
- crun feature-tag printer (`libcrun_handler_manager_print_feature_tags`):
  <https://github.com/containers/crun/blob/main/src/libcrun/custom-handler.c>
- crun `krun.1` manpage on Tumbleweed:
  <https://manpages.opensuse.org/Tumbleweed/crun/krun.1.en.html>
- crun releases (latest 1.27.1):
  <https://github.com/containers/crun/releases>
- libkrun releases (latest 1.18.0, 2026-04-24):
  <https://github.com/containers/libkrun/releases>
- libkrun README (TSI networking limits):
  <https://github.com/containers/libkrun>

### Known issues to surface in the doctor

- libkrun #674 — vsock TX `BufDescTooSmall` on guest kernels >= 6.2 (open as
  of 2026-05): <https://github.com/containers/libkrun/issues/674>
- crun #1894 — `krun` fails despite `/dev/kvm` rw without POSIX ACL:
  <https://github.com/containers/crun/issues/1894>

### openSUSE packaging

- Tumbleweed package pages:
  <https://software.opensuse.org/package/crun>,
  <https://software.opensuse.org/package/libkrun>,
  <https://software.opensuse.org/package/libkrunfw>
- OBS `Virtualization/libkrunfw` (latest 5.2.x):
  <https://build.opensuse.org/package/show/Virtualization/libkrunfw>
- openSUSE Factory ML — original libkrun submission:
  <https://lists.opensuse.org/archives/list/factory@lists.opensuse.org/thread/MO4PYYD3BEUJCUWGJQCQ2P7OW4LTG336/>
- SUSE Package Hub — libkrun (Leap 15 SP7):
  <https://packagehub.suse.com/packages/libkrun/>
- Fedora — `crun-krun` subpackage:
  <https://packages.fedoraproject.org/pkgs/crun/crun-krun/>

### Rootless Podman preflight

- SUSE — rootless Podman guide:
  <https://documentation.suse.com/smart/container/html/rootless-podman/index.html>
- Podman — rootless tutorial:
  <https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md>
- Red Hat — rootless Podman cgroups v2 solution:
  <https://access.redhat.com/solutions/5913671>
- Arch wiki — Podman (`unprivileged_userns_clone`):
  <https://wiki.archlinux.org/title/Podman>
- `podman-info(1)`:
  <https://docs.podman.io/en/latest/markdown/podman-info.1.html>
- `podman-network(1)`:
  <https://docs.podman.io/en/latest/markdown/podman-network.1.html>

### Networking shift

- pasta-default rootless networking:
  <https://sanj.dev/post/podman-pasta-vs-slirp4netns-networking>

### KVM / /dev/kvm group

- openSUSE wiki — KVM:
  <https://en.opensuse.org/KVM>
- Arch BBS — classic `/dev/kvm` group-id discussion:
  <https://bbs.archlinux.org/viewtopic.php?id=69454>
