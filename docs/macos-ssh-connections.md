# macOS SSH Connections

Ghostty's macOS SSH sidebar stores a small app-owned connection library for
launching system `ssh` in new tabs.

The library is stored as JSON at:

```text
Application Support/<bundle-identifier>/ssh-connections.json
```

Saved fields are limited to display name, group, host, port, username, private
key file path, and notes. Ghostty does not store passwords, private key
contents, or key passphrases. Authentication remains the responsibility of
system `ssh` and the user's normal SSH agent or keychain setup.

Reachability status is a manual TCP host/port check. It does not authenticate,
run `ssh`, or prove that login will succeed. Connections start as unknown until
the user refreshes one server, one group, or the visible filtered list.

## Local Test Packaging

Use the canonical local package flow when building this feature for testing:

```sh
macos/package-ssh-test.zsh
```

The script uses Zig 0.15.2 for the GhosttyKit preparation step. Install the
matching Homebrew keg first if needed:

```sh
brew install zig@0.15
```

The script builds the macOS app, stages a renamed `Ghostty SSH.app`, sets
the test bundle ID `com.mitchellh.ghostty.ssh-test`, migrates the first test
config into that bundle's Application Support directory, ad-hoc signs it,
installs it to `/Applications/Ghostty SSH.app`, creates
`dist/Ghostty-SSH.dmg`, and verifies both the app signature and the DMG.

If the underlying GhosttyKit library or resources are missing or stale, run:

```sh
macos/package-ssh-test.zsh --prepare-core
```

This flow intentionally keeps the test build separate from
`/Applications/Ghostty.app` and keeps its config separate from the official
`com.mitchellh.ghostty` config.
