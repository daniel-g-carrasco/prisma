# SPDX-License-Identifier: GPL-3.0-or-later
"""One live command object for menus, toolbars and shortcuts."""
from PySide6.QtCore import Property, QObject, Signal, Slot


class Command(QObject):
    """`more`: IDs of the registered commands offered in this command's split button, as Meridiana's tools. `tip`:
    the host's explanation under the name in the tooltip. `reason`: why the command is off, shown in its tooltip and
    beside it in the menus while it is off. `checked`: a command with two states, lit in the bar and in the menus.
    `label`: a shorter name for the bar, as Meridiana's Tool.label; the menus and the tooltip keep `text`.
    `icon_on`, `icon_off`: a sign for each state of a command with two states, as a switch Read only/Edit
    (`lock` and `lock-open`); without them the command keeps `icon` in both (21/11/2026, Quotario).
    `counted`: the text for a number of rows, as `lambda n: ngettext('Remove {n} item', 'Remove {n} items', n)
    .format(n=n)`, for the DataTable's menu (contextCommands: «Elimina 7 voci»); without it `text`.
    A switch that is on can always be turned off: `enabled=False` holds only for turning it on (Daniel 22/11/2026,
    Quotario's Edit lit and off together without a bill); the host turns it off when its condition falls."""
    changed = Signal()

    def __init__(self, id, text, shortcut='', enabled=True, checked=False, callback=None, *, icon='folder-open',
                 more=(), tip='', reason='', label='', icon_on='', icon_off='', counted=None):
        super().__init__()
        self._id, self._text, self._shortcut = id, text, shortcut
        self._label = label
        self._enabled, self._checked, self.callback = enabled, checked, callback
        self._tip, self._reason = tip, reason
        self.icon = icon
        self.icon_on, self.icon_off = icon_on, icon_off
        self.more = tuple(more)
        self.counted = counted

    id = Property(str, lambda self: self._id, constant=True)
    text = Property(str, lambda self: self._text, notify=changed)
    label = Property(str, lambda self: self._label or self._text, notify=changed)
    shortcut = Property(str, lambda self: self._shortcut, notify=changed)
    enabled = Property(bool, lambda self: bool((self._enabled or self._checked) and callable(self.callback)),
                       notify=changed)
    checked = Property(bool, lambda self: self._checked, notify=changed)
    tip = Property(str, lambda self: self._tip, notify=changed)
    reason = Property(str, lambda self: self._reason, notify=changed)
    note = Property(str, lambda self: '' if self.enabled else self._reason, notify=changed)
    # the sign of the state it is in
    currentIcon = Property(str, lambda self: (self.icon_on if self._checked else self.icon_off) or self.icon,
                           notify=changed)

    @Slot(int, result=str)
    def textFor(self, count):
        """The text for `count` rows (the DataTable's menu): the host's `counted`, else `text`."""
        return self.counted(count) if callable(self.counted) else self._text

    def set_state(self, *, enabled=None, checked=None, text=None, shortcut=None, tip=None, reason=None, label=None):
        for key, value in locals().copy().items():
            if key != 'self' and value is not None:
                setattr(self, '_' + key, value)
        self.changed.emit()

    @Slot(result=bool)
    def trigger(self):
        if not self.enabled:
            return False
        self.callback()
        return True
