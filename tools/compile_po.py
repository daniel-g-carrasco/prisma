#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compile po/*.po into GNU gettext catalogues, with msgfmt (GNU gettext:
on Linux, in the Flatpak SDK, in MSYS2) or, where there is none (Windows
with python.org's Python), with the compiler below: the same .mo for what
the catalogues use (contexts, plurals, the header; fuzzy and untranslated
entries left out, as msgfmt does), and a check of the {placeholders} a
translation may not add (a KeyError at run time).

  python3 tools/compile_po.py                 -> locale/<lang>/LC_MESSAGES/<domain>.mo (and .qm with QML)
  python3 tools/compile_po.py --dest /app/share/locale
  python3 tools/compile_po.py --python        the compiler below even when msgfmt is there
  python3 tools/compile_po.py --update        refresh po/<domain>.pot and merge it into po/*.po
  python3 tools/compile_po.py --check         broken encoding, keys twice, placeholders, entries
                                              src does not use, messages src asks for that are missing
                                              or not translated, dictionaries of translations in src

What is a message: it is marked, not guessed (docs/24-lingue.md). Python: _("..."), N_("...") for a
text translated later, pgettext("context", "..."), ngettext("one", "many", n), npgettext(...). QML:
qsTr("..."), qsTr("...", "context"), qsTr("%n one", "%n many", n), QT_TR_NOOP("..."),
QT_TRANSLATE_NOOP("context", "..."); the bridge is src/<package>/gui/casa/translator.py. Still guessed,
until the call sites are marked: the values of variables, tables and helper parameters that reach _().

The domain is the TEXTDOMAIN of the one package under src/, read without
importing it. What an app finds in its own way (tables of messages, files
of its own, more keywords for xgettext) it says in tools/po_messages.py,
which is the app's and is read when it is there; every name is optional:

  SOURCES = ("extensions/*.py",)       more Python files for xgettext and for --check
  KEYWORDS = ("tr",)                   more xgettext keywords
  TABLES = ("NAMES",)                  dictionaries whose keys are messages (better: N_ on each)
  CONTEXTS = {"some_locale": "ctx"}    a module whose _ translates in a context (that context
                                       falls back to the message without one, in --check)
  def messages(root): ...              more messages src asks for: {(context or None, msgid)}
  NOT_TRANSLATIONS = {("src/x.py", "NAME"): "why"}   a table of words that --check would take
                                       for a dictionary of translations, and why it is not one

--update on Windows: MSYS2's xgettext writes location comments differently
from Linux's, so it rewrites thousands of lines of the .po files; run it on
Linux, or add the new entries to it.po by hand (docs of the template).
"""

import argparse
import ast
import importlib.util
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIELD = re.compile(r"(?<!\{)\{([^{}!:]*)[^{}]*\}(?!\})")       # {name}, {name:.1f}; not {{ }}
CALLS = ("_", "N_", "gettext", "pgettext", "ngettext", "npgettext")
KEYWORDS = ("--keyword=_", "--keyword=ngettext:1,2", "--keyword=pgettext:1c,2", "--keyword=npgettext:1c,2,3",
            "--keyword=N_")
EXTENSION = Path(__file__).resolve().parent / "po_messages.py"       # the app's, when it has one


class PoError(ValueError):
    pass


# ---- the app ----------------------------------------------------------------

def package(root: Path) -> Path:
    """The app's package: the one folder under src/ with an __init__.py."""
    src = Path(root) / "src"
    found = sorted(p for p in src.iterdir() if (p / "__init__.py").is_file()) if src.is_dir() else []
    if len(found) != 1:
        raise SystemExit(f"{src}: one package expected, {len(found)} found")
    return found[0]


def identity(root: Path) -> dict[str, str]:
    """The names the package's __init__.py sets to a text (APP_ID, SLUG,
    TEXTDOMAIN...), read with ast: nothing of the app is imported."""
    tree = ast.parse((package(root) / "__init__.py").read_text(encoding="utf-8"))
    names: dict[str, str] = {}

    def value(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.Name):
            return names.get(node.id)
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            left, right = value(node.left), value(node.right)
            return left + right if left is not None and right is not None else None
        if isinstance(node, ast.JoinedStr):
            parts = []
            for part in node.values:
                if isinstance(part, ast.FormattedValue) and part.conversion == -1 and part.format_spec is None:
                    part = value(part.value)
                elif isinstance(part, ast.Constant):
                    part = part.value
                else:
                    part = None
                if not isinstance(part, str):
                    return None
                parts.append(part)
            return "".join(parts)
        return None

    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            target, found = node.targets[0].id, value(node.value)
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.value is not None:
            target, found = node.target.id, value(node.value)
        else:
            continue
        if found is not None:
            names[target] = found
    return names


def domain(root: Path) -> str:
    names = identity(root)
    found = names.get("TEXTDOMAIN") or names.get("SLUG")
    if not found:
        raise SystemExit(f"{package(root) / '__init__.py'}: no TEXTDOMAIN")
    return found


@lru_cache(maxsize=None)
def extension():
    """The app's tools/po_messages.py (next to this file, whatever root is looked at), or None."""
    if not EXTENSION.is_file():
        return None
    spec = importlib.util.spec_from_file_location("po_messages", EXTENSION)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _extra(name: str, default):
    module = extension()
    return getattr(module, name, default) if module is not None else default


def domains(root):
    """Explicit library catalogues, each owning its source paths and output.

    DOMAINS in po_messages.py maps a domain to sources (directories), po,
    dest and optional qml_calls. Everything else belongs to the app domain.
    An unregistered nested catalogue still fails; no messages are discarded.
    """
    return dict(_extra('DOMAINS', {}))


def missing_catalogues(root):
    return [f'{name}: required catalogue is missing' for name in _extra('REQUIRED_CATALOGS', ())
            if not (Path(root) / name).is_file()]


def owns(path, root, name=None):
    for key, config in domains(root).items():
        if any(path.is_relative_to(Path(root) / folder) for folder in config['sources']):
            return name == key
    return name is None


def sources(root: Path) -> list[Path]:
    """The Python files xgettext reads: the package's, and the app's SOURCES."""
    found = set(package(root).rglob("*.py"))
    for pattern in _extra("SOURCES", ()):
        found.update(p for p in Path(root).glob(pattern) if p.is_file())
    return sorted(found)


# ---- the messages src asks for ------------------------------------------------

def _python_messages(tree: ast.AST, tables=(), contexts=None, plurals=None) -> set[tuple[str | None, str]]:
    """Resolve literal arguments, local tables and helper parameters without importing application code.

    Bindings are kept per lexical scope. Unknown runtime values (user names, remote
    responses) are not catalogued. Explicit fallback dictionaries contribute keys.
    `tables`: names of dictionaries whose keys are messages; `contexts`: {module: context}, a module
    whose _ translates in that context when this file imports _ from it; `plurals` receives the
    English plural of each ngettext: {(context, msgid): msgid_plural}.
    """
    bindings = {}
    scopes = {}
    functions = {}
    context_of_underscore = None
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and any(alias.name == "_" for alias in node.names):
            for module, context in (contexts or {}).items():
                if (node.module or "").endswith(module):
                    context_of_underscore = context

    def visit(node, scope):
        scopes[id(node)] = scope
        child_scope = scope
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            functions.setdefault(node.name, []).append(node)
            child_scope = node
        elif isinstance(node, (ast.DictComp, ast.ListComp, ast.SetComp, ast.GeneratorExp)):
            child_scope = node
        for child in ast.iter_child_nodes(node):
            visit(child, child_scope)

    visit(tree, tree)

    def bind(target, value, scope):
        if isinstance(target, ast.Name):
            bindings.setdefault((id(scope), target.id), []).append(value)
        elif isinstance(target, (ast.Tuple, ast.List)):
            for index, item in enumerate(target.elts):
                bind(item, (value, index), scope)

    for node in ast.walk(tree):
        scope = scopes[id(node)]
        if isinstance(node, ast.Assign):
            for target in node.targets:
                bind(target, node.value, scope)
        elif isinstance(node, ast.AnnAssign) and node.value:
            bind(node.target, node.value, scope)
        elif isinstance(node, (ast.For, ast.comprehension)):
            bind(node.target, (node.iter, "each"), scope)
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            for function in functions.get(node.func.id, []):
                parameters = function.args.posonlyargs + function.args.args
                for parameter, value in zip(parameters, node.args, strict=False):
                    bindings.setdefault((id(function), parameter.arg), []).append(value)
                for keyword in node.keywords:
                    if keyword.arg:
                        bindings.setdefault((id(function), keyword.arg), []).append(keyword.value)

    @lru_cache(maxsize=None)
    def values(node, trail=frozenset()):
        if isinstance(node, tuple):
            value, selector = node
            result = []
            for item in values(value, trail):
                if selector == "each" and isinstance(item, (tuple, list, dict)):
                    result.extend(item)
                elif isinstance(selector, int) and isinstance(item, (tuple, list)) and selector < len(item):
                    result.append(item[selector])
            return result
        if isinstance(node, ast.Name):
            scope = scopes.get(id(node), tree)
            key = (id(scope), node.id)
            if key not in bindings:
                parent = scopes.get(id(scope), tree)
                key = (id(parent), node.id)
            if key not in bindings:
                key = (id(tree), node.id)
            if key in trail:
                return []
            return [v for origin in bindings.get(key, []) for v in values(origin, trail | {key})]
        if isinstance(node, ast.Constant):
            return [node.value]
        if isinstance(node, (ast.List, ast.Tuple)):
            return [tuple(v for child in node.elts for v in values(child, trail))]
        if isinstance(node, ast.Dict):
            return [{k: v for key, value in zip(node.keys, node.values, strict=True) for k in values(key, trail)
                     for v in values(value, trail)}]
        if isinstance(node, ast.IfExp):
            return values(node.body, trail) + values(node.orelse, trail)
        if isinstance(node, ast.Subscript):
            return [v[key] for v in values(node.value, trail) for key in values(node.slice, trail)
                    if isinstance(v, dict) and key in v]
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name) and node.func.id == "dict":
                return [{k.arg: v for k in node.keywords for v in values(k.value, trail) if k.arg}]
            if isinstance(node.func, ast.Attribute) and node.func.attr in ("items", "values", "keys"):
                return [tuple(getattr(value, node.func.attr)()) for value in values(node.func.value, trail)
                        if isinstance(value, dict)]
        return []

    found = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id in tables for t in node.targets):
            for table in values(node.value):
                if isinstance(table, dict):
                    found.update((None, key) for key in table if isinstance(key, str) and key)
        if not isinstance(node, ast.Call):
            continue
        name = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
        if name not in CALLS or not node.args:
            continue
        contextual = name in ("pgettext", "npgettext") and len(node.args) > 1
        contexts_here = values(node.args[0]) if contextual else [context_of_underscore if name == "_" else None]
        first = 1 if contextual else 0
        messages = [(context, value) for context in contexts_here for value in values(node.args[first])
                    if (context is None or isinstance(context, str)) and isinstance(value, str) and value]
        found.update(messages)
        if plurals is not None and name in ("ngettext", "npgettext") and len(node.args) > first + 1:
            for plural in (v for v in values(node.args[first + 1]) if isinstance(v, str) and v):
                plurals.update(dict.fromkeys(messages, plural))
    return found


def _literal_messages(tree: ast.AST) -> set[tuple[str | None, str]]:
    """The messages xgettext finds on its own: a literal written in the call."""
    found = set()
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not node.args:
            continue
        name = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
        if name in ("pgettext", "npgettext") and len(node.args) > 1:
            context, message = node.args[0], node.args[1]
            if isinstance(context, ast.Constant) and isinstance(message, ast.Constant):
                found.add((context.value, message.value))
        elif name in CALLS and isinstance(node.args[0], ast.Constant):
            found.add((None, node.args[0].value))
    return found


NOOPS = ("QT_TR_NOOP", "QT_TRANSLATE_NOOP")


def _qml_messages(text: str, calls=('qsTr',), plurals=None) -> set[tuple[str | None, str]]:
    """The marked texts of a QML file (gui/casa/translator.py): call(text), call(text, context),
    call(one, many, n) for each of `calls` (qsTr, the kit's Theme.tr), QT_TR_NOOP(text) and
    QT_TRANSLATE_NOOP(context, text); a text written as literals joined with + too. `plurals`
    receives the English plural of each call with a number."""
    quoted = r'''"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*' '''.strip()
    invocation = r'\b(?:' + '|'.join(re.escape(call) for call in (*calls, *NOOPS)) + r')\s*\('
    tokens = re.compile(r"//[^\n]*|/\*[\s\S]*?\*/|" + quoted + '|' + invocation + r"|\w+|\S")
    stream = [m.group() for m in tokens.finditer(text) if not m.group().startswith(("//", "/*"))]

    def literal(position):
        """The literal (pieces joined with +) that starts at `position`, and where it ends."""
        pieces = []
        while position < len(stream) and stream[position].startswith(('"', "'")):
            pieces.append(ast.literal_eval(stream[position]))
            position += 1
            if position >= len(stream) or stream[position] != "+":
                break
            position += 1
        return ("".join(pieces) if pieces else None), position

    found = set()
    for index, token in enumerate(stream):
        if not re.fullmatch(invocation, token):
            continue
        name = token.split("(")[0].strip()
        args, position = [], index + 1
        while len(args) < 3:
            value, position = literal(position)
            args.append(value)
            if position >= len(stream) or stream[position] != ",":
                break
            position += 1
        if name == "QT_TRANSLATE_NOOP":
            if len(args) > 1 and args[0] and args[1]:
                found.add((args[0], args[1]))
        elif not args[0]:
            continue
        elif name != "QT_TR_NOOP" and len(args) == 3 and args[1]:
            found.add((None, args[0]))
            if plurals is not None:
                plurals[(None, args[0])] = args[1]
        elif name != "QT_TR_NOOP" and len(args) == 2 and args[1]:
            found.add((args[1], args[0]))
        else:
            found.add((None, args[0]))
    return found


def required_messages(root: Path = ROOT, literal: set | None = None, domain_name=None,
                      plurals: dict | None = None) -> set[tuple[str | None, str]]:
    """Messages required by src's Python (literal arguments and the tables resolved) and QML calls, by the
    app's SOURCES and by its tools/po_messages.py. With `literal` (a set), the messages xgettext finds on its own
    are added to it; with `plurals` (a dict), the English plural of each message asked with a number."""
    root = Path(root)
    tables, contexts = tuple(_extra("TABLES", ())), dict(_extra("CONTEXTS", {}))
    found = set()
    paths = set((root / "src").rglob("*.py")) | set((root / "src").rglob("*.qml"))
    for pattern in _extra("SOURCES", ()):
        paths.update(p for p in root.glob(pattern) if p.is_file())
    for path in sorted(paths):
        if not owns(path, root, domain_name):
            continue
        if path.suffix == ".py":
            tree = ast.parse(path.read_text(encoding="utf-8-sig"))
            found.update(_python_messages(tree, tables, contexts, plurals))
            if literal is not None:
                literal.update(_literal_messages(tree))
        else:
            calls = domains(root).get(domain_name, {}).get('qml_calls', ('qsTr',))
            found.update(_qml_messages(path.read_text(encoding="utf-8"), calls, plurals))
    more = _extra("messages", None)
    if more is not None and domain_name is None:
        found.update(more(root))
    found.discard((None, ""))
    return found


# ---- --update ------------------------------------------------------------------

def update(root: Path = ROOT) -> None:
    root = Path(root)
    name = domain(root)
    pot = root / "po" / f"{name}.pot"
    files = [p.relative_to(root).as_posix() for p in sources(root)]
    keywords = [*KEYWORDS, *(f"--keyword={k}" for k in _extra("KEYWORDS", ()))]
    literal: set = set()
    # what xgettext cannot see (the tables resolved, QML, the app's own) goes to it in a temporary source,
    # outside the checkout; nothing when there is nothing, so that the .pot is xgettext's alone
    plurals: dict = {}
    extra = sorted(required_messages(root, literal, plurals=plurals) - literal, key=str)

    def line(context, message):
        plural = plurals.get((context, message))
        if plural is not None:
            return (f"npgettext({context!r}, {message!r}, {plural!r}, 1)" if context
                    else f"ngettext({message!r}, {plural!r}, 1)")
        return f"pgettext({context!r}, {message!r})" if context else f"N_({message!r})"
    with tempfile.TemporaryDirectory() as folder:
        more = []
        if extra:
            more = [str(Path(folder) / "qml_and_tables.py")]
            Path(more[0]).write_text("\n".join(line(context, message) for context, message in extra), encoding="utf-8")
        subprocess.run(["xgettext", "--language=Python", *keywords, "--from-code=UTF-8", f"--package-name={name}",
                        "--add-comments=TRANSLATORS", "--output", str(pot), *files, *more], cwd=root, check=True)
    for po in sorted((root / "po").glob("*.po")):
        subprocess.run(["msgmerge", "--quiet", "--update", "--backup=none", str(po), str(pot)], check=True)


# ---- reading a .po ---------------------------------------------------------------

def parse(text: str, name: str = "po") -> list[dict]:
    """The entries of a .po file: {"msgctxt"?, "msgid", "msgid_plural"?, "msgstr" or "msgstr[n]"..., "fuzzy"};
    obsolete entries (#~) are left out."""
    entries: list[dict] = []
    entry: dict = {}
    key = None

    def close() -> None:
        nonlocal entry, key
        if "msgid" in entry:
            entries.append(entry)
        elif entry.get("msgctxt") is not None or len(entry) > 1:
            raise PoError(f"{name}: an entry without msgid")
        entry, key = {"fuzzy": False}, None

    close()
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#"):
            if line.startswith("#,") and "fuzzy" in (f.strip() for f in line[2:].split(",")):
                if "msgid" in entry:
                    close()
                entry["fuzzy"] = True
            elif "msgid" in entry and key is not None and key.startswith("msgstr"):
                close()
            continue
        word, _space, rest = line.partition(" ")
        if line.startswith('"'):
            if key is None:
                raise PoError(f"{name}:{n}: a string outside an entry")
            entry[key] += _string(line, name, n)
            continue
        if word in ("msgctxt", "msgid") and "msgid" in entry and key is not None and key.startswith("msgstr"):
            close()
        if word == "msgctxt" or word == "msgid" or word == "msgid_plural" or re.fullmatch(r"msgstr(\[\d+\])?", word):
            if word in entry:
                raise PoError(f"{name}:{n}: {word} twice in an entry")
            key = word
            entry[key] = _string(rest.strip(), name, n)
            continue
        raise PoError(f"{name}:{n}: what is this? {line[:40]}")
    close()
    return entries


def _string(quoted: str, name: str, n: int) -> str:
    if not (len(quoted) >= 2 and quoted[0] == quoted[-1] == '"'):
        raise PoError(f"{name}:{n}: not a quoted string")
    try:
        return ast.literal_eval(quoted)          # C's escapes are Python's: \n \t \" \\
    except (SyntaxError, ValueError) as error:
        raise PoError(f"{name}:{n}: {error}") from None


def check(entries: list[dict], name: str = "po") -> None:
    """A translation that names a {field} its source does not have would raise KeyError when it is formatted."""
    for e in entries:
        source = set(FIELD.findall(e["msgid"])) | set(FIELD.findall(e.get("msgid_plural", "")))
        for k, v in e.items():
            if k.startswith("msgstr") and v and e["msgid"]:
                extra = set(FIELD.findall(v)) - source
                if extra:
                    raise PoError(f"{name}: «{e['msgid'][:50]}» translated with {sorted(extra)} it does not have")


# ---- --check ---------------------------------------------------------------------

BROKEN = re.compile(r"[^\W\d_]\?[^\W\d_]|\s\?\s|�|Ã.|â€|Â")   # «un?immagine», «non ? disponibile», mojibake
PRINTF = re.compile(r"%(?:\([A-Za-z_]\w*\))?[sdifr]|%\d|%L?n\b")            # %s, %(name)s, Qt's %1 and %n
SOURCE_SUFFIXES = {".py", ".qml", ".js", ".json", ".txt", ".toml", ".yaml", ".yml", ".csv", ".html"}


def _literals(root: Path, domain_name=None) -> tuple[set, str]:
    """Every string written in src (and in the app's SOURCES): Python's constants (implicit concatenations
    joined), the other files' quoted strings; and the raw text of the files, for what is written another way."""
    root = Path(root)
    found, raw = set(), []
    paths = set((root / "src").rglob("*"))
    for pattern in _extra("SOURCES", ()):
        paths.update(root.glob(pattern))
    for p in sorted(paths):
        if not owns(p, root, domain_name):
            continue
        if not p.is_file() or p.suffix.lower() not in SOURCE_SUFFIXES:
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        raw.append(text)
        if p.suffix == ".py":
            try:
                found.update(n.value for n in ast.walk(ast.parse(text))
                             if isinstance(n, ast.Constant) and isinstance(n.value, str))
            except SyntaxError:
                pass
            continue
        for m in re.finditer(r'"((?:[^"\\\n]|\\.)*)"|\'((?:[^\'\\\n]|\\.)*)\'', text):
            s = m.group(1) if m.group(1) is not None else m.group(2)
            if "\\" in s:
                try:
                    s = s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")
                except UnicodeError:
                    pass
            found.add(s)
    return found, "\n".join(raw)


def problems(po: Path, used: tuple[set, str] | None = None, root: Path = ROOT) -> list[str]:
    """What --check refuses in one catalogue: broken encoding, keys twice, placeholders that differ between msgid
    and msgstr, entries no line of src asks for (used: the literals of src, _literals(root))."""
    root = Path(root)
    name = po.relative_to(root).as_posix() if po.is_relative_to(root) else po.name
    try:
        text = po.read_bytes().decode("utf-8")
    except UnicodeDecodeError as error:
        return [f"{name}: not UTF-8 ({error})"]
    try:
        entries = parse(text, name)
    except PoError as error:
        return [str(error)]
    out, seen = [], set()
    for e in entries:
        msgid, label = e["msgid"], e["msgid"][:60].replace("\n", " ")
        key = (e.get("msgctxt"), msgid)
        if key in seen:
            out.append(f"{name}: key twice: {key[0] or ''}|{label}")
        seen.add(key)
        if not msgid:
            continue
        forms = {k: v for k, v in e.items() if k.startswith("msgstr") and v}
        source = msgid + e.get("msgid_plural", "")
        for v in forms.values():
            if BROKEN.search(v) and not BROKEN.search(source):
                out.append(f"{name}: broken encoding in «{label}»: {v[:60]}")
            mine, theirs = set(FIELD.findall(source)), set(FIELD.findall(v))
            pm, pt = sorted(PRINTF.findall(source)), sorted(PRINTF.findall(v))
            if "msgid_plural" in e:
                bad = not theirs <= mine or not set(pt) <= set(pm)
            else:
                bad = mine != theirs or pm != pt
            if bad:
                out.append(f"{name}: placeholders differ in «{label}»: {sorted(mine | set(pm))} / {sorted(theirs | set(pt))}")
        if used is not None and msgid not in used[0] and msgid not in used[1]:
            out.append(f"{name}: no line of src uses «{label}»")
    return out


ACCENTED = re.compile("[àèéìòùÀÈÉÌÒÙ]")
ITALIAN_WORDS = frozenset(
    "il lo gli della dello dei degli delle alla allo agli alle dal dalla dai dalle nel nella nei nelle sul sulla sui "
    "sulle tra fra non che sono questo questa questi queste ciò anche oppure ancora già poi ogni senza sotto sopra "
    "dopo prima".split())


def _italian(text: str) -> bool:
    return bool(ACCENTED.search(text)) or any(w in ITALIAN_WORDS for w in re.findall(r"[^\W\d_]+", text.lower()))


def dictionaries(root: Path = ROOT, catalogues=()) -> list[str]:
    """The dictionaries of translations written in src (a translation is looked for in one place, po/): a Python
    dict (literal or dict(...)) with at least three pairs from a text to its translation, a translation being a msgstr
    of the catalogues (`catalogues`: {msgid: msgstr} of each one) or Italian words where the key has none. The app's
    NOT_TRANSLATIONS (tools/po_messages.py) names the tables that are something else, by the variable they are
    assigned to or by their first key."""
    root = Path(root)
    allowed_names = dict(_extra("NOT_TRANSLATIONS", {}))
    translations = {v for c in catalogues for k, v in c.items() if v and v != k}
    paths = set((root / "src").rglob("*.py"))
    for pattern in _extra("SOURCES", ()):
        paths.update(p for p in root.glob(pattern) if p.is_file() and p.suffix == ".py")
    out = []
    for path in sorted(paths):
        rel = path.relative_to(root).as_posix()
        try:
            tree = ast.parse(path.read_text(encoding="utf-8-sig"))
        except (SyntaxError, UnicodeDecodeError):
            continue
        allowed = {id(inner) for node in ast.walk(tree) if isinstance(node, ast.Assign)
                   for target in node.targets
                   if isinstance(target, ast.Name) and (rel, target.id) in allowed_names
                   for inner in ast.walk(node.value)}
        for node in ast.walk(tree):
            if id(node) in allowed:
                continue
            if isinstance(node, ast.Dict):
                pairs = [(k.value, v.value) for k, v in zip(node.keys, node.values, strict=True)
                         if isinstance(k, ast.Constant) and isinstance(v, ast.Constant)
                         and isinstance(k.value, str) and isinstance(v.value, str)]
            elif isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "dict":
                pairs = [(k.arg, k.value.value) for k in node.keywords if k.arg
                         and isinstance(k.value, ast.Constant) and isinstance(k.value.value, str)]
            else:
                continue
            if pairs and (rel, pairs[0][0]) in allowed_names:
                continue
            translated = [(key, value) for key, value in pairs if value != key and (
                value in translations or any(c.get(key) == value for c in catalogues)
                or (_italian(value) and not _italian(key)))]
            if len(translated) >= 3:
                key, value = translated[0]
                out.append(f"{rel}:{node.lineno}: a dictionary of translations ({len(translated)} pairs, such as "
                           f"«{key[:40]}» → «{value[:40]}»): the entries go in po/, the code calls _()")
    return out


def check_all(root: Path = ROOT) -> list[str]:
    """--check on every catalogue: one catalogue per language, directly in po/; no dictionary of translations in src."""
    root = Path(root)
    registered = domains(root)
    catalogues = [(None, root / 'po')]
    catalogues += [(name, root / config['po']) for name, config in registered.items()]
    fallback = set(dict(_extra("CONTEXTS", {})).values())
    out = missing_catalogues(root) + [f"{p.relative_to(root).as_posix()}: a second catalogue; its entries go in po/{p.name}"
           for p in sorted((root / "po").rglob("*.po")) if p.parent not in {folder for _, folder in catalogues}]
    translations = []
    for name, folder in catalogues:
        if name is not None and not list(folder.glob('*.po')):
            out.append(f'{folder}: registered domain has no catalogues')
        out.extend(_check_domain(root, name, folder, fallback, translations))
    return out + dictionaries(root, translations)


def _check_domain(root, name, folder, fallback, translations=None):
    out = []
    used = _literals(root, name)
    plurals: dict = {}
    required = required_messages(root, domain_name=name, plurals=plurals)
    for po in sorted(folder.glob('*.po')):
        out += problems(po, used, root)
        try:
            entries = parse(po.read_text(encoding="utf-8"))
        except (PoError, UnicodeError):
            continue  # the syntax/encoding diagnostic above is sufficient
        by_key = {(e.get("msgctxt"), e["msgid"]): e for e in entries}
        if translations is not None and po.stem != "en":
            translations.append({e["msgid"]: e.get("msgstr") for e in entries
                                 if "msgctxt" not in e and e.get("msgstr")})
        for context, message in sorted(required - set(by_key), key=str):
            if context in fallback and (None, message) in by_key:
                continue  # that module's _ falls back to the shared catalogue
            out.append(f"{po.name}: missing message: {context or ''}|{message}")
        for key in sorted(required & set(by_key), key=str):
            e = by_key[key]
            if e["fuzzy"] or not any(v for k, v in e.items() if k.startswith("msgstr")):
                out.append(f"{po.name}: not translated: {key[0] or ''}|{key[1]}")
            if key in plurals and "msgid_plural" not in e:
                out.append(f"{po.name}: asked with a number, without a plural: {key[0] or ''}|{key[1]}")
    return out


# ---- compiling ---------------------------------------------------------------------

def mo(entries: list[dict]) -> bytes:
    """The catalogue as GNU's .mo (little endian, no hash table: gettext reads it so)."""
    table = {}
    for e in entries:
        if e["fuzzy"] and e["msgid"]:
            continue
        key = e["msgid"] if "msgctxt" not in e else e["msgctxt"] + "\x04" + e["msgid"]
        if "msgid_plural" in e:
            forms = [e[k] for k in sorted((k for k in e if k.startswith("msgstr[")), key=lambda k: int(k[7:-1]))]
            if not any(forms):
                continue
            table[key + "\x00" + e["msgid_plural"]] = "\x00".join(forms)
        elif e.get("msgstr"):
            table[key] = e["msgstr"]
    if "" in table:                     # as msgfmt: the header without the date of the template (a build repeatable)
        table[""] = "".join(line for line in table[""].splitlines(keepends=True)
                            if not line.startswith("POT-Creation-Date:"))
    keys = sorted(table, key=lambda k: k.encode("utf-8"))
    ids = [k.encode("utf-8") for k in keys]
    strs = [table[k].encode("utf-8") for k in keys]
    n = len(keys)
    start = 7 * 4 + 16 * n
    offsets, blob = [], b""
    for data in ids + strs:
        offsets.append((len(data), start + len(blob)))
        blob += data + b"\x00"
    header = struct.pack("<7I", 0x950412DE, 0, n, 7 * 4, 7 * 4 + 8 * n, 0, start)
    return header + b"".join(struct.pack("<2I", *o) for o in offsets) + blob


def compile_python(po: Path, out: Path) -> None:
    entries = parse(po.read_text(encoding="utf-8"), po.name)
    check(entries, po.name)
    out.write_bytes(mo(entries))


QM_MAGIC = bytes((0x3C, 0xB8, 0x64, 0x18, 0xCA, 0xEF, 0x9C, 0x95, 0xCD, 0x21, 0x1C, 0xBF, 0x60, 0xA1, 0xBD, 0xDD))
QM_PLURALS = {"nplurals=2; plural=(n != 1);": b"\x01\x01"}       # Qt's numerus rule: form 0 when n == 1


def _elf_hash(data: bytes) -> int:
    """Qt's hash of a message (QTranslator: elfHash of the source, then of the comment)."""
    h = 0
    for byte in data:
        h = ((h << 4) + byte) & 0xFFFFFFFF
        g = h & 0xF0000000
        if g:
            h ^= g >> 24
        h &= ~g & 0xFFFFFFFF
    return h or 1


def _plural_rule(entries: list[dict], name: str) -> bytes:
    header = next((e.get("msgstr", "") for e in entries if e["msgid"] == "" and "msgctxt" not in e), "")
    found = re.search(r"Plural-Forms:\s*([^\n]*)", header)
    rule = re.sub(r"\s+", " ", found.group(1)).strip().rstrip(";") + ";" if found else "nplurals=2; plural=(n != 1);"
    if rule not in QM_PLURALS:
        raise PoError(f"{name}: the plural rule «{rule}» has no Qt numerus rule in QM_PLURALS")
    return QM_PLURALS[rule]


def qm(entries: list[dict], language: str = "", name: str = "po", english: bool = False) -> bytes:
    """The catalogue as Qt's .qm, for the QTranslator of C++ that answers the QML's qsTr (gui/casa/translator.py): no
    Python on the threads where Qt translates (the QML loader's: the stall of 20/11/2026). Its messages have
    no Qt context, so a text is the same in every QML file, as in gettext; msgctxt is Qt's disambiguation, and a
    plural keeps its English plural there: qsTr(text), qsTr(text, msgctxt), qsTr(one, many, n). With `english`, the
    plurals alone with their English forms (English has no catalogue, and Qt would say «3 module»)."""
    records = []
    for e in entries:
        if not e["msgid"] or (e["fuzzy"] and not english):
            continue
        if "msgid_plural" in e:
            if english:
                forms = [e["msgid"], e["msgid_plural"]]
            else:
                forms = [e[k] for k in sorted((k for k in e if k.startswith("msgstr[")), key=lambda k: int(k[7:-1]))]
            comment = e["msgid_plural"]
            if not all(forms):
                continue
        elif english:
            continue
        else:
            forms, comment = [e.get("msgstr", "")], e.get("msgctxt", "")
            if not forms[0]:
                continue
        source, note = e["msgid"].encode("utf-8"), comment.encode("utf-8")
        body = b"".join(b"\x03" + struct.pack(">I", len(f.encode("utf-16-be"))) + f.encode("utf-16-be") for f in forms)
        body += b"\x06" + struct.pack(">I", len(source)) + source
        if note:
            body += b"\x08" + struct.pack(">I", len(note)) + note
        records.append((_elf_hash(source + note), body + b"\x01"))
    if not records:
        return b""
    messages, hashes = b"", []
    for h, body in records:
        hashes.append((h, len(messages)))
        messages += body
    table = b"".join(struct.pack(">II", h, offset) for h, offset in sorted(hashes))
    out = QM_MAGIC
    for tag, data in ((0x42, table), (0x69, messages), (0x88, _plural_rule(entries, name)),
                      (0xA7, language.encode("utf-8"))):
        if data:
            out += bytes((tag,)) + struct.pack(">I", len(data)) + data
    return out


def compile_all(dest: Path, python: bool = False, root: Path = ROOT) -> list[Path]:
    """Every catalogue as gettext's .mo. For an app with QML, its own catalogues also as Qt's .qm beside the .mo,
    and en.qm with the English plurals when there is no po/en.po: what gui/casa/translator.py gives Qt."""
    root = Path(root)
    missing = missing_catalogues(root)
    if missing:
        raise PoError('; '.join(missing))
    name = domain(root)
    msgfmt = None if python else shutil.which("msgfmt")
    written = []
    catalogues = [(name, root / 'po', Path(dest))]
    catalogues += [(key, root / config['po'], root / config['dest'])
                   for key, config in domains(root).items()]
    qml = any(owns(p, root) for p in (root / "src").rglob("*.qml"))
    for key, folder, destination in catalogues:
        plurals: list[dict] = []
        for po in sorted(folder.glob('*.po')):
            out = destination / po.stem / 'LC_MESSAGES' / f'{key}.mo'
            _compile_one(po, out, msgfmt)
            written.append(out)
            if qml and key == name:
                entries = parse(po.read_text(encoding="utf-8"), po.name)
                written += _write_qm(out.with_suffix(".qm"), qm(entries, po.stem, po.name))
                plurals += [e for e in entries if "msgid_plural" in e and not e["fuzzy"]]
        if qml and key == name and not (folder / "en.po").is_file():
            english = destination / "en" / "LC_MESSAGES" / f"{key}.qm"
            english.parent.mkdir(parents=True, exist_ok=True)
            written += _write_qm(english, qm(plurals, "en", "en", english=True))
    return written


def _write_qm(path: Path, data: bytes) -> list[Path]:
    if not data:
        path.unlink(missing_ok=True)
        return []
    path.write_bytes(data)
    return [path]


def _compile_one(po, out, msgfmt):
        out.parent.mkdir(parents=True, exist_ok=True)
        if msgfmt:
            subprocess.run([msgfmt, "--check", "--output-file", str(out), str(po)], check=True)
        else:
            compile_python(po, out)


def main(argv: list[str] | None = None, root: Path = ROOT) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dest", type=Path, default=Path(root) / "locale")
    parser.add_argument("--update", action="store_true")
    parser.add_argument("--python", action="store_true", help="the compiler of this file, not msgfmt")
    parser.add_argument("--check", action="store_true",
                        help="refuse broken encoding, keys twice, placeholders that differ, entries src does not use, "
                             "messages src asks for that are missing")
    args = parser.parse_args(argv)
    if args.check:
        found = check_all(root)
        print("\n".join(found) or "po: every catalogue is in order")
        return 1 if found else 0
    if args.update:
        update(root)
    for out in compile_all(args.dest, args.python, root):
        print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
