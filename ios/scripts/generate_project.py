#!/usr/bin/env python3
"""Generate the checked-in Xcode project with Python's standard library only."""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def ident(key):
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()


def add(key, isa, **fields):
    ref = ident(key)
    objects[ref] = dict(isa=isa, **fields)
    return ref


def serialize(value, indent=0):
    pad = "\t" * indent
    if isinstance(value, dict):
        return "{\n" + "".join(pad + "\t" + json.dumps(str(k)) + " = " + serialize(v, indent + 1) + ";\n" for k, v in value.items()) + pad + "}"
    if isinstance(value, list):
        return "(\n" + "".join(pad + "\t" + serialize(v, indent + 1) + ",\n" for v in value) + pad + ")"
    return str(value) if isinstance(value, int) else json.dumps(str(value), ensure_ascii=False)


app_name = "NITechVacancyViewer"
unit_name = app_name + "Tests"
ui_name = app_name + "UITests"
file_refs = {}
app_sources = sorted((ROOT / app_name).rglob("*.swift"))
unit_sources = sorted((ROOT / unit_name).glob("*.swift"))
ui_sources = sorted((ROOT / ui_name).glob("*.swift"))
resources = sorted((ROOT / app_name / "Resources").glob("*.json"))
resources += [ROOT / app_name / "Resources" / name for name in ("Assets.xcassets", "extract-schedule.js", "PrivacyInfo.xcprivacy")]

for path in app_sources + unit_sources + ui_sources + resources:
    relative = path.relative_to(ROOT).as_posix()
    kind = {".swift": "sourcecode.swift", ".json": "text.json", ".js": "sourcecode.javascript", ".xcassets": "folder.assetcatalog", ".xcprivacy": "text.xml"}[path.suffix]
    file_refs[relative] = add("file:" + relative, "PBXFileReference", lastKnownFileType=kind, path=relative, sourceTree="<group>")

product_refs = []
target_refs = []
common = dict(
    CLANG_ENABLE_MODULES="YES", CLANG_ENABLE_OBJC_ARC="YES",
    IPHONEOS_DEPLOYMENT_TARGET="16.0", SDKROOT="iphoneos", SWIFT_VERSION="5.0",
    TARGETED_DEVICE_FAMILY="1,2", ENABLE_USER_SCRIPT_SANDBOXING="YES",
)
project_configs = []
for mode in ("Debug", "Release"):
    settings = dict(common, DEBUG_INFORMATION_FORMAT="dwarf" if mode == "Debug" else "dwarf-with-dsym")
    settings.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if mode == "Debug" else "-O", SWIFT_COMPILATION_MODE="singlefile" if mode == "Debug" else "wholemodule")
    if mode == "Debug":
        settings.update(ENABLE_TESTABILITY="YES", SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG", ONLY_ACTIVE_ARCH="YES")
    project_configs.append(add("project-config:" + mode, "XCBuildConfiguration", name=mode, buildSettings=settings))
project_config_list = add("project-config-list", "XCConfigurationList", buildConfigurations=project_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

for name, sources, product_type in (
    (app_name, app_sources, "com.apple.product-type.application"),
    (unit_name, [p for p in app_sources if p.parent.name == "Core"] + unit_sources, "com.apple.product-type.bundle.unit-test"),
    (ui_name, ui_sources, "com.apple.product-type.bundle.ui-testing"),
):
    is_app = name == app_name
    product = name + (".app" if is_app else ".xctest")
    product_ref = add("product:" + name, "PBXFileReference", explicitFileType="wrapper.application" if is_app else "wrapper.cfbundle", includeInIndex=0, path=product, sourceTree="BUILT_PRODUCTS_DIR")
    product_refs.append(product_ref)
    source_builds = [add("build:" + name + ":" + p.relative_to(ROOT).as_posix(), "PBXBuildFile", fileRef=file_refs[p.relative_to(ROOT).as_posix()]) for p in sources]
    phases = [add("sources:" + name, "PBXSourcesBuildPhase", buildActionMask=2147483647, files=source_builds, runOnlyForDeploymentPostprocessing=0), add("frameworks:" + name, "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)]
    resource_builds = [add("resource-build:" + p.name, "PBXBuildFile", fileRef=file_refs[p.relative_to(ROOT).as_posix()]) for p in resources] if is_app else []
    phases.append(add("resources:" + name, "PBXResourcesBuildPhase", buildActionMask=2147483647, files=resource_builds, runOnlyForDeploymentPostprocessing=0))
    configs = []
    for mode in ("Debug", "Release"):
        settings = dict(PRODUCT_NAME="$(TARGET_NAME)", PRODUCT_BUNDLE_IDENTIFIER="jp.nothingwillbenothing.nitechsearch" + ("" if is_app else "." + name.lower()), CODE_SIGN_STYLE="Automatic", GENERATE_INFOPLIST_FILE="YES", SUPPORTED_PLATFORMS="iphoneos iphonesimulator", SWIFT_EMIT_LOC_STRINGS="YES")
        if is_app:
            settings.update(ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon", ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME="AccentColor", MARKETING_VERSION="1.2", CURRENT_PROJECT_VERSION="4", INFOPLIST_KEY_NSLocalNetworkUsageDescription="学内の施設予約サーバーへ接続して講義室の空室状況を取得します。", INFOPLIST_KEY_CFBundleDisplayName="NITechSearch", INFOPLIST_KEY_LSApplicationCategoryType="public.app-category.education", INFOPLIST_KEY_UILaunchScreen_Generation="YES", INFOPLIST_KEY_UIApplicationSceneManifest_Generation="YES", INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents="YES", INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone="UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight", INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad="UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight", LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks"])
        else:
            settings.update(LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"])
            if name == ui_name:
                settings["TEST_TARGET_NAME"] = app_name
        configs.append(add("config:" + name + ":" + mode, "XCBuildConfiguration", name=mode, buildSettings=settings))
    config_list = add("config-list:" + name, "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
    dependencies = []
    if name == ui_name:
        proxy = add("ui-proxy", "PBXContainerItemProxy", containerPortal=ident("project"), proxyType=1, remoteGlobalIDString=ident("target:" + app_name), remoteInfo=app_name)
        dependencies.append(add("ui-dependency", "PBXTargetDependency", target=ident("target:" + app_name), targetProxy=proxy))
    target_refs.append(add("target:" + name, "PBXNativeTarget", buildConfigurationList=config_list, buildPhases=phases, buildRules=[], dependencies=dependencies, name=name, productName=name, productReference=product_ref, productType=product_type))

products = add("products", "PBXGroup", children=product_refs, name="Products", sourceTree="<group>")
main_group = add("main-group", "PBXGroup", children=list(file_refs.values()) + [products], sourceTree="<group>")
project = add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1600", "TargetAttributes": {ident("target:" + ui_name): {"TestTargetID": ident("target:" + app_name)}}}, buildConfigurationList=project_config_list, compatibilityVersion="Xcode 14.0", developmentRegion="ja", hasScannedForEncodings=0, knownRegions=["ja", "en", "Base"], mainGroup=main_group, productRefGroup=products, projectDirPath="", projectRoot="", targets=target_refs)

project_dir = ROOT / (app_name + ".xcodeproj")
project_dir.mkdir(exist_ok=True)
document = dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project)
(project_dir / "project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize(document) + "\n", encoding="utf-8", newline="\n")

scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")
build_action = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
entries = ET.SubElement(build_action, "BuildActionEntries")


def buildable(parent, name):
    ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=ident("target:" + name), BuildableName=name + (".app" if name == app_name else ".xctest"), BlueprintName=name, ReferencedContainer="container:" + app_name + ".xcodeproj")


for name in (app_name, unit_name, ui_name):
    entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES" if name == app_name else "NO", buildForProfiling="YES" if name == app_name else "NO", buildForArchiving="YES" if name == app_name else "NO", buildForAnalyzing="YES")
    buildable(entry, name)
test_action = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
testables = ET.SubElement(test_action, "Testables")
for name in (unit_name, ui_name):
    buildable(ET.SubElement(testables, "TestableReference", skipped="NO"), name)
launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", debugServiceExtension="internal", allowLocationSimulation="YES")
buildable(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), app_name)
profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES", savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
buildable(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), app_name)
ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
ET.indent(scheme)
scheme_dir = project_dir / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
ET.ElementTree(scheme).write(scheme_dir / (app_name + ".xcscheme"), encoding="UTF-8", xml_declaration=True)
print(f"Generated {project_dir.name}: {len(app_sources)} app sources, unit tests, UI tests.")
