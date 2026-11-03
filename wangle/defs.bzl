load("@fbcode_macros//build_defs:cpp_binary.bzl", "cpp_binary")
load("@fbcode_macros//build_defs:cpp_library.bzl", "cpp_library")
load("@fbcode_macros//build_defs:cpp_unittest.bzl", "cpp_unittest")
load("@fbsource//tools/build_defs:cell_defs.bzl", "get_fbsource_cell")
load("@fbsource//tools/build_defs:fb_xplat_cxx_binary.bzl", "fb_xplat_cxx_binary")
load("@fbsource//tools/build_defs:fb_xplat_cxx_library.bzl", "fb_xplat_cxx_library")
load("@fbsource//tools/build_defs:fb_xplat_cxx_test.bzl", "fb_xplat_cxx_test")
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
    "-msse4.2",
    "-DBOOST_HAS_THREADS",
]

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
        compiler_flags = compiler_flags + CXXFLAGS,
        platforms = DEFAULT_PLATFORMS,
        preferred_linkage = "static",
        fbandroid_compiler_flags = fbandroid_compiler_flags + FBANDROID_CXXFLAGS,
        fbobjc_compiler_flags = fbobjc_compiler_flags + FBOBJC_CXXFLAGS,
        windows_compiler_flags = windows_compiler_flags + WINDOWS_CLANG_CXX_FLAGS,
        windows_msvc_compiler_flags_override = windows_msvc_compiler_flags_override + WINDOWS_MSVC_CXXFLAGS,
        visibility = ["PUBLIC"],
        **kwargs,
    )

def wangle_cxx_binary(name, **kwargs):
    fb_xplat_cxx_binary(name = name, platforms = (CXX,), **kwargs)

def wangle_cxx_test(name, **kwargs):
    fb_xplat_cxx_test(name = name, platforms = (CXX,), **kwargs)

# `cpp_library`-style front ends: one declaration per target that builds with
# the fbcode macros in the fbcode cell and with `wangle_cxx_*` in xplat.

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
    if get_fbsource_cell() == "fbcode":
        cpp_library(
            name = name,
            srcs = srcs,
            headers = headers,
            private_headers = private_headers,
            deps = deps,
            exported_deps = exported_deps,
            external_deps = external_deps,
            exported_external_deps = exported_external_deps,
            propagated_pp_flags = propagated_pp_flags,
            **kwargs,
        )
        return
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
        **kwargs,
    )

def wangle_cpp_unittest(name, deps = None, external_deps = None, supports_static_listing = None, remote_execution = None, test_main = None, **kwargs):
    if get_fbsource_cell() == "fbcode":
        for key, value in (
            ("supports_static_listing", supports_static_listing),
            ("remote_execution", remote_execution),
            ("test_main", test_main),
        ):
            if value != None:
                kwargs[key] = value
        cpp_unittest(name = name, deps = deps, external_deps = external_deps, **kwargs)
        return

    # `supports_static_listing` and `remote_execution` are `cpp_unittest`-only.
    # `cpp_unittest`'s default main calls `folly::init`, so link folly's test
    # main here too unless the target names its own.
    converted_deps = deps_map_utils.convert_all_to_fbsource_deps(
        deps = (deps or []) + [test_main or "fbsource//xplat/folly/test/common:test_main"],
        external_deps = external_deps,
    )
    wangle_cxx_test(name = name, use_gtest_dep = False, deps = converted_deps.deps, **kwargs)

def wangle_cpp_binary(name, deps = None, external_deps = None, **kwargs):
    if get_fbsource_cell() == "fbcode":
        cpp_binary(name = name, deps = deps, external_deps = external_deps, **kwargs)
        return
    converted_deps = deps_map_utils.convert_all_to_fbsource_deps(
        deps = deps,
        external_deps = external_deps,
    )
    wangle_cxx_binary(name = name, deps = converted_deps.deps, **kwargs)
