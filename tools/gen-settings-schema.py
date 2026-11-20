"""Generates plugin/src/15_schema.lua from retail UtilityBelt's C# source.

Usage: python tools/gen-settings-schema.py <UtilityBelt source folder> [out.lua]

Reads every tool ([Name("X")] class) and its settings declarations
([Summary] public readonly Setting<T> Name = new Setting<T>(default)), following
composite ISetting classes (ColorToggleOption and friends) into their fields.
The output lists each setting's full name (as /ub opt uses it), type, default
and summary, so the plugin's settings window and /ub opt match retail exactly.
Only reads files; run it by hand when the UB baseline changes and commit the result.
"""
import json
import os
import re
import sys

SETTING_KINDS = {"Setting": "setting", "CharacterState": "state", "Global": "global"}
SKIP_TOOLS = {"PlayerOptions", "Client"}  # retail client options and UI layout: no AC:Unreal equivalent


def strip_comments(text):
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '"' or (c == '@' and i + 1 < n and text[i + 1] == '"'):
            verbatim = c == '@'
            j = i + (2 if verbatim else 1)
            while j < n:
                if verbatim and text[j] == '"' and j + 1 < n and text[j + 1] == '"':
                    j += 2
                    continue
                if not verbatim and text[j] == '\\':
                    j += 2
                    continue
                if text[j] == '"':
                    break
                j += 1
            out.append(text[i:j + 1])
            i = j + 1
        elif c == "'" and i + 2 < n:
            j = text.find("'", i + 2 if text[i + 1] == '\\' else i + 1)
            j = j if j > 0 else i
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def match_brace(text, start):
    """Index just past the brace/paren that closes text[start]."""
    open_c = text[start]
    close_c = {"{": "}", "(": ")", "<": ">"}[open_c]
    depth, i, n = 0, start, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == '\\' else 1
            i = j
        elif c == open_c:
            depth += 1
        elif c == close_c:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


CLASS_RE = re.compile(r"\bclass\s+(\w+)\s*(?::\s*([\w.<>, ]+?))?\s*\{")


def find_classes(text):
    """{name: (body_without_nested_classes, attrs_text, bases, full_body)} for every class."""
    classes = {}
    for m in CLASS_RE.finditer(text):
        body_start = m.end() - 1
        body_end = match_brace(text, body_start)
        body = text[body_start + 1:body_end - 1]
        # Attributes directly before the class keyword.
        head = re.sub(r"(?:\b(?:public|internal|private|static|sealed|abstract|partial)\s*)+$", "", text[max(0, m.start() - 20000):m.start()].rstrip()).rstrip()
        attrs = attrs_before(head)
        # Remove nested class bodies so field scans see only direct members.
        flat, k = [], 0
        for nm in CLASS_RE.finditer(body):
            if nm.start() < k:
                continue
            flat.append(body[k:nm.start()])
            k = match_brace(body, nm.end() - 1)
        flat.append(body[k:])
        classes.setdefault(m.group(1), ("".join(flat), attrs, m.group(2) or "", body))
    return classes


def attrs_before(head):
    """The [Attribute(...)] blocks that end exactly at the end of head (scanning backwards)."""
    end, parts = len(head), []
    while end > 0 and head[end - 1] == "]":
        depth, i, in_str = 0, end - 1, False
        while i >= 0:
            c = head[i]
            if c == '"' and (i == 0 or head[i - 1] != '\\'):
                in_str = not in_str
            elif not in_str:
                if c == "]":
                    depth += 1
                elif c == "[":
                    depth -= 1
                    if depth == 0:
                        break
            i -= 1
        if i < 0:
            break
        parts.append(head[i:end])
        end = len(head[:i].rstrip())
        head = head[:end]
    return "\n".join(reversed(parts))


def attr_string(attrs, name):
    m = re.search(r"\[\s*" + name + r"\s*\(\s*@?\"((?:[^\"\\]|\\.|\"\")*)\"", attrs)
    if not m:
        return None
    return m.group(1).replace('\\"', '"').replace('""', '"')


FIELD_RE = re.compile(
    r"public\s+(?:readonly\s+)?(?:static\s+)?"
    r"([\w.]+(?:<[\w.<>, ?]+>)?\??)\s+(\w+)\s*=\s*new\s+([\w.]+(?:<[\w.<>, ?]+>)?)\s*\(")


def split_args(text):
    args, depth, cur, i = [], 0, [], 0
    while i < len(text):
        c = text[i]
        if c == '"':
            j = i + 1
            while j < len(text) and text[j] != '"':
                j += 2 if text[j] == '\\' else 1
            cur.append(text[i:j + 1])
            i = j + 1
            continue
        if c in "(<{[":
            depth += 1
        elif c in ")>}]":
            depth -= 1
        if c == "," and depth == 0:
            args.append("".join(cur).strip())
            cur = []
        else:
            cur.append(c)
        i += 1
    if "".join(cur).strip():
        args.append("".join(cur).strip())
    return args


NAMED_COLORS = {
    "White": 0xFFFFFFFF, "Black": 0xFF000000, "Red": 0xFFFF0000, "Lime": 0xFF00FF00, "Green": 0xFF008000,
    "Blue": 0xFF0000FF, "Yellow": 0xFFFFFF00, "Orange": 0xFFFFA500, "Purple": 0xFF800080, "Cyan": 0xFF00FFFF,
    "Magenta": 0xFFFF00FF, "Gray": 0xFF808080, "Grey": 0xFF808080, "LightGray": 0xFFD3D3D3, "DarkGray": 0xFFA9A9A9,
    "Gold": 0xFFFFD700, "Pink": 0xFFFFC0CB, "LightBlue": 0xFFADD8E6, "LightGreen": 0xFF90EE90, "Brown": 0xFFA52A2A,
    "Aqua": 0xFF00FFFF, "Transparent": 0x00FFFFFF, "SkyBlue": 0xFF87CEEB, "Violet": 0xFFEE82EE, "Tomato": 0xFFFF6347,
    "OrangeRed": 0xFFFF4500, "LawnGreen": 0xFF7CFC00, "DodgerBlue": 0xFF1E90FF, "Silver": 0xFFC0C0C0,
}


def to_signed(v):
    return v - 0x100000000 if v >= 0x80000000 else v


def eval_default(expr, ctype, params=None):
    """Returns (ok, value). Unknown expressions return (False, raw text)."""
    e = expr.strip()
    if params and e in params:
        return params[e]
    if e in ("true", "false"):
        return True, e == "true"
    if e == "null":
        return True, None
    m = re.fullmatch(r"\"((?:[^\"\\]|\\.)*)\"", e)
    if m:
        return True, m.group(1).encode().decode("unicode_escape")
    m = re.fullmatch(r"\(?\s*(?:int|uint|float|double)?\s*\)?\s*(-?(?:0x[0-9A-Fa-f]+|\d+(?:\.\d+)?))[fFdDuUlL]*", e)
    if m:
        s = m.group(1)
        v = int(s, 16) if s.lower().startswith(("0x", "-0x")) else (float(s) if "." in s else int(s))
        if isinstance(v, int) and ctype in ("int",) and v > 0x7FFFFFFF:
            v = to_signed(v)
        return True, v
    if re.fullmatch(r"[\d\s*+\-/().]+", e):
        try:
            return True, eval(e, {"__builtins__": {}})
        except Exception:
            pass
    m = re.fullmatch(r"(?:System\.Drawing\.)?Color\.(\w+)\.ToArgb\(\)", e)
    if m and m.group(1) in NAMED_COLORS:
        return True, to_signed(NAMED_COLORS[m.group(1)])
    m = re.fullmatch(r"(?:System\.Drawing\.)?Color\.FromArgb\(([^)]*)\)\.ToArgb\(\)", e)
    if m:
        parts = [p.strip() for p in m.group(1).split(",")]
        try:
            nums = [int(p, 0) for p in parts]
            if len(nums) == 3:
                nums = [255] + nums
            if len(nums) == 4:
                return True, to_signed((nums[0] << 24) | (nums[1] << 16) | (nums[2] << 8) | nums[3])
            if len(nums) == 1:
                return True, nums[0]
        except ValueError:
            pass
    m = re.fullmatch(r"(?:[\w.]+\.)?(\w+)\.(\w+)", e)
    if m:
        return True, m.group(2)   # enum member, e.g. ChatMessageType.System -> "System"
    m = re.fullmatch(r"new\s+[\w.]*(?:ObservableCollection|List)<[^()]*>\s*\(\s*\)\s*(\{(.*)\})?", e, re.S)
    if m:
        items = []
        for item in split_args(m.group(2) or ""):
            ok, v = eval_default(item, "")
            if ok:
                items.append(v)
        return True, items
    m = re.fullmatch(r"new\s+[\w.]*(?:ObservableDictionary|Dictionary)<[^()]*>\s*\(\s*\)\s*(\{(.*)\})?", e, re.S)
    if m:
        out = {}
        for pair in re.finditer(r"\{([^{}]*)\}", m.group(2) or ""):
            kv = split_args(pair.group(1))
            if len(kv) == 2:
                ok1, k = eval_default(kv[0], "")
                ok2, v = eval_default(kv[1].replace(" .", " 0.").replace("(.", "(0.") if kv[1].startswith(".") is False else "0" + kv[1], "")
                if ok1 and ok2:
                    out[str(k)] = v
        return True, out
    return False, e


def type_of(inner):
    t = inner.replace(" ", "")
    nullable = t.endswith("?")
    t = t.rstrip("?")
    simple = {"bool": "bool", "int": "int", "uint": "int", "short": "int", "long": "int", "byte": "int",
              "float": "float", "double": "float", "string": "string", "String": "string"}
    if t in simple:
        return simple[t], nullable
    if re.fullmatch(r"ObservableCollection<(string|String)>", t):
        return "list", nullable
    if t.startswith("ObservableCollection<"):
        return "complex_list", nullable
    if t.startswith("ObservableDictionary<") or t.startswith("Dictionary<"):
        return "dict", nullable
    if re.fullmatch(r"[\w.]+", t):
        return "enum", nullable
    return "complex", nullable


def csharp_default(kind):
    return {"bool": False, "int": 0, "float": 0, "string": "", "list": [], "dict": {}}.get(kind)


def parse_ctor(class_name, full_body):
    """Returns (param_names, {field: expr}, base_args) for the first constructor with params."""
    m = re.search(r"public\s+" + class_name + r"\s*\(([^)]*)\)\s*(?::\s*base\s*\(([^)]*)\))?\s*\{", full_body)
    if not m:
        return [], {}, []
    params = [p.strip().split()[-1].split("=")[0].strip() for p in m.group(1).split(",") if p.strip()]
    body = full_body[m.end() - 1:match_brace(full_body, m.end() - 1)]
    assigns = {}
    for a in re.finditer(r"(\w+)\.Value\s*=\s*([^;]+);", body):
        assigns[a.group(1)] = a.group(2).strip()
    return params, assigns, split_args(m.group(2) or "")


def expand_composite(cls, args, ctx_params, classes, prefix, out, problems, depth):
    """Fields of a composite ISetting class and its base classes, with constructor defaults."""
    if cls not in classes or depth > 6:
        return
    sub_body, _, bases, sub_full = classes[cls]
    params, assigns, base_args = parse_ctor(cls, sub_full)
    pmap = {}
    for i, p in enumerate(params):
        if i < len(args):
            pmap[p] = eval_default(args[i], "", ctx_params)
    base = (bases.split(",")[0].strip().split(".")[-1] if bases else "")
    if base and base in classes and base != "ISetting":
        expand_composite(base, base_args, pmap, classes, prefix, out, problems, depth + 1)
    collect(sub_body, classes, prefix, out, problems, pmap, assigns, depth + 1)


def collect(body, classes, prefix, out, problems, ctx_params=None, ctor_assigns=None, depth=0):
    for m in FIELD_RE.finditer(body):
        decl_type, name, new_type = m.group(1), m.group(2), m.group(3)
        attrs = attrs_before(body[max(0, m.start() - 20000):m.start()].rstrip())
        args_start = m.end() - 1
        args_end = match_brace(body, args_start)
        args = split_args(body[args_start + 1:args_end - 1])
        base = re.match(r"([\w.]+)", new_type).group(1).split(".")[-1]
        summary = attr_string(attrs, "Summary") or ""
        hidden = "DontShowInSettings" in attrs
        hotkey = "Hotkey" in attrs
        full = prefix + name
        if base in SETTING_KINDS:
            inner = re.search(r"<(.+)>", new_type)
            inner = inner.group(1) if inner else "bool"
            kind, nullable = type_of(inner)
            entry = {"name": full, "type": kind, "summary": summary, "store": SETTING_KINDS[base]}
            if hidden:
                entry["hidden"] = True
            if hotkey:
                entry["hotkey"] = True
            if kind in ("enum", "complex", "complex_list"):
                entry["cstype"] = inner
            expr = None
            if ctor_assigns and name in ctor_assigns:
                expr = ctor_assigns[name]
            elif args and not args[0].startswith(("(", "value")) and "=>" not in args[0]:
                expr = args[0]
            if expr is not None:
                ok, val = eval_default(expr, kind, ctx_params)
                if ok:
                    entry["default"] = val
                else:
                    entry["default_expr"] = val
                    problems.append(f"{full}: default not resolved: {val}")
            else:
                d = csharp_default(kind)
                if d is not None and not nullable:
                    entry["default"] = d
            out.append(entry)
        elif base in classes and depth < 4:
            expand_composite(base, args, ctx_params, classes, full + ".", out, problems, depth)


def main():
    src = sys.argv[1]
    out_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "plugin", "src", "15_schema.lua")
    texts = []
    for root, _, files in os.walk(src):
        for f in files:
            if f.endswith(".cs"):
                with open(os.path.join(root, f), encoding="utf-8-sig", errors="replace") as fh:
                    texts.append((os.path.join(root, f), strip_comments(fh.read())))
    classes = {}
    for _, t in texts:
        for k, v in find_classes(t).items():
            classes.setdefault(k, v)
    tools, problems = [], []
    for path, t in texts:
        if os.sep + "Tools" + os.sep not in path:
            continue
        for cname, (body, attrs, bases, _) in find_classes(t).items():
            tool = attr_string(attrs, "Name")
            if not tool or "ToolBase" not in bases or tool in SKIP_TOOLS:
                continue
            settings = []
            collect(body, classes, tool + ".", settings, problems)
            tools.append({"name": tool, "summary": attr_string(attrs, "Summary") or "",
                          "leaftide": (os.sep + "Leaftide" + os.sep) in path, "settings": settings})
    tools.sort(key=lambda x: x["name"].lower())

    def lua(v, ind=""):
        if v is None:
            return "nil"
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, (int, float)):
            return repr(v)
        if isinstance(v, str):
            return json.dumps(v, ensure_ascii=False)
        if isinstance(v, list):
            return "{" + ", ".join(lua(x, ind) for x in v) + "}"
        if isinstance(v, dict):
            return "{" + ", ".join((k if re.fullmatch(r"[A-Za-z_]\w*", k) else "[" + json.dumps(k) + "]") + " = " + lua(x, ind) for k, x in v.items()) + "}"
        raise TypeError(v)

    lines = ["-- GENERATED by tools/gen-settings-schema.py from UtilityBelt ILT source. Do not edit.",
             "-- Every retail UB setting: full name (as /ub opt uses it), type, default, summary.",
             "-- store: setting = settings.json (profile), state = state.json (per character).",
             "local UB_SCHEMA = {"]
    count = 0
    for tool in tools:
        lines.append("    {name = %s, summary = %s, leaftide = %s, settings = {" % (
            lua(tool["name"]), lua(tool["summary"]), lua(tool["leaftide"])))
        for s in tool["settings"]:
            lines.append("        " + lua(s) + ",")
            count += 1
        lines.append("    }},")
    lines.append("}")
    with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"{len(tools)} tools, {count} settings -> {out_path}")
    for p in problems:
        print("note", p)


if __name__ == "__main__":
    main()
