# Source this to get the local Swift 6.1 toolchain on PATH (Linux dev only).
# The ncurses shim exists because the Ubuntu 24.04 toolchain wants
# libncurses.so.6 while Arch ships it as libncursesw.so.6.
export PATH="$HOME/.local/swift/swift-6.1-RELEASE-ubuntu24.04/usr/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/.local/swift/compat:$LD_LIBRARY_PATH"
