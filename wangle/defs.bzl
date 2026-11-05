load("@fbsource//tools/build_defs:fb_xplat_cxx_binary.bzl", "fb_xplat_cxx_binary")
load("@fbsource//tools/build_defs:fb_xplat_cxx_library.bzl", "fb_xplat_cxx_library")
load("@fbsource//tools/build_defs:fb_xplat_cxx_test.bzl", "fb_xplat_cxx_test")
load("@fbsource//tools/build_defs:fbsource_utils.bzl", "is_fbcode_compatible")
load(
    "@fbsource//tools/build_defs:platform_defs.bzl",
    "ANDROID",
    "APPLE",
    "CXX",
    "FBCODE",
    "IOS",
    "MACOSX",
    "WINDOWS",
)
load("@fbsource//tools/build_defs/xplat:deps_map_utils.bzl", "deps_map_utils")

CXXFLAGS = [
    "-frtti",
    "-fexceptions",
    "-Wno-error",
    "-Wno-unused-local-typedefs",
    "-Wno-unused-variable",
    "-Wno-sign-compare",
    "-Wno-comment",
    "-Wno-return-type",
    "-Wno-global-constructors",
]

FBANDROID_CXXFLAGS = [
    "-ffunction-sections",
    "-Wno-uninitialized",
]

FBOBJC_CXXFLAGS = [
    "-Wno-global-constructors",
]

WINDOWS_MSVC_CXXFLAGS = [
    "/EHs",
]

WINDOWS_CLANG_CXX_FLAGS = [
    "-Wno-deprecated-declarations",
    "-Wno-microsoft-cast",
    "-Wno-missing-braces",
    "-Wno-unused-function",
    "-DBOOST_HAS_THREADS",
]

# wangle must not opt into SSE4.2 on its own: it changes folly's F14 intrinsics
# mode, which has to match across every object in the link.
WINDOWS_CLANG_SSE4_FLAGS = select({
    "DEFAULT": [],
    "ovr_config//os:windows-gcc-or-clang": select({
        "DEFAULT": [],
        "ovr_config//cpu/x86:avx2": ["-msse4.2"],
        "ovr_config//cpu/x86:sse42": ["-msse4.2"],
    }),
})

DEFAULT_APPLE_SDKS = (IOS, MACOSX)

DEFAULT_PLATFORMS = (ANDROID, APPLE, CXX, FBCODE, WINDOWS)

def _compute_include_directories():
    base_path = native.package_name()
    if base_path == "xplat/wangle":
        return [".."]
    thrift_path = base_path[6:]
    return ["/".join(len(thrift_path.split("/")) * [".."])]

def wangle_cxx_library(
    name, compiler_flags = [], fbandroid_compiler_flags = [], fbobjc_compiler_flags = [], windows_compiler_flags = [], windows_msvc_compiler_flags_override = [], **kwargs
):
    """Translate a simpler declartion into the more complete library target"""
    fb_xplat_cxx_library(
        name = name,
        header_namespace = "",
        public_include_directories = _compute_include_directories(),
        apple_sdks = DEFAULT_APPLE_SDKS,
        compiler_flags = compiler_flags + CXXFLAGS + WINDOWS_CLANG_SSE4_FLAGS,
        platforms = DEFAULT_PLATFORMS,
        # fbcode dev builds link shared; a static copy of wangle in every `.so`
        # that uses it trips gflags' duplicate-flag check at startup. Keyed on
        # the runtime rather than the FBCODE arm: `fbobjc/mode/buck2/linux`
        # builds these targets with the CXX arm against fbcode's shared deps.
        preferred_linkage = select({
            "DEFAULT": select({
                "DEFAULT": "static",
                "ovr_config//build_mode/constraints:conda-linkage[static]": "any",
                "ovr_config//runtime:fbcode": "any",
            }),
            "ovr_config//build_mode:arvr_mode[enabled]": "static",
        }),
        fbandroid_compiler_flags = fbandroid_compiler_flags + FBANDROID_CXXFLAGS,
        fbobjc_compiler_flags = fbobjc_compiler_flags + FBOBJC_CXXFLAGS,
        windows_compiler_flags = windows_compiler_flags + WINDOWS_CLANG_CXX_FLAGS,
        windows_msvc_compiler_flags_override = windows_msvc_compiler_flags_override + WINDOWS_MSVC_CXXFLAGS,
        visibility = ["PUBLIC"],
        **kwargs,
    )

def wangle_cxx_binary(name, platforms = (CXX,), **kwargs):
    fb_xplat_cxx_binary(name = name, platforms = platforms, **kwargs)

def wangle_cxx_test(name, **kwargs):
    fb_xplat_cxx_test(name = name, platforms = (CXX, FBCODE), **kwargs)

# `cpp_library`-style front ends over `wangle_cxx_*`, so the `BUCK` files read
# like the fbcode ones they replaced. `fbcode//wangle/...` is a set of aliases
# into these targets.

def _convert_deps(deps, external_deps, keep_fbcode_only = False):
    """`cpp_library`-style deps -> fbsource deps.

    `convert_to_fbsource_fp_deps` drops a dep it has no xplat mapping for
    (e.g. `//thrift/test:...`). Rules that only build for FBCODE can keep those
    as explicit `fbcode//` deps, but only on hosts that can build fbcode at
    all: the fbcode cell does not resolve on macOS.
    """
    converted = []
    for dep in deps or []:
        xplat_dep = deps_map_utils.convert_to_fbsource_fp_deps([dep])
        if xplat_dep:
            converted.extend(xplat_dep)
        elif not dep.startswith("//") or dep.startswith("//xplat/"):
            # Already an fbsource label (`:x`, `//xplat/...`, `fbsource//...`).
            converted.append(dep)
        elif keep_fbcode_only and is_fbcode_compatible():
            converted.append("fbcode" + dep)
    return converted + deps_map_utils.convert_to_fbsource_tp_deps(external_deps or [])

def wangle_cpp_library(
    name,
    srcs = [],
    headers = [],
    private_headers = [],
    deps = None,
    exported_deps = None,
    external_deps = None,
    exported_external_deps = None,
    propagated_pp_flags = (),
    **kwargs,
):
    converted_deps = deps_map_utils.convert_all_to_fbsource_deps(
        deps = deps,
        exported_deps = exported_deps,
        external_deps = external_deps,
        exported_external_deps = exported_external_deps,
    )
    wangle_cxx_library(
        name = name,
        srcs = srcs,
        raw_headers = headers,
        headers = private_headers,
        exported_preprocessor_flags = propagated_pp_flags,
        deps = converted_deps.deps,
        exported_deps = converted_deps.exported_deps,
        # fbcode's `cpp_library` never re-exports `deps`; keep that for the
        # fbcode build so wangle's private deps stay private to its consumers.
        fbcode_reexport_all_header_dependencies = False,
        **kwargs,
    )

def wangle_cpp_unittest(name, deps = None, external_deps = None, supports_static_listing = None, remote_execution = None, test_main = None, **kwargs):
    # `supports_static_listing` only means something to the fbcode arm. That
    # arm always links `cpp_unittest`'s default main, which calls `folly::init`
    # (the wrapper does not take `test_main`); the other arms link folly's test
    # main too unless the target names its own.
    if supports_static_listing != None:
        kwargs["fbcode_supports_static_listing"] = supports_static_listing
    if remote_execution != None:
        kwargs["remote_execution"] = remote_execution
    wangle_cxx_test(
        name = name,
        use_gtest_dep = False,
        deps = _convert_deps(deps, external_deps, keep_fbcode_only = True) + select({
            "DEFAULT": [test_main or "fbsource//xplat/folly/test/common:test_main"],
            "ovr_config//runtime/constraints:fbcode": [],
        }),
        **kwargs,
    )

def wangle_cpp_binary(name, deps = None, external_deps = None, **kwargs):
    wangle_cxx_binary(
        name = name,
        deps = _convert_deps(deps, external_deps, keep_fbcode_only = True),
        platforms = (CXX, FBCODE),
        **kwargs,
    )
