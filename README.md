# git-diff-toggle.yazi

Toggle between git diff and normal file preview in [yazi](https://github.com/sxyazi/yazi)'s preview pane.

Press a key to switch to git diff mode -- modified files show `git diff` output with color directly in the preview panel. Press again to switch back to normal preview.

## Requirements

- yazi >= 25.5.31
- git

## Installation

### Using [ya pack](https://yazi-rs.github.io/docs/plugins#installing-plugins)

```bash
ya pkg add cxwx/git-diff-toggle
```

### Manual

Clone this repository into your yazi plugins directory:

```bash
git clone https://github.com/cxwx/git-diff-toggle.yazi.git ~/.config/yazi/plugins/git-diff-toggle.yazi
```

## Configuration

### 1. Add the previewer

In `~/.config/yazi/yazi.toml`, add at the **end** of your `prepend_previewers` list:

```toml
[[plugin.prepend_previewers]]
mime = "text/*"
run = "git-diff-toggle"
```

> Place it after your other previewers so they take priority for specific file types (e.g. `.md`, `.json`).

### 2. Add a keybinding

In `~/.config/yazi/keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on   = [ "g", "t" ]
run  = "plugin git-diff-toggle"
desc = "Toggle git diff preview"
```

## Usage

1. Navigate to a file with git changes in yazi
2. Press `g` then `t` to enable diff mode
3. The preview pane shows `git diff --color=always` output
4. Press `g` then `t` again to switch back to normal preview

### Behavior

| File state | Diff mode ON | Diff mode OFF |
|---|---|---|
| Modified (unstaged) | Shows unstaged diff | Normal preview |
| Staged | Shows staged diff | Normal preview |
| Clean / Untracked | Normal preview | Normal preview |
| Not in git repo | Disables diff mode, shows normal preview | Normal preview |

Diff results are cached per file -- navigating back to the same file won't re-run git.

## Known Issues

### Zombie processes on exit

yazi's `Command` API (`Command():output()`, `Command():spawn()`) may leave zombie `git` processes when yazi exits. Every toggle or file hover that triggers a `Command` call can produce a lingering process. This affects **all yazi plugins** that spawn external commands, not just this one.

Workarounds:
- The plugin caches diff results per file to minimize `Command` calls
- After exiting yazi, you can clean up zombies: `pkill -f "git.*diff"` or just wait for them to be reaped

Related: [yazi#3289](https://github.com/sxyazi/yazi/issues/3289), [yazi#2681](https://github.com/sxyazi/yazi/issues/2681)

### Text files only

Only works for files yazi detects as `text/*` mime type. Binary files, images, etc. use their default previewers.

## Credits

This plugin was developed with [MiMo](https://github.com/XiaomiMiMo/MiMo), an AI model by Xiaomi.

## License

MIT
