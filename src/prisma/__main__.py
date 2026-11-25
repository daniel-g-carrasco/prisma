# SPDX-License-Identifier: GPL-3.0-or-later
"""Freeze support precedes imports and Qt."""
import multiprocessing


def main():
    multiprocessing.freeze_support()
    from prisma.cli import main as run
    return run()


if __name__ == '__main__':
    raise SystemExit(main())
