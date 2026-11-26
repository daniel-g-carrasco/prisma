# Contributing to Prisma

Prisma currently ships a development shell. The standalone IFC viewport and model loading are still being developed.

## Language

Use English for public documentation, help, metadata, issues, pull requests, commit messages, workflow text, source messages and comments. Add interface translations to the gettext catalogues under `po/`. Preserve existing upstream notices, licences and attributions in shared code and assets.

## Run from source

Use Python 3.12 on Windows or Linux. From the repository root, create an isolated environment.

```sh
python -m venv .venv
```

Activate it with `.\.venv\Scripts\Activate.ps1` in PowerShell, or with `source .venv/bin/activate` on Linux. Then run these commands in the same shell.

```sh
python -m pip install -e ".[dev]"
python tools/compile_po.py --python
python -m prisma
```

Add `--language it` to launch the Italian interface. Use `python -m prisma --help` for the available options. On minimal Linux installations, install the Qt runtime libraries listed in [Checks](.github/workflows/test.yml).

## Verify changes

Run these checks after compiling the catalogues. The automated tests and smoke command use the offscreen Qt platform and temporary profiles.

```sh
python tools/check_public.py
python tools/compile_po.py --check
python tools/make_style.py --check
python -m ruff check .
python -m unittest discover -s tests -p "test_*.py"
prisma --smoke-test
```

`check_public.py` checks the Git index. Stage the intended changes before running it. [Checks](.github/workflows/test.yml) runs on Windows and Linux and also exercises the Linux source launcher.

## Package and security checks

[Security](.github/workflows/security.yml) runs Ruff security rules on the
Python source and Gitleaks with redacted values on pull request commits.
[Package inventory](.github/workflows/inventory.yml) builds the current
Prisma wheel, installs it in a clean Python 3.12 environment on Windows and
Linux, and smoke-tests it from outside the checkout. The inventory binds the
wheel digest and build commit to the dependencies installed on each runner.
The weekly check reruns the dependency resolution and queries OSV for PyPI
advisories.

Prisma currently provides source installation. The wheel does not contain the
IFC engine, and the checks cover PyPI package advisories. The Qt libraries
inside the wheels and any future native distribution require their own
inventory and advisory coverage.

## Architecture

Keep Qt in `src/prisma/gui/`. Put computations in `core/`, formats and persistence in `data/`, and independent services in `app/`. Run expensive work through the shared process bridge in `app/work.py`. Update style values in `style/tokens.toml`, then run `python tools/make_style.py`.

The shared Python modules and Casa sources are tracked by SHA-256 in `impronte/`. Update them from their upstream sources using the upstream manifest tool. The fingerprint tests check the copies from an ordinary Prisma checkout. Third-party licence notices are included with the fonts and icons in `src/prisma/gui/casa/data/`.

## Viewer migration

The prototype runs in Meridiana. The standalone viewer still needs the shared IFC engine as a dependency, an import and cancellation pipeline for opening and combining models, a 3D viewport with camera controls, object selection and property inspection, and section-box tools. Local MCP integration and the Windows and Linux distribution builds follow separate verification.
