# Rust/Cargo - add cargo-installed binaries to PATH
if [[ -d "${HOME}/.cargo/bin" ]]; then
  export PATH="${PATH}:${HOME}/.cargo/bin"
fi
