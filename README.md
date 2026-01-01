# frank

a Yazi plugin that stitches `fzf`, `fd`, `rg`, `rga`, `bat`, and `eza` together
to provide a live search (by name or content) with some preview capabilities

**supported shells**: `bash`, `fish`, and `zsh`

## dependencies

- [bat](https://github.com/sharkdp/bat)
- [eza](https://eza.rocks/)
- [fd](https://github.com/sharkdp/fd)
- [fzf](https://junegunn.github.io/fzf/)
- [ripgrep](https://github.com/BurntSushi/ripgrep)
- [ripgrep-all](https://github.com/phiresky/ripgrep-all)

note that `fzf` is required for the interface, while other dependencies are
optional depending on your usage (see tables below)

## installation

```sh
ya pkg add lpnh/frank
```

## usage

> [!NOTE]
> **experimental API**: i'm still figuring out the best defaults and arguments
>
> if you have suggestions for better defaults and/or arguments, feel free to
> open an issue or start a discussion — opinions are more than welcome

### plugin arguments

to avoid ambiguity, this plugin has a two-argument structure, so we can
differentiate the search method (by name vs content) and their respective options

for convenience, you can pass only the first argument and let the plugin fall
back to a default second argument. this is the "alias" option you'll see below

#### search by content

- `content`: alias for `content rg`
- `content rg`: search using `ripgrep`
- `content rga`: search using `ripgrep-all`

#### search by name

- `name`: alias for `name all`
- `name all`: search files and directories
- `name cwd`: search files and directories in the current directory
- `name dir`: search directories only
- `name file`: search files only

### dependencies by usage

the tables below show what dependencies are required for each usage

#### search engine

| tool        | plugin option                                   |
| ----------- | ----------------------------------------------- |
| ripgrep     | `content rg`                                    |
| ripgrep-all | `content rga`                                   |
| fd          | `name all`, `name cwd`, `name dir`, `name file` |

#### file content preview

| tool        | plugin option                                     |
| ----------- | ------------------------------------------------- |
| bat         | `content rg`, `name all`, `name cwd`, `name file` |
| ripgrep-all | `content rga`                                     |

#### directory content preview

| tool        | plugin option                      |
| ----------- | ---------------------------------- |
| eza         | `name all`, `name cwd`, `name dir` |

#### file metadata preview

| tool        | plugin option                            |
| ----------- | ---------------------------------------- |
| eza         | `content rg`, `content rga`, `name file` |

#### directory metadata preview

| tool        | plugin option                      |
| ----------- | ---------------------------------- |
| eza         | `name all`, `name cwd`, `name dir` |

### keymaps

#### minimal config

below is an example of how to configure both searches in the
`~/.config/yazi/keymap.toml` file, using only the aliases:

```toml
[[mgr.prepend_keymap]]
on = ["f", "r"]
run = "plugin frank content"
desc = "Search file by content (rg)"

[[mgr.prepend_keymap]]
on = ["f", "d"]
run = "plugin frank name"
desc = "Search by name, files and dirs (fd)"
```

#### full config

below is an example how to configure all the available options:

```toml
[[mgr.prepend_keymap]]
on = ["f", "r"]
run = "plugin frank 'content rg'"
desc = "Search file by content (rg)"

[[mgr.prepend_keymap]]
on = ["f", "A"]
run = "plugin frank 'content rga'"
desc = "Search file by content (rga)"

[[mgr.prepend_keymap]]
on = ["f", "a"]
run = "plugin frank 'name all'"
desc = "Search by name, files and dirs"

[[mgr.prepend_keymap]]
on = ["f", "c"]
run = "plugin frank 'name cwd'"
desc = "Search by name, files and dirs (CWD)"

[[mgr.prepend_keymap]]
on = ["f", "d"]
run = "plugin frank 'name dir'"
desc = "Search directory by name"

[[mgr.prepend_keymap]]
on = ["f", "f"]
run = "plugin frank 'name file'"
desc = "Search file by name"
```

**important**: before using the examples above, ensure the keybindings don't
conflict with your other commands/plugins. the descriptions can also be changed
to your preference

### fzf binds

this plugin provides the following custom `fzf` keybindings:

- `alt-p`: toggle the preview ("content", "metadata")
- `ctrl-o`: open selected entry with default editor (`$EDITOR`)
- `ctrl-r`: reload the search
- `ctrl-s`: toggle `fzf` match for the current query results
- `ctrl-]`: toggle the preview window size (66%, 80%)
- `ctrl-\`: toggle the preview window position (top, right)

## customization

### color themes

#### fzf

you can customize the default `fzf` colors using the `FZF_DEFAULT_OPTS`
environment variable. for an example, check out [Catppuccin's fzf
repo](https://github.com/catppuccin/fzf?tab=readme-ov-file#usage)

more examples of color themes can be found in the [fzf
documentation](https://github.com/junegunn/fzf/blob/master/ADVANCED.md#color-themes)

#### eza

you can customize the colors of `eza` previews using its
`~/.config/eza/theme.yml` configuration file. check the
[eza-theme](https://github.com/eza-community/eza-themes) repository for some
existing themes

for more details, see
[eza_colors-explanation](https://github.com/eza-community/eza/blob/main/man/eza_colors-explanation.5.md)

### advanced

for those seeking further customization, you can tweak all the integrated tools
used by this plugin in your `~/.config/yazi/init.lua` file. simply pass a table
to the `setup` function with any of the following fields and their respectives
options:

```lua
require("frank"):setup({
  fzf = "",            -- global fzf options
  -- content search options
  rg = "",             -- ripgrep options
  rga = "",            -- ripgrep-all options
  -- name search options
  fd = "",             -- fd options
  -- preview options
  bat = "",            -- bat options for file preview (rg,fd)
  eza = "",            -- eza options for directory preview (fd)
  eza_meta = "",       -- eza metadata options (rg,rga,fd)
  rga_preview = "",    -- ripgrep-all preview options (rga)
})
```

all fields are optional and accept either a string or a table of strings
containing command-line options

example:

```lua
require("frank"):setup {
  fzf = [[--info-command='echo -e "$FZF_INFO 💛"' --no-scrollbar]],
  rg = "--colors 'line:fg:red' --colors 'match:style:nobold'",
  rga = {
    "--follow",
    "--hidden",
    "--no-ignore",
    "--glob",
    "'!.git'",
    "--glob",
    "!'.venv'",
    "--glob",
    "'!node_modules'",
    "--glob",
    "'!.history'",
    "--glob",
    "'!.Rproj.user'",
    "--glob",
    "'!.ipynb_checkpoints'",
  },
  fd = "--hidden",
  bat = "",
  eza = "",
  eza_meta = "--total-size",
  rga_preview = {
    "--colors 'column:fg:black'"
      .. " --colors 'line:fg:black'"
      .. " --colors 'match:fg:black'"
      .. " --colors 'match:bg:blue'"
      .. " --colors 'match:style:nobold'"
      .. [[ --context-separator=" "]]
      .. [[ --field-context-separator=" "]]
      .. [[ --field-match-separator=" "]],
  },
}
```

almost everything from interface elements to search filters can be customized —
you just need to find the right flag
