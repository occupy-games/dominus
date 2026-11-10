"""Dependency lint for the simulation/presentation boundary (not a type checker)."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
# Comments and string literals are separate tokens so prose does not trigger API checks.
TOKENS = re.compile(r'#[^\n]*|"""[\s\S]*?"""|\x27\x27\x27[\s\S]*?\x27\x27\x27|"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27|[A-Za-z_][A-Za-z_0-9]*|[^\s]')
FORBIDDEN = {
    "Input", "InputMap", "Time", "OS", "Engine", "DisplayServer", "RenderingServer",
    "AudioServer", "SceneTree", "Resource", "ResourceLoader", "ResourceSaver",
    "FileAccess", "DirAccess", "ConfigFile", "SQLite", "ProjectSettings",
    "PackedScene", "Texture2D", "Image", "Mesh", "Material", "Shader",
    "load", "get_node", "get_tree", "get_viewport", "get_parent", "add_child",
    "call_deferred", "get_process_delta_time", "get_physics_process_delta_time",
    "randf", "randi", "randomize", "seed", "randf_range", "randi_range",
    "weakref", "instance_from_id", "ClassDB", "Expression",
}


def violations(source, layer):
    tokens = [t for t in TOKENS.findall(source) if not t.startswith("#")]
    strings = [t for t in tokens if t.startswith(('"', "'"))]
    code = [t for t in tokens if not t.startswith(('"', "'"))]
    issues = []
    for literal in strings:
        value = literal.strip("\"'")
        if value.startswith(("res://", "uid://")):
            if layer == "simulation" and not (
                value.startswith("res://simulation/") and value.endswith(".gd")
                and ".." not in value.split("/")
            ):
                issues.append("simulation resource dependency: " + value)
            if layer == "presentation" and value.startswith("res://simulation/"):
                issues.append("presentation must receive data through application: " + value)
    if layer == "simulation":
        if "extends" not in code or code[code.index("extends") + 1:code.index("extends") + 2] != ["RefCounted"]:
            issues.append("simulation classes must explicitly extend RefCounted")
        for index, token in enumerate(code):
            # An explicitly supplied RandomNumberGenerator.seed property is allowed.
            if token in {"seed", "randi", "randf", "randi_range", "randf_range"} and index > 0 and code[index - 1] == ".":
                continue
            if token in FORBIDDEN or re.fullmatch(r"(?:Node|InputEvent|PhysicsServer|NavigationServer|RenderingDevice).*", token):
                issues.append("simulation service dependency: " + token)
    return sorted(set(issues))


def check_tree(root):
    issues = []
    for layer in ("simulation", "presentation"):
        directory = root / "game" / layer
        if not directory.is_dir():
            issues.append(f"missing layer directory: {directory}")
            continue
        for path in sorted(directory.rglob("*")):
            if path.suffix == ".gd":
                issues.extend(f"{path.relative_to(root)}: {issue}" for issue in violations(path.read_text(), layer))
            elif layer == "simulation" and path.suffix not in (".md", ".uid") and path.is_file():
                issues.append(f"{path.relative_to(root)}: simulation must contain code and documentation only")
    return issues


if __name__ == "__main__":
    errors = check_tree(ROOT)
    for error in errors:
        print(error)
    print(f"Architecture check: {len(errors)} violations")
    raise SystemExit(bool(errors))
