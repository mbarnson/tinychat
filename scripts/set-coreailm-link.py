#!/usr/bin/env python3
"""Enable or disable the app target's CoreAILM package product link.

Use after installing Xcode/SDK 27:

    scripts/set-coreailm-link.py enable
    TINYCHAT_RUN_REAL_MODEL_UI_TEST=1 xcodebuild ... test

Use `disable` to return to the SDK-26.5-compatible project shape.
"""

from __future__ import annotations

import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1] / "tinychat.xcodeproj" / "project.pbxproj"
COREAILM_PRODUCT_ID = "9D91F0522FF5F245009E9EF7"
COREAILM_BUILD_FILE_ID = "9D91F0532FF5F245009E9EF7"
APP_FRAMEWORKS_PHASE_ID = "9D91F0192FF5F245009E9EF7"

BUILD_FILE_ENTRY = (
    f"\t\t{COREAILM_BUILD_FILE_ID} /* CoreAILM in Frameworks */ = "
    f"{{isa = PBXBuildFile; productRef = {COREAILM_PRODUCT_ID} /* CoreAILM */; }};\n"
)

EMPTY_APP_FRAMEWORKS = f"""\t\t{APP_FRAMEWORKS_PHASE_ID} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
"""

LINKED_APP_FRAMEWORKS = f"""\t\t{APP_FRAMEWORKS_PHASE_ID} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{COREAILM_BUILD_FILE_ID} /* CoreAILM in Frameworks */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
"""

EMPTY_APP_PACKAGE_DEPS = """\t\t\tpackageProductDependencies = (
\t\t\t);
\t\t\tproductName = tinychat;
"""

LINKED_APP_PACKAGE_DEPS = f"""\t\t\tpackageProductDependencies = (
\t\t\t\t{COREAILM_PRODUCT_ID} /* CoreAILM */,
\t\t\t);
\t\t\tproductName = tinychat;
"""


def ensure(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def enable(text: str) -> str:
    if COREAILM_BUILD_FILE_ID not in text:
        marker = "\n/* Begin PBXContainerItemProxy section */\n"
        ensure(marker in text, "Could not find insertion point for PBXBuildFile section")
        build_file_section = "\n/* Begin PBXBuildFile section */\n" + BUILD_FILE_ENTRY + "/* End PBXBuildFile section */\n"
        text = text.replace(marker, build_file_section + marker, 1)

    if LINKED_APP_FRAMEWORKS not in text:
        ensure(EMPTY_APP_FRAMEWORKS in text, "App Frameworks phase is not in the expected unlinked shape")
        text = text.replace(EMPTY_APP_FRAMEWORKS, LINKED_APP_FRAMEWORKS, 1)

    if LINKED_APP_PACKAGE_DEPS not in text:
        ensure(EMPTY_APP_PACKAGE_DEPS in text, "App packageProductDependencies is not in the expected unlinked shape")
        text = text.replace(EMPTY_APP_PACKAGE_DEPS, LINKED_APP_PACKAGE_DEPS, 1)

    return text


def disable(text: str) -> str:
    text = text.replace(LINKED_APP_FRAMEWORKS, EMPTY_APP_FRAMEWORKS, 1)
    text = text.replace(LINKED_APP_PACKAGE_DEPS, EMPTY_APP_PACKAGE_DEPS, 1)

    build_file_section = "\n/* Begin PBXBuildFile section */\n" + BUILD_FILE_ENTRY + "/* End PBXBuildFile section */\n"
    text = text.replace(build_file_section, "", 1)
    text = text.replace(BUILD_FILE_ENTRY, "", 1)
    return text


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in {"enable", "disable"}:
        print("usage: scripts/set-coreailm-link.py enable|disable", file=sys.stderr)
        return 2

    text = PROJECT.read_text()
    updated = enable(text) if sys.argv[1] == "enable" else disable(text)
    if updated == text:
        print(f"CoreAILM link already {sys.argv[1]}d")
        return 0

    PROJECT.write_text(updated)
    print(f"CoreAILM link {sys.argv[1]}d in {PROJECT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
