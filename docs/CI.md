# Continuous Integration for FPC/Lazarus on GitHub Actions

How to build and test a Free Pascal / Lazarus project on GitHub Actions
without depending on unmaintained third-party actions. Sections 1–3 hold for
any FPC/Lazarus project; section 4 applies them to this one (roadmap R-24).

## 1. Rule: No Unmaintained Actions

A workflow uses the official `actions/*` (checkout, cache, upload-artifact)
and otherwise installs its toolchain itself, from sources that are
maintained.

`gcarreno/setup-lazarus`, the action most guides point to, was checked on
2026-09-26 and rejected: its maintainer has stepped back. An action that
downloads and installs a compiler runs with the workflow's rights; one that
nobody maintains anymore breaks on the next runner image, or worse.

The large Pascal projects keep the installation in their own hands too:

| Project | How FPC/Lazarus get onto the runner |
|---|---|
| [Castle Game Engine](https://github.com/castle-engine/castle-engine/tree/master/.github/workflows) | own script repo `castle-build-ci` (`setup_castle_engine --install-lazarus=true`); a matrix of linux-x86_64, win64, win32, darwin-x86_64, darwin-aarch64; a Docker image for Linux and cross-builds |
| [Double Commander](https://github.com/doublecmd/doublecmd/tree/master/.github/workflows) | own actions `doublecmd/lazarus-install@win` / `@mac`; on macOS Lazarus is built from `fpc/Lazarus` |

## 2. Three Ways to Install the Toolchain

**A. Package managers, all in the workflow file.** `apt` on Ubuntu, Chocolatey
on Windows, Homebrew on macOS. No code of our own beyond the YAML, and the
packages are maintained by the distributions. The Lazarus version is the
package manager's, so it can differ per OS.

**B. Own install script.** A script in the repository (`ci/install-toolchain.sh`,
`.ps1`) downloads the official installers of a fixed FPC and Lazarus version
from SourceForge or `downloads.freepascal.org` and caches them with
`actions/cache`. The same versions on every OS, macOS arm64 included; each
Lazarus release means updating URLs and versions. This is Castle Game
Engine's way.

**C. Docker image for Linux.** A versioned image with FPC, Lazarus and all
libraries, used as the job's `container:`; Windows and macOS use A or B. Fast
and reproducible, and one image can carry variants (an older distribution,
a library missing). The image itself is a second thing to build and maintain.

**Choice:** A first. B for a single job if a package manager does not deliver
(an outdated or missing package, macOS arm64). C only when a project needs
several Linux variants regularly.

**FPC or Lazarus.** FPC alone builds a program whose units it finds by
`-Fu` paths. A project file (`.lpi`) that requires packages (`.lpk`), or a
program that uses the LCL (`Graphics`, `Interfaces`), needs `lazbuild`, the
LCL and a widgetset — the IDE itself is not needed, but distributions ship
these as Lazarus packages.

**Linux distributions** (Repology, 2026-10-03):

| Distribution | Lazarus | FPC | Runner |
|---|---|---|---|
| Ubuntu 26.04 | 4.4 | 3.2.2 | native, `ubuntu-26.04` |
| Ubuntu 24.04 | 3.0 | 3.2.2 | native, `ubuntu-24.04` = `ubuntu-latest` |
| Debian 13 | 4.0 | 3.2.2 | container |
| Fedora 43, Arch, openSUSE Tumbleweed | 4.8 (newest) | 3.2.2 | container |

All ship FPC 3.2.2. Ubuntu 26.04 is the best fit for a first job: a current
Lazarus on a native runner, no container. The rolling distributions are
newer but only reachable through a container. Pin the runner label;
`ubuntu-latest` moves to the next release within a month or two.

## 3. Pitfalls Common to FPC/Lazarus

- **Exit code.** CI sees a failure only through the exit code. mORMot2's
  `TSynTests.RunAsConsole` sets `ExitCode := 1` when a test fails
  (`mormot.core.test.pas`); other frameworks need checking.
- **Waiting for Enter.** A test runner that waits for input hangs the job
  until its timeout; pass the parameter that turns it off.
- **Packages.** `lazbuild --add-package-link <path>.lpk` registers a package
  checked out next to the project; do it before the first `lazbuild` of a
  project that requires it.
- **LCL programs on Linux** link against the widgetset: the GTK2 development
  packages are needed even for a console test runner that uses
  `Interfaces`. Running them may need a display (`xvfb-run`).
- **macOS runners are arm64** (`macos-latest`; `macos-15-intel` for x86_64).
  The linker's `built for newer macOS version` warnings are noise.
- **Fonts.** Runner images bring few fonts. Tests that need a face should
  skip without it, and the workflow should install the faces, or the run is
  green and tests nothing.
- **Pin dependencies.** Check out a dependency at a fixed commit, not its
  default branch, so a failure means a change of ours.

## 4. This Project (R-24)

**Goal.** A push builds and runs `test_runner` on Linux. Windows and macOS
come later, each as a job of its own.

**Lazarus is needed, not FPC alone:** `tests/test_runner.lpi` requires the
packages `mormot2` and `LCL`, and the runner uses `Interfaces` and
`Graphics` — the report engine draws on an LCL `TCanvas`.

**Steps:**
1. **Linux** on `ubuntu-26.04` (Lazarus 4.4, FPC 3.2.2, way A):
   Lazarus with the GTK2 widgetset from `apt`, `libfreetype6`,
   `libharfbuzz0b`, `libharfbuzz-subset0`, the faces the tests name
   (DejaVu, Liberation, Droid Sans Fallback, Noto Naskh Arabic, Noto CJK),
   then `lazbuild tests/test_runner.lpi -B` and
   `tests/bin/x86_64-linux/test_runner`, under `xvfb-run` if the widgetset
   wants a display. A second step may run `tests/no_hbsubset.sh` for the
   path without hb-subset
2. **Demos:** build the eight demos (the GUI demos with `--export`) and
   upload their PDFs as artifacts, for PAC and veraPDF by hand
3. later: a second Linux job on `ubuntu-24.04` (HarfBuzz 8, below the 10.0
   that commit 7de7b9b, the empty hb-subset result, is about); **Windows**
   (`windows-latest`, `test_runner.exe --noenter`); **macOS**
   (`aarch64-darwin`) only if Homebrew installs FPC and Lazarus cleanly

**mORMot2:** `actions/checkout` of `synopse/mORMot2` at the commit pinned in
the refactoring baseline (`docs/REFACTORING.md`, Phase 0 step 3), its
packages registered with `lazbuild --add-package-link`, plus the static
libraries from `mormot2static.tgz`.

**The workflow:** `.github/workflows/linux.yml`. On Ubuntu 26.04 `lazbuild`
is in `lcl-utils`, the GTK2 LCL in `lcl-gtk2`. The whole
`mormot2static.tgz` is unpacked, checked against `static/dev.sha256` of the
pinned commit: synopse.info serves only the newest archive, so a failed
check means the pin is stale. `no_hbsubset.sh` needs
`kernel.apparmor_restrict_unprivileged_userns=0` on Ubuntu.

**Still to check:**
- the first run: whether `lazbuild` finds the LCL without `--lazarusdir`,
  whether `test_runner` needs `xvfb-run`, and how many assertions run
  instead of skipping (318 on the Debian machine)
- later, for Windows: which faces the runner has (Calibri, Microsoft YaHei,
  an Arabic face) — missing ones turn tests into skips — and whether
  Chocolatey's Lazarus is current enough; else way B for that job

**Not in CI:** golden files (the baseline depends on the fonts installed, see
`CLAUDE.md`), Delphi 7 and Delphi 2010 (no licence on a runner), PAC 2024 (a
Windows GUI). veraPDF runs on Java and could follow later.

**After R-28** the code lives in the mORMot2 trunk as `src/pdf`; paths and the
mORMot2 checkout in the workflow change then. Keep the workflow small until
that is done.
