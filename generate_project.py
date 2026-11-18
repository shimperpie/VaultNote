#!/usr/bin/env python3
"""生成 VaultNote.xcodeproj — macOS SwiftUI 项目"""

import os
import uuid
import hashlib
import plistlib

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
XCODEPROJ = os.path.join(PROJECT_DIR, "VaultNote.xcodeproj")
PROJECT_FILE = os.path.join(XCODEPROJ, "project.pbxproj")

# ── 源文件列表 ──────────────────────────────────────────────
# (相对路径, 文件名, 最后文件组件)
SOURCES = [
    "VaultNote/VaultNoteApp.swift",
    "VaultNote/AppState.swift",
    "VaultNote/Models/Note.swift",
    "VaultNote/Services/CryptoService.swift",
    "VaultNote/Services/KeychainManager.swift",
    "VaultNote/Services/NoteManager.swift",
    "VaultNote/Views/ContentView.swift",
    "VaultNote/Views/LockView.swift",
    "VaultNote/Views/SetupView.swift",
    "VaultNote/Views/NoteListView.swift",
    "VaultNote/Views/NoteEditorView.swift",
    "VaultNote/Views/RichTextEditor.swift",
    "VaultNote/Utilities/Constants.swift",
]


def make_id(seed="") -> str:
    """生成 24 字符十六进制伪 UUID (Xcode PBX 风格)"""
    h = hashlib.md5(seed.encode()).hexdigest()[:24]
    return h.upper()


def main():
    # ── IDs ──────────────────────────────────────────────────
    ids = {}
    for s in SOURCES:
        ids[f"fileref_{s}"] = make_id(f"fileref_{s}")
    for s in SOURCES:
        ids[f"buildfile_{s}"] = make_id(f"buildfile_{s}")

    ids["group_root"] = make_id("group_root")
    ids["group_vaultnote"] = make_id("group_vaultnote")
    ids["group_models"] = make_id("group_models")
    ids["group_services"] = make_id("group_services")
    ids["group_views"] = make_id("group_views")
    ids["group_utilities"] = make_id("group_utilities")
    ids["group_products"] = make_id("group_products")

    ids["product_ref"] = make_id("product_ref")
    ids["product_buildfile"] = make_id("product_buildfile")  # not really used

    ids["native_target"] = make_id("native_target")
    ids["project_obj"] = make_id("project_obj")
    ids["main_group"] = make_id("main_group")

    ids["sources_phase"] = make_id("sources_phase")
    ids["resources_phase"] = make_id("resources_phase")  # not used but included

    ids["config_list_project"] = make_id("config_list_project")
    ids["config_list_target"] = make_id("config_list_target")
    ids["config_debug_project"] = make_id("config_debug_project")
    ids["config_release_project"] = make_id("config_release_project")
    ids["config_debug_target"] = make_id("config_debug_target")
    ids["config_release_target"] = make_id("config_release_target")

    # ── PBXBuildFile ────────────────────────────────────────
    build_files = {}
    for s in SOURCES:
        build_files[ids[f"buildfile_{s}"]] = {
            "isa": "PBXBuildFile",
            "fileRef": ids[f"fileref_{s}"],
        }

    # ── PBXFileReference ────────────────────────────────────
    file_refs = {}

    # Product
    file_refs[ids["product_ref"]] = {
        "isa": "PBXFileReference",
        "explicitFileType": "wrapper.application",
        "includeInIndex": "0",
        "path": "VaultNote.app",
        "sourceTree": "BUILT_PRODUCTS_DIR",
    }

    # Sources
    for s in SOURCES:
        name = os.path.basename(s)
        if s.endswith(".swift"):
            ftype = "sourcecode.swift"
        else:
            ftype = "text"
        file_refs[ids[f"fileref_{s}"]] = {
            "isa": "PBXFileReference",
            "lastKnownFileType": ftype,
            "path": name,
            "sourceTree": "<group>",
        }

    # ── PBXGroup ────────────────────────────────────────────
    # 子 groups
    def _sources_in(path):
        return [s for s in SOURCES if s.startswith(path)]

    group_models_files = [ids[f"fileref_{s}"] for s in _sources_in("VaultNote/Models/")]
    group_services_files = [ids[f"fileref_{s}"] for s in _sources_in("VaultNote/Services/")]
    group_views_files = [ids[f"fileref_{s}"] for s in _sources_in("VaultNote/Views/")]
    group_utilities_files = [ids[f"fileref_{s}"] for s in _sources_in("VaultNote/Utilities/")]
    group_root_files = [
        ids[f"fileref_{s}"]
        for s in SOURCES
        if s.startswith("VaultNote/") and "/" not in s[len("VaultNote/"):]
    ]

    groups = {}

    groups[ids["group_root"]] = {
        "isa": "PBXGroup",
        "children": [
            ids["group_vaultnote"],
            ids["group_products"],
        ],
        "sourceTree": "<group>",
    }

    groups[ids["group_vaultnote"]] = {
        "isa": "PBXGroup",
        "children": group_root_files
        + [
            ids["group_models"],
            ids["group_services"],
            ids["group_views"],
            ids["group_utilities"],
        ],
        "path": "VaultNote",
        "sourceTree": "<group>",
    }

    groups[ids["group_models"]] = {
        "isa": "PBXGroup",
        "children": group_models_files,
        "name": "Models",
        "path": "Models",
        "sourceTree": "<group>",
    }

    groups[ids["group_services"]] = {
        "isa": "PBXGroup",
        "children": group_services_files,
        "name": "Services",
        "path": "Services",
        "sourceTree": "<group>",
    }

    groups[ids["group_views"]] = {
        "isa": "PBXGroup",
        "children": group_views_files,
        "name": "Views",
        "path": "Views",
        "sourceTree": "<group>",
    }

    groups[ids["group_utilities"]] = {
        "isa": "PBXGroup",
        "children": group_utilities_files,
        "name": "Utilities",
        "path": "Utilities",
        "sourceTree": "<group>",
    }

    groups[ids["group_products"]] = {
        "isa": "PBXGroup",
        "children": [ids["product_ref"]],
        "name": "Products",
        "sourceTree": "<group>",
    }

    # ── PBXSourcesBuildPhase ─────────────────────────────────
    sources_phase = {
        ids["sources_phase"]: {
            "isa": "PBXSourcesBuildPhase",
            "buildActionMask": "2147483647",
            "files": [ids[f"buildfile_{s}"] for s in SOURCES],
            "runOnlyForDeploymentPostprocessing": "0",
        }
    }

    # ── PBXNativeTarget ──────────────────────────────────────
    native_target = {
        ids["native_target"]: {
            "isa": "PBXNativeTarget",
            "buildConfigurationList": ids["config_list_target"],
            "buildPhases": [ids["sources_phase"]],
            "buildRules": [],
            "dependencies": [],
            "name": "VaultNote",
            "productName": "VaultNote",
            "productReference": ids["product_ref"],
            "productType": "com.apple.product-type.application",
        }
    }

    # ── PBXProject ──────────────────────────────────────────
    project = {
        ids["project_obj"]: {
            "isa": "PBXProject",
            "attributes": {
                "BuildIndependentTargetsInParallel": "YES",
                "LastSwiftUpdateCheck": "1600",
                "LastUpgradeCheck": "1600",
            },
            "buildConfigurationList": ids["config_list_project"],
            "compatibilityVersion": "Xcode 15.0",
            "developmentRegion": "zh-Hans",
            "hasScannedForEncodings": "0",
            "knownRegions": ["en", "zh-Hans"],
            "mainGroup": ids["group_root"],
            "productRefGroup": ids["group_products"],
            "projectDirPath": "",
            "projectRoot": "",
            "targets": [ids["native_target"]],
        }
    }

    # ── Build Configs ───────────────────────────────────────
    build_settings_project_base = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "COPY_PHASE_STRIP": "NO",
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_TESTABILITY": "YES",
        "GCC_DYNAMIC_NO_PIC": "NO",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    }

    build_settings_project_release = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "COPY_PHASE_STRIP": "NO",
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_OPTIMIZATION_LEVEL": "s",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": "-O",
        "VALIDATE_PRODUCT": "YES",
    }

    build_settings_target_common = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": "",
        "ENABLE_HARDENED_RUNTIME": "YES",
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_KEY_LSMinimumSystemVersion": "14.0",
        "INFOPLIST_KEY_NSHumanReadableCopyright": "VaultNote - 私密笔记",
        "INFOPLIST_KEY_NSMainNibFile": "",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
        "MACOSX_DEPLOYMENT_TARGET": "14.0",
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.vaultnote.app",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
    }

    configs = {}

    configs[ids["config_debug_project"]] = {
        "isa": "XCBuildConfiguration",
        "buildSettings": build_settings_project_base,
        "name": "Debug",
    }

    configs[ids["config_release_project"]] = {
        "isa": "XCBuildConfiguration",
        "buildSettings": build_settings_project_release,
        "name": "Release",
    }

    configs[ids["config_debug_target"]] = {
        "isa": "XCBuildConfiguration",
        "buildSettings": build_settings_target_common
        | {"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"},
        "name": "Debug",
    }

    configs[ids["config_release_target"]] = {
        "isa": "XCBuildConfiguration",
        "buildSettings": build_settings_target_common,
        "name": "Release",
    }

    config_lists = {}
    config_lists[ids["config_list_project"]] = {
        "isa": "XCConfigurationList",
        "buildConfigurations": [ids["config_debug_project"], ids["config_release_project"]],
        "defaultConfigurationIsVisible": "0",
        "defaultConfigurationName": "Release",
    }
    config_lists[ids["config_list_target"]] = {
        "isa": "XCConfigurationList",
        "buildConfigurations": [ids["config_debug_target"], ids["config_release_target"]],
        "defaultConfigurationIsVisible": "0",
        "defaultConfigurationName": "Release",
    }

    # ── 组装 root object ────────────────────────────────────
    root_object = ids["project_obj"]

    objects = {}
    objects.update(build_files)
    objects.update(file_refs)
    objects.update(groups)
    objects.update(sources_phase)
    objects.update(native_target)
    objects.update(project)
    objects.update(configs)
    objects.update(config_lists)

    plist = {
        "archiveVersion": "1",
        "classes": {},
        "objectVersion": "56",
        "objects": objects,
        "rootObject": root_object,
    }

    # ── 写入 ─────────────────────────────────────────────────
    os.makedirs(XCODEPROJ, exist_ok=True)

    # 写入 XML plist (Xcode 可以读取)
    with open(PROJECT_FILE, "wb") as f:
        plistlib.dump(plist, f)

    print(f"✅ Xcode 项目已生成: {XCODEPROJ}")
    print(f"   包含 {len(SOURCES)} 个源文件")
    print()
    print("下一步:")
    print(f"   open {XCODEPROJ}")


if __name__ == "__main__":
    main()
