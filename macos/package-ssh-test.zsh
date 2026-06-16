#!/usr/bin/env zsh

set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h}

scheme="Ghostty"
configuration="Debug"
arch="arm64"
app_name="Ghostty SSH"
bundle_id="com.mitchellh.ghostty.ssh-test"
dmg_name="Ghostty-SSH.dmg"
install_dir="/Applications"
dist_dir="$repo_root/dist"
prepare_core="auto"
install_app=1
create_dmg=1
quiet_xcode=1
official_bundle_id="com.mitchellh.ghostty"
required_zig_version="0.15.2"
zig_cmd="${ZIG:-}"

die() {
    print -u2 -- "error: $*"
    exit 1
}

log() {
    print -- "==> $*"
}

usage() {
    cat <<EOF
Usage: macos/package-ssh-test.zsh [options]

Build, rename, install, package, and verify the local macOS SSH test app.

Options:
  --configuration <name>  Xcode configuration. Default: Debug
  --scheme <name>         Xcode scheme. Default: Ghostty
  --arch <name>           Xcode architecture. Default: arm64
  --name <name>           App display name. Default: Ghostty SSH
  --bundle-id <id>        Bundle identifier. Default: com.mitchellh.ghostty.ssh-test
  --dmg-name <name>       DMG filename. Default: Ghostty-SSH.dmg
  --install-dir <path>    Install destination. Default: /Applications
  --dist-dir <path>       DMG output directory. Default: dist
  --prepare-core          Force Zig preparation of GhosttyKit/resources
  --skip-core             Do not run Zig preparation
  --no-install            Build and package without installing the app
  --no-dmg                Build and install without creating the DMG
  --zig <path>            Zig executable. Default: ZIG env, then zig@0.15
  --verbose-xcode         Show full xcodebuild output
  -h, --help              Show this help

Default outputs:
  /Applications/Ghostty SSH.app
  dist/Ghostty-SSH.dmg
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_value() {
    [[ $# -ge 2 ]] || die "$1 requires a value"
}

resolve_zig() {
    local candidates=()
    local candidate version

    if [[ -n "$zig_cmd" ]]; then
        candidates+=("$zig_cmd")
    fi
    candidates+=(
        "/opt/homebrew/opt/zig@0.15/bin/zig"
        "/usr/local/opt/zig@0.15/bin/zig"
    )
    if command -v zig >/dev/null 2>&1; then
        candidates+=("$(command -v zig)")
    fi

    for candidate in "${candidates[@]}"; do
        [[ -x "$candidate" ]] || continue
        version=$("$candidate" version 2>/dev/null) || continue
        if [[ "$version" == "$required_zig_version" ]]; then
            zig_cmd="$candidate"
            return
        fi
    done

    die "missing Zig $required_zig_version. Install it with: brew install zig@0.15, or pass --zig /path/to/zig"
}

run_zig_build() {
    env \
        -u HTTP_PROXY \
        -u HTTPS_PROXY \
        -u ALL_PROXY \
        -u http_proxy \
        -u https_proxy \
        -u all_proxy \
        "$zig_cmd" build "$@"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration)
            require_value "$@"
            configuration="$2"
            shift 2
            ;;
        --scheme)
            require_value "$@"
            scheme="$2"
            shift 2
            ;;
        --arch)
            require_value "$@"
            arch="$2"
            shift 2
            ;;
        --name)
            require_value "$@"
            app_name="$2"
            shift 2
            ;;
        --bundle-id)
            require_value "$@"
            bundle_id="$2"
            shift 2
            ;;
        --dmg-name)
            require_value "$@"
            dmg_name="$2"
            shift 2
            ;;
        --install-dir)
            require_value "$@"
            install_dir="$2"
            shift 2
            ;;
        --dist-dir)
            require_value "$@"
            dist_dir="$2"
            shift 2
            ;;
        --prepare-core)
            prepare_core="yes"
            shift
            ;;
        --skip-core)
            prepare_core="no"
            shift
            ;;
        --no-install)
            install_app=0
            shift
            ;;
        --no-dmg)
            create_dmg=0
            shift
            ;;
        --zig)
            require_value "$@"
            zig_cmd="$2"
            shift 2
            ;;
        --verbose-xcode)
            quiet_xcode=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

require_command xcodebuild
require_command codesign
require_command ditto
require_command hdiutil
[[ -x /usr/libexec/PlistBuddy ]] || die "missing required command: /usr/libexec/PlistBuddy"
if (( create_dmg )); then
    require_command create-dmg
fi

migrate_config() {
    local dest_dir="$HOME/Library/Application Support/$bundle_id"
    local dest="$dest_dir/config.ghostty"
    local legacy_dest="$dest_dir/config"
    local candidates=(
        "$HOME/Library/Application Support/$official_bundle_id/config.ghostty"
        "$HOME/Library/Application Support/$official_bundle_id/config"
        "$HOME/.config/ghostty/config.ghostty"
        "$HOME/.config/ghostty/config"
    )

    if [[ -e "$dest" || -e "$legacy_dest" ]]; then
        log "Keeping existing SSH test config at $dest_dir"
        return
    fi

    for source in "${candidates[@]}"; do
        if [[ -s "$source" ]]; then
            log "Migrating initial SSH test config from $source"
            mkdir -p "$dest_dir"
            cp "$source" "$dest"
            chmod 600 "$dest"
            return
        fi
    done

    log "No existing Ghostty config found to migrate"
}

core_lib="$repo_root/macos/GhosttyKit.xcframework/macos-arm64_x86_64/ghostty-internal.a"
resources_dir="$repo_root/zig-out/share"
needs_core=0
if [[ ! -f "$core_lib" || ! -d "$resources_dir" ]]; then
    needs_core=1
fi
if [[ "$bundle_id" != "$official_bundle_id" && "$prepare_core" == "auto" ]]; then
    needs_core=1
fi

if [[ "$prepare_core" == "yes" || ( "$prepare_core" == "auto" && "$needs_core" == "1" ) ]]; then
    resolve_zig
    log "Preparing GhosttyKit.xcframework and resources with Zig $required_zig_version for $bundle_id"
    (
        cd "$repo_root"
        run_zig_build -Demit-macos-app=false -Dbundle-id="$bundle_id"
    )
elif [[ "$prepare_core" == "auto" ]]; then
    log "Using existing GhosttyKit.xcframework and zig-out resources"
else
    [[ "$bundle_id" == "$official_bundle_id" ]] || die "--skip-core cannot be used with custom bundle id $bundle_id; rebuild core so config paths are isolated"
    log "Skipping Zig core preparation"
fi

[[ -f "$core_lib" ]] || die "missing $core_lib; rerun with --prepare-core after installing Zig"
[[ -d "$resources_dir" ]] || die "missing $resources_dir; rerun with --prepare-core after installing Zig"

build_dir="$repo_root/macos/build"
derived_data_dir="$build_dir/DerivedData"
built_app="$build_dir/$configuration/Ghostty.app"
stage_root=$(mktemp -d "${TMPDIR:-/tmp}/ghostty-ssh-test.XXXXXX")
staged_app="$stage_root/$app_name.app"
plist="$staged_app/Contents/Info.plist"
install_app_path="$install_dir/$app_name.app"
dmg_path="$dist_dir/$dmg_name"

cleanup() {
    rm -rf "$stage_root"
}
trap cleanup EXIT

log "Building $scheme $configuration for $arch"
xcode_args=(
    -project "$repo_root/macos/Ghostty.xcodeproj"
    -scheme "$scheme"
    -configuration "$configuration"
    "SYMROOT=$build_dir"
    -derivedDataPath "$derived_data_dir"
    -arch "$arch"
    -skipPackagePluginValidation
)
if (( quiet_xcode )); then
    xcode_args=(-quiet "${xcode_args[@]}")
fi

(
    cd "$repo_root"
    env -i \
        "HOME=${HOME:-$repo_root}" \
        "PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin" \
        xcodebuild "${xcode_args[@]}" build
)

[[ -d "$built_app" ]] || die "xcodebuild did not produce $built_app"

log "Staging renamed app: $staged_app"
ditto "$built_app" "$staged_app"

log "Applying test bundle metadata"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $app_name" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $app_name" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$plist"
if /usr/libexec/PlistBuddy -c "Print :NSServices:0:NSMenuItem:default" "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :NSServices:0:NSMenuItem:default New $app_name Tab Here" "$plist"
fi
if /usr/libexec/PlistBuddy -c "Print :NSServices:1:NSMenuItem:default" "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :NSServices:1:NSMenuItem:default New $app_name Window Here" "$plist"
fi

migrate_config

log "Signing staged app"
codesign --force --deep --sign - "$staged_app"
codesign --verify --deep --strict --verbose=2 "$staged_app"

if (( install_app )); then
    [[ "$install_app_path" != "/Applications/Ghostty.app" ]] || die "refusing to overwrite /Applications/Ghostty.app"
    log "Installing $install_app_path"
    rm -rf "$install_app_path"
    ditto "$staged_app" "$install_app_path"
    codesign --verify --deep --strict --verbose=2 "$install_app_path"
fi

if (( create_dmg )); then
    log "Creating $dmg_path"
    mkdir -p "$dist_dir"
    rm -f "$dmg_path"
    create-dmg \
        --volname "$app_name" \
        --window-pos 200 120 \
        --window-size 640 420 \
        --icon-size 96 \
        --icon "$app_name.app" 160 190 \
        --app-drop-link 460 190 \
        "$dmg_path" \
        "$staged_app"
    hdiutil verify "$dmg_path"
fi

print -- ""
print -- "Packaged SSH test build:"
print -- "  Built app: $built_app"
if (( install_app )); then
    print -- "  Installed app: $install_app_path"
fi
if (( create_dmg )); then
    print -- "  DMG: $dmg_path"
fi
