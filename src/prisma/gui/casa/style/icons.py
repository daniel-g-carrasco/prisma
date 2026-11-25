# SPDX-License-Identifier: GPL-3.0-or-later
"""The kit's icons in the theme's colours (docs/30-icone.md): Phosphor Duotone draws the stroke in currentColor and its
second layer, the only element with opacity="0.2", in the same colour; here the layer takes the theme's second colour.
The thin stroke is Phosphor's Light weight over the same second layer (it has the same shape in every weight)."""
import re

DUO_LAYER = b'opacity="0.2"'
STROKES = ('regular', 'light', 'auto')     # the setting "Stroke of the icons": Normal, Thin, Automatic
# The Icons group's defaults, the one place for them (Daniel 22/11/2026: «passiamo già direttamente al Light di Phosphor
# per tutto come predefinito»): the thin stroke everywhere, in the soft ink, over the neutral second colour.
DEFAULTS = {'iconStroke': 'light', 'iconInk': 'soft', 'iconDuo': 'neutral'}
LIGHT_MIN_DPR = 1.5                        # Light strokes need enough physical pixels
LIGHT_FROM = 24                            # Automatic: the thin stroke from this size up (logical pixels)
_LAYER = re.compile(rb'<[^<>]*opacity="0\.2"[^<>]*/>')
_BODY = re.compile(rb'<svg[^>]*>(.*)</svg>', re.DOTALL)


def drawing(name, resources, weight='regular'):
    """The Duotone SVG of `name`; with `weight` "light", the Light paths over the Duotone's second layer."""
    path = resources.icon(name)
    duotone = path.read_bytes()
    if weight != 'light':
        return duotone
    light = path.with_name(path.name.replace('-duotone.svg', '-light.svg')).read_bytes()
    return duotone[:duotone.index(b'>') + 1] + _LAYER.search(duotone).group(0) + _BODY.search(light).group(1) + b'</svg>'


def svg(name, resources, color, duo, weight='regular'):
    """The SVG of `name` with the stroke in `color` and the second layer in `duo` (QColor, its alpha the opacity)."""
    layer = f'fill="{duo.name()}" opacity="{duo.alphaF():.2g}"'.encode('ascii')
    return drawing(name, resources, weight).replace(DUO_LAYER, layer).replace(b'currentColor', color.name().encode('ascii'))
