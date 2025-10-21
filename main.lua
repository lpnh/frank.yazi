--- @since 25.5.31

local shell = os.getenv("SHELL"):match(".*/(.*)")
local get_cwd = ya.sync(function() return cx.active.current.cwd end)
local fail = function(s, ...)
	ya.notify { title = "frank", content = string.format(s, ...), timeout = 5, level = "error" }
end

-- shell compatibility table
local sh_compat_tbl = {
	default = {
		wrap = function(cmd) return "(" .. cmd .. ")" end,
		prompt = function(s) return string.format("[[ ! $FZF_PROMPT =~ %s ]] &&", s) end,
		prev = function(s) return string.format("[[ $FZF_PREVIEW_LABEL =~ %s ]] &&", s) end,
		op = "||",
	},
	fish = {
		wrap = function(cmd) return "begin; " .. cmd .. "; end" end,
		prompt = function(s) return string.format([[not string match -q "*%s*" $FZF_PROMPT; and]], s) end,
		prev = function(s) return string.format([[string match -q "*%s*" $FZF_PREVIEW_LABEL; and]], s) end,
		op = "; or",
	},
}
local function get_sh_helper() return sh_compat_tbl[shell] or sh_compat_tbl.default end

-- get custom options from user setup
local fmt_opts = function(opt)
	if type(opt) == "string" then
		return " " .. opt
	elseif type(opt) == "table" then
		return " " .. table.concat(opt, " ")
	end
	return ""
end
local get_user_opts = ya.sync(function(self)
	local opts = self.custom_opts or {}

	return {
		fzf = fmt_opts(opts.fzf),
		rg = fmt_opts(opts.rg),
		rga = fmt_opts(opts.rga),
		fd = fmt_opts(opts.fd),
		bat = fmt_opts(opts.bat),
		eza = fmt_opts(opts.eza),
		eza_meta = fmt_opts(opts.eza_meta),
		rga_preview = fmt_opts(opts.rga_preview),
	}
end)

-- mimic `bat` grid,header style
local ansi_grid_header = function()
	-- ANSI
	local bold = "\x1b[1m"
	local bar_color = "\x1b[38;2;127;132;156m"
	local reset = "\x1b[m"

	local bar_line = string.rep("─", 80)
	local colored_bar = bar_color .. bar_line .. reset

	local label = {
		default = string.format([[echo -ne "Dir: %s\{}%s";]], bold, reset),
		file = string.format([[echo -e "File: %s\{}%s";]], bold, reset),
		meta = string.format(
			[[test -d \{1} && echo -ne "Dir: %s\{1}%s" || echo -ne "File: %s\{1}%s";]],
			bold,
			reset,
			bold,
			reset
		),
	}

	return {
		bar = string.format([[echo -e "%s";]], colored_bar),
		bar_with_new_line = string.format([[echo -e "\n%s";]], colored_bar),
		label = label,
	}
end

local function eza_preview(prev_type, opts)
	local header = ansi_grid_header()

	local extra_flags = {
		default = "--oneline " .. opts.eza,
		meta = "--git --git-repos --header --long --mounts --no-user --octal-permissions " .. opts.eza_meta,
	}

	return table.concat({
		header.bar,
		header.label[prev_type],
		[[test -z "$(eza -A \{1})" && echo -e "  <EMPTY>" || ]] .. header.bar_with_new_line,
		string.format([[eza %s --all --color=always --group-directories-first --icons \{1};]], extra_flags[prev_type]),
		header.bar,
	}, " ")
end

local rga_preview_with_header = function(user_opts)
	local sh = get_sh_helper()
	local header = ansi_grid_header()

	return [[test -n \{} && ]]
		.. sh.wrap(table.concat({
			header.bar,
			header.label.file,
			header.bar,
			"rga --context 5 --no-messages --pretty " .. user_opts .. [[ \{q} \{};]],
			header.bar,
		}, " "))
end

-- common `fzf` base cmd
local function build_from_fzf_base(search_cmd, preview_cmd, preview_window, prompt, user_opts, specific_options)
	local sh = get_sh_helper()
	local toggle_preview = string.format(
		[[%s echo '\''change-preview-label(metadata)+change-preview-window(~5)+change-preview:%s'\'' %s ]]
			.. [[echo '\''change-preview-label(content)+change-preview-window(~3)+change-preview:%s'\'']],
		sh.prev("content"),
		eza_preview("meta", user_opts),
		sh.op,
		preview_cmd
	)

	local base_tbl = {
		"fzf",
		"--ansi",
		"--no-multi",
		"--reverse",
		string.format("--bind='start:reload(%s)+transform:%s'", search_cmd, toggle_preview),
		string.format("--bind='change:reload:sleep 0.1; %s || true'", search_cmd),
		string.format("--bind='ctrl-r:clear-query+reload:%s || true'", search_cmd),
		string.format("--prompt='%s'", prompt),
		string.format("--preview='echo loading'"),
		string.format("--preview-window='%s'", preview_window),
		"--bind='ctrl-]:change-preview-window(80%|66%)'",
		"--bind='ctrl-\\:change-preview-window(right|up)'",
		string.format([[--bind 'alt-p:transform:%s']], toggle_preview),
	}

	for _, option in ipairs(specific_options) do
		table.insert(base_tbl, option)
	end

	table.insert(base_tbl, user_opts.fzf) -- user `fzf` options at the end

	return base_tbl
end

-- fzf with `rg` or `rga` search
local function build_search_by_content(search_type, user_opts)
	local sh = get_sh_helper()
	local cmd_tbl = {
		rg = {
			grep = "rg --color=always --line-number --smart-case" .. user_opts.rg .. " {q}",
			prev = string.format([[bat --color=always %s --highlight-line=\{2} \{1}]], user_opts.bat),
			prev_window = "~3,+{2}+3/2,up,66%",
			prompt = "rg> ",
			specific_options = { "--disabled", "--bind='ctrl-o:execute:$EDITOR {1} +{2}'", "--delimiter=:", "--nth=3.." },
			fzf_match = function(cmd_grep)
				local bind_fzf_match_tmpl = "--bind='ctrl-s:transform:%s "
					.. [[echo "rebind(change)+change-prompt(rg> )+disable-search+clear-query+reload:%s || true" %s ]]
					.. [[echo "unbind(change)+change-prompt(fzf> )+enable-search+clear-query"']]
				return string.format(bind_fzf_match_tmpl, sh.prompt("rg"), cmd_grep, sh.op)
			end,
		},
		rga = {
			grep = "rga --color=always --files-with-matches --smart-case" .. user_opts.rga .. " {q}",
			prev = rga_preview_with_header(user_opts.rga_preview),
			prev_window = "up,66%",
			prompt = "rga> ",
			specific_options = { "--disabled", "--bind='ctrl-o:execute:$EDITOR {}'" },
		},
	}

	local cmd = cmd_tbl[search_type]
	if not cmd then
		fail("`%s` is not a valid argument for `content` search.\nUse `rg` or `rga` instead", search_type)
		return nil
	end

	if cmd.fzf_match then
		table.insert(cmd.specific_options, cmd.fzf_match(cmd.grep)) -- `fzf` match for `rg`
	end

	local fzf_tbl = build_from_fzf_base(cmd.grep, cmd.prev, cmd.prev_window, cmd.prompt, user_opts, cmd.specific_options)

	return table.concat(fzf_tbl, " ")
end

-- fzf with `fd` search
local function build_search_by_name(search_type, user_opts)
	local sh = get_sh_helper()
	local cmd_tbl = {
		all = sh.wrap(string.format("fd --type=d %s {q}; fd --type=f %s {q}", user_opts.fd, user_opts.fd)),
		cwd = sh.wrap(
			string.format("fd --max-depth=1 --type=d %s {q}; fd --max-depth=1 --type=f %s {q}", user_opts.fd, user_opts.fd)
		),
		dir = "fd --type=dir " .. user_opts.fd .. " {q}",
		file = "fd --type=file " .. user_opts.fd .. " {q}",
	}

	local fd_cmd = cmd_tbl[search_type]
	if not fd_cmd then
		fail("`%s` is not a valid argument for `name` search.\nUse `all`, `cwd`, `dir`, or `file` instead", search_type)
		return nil
	end

	local bat_prev = string.format([[bat --color=always %s \{}]], user_opts.bat)
	local default_prev = string.format([[test -d \{} && %s || %s]], sh.wrap(eza_preview("default", user_opts)), bat_prev)

	local specific_options = {
		"--bind='ctrl-o:execute:$EDITOR {1}'",
		string.format(
			"--bind='ctrl-s:transform:%s "
				.. [[echo "rebind(change)+change-prompt(fd> )+clear-query+reload:%s" %s ]]
				.. [[echo "unbind(change)+change-prompt(fzf> )+clear-query"']],
			sh.prompt("fd"),
			fd_cmd,
			sh.op
		),
	}

	local fzf_tbl = build_from_fzf_base(fd_cmd, default_prev, "up,66%", "fd> ", user_opts, specific_options)

	return table.concat(fzf_tbl, " ")
end

local function entry(_, job)
	-- TODO: remove fallback after next stable release
	local _permit = ui.hide and ui.hide() or ya.hide()

	local user_opts = get_user_opts() -- from user setup
	local cwd = tostring(get_cwd())

	local search_type, search_opt = job.args[1], job.args[2]
	local args

	if search_type == "content" then
		args = build_search_by_content(search_opt or "rg", user_opts) -- fallback to `rg` search
	elseif search_type == "name" then
		args = build_search_by_name(search_opt or "all", user_opts) -- fallback to `fd` "all" search (dirs and files)
	else
		return fail("Please specify either 'content' or 'name' as the first argument")
	end

	if not args then
		return -- no valid second argument
	end

	local child, err = Command(shell)
		:arg({ "-c", args })
		:cwd(cwd)
		:stdin(Command.INHERIT)
		:stdout(Command.PIPED)
		:stderr(Command.INHERIT)
		:spawn()

	if not child then
		return fail("Command failed with error code %s", err)
	end

	local output, err = child:wait_with_output()
	if not output then -- unreachable?
		return fail("Cannot read command output, error code %s", err)
	end

	if output.status.code == 130 then -- interrupted with <ctrl-c> or <esc>
		return nil
	elseif output.status.code == 1 then -- no match
		ya.notify { title = "frank", content = "No match found", timeout = 5 }
		return nil
	elseif output.status.code ~= 0 then -- anything other than normal exit
		fail("`fzf` exited with error code %s", output.status.code)
		return nil
	end

	local target = output.stdout:gsub("\n$", "")
	if target ~= "" then
		if search_type == "content" then
			local colon_pos = string.find(target, ":")
			local file_url = colon_pos and string.sub(target, 1, colon_pos - 1) or target
			if file_url then
				ya.emit("reveal", { file_url })
			end
		elseif search_type == "name" then
			local is_dir = target:sub(-1) == "/"
			ya.emit(is_dir and "cd" or "reveal", { target })
		end
	end
end

local function setup(self, opts)
	opts = opts or {}

	self.custom_opts = {
		fzf = opts.fzf,
		rg = opts.rg,
		rga = opts.rga,
		fd = opts.fd,
		bat = opts.bat,
		eza = opts.eza,
		eza_meta = opts.eza_meta,
		rga_preview = opts.rga_preview,
	}
end

return { entry = entry, setup = setup }
