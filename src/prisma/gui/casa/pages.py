# SPDX-License-Identifier: GPL-3.0-or-later
"""Host-resolved pages; stable identifiers are independent of their labels."""
from dataclasses import dataclass


@dataclass(frozen=True)
class Page:
    """`enabled` False: a tab that does not open, with `reason` in its tooltip (a page not available yet).
    `numbered` False: a tab without the disc of its number (a view, not a phase); the phases keep counting 1, 2, 3.
    `framed` False: the page supplies its own cards within the workspace."""
    id: str
    title: str
    source: object
    enabled: bool = True
    reason: str = ''
    numbered: bool = True
    framed: bool = True


def indexed(items):
    result = {}
    for item in items:
        if not isinstance(item.id, str) or not item.id or item.id in result:
            raise ValueError('Empty or duplicate registration: ' + str(item.id))
        result[item.id] = item
    return result
