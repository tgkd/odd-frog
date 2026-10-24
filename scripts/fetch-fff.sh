#!/bin/zsh
# Downloads the pinned fff C library into vendor/fff and verifies its checksum.
set -euo pipefail

root="${0:A:h:h}"
tag="v0.11.0"
case "$(uname -m)" in
  arm64)  arch="aarch64"; sha="d052aae92b8d89f4734399aa53f80a327c4931f1b5dea0a7d96f9c488229ba43" ;;
  x86_64) arch="x86_64";  sha="bc360aeb6eec256ecc0ae4c3aaae83efd5928e823c04b47c87d8bdb395b7a39c" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

dir="$root/vendor/fff"
lib="$dir/libfff_c.dylib"
mkdir -p "$dir"
if [[ -f "$lib" && "$(shasum -a 256 "$lib" | cut -d' ' -f1)" == "$sha" ]]; then
  exit 0
fi

curl -fsSL -o "$lib" "https://github.com/dmtrKovalenko/fff.nvim/releases/download/$tag/c-lib-$arch-apple-darwin.dylib"
actual="$(shasum -a 256 "$lib" | cut -d' ' -f1)"
if [[ "$actual" != "$sha" ]]; then
  rm -f "$lib"
  echo "Checksum mismatch for fff library: $actual" >&2
  exit 1
fi
echo "Fetched fff $tag ($arch)"
