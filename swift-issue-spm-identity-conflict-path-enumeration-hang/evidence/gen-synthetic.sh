#!/bin/zsh
# Synthetic reproducer for the SwiftPM identity-conflict path-enumeration hang.
# Pure topology: local git repos only. No network, no mirrors.json, no institute packages.
#
# Shape:
#   root -> a1, b1                (lattice entry)
#   ai -> a(i+1), b(i+1)          (i = 1..N-1)   \  2^N distinct paths
#   bi -> a(i+1), b(i+1)          (i = 1..N-1)   /
#   aN, bN -> tail
#   root       -> conflicted  via $REPOS/conflicted        (canonical location 1)
#   a1         -> conflicted  via $REPOS_ALIAS/conflicted  (canonical location 2, same identity)
#
# With CONFLICT=1 the same identity "conflicted" is reachable under two canonical
# locations -> SwiftPM 6.3.x createResolvedPackages enters the "conflicting identity"
# branch -> findAllTransitiveDependencies enumerates ALL 2^N+ paths -> spin.
# With CONFLICT=0 both edges use the same location -> loads instantly.
set -euo pipefail
N=${N:-18}
CONFLICT=${CONFLICT:-1}
BASE=$1
REPOS="$BASE/repos"
mkdir -p "$REPOS"

make_pkg() { # $1=dir  $2=name  $3=deps-swift-array-body  $4=target-product-deps
  local dir="$1" name="$2" deps="$3" tdeps="${4:-}"
  mkdir -p "$dir/Sources/$name"
  echo "public enum K_$name {}" > "$dir/Sources/$name/K.swift"
  cat > "$dir/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "$name",
    products: [.library(name: "$name", targets: ["$name"])],
    dependencies: [$deps],
    targets: [.target(name: "$name", dependencies: [$tdeps])]
)
EOF
  git -C "$dir" init -q -b main
  git -C "$dir" add -A
  git -C "$dir" -c user.email=probe@invalid -c user.name=probe commit -qm init
}

# leaf packages
make_pkg "$REPOS/tail" "tail" ""
make_pkg "$REPOS/conflicted" "conflicted" ""

# second canonical location for the same identity: a physical second clone
git clone -q "$REPOS/conflicted" "$BASE/repos-alias/conflicted"

# lattice, built bottom-up
for ((i=N; i>=1; i--)); do
  if (( i == N )); then
    deps=".package(url: \"$REPOS/tail\", branch: \"main\")"
    tdeps=".product(name: \"tail\", package: \"tail\")"
  else
    deps=".package(url: \"$REPOS/a$((i+1))\", branch: \"main\"), .package(url: \"$REPOS/b$((i+1))\", branch: \"main\")"
    tdeps=".product(name: \"a$((i+1))\", package: \"a$((i+1))\"), .product(name: \"b$((i+1))\", package: \"b$((i+1))\")"
  fi
  if (( i == 1 )); then
    if (( CONFLICT )); then
      deps="$deps, .package(url: \"$BASE/repos-alias/conflicted\", branch: \"main\")"
    else
      deps="$deps, .package(url: \"$REPOS/conflicted\", branch: \"main\")"
    fi
    tdeps="$tdeps, .product(name: \"conflicted\", package: \"conflicted\")"
  fi
  make_pkg "$REPOS/a$i" "a$i" "$deps" "$tdeps"
  make_pkg "$REPOS/b$i" "b$i" "$deps" "$tdeps"
done

# root package (not a git repo; plain directory)
mkdir -p "$BASE/root/Sources/Root"
echo "public enum Root {}" > "$BASE/root/Sources/Root/Root.swift"
cat > "$BASE/root/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "synthetic-root",
    dependencies: [
        .package(url: "$REPOS/a1", branch: "main"),
        .package(url: "$REPOS/b1", branch: "main"),
        .package(url: "$REPOS/conflicted", branch: "main"),
    ],
    targets: [.target(name: "Root", dependencies: [
        .product(name: "a1", package: "a1"),
        .product(name: "b1", package: "b1"),
        .product(name: "conflicted", package: "conflicted"),
    ])]
)
EOF
# empty local mirror config so the user's shared mirrors.json cannot interfere
mkdir -p "$BASE/root/.swiftpm/configuration"
echo '{"version":1,"object":[{"original":"https://example.invalid/unused.git","mirror":"https://example.invalid/unused-mirror.git"}]}' > "$BASE/root/.swiftpm/configuration/mirrors.json"
echo "generated N=$N CONFLICT=$CONFLICT at $BASE"
