# Odd Frog

A small native macOS launcher: global hotkey, floating panel, fuzzy search over installed
apps, your own commands, and optional window management.

## Build and run

Requires Xcode command line tools with Swift 6. No Xcode project; SwiftPM plus a Makefile.

### Install a release build

```
scripts/release.sh
```

This does the whole thing in one go: release build, plugin packaging and signing, quitting the
running app, copying the bundle to `/Applications/OddFrog.app`, verifying the signature, and
relaunching. Environment variables:

| Variable | Default         | Purpose                                   |
|----------|-----------------|-------------------------------------------|
| `SIGN`   | `-` (ad-hoc)    | Code-signing identity, e.g. `OddFrog Dev` |
| `DEST`   | `/Applications` | Install directory                         |
| `LAUNCH` | `1`             | Set to `0` to install without relaunching |

```
SIGN="OddFrog Dev" scripts/release.sh
LAUNCH=0 DEST=~/Applications scripts/release.sh
```

### Develop

```
make run       # release build, bundle to build/OddFrog.app, relaunch from there
make install   # bundle and copy to ~/Applications (needed for Launch at Login)
make bundle    # build build/OddFrog.app without launching
make test      # swift test
make clean     # remove .build and build
```

`make run` launches the bundle from `build/`, so use it for quick iteration; `make install` or
`scripts/release.sh` when you want the installed copy updated.

### Signing and permissions

`SIGN` defaults to an ad-hoc signature (`-`). Rebuilding changes that identity and can invalidate
macOS Accessibility, Calendar, and Reminders access, even if System Settings still shows them
enabled. For a stable identity, create a self-signed code-signing certificate in Keychain Access →
Certificate Assistant → Create a Certificate… (certificate type "Code Signing", name e.g.
`OddFrog Dev`), then pass it to any target: `make run SIGN="OddFrog Dev"` or
`SIGN="OddFrog Dev" scripts/release.sh`. If access stops working after an ad-hoc rebuild, remove
Odd Frog from the relevant privacy pane and add the rebuilt app again.

## App icon

The original frog artwork and all macOS icon sizes can be regenerated with
`swift scripts/generate-icon.swift`. The generated `Resources/AppIcon.icns` is included in
normal builds, so running the generator is only necessary when changing the artwork.
