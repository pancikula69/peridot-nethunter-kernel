# Kleaf workspace for Xiaomi peridot (SM8650) kernel build.
load("//build/kernel/kleaf:workspace.bzl", "define_kleaf_workspace")

define_kleaf_workspace(
    # Kernel source is in msm-kernel/, not the default //common
    common_kernel_package = "//msm-kernel",
)

load("//build/kernel/kleaf:workspace_epilog.bzl", "define_kleaf_workspace_epilog")
define_kleaf_workspace_epilog()

### DTC (device-tree compiler, compiled from source by Bazel) ###
new_local_repository(
    name = "dtc",
    path = "external/dtc",
    build_file = "msm-kernel/BUILD.dtc",
)

### rules_pkg stub (prebuilts/kernel-build-tools/BUILD.bazel loads pkg_files) ###
local_repository(
    name = "rules_pkg",
    path = "build/bazel_common_rules/rules/pkg_stub",
)
