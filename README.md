# dotfiles

Cross-OS bootstrap built around [`pacaptr`](https://github.com/rami3l/pacaptr),
a `pacman`-style wrapper over `brew`, `apt`, `pacman`, `scoop`, and friends.

One command turns a blank box into a working dev environment.

## Supported platforms

| OS                  | Backend pacaptr uses |
| ------------------- | -------------------- |
| macOS               | Homebrew             |
| Debian / Ubuntu     | apt                  |
| Arch Linux          | pacman               |
| WSL (Ubuntu/Debian) | apt                  |
| Windows (native)    | *not yet* (needs a PowerShell stage 1) |

## Usage

### Fresh machine

```bash
curl -fsSL https://raw.githubusercontent.com/mxwlf/dotfiles/main/bootstrap.sh | bash
```

That does, in order:

1. Detects the OS.
2. Installs a C toolchain (xcode CLT / build-essential / base-devel).
3. Installs `rustup` + stable Rust.
4. Installs `cargo-binstall`, then `pacaptr` (falls back to `cargo install pacaptr` from source).
5. Installs `git` via `pacaptr`.
6. Clones this repo to `~/.dotfiles`.
7. Hands off to `~/.dotfiles/install.sh`.

### Already bootstrapped

```bash
~/.dotfiles/bootstrap.sh   # re-runs the whole chain; idempotent
~/.dotfiles/install.sh     # just the stage-2 parts (pacaptr, hooks, linking)
```

### Environment overrides

| Variable           | Default                                   | Effect                               |
| ------------------ | ----------------------------------------- | ------------------------------------ |
| `DOTFILES_REPO`    | `https://github.com/mxwlf/dotfiles`       | Git URL to clone in stage 1          |
| `DOTFILES_BRANCH`  | `main`                                    | Branch to track                      |
| `DOTFILES_DIR`     | `$HOME/.dotfiles`                         | Where to clone the repo              |
| `SKIP_PACKAGES=1`  | off                                       | Stage 2 skips `pacaptr -S`           |
| `SKIP_HOOKS=1`     | off                                       | Stage 2 skips `hooks/<distro>-post.sh` |
| `SKIP_LINK=1`      | off                                       | Stage 2 skips dotfile linking        |

## Repository layout

```
.
├── bootstrap.sh                  # stage 1, curl-able entrypoint
├── install.sh                    # stage 2 orchestrator
├── lib/common.sh                 # OS detection + logging helpers
├── packages/
│   ├── common.txt                # installed on every OS (git, curl, wget, jq, ripgrep)
│   ├── macos.txt                 # extra brew formulae
│   ├── macos-cask.txt            # brew casks (GUI apps)
│   ├── linux-debian.txt          # apt-specific overrides
│   ├── linux-arch.txt            # pacman-specific overrides
│   └── windows.txt               # reserved for future scoop use
├── config/pacaptr/pacaptr.toml   # symlinked into $XDG_CONFIG_HOME/pacaptr/
└── hooks/
    ├── macos-post.sh
    ├── debian-post.sh
    ├── arch-post.sh
    └── windows-post.sh
```

## Package list conventions

`pacaptr` doesn't define a "Pkgfile" format — the docs recommend passing
package names directly to `pacaptr -S`. We split that list into plain text
files:

- **`common.txt`** — packages whose name is identical on every backend
  (e.g. `git`, `curl`, `wget`, `jq`, `ripgrep`).
- **`<os>.txt`** — per-OS additions and name overrides (e.g. `fd-find` on
  Debian vs `fd` on brew/pacman).

Format: one package per line. `#` starts a comment. Blank lines are ignored.

Stage 2 builds the final list with:

```
cat packages/common.txt packages/<distro>.txt | strip comments/blanks | sort -u
```

and feeds it to a single `pacaptr -S --noconfirm …` call. On macOS, a
second pass installs `macos-cask.txt` with `-- --cask` appended so brew
treats them as casks.

## pacaptr.toml

Only one knob is set: `needed = true`. That makes `pacaptr -S` a no-op
for already-installed packages, so re-running `install.sh` is cheap and
safe.

System upgrades (`pacaptr -Syu`) are **not** performed automatically.
Run them manually when you want them:

```bash
pacaptr -Syu
```

## Dotfile linking

Deferred — `install.sh` has a `link_dotfiles()` stub that's currently a
no-op. Decide between `stow`, a hand-rolled `ln -s` loop, or `chezmoi`,
then fill it in.

## License

MIT.
