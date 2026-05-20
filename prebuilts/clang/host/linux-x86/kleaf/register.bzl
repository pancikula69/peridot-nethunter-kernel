"""Register Clang CC toolchains for Kleaf host/target builds."""

def register_clang_toolchains():
    """Register all Clang CC toolchains from prebuilts/clang/host/linux-x86/kleaf."""
    native.register_toolchains(
        "//prebuilts/clang/host/linux-x86/kleaf:linux_x86_64_clang_toolchain",
        "//prebuilts/clang/host/linux-x86/kleaf:android_arm64_clang_toolchain",
        "//prebuilts/clang/host/linux-x86/kleaf:android_x86_64_clang_toolchain",
        "//prebuilts/clang/host/linux-x86/kleaf:android_riscv64_clang_toolchain",
    )
