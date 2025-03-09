--- @since 25.2.7

-- utilities
local shell = os.getenv("SHELL"):match(".*/(.*)")
local get_cwd = ya.sync(function() return cx.active.current.cwd end)
local fail = function(s, ...)
	ya.notify { title = "frank", content = string.format(s, ...), timeout = 5, level = "error" }
end
local fmt_opts = function(opt)
	if type(opt) == "string" then
		return " " .. opt
	elseif type(opt) == "table" then
		return " " .. table.concat(opt, " ")
	end
	return ""
end

-- shell compatibility table
local sh_compat_tbl = {
	default = {
		wrap = function(cmd) return "(" .. cmd .. ")" end,
		rg_prompt = { cond = "[[ ! $FZF_PROMPT =~ rg ]] &&", op = "||" },
		fd_prompt = { cond = "[[ ! $FZF_PROMPT =~ fd ]] &&", op = "||" },
	},
	fish = {
		wrap = function(cmd) return "begin; " .. cmd .. "; end" end,
		rg_prompt = { cond = 'not string match -q "*rg*" $FZF_PROMPT; and', op = "; or" },
		fd_prompt = { cond = 'not string match -q "*fd*" $FZF_PROMPT; and', op = "; or" },
	},
}
local function get_sh_helper() return sh_compat_tbl[shell] or sh_compat_tbl.default end

-- get custom options from setup
local get_custom_opts = ya.sync(function(self)
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

local function eza_preview(prev_type, opts)
	-- mimic bat grid,header style
	local bar =
		[[echo -e "\x1b[38;2;148;130;158m────────────────────────────────────────────────────────────────────────────────\x1b[m";]]
	local bar_n =
		[[echo -e "\n\x1b[38;2;148;130;158m────────────────────────────────────────────────────────────────────────────────\x1b[m";]]

	local eza_prev_type = {
		default = [[echo -ne "Dir: \x1b[1m\x1b[38m{}\x1b[m";]],
		meta_fd = [[test -d {} && echo -ne "Dir: \x1b[1m\x1b[38m{}\x1b[m"]]
			.. [[ || echo -ne "File: \x1b[1m\x1b[38m{}\x1b[m";]],
		meta_rg = [[echo -ne "File: \x1b[1m\x1b[38m{]] .. "1" .. [[}\x1b[m";]],
	}

	local extra_flags = {
		default = "--oneline " .. opts.eza,
		meta_fd = "--git --git-repos --header --long --mounts --no-user --octal-permissions " .. opts.eza_meta,
		meta_rg = "--git --git-repos --header --long --mounts --no-user --octal-permissions " .. opts.eza_meta,
	}

	return table.concat({
		bar,
		eza_prev_type[prev_type],
		[[test -z "$(eza -A {1})" && echo -ne "  <EMPTY>\n" ||]],
		bar_n,
		"eza",
		extra_flags[prev_type],
		"--color=always --group-directories-first --icons {" .. "1" .. "};",
		bar,
	}, " ")
end

-- fzf with `rg` or `rga` search
local function get_fzf_cmd_for_content_search(search_type, opts)
	local sh = get_sh_helper()
	local cmd_tbl = {
		rg = {
			grep = "rg --color=always --line-number --smart-case" .. opts.rg,
			prev = "bat --color=always " .. opts.bat .. " --highlight-line={2} {1}",
			prev_window = "~3,+{2}+3/2,up,66%",
			prompt = "--prompt='rg> '",
			fzf_match = function(cmd_grep)
				-- fzf match option <ctrl-s>
				local bind_fzf_match_tmpl = "--bind='ctrl-s:transform:%s "
					.. [[echo "rebind(change)+change-prompt(rg> )+disable-search+clear-query+reload(%s {q} || true)" %s ]]
					.. [[echo "unbind(change)+change-prompt(fzf> )+enable-search+clear-query"']]
				return string.format(bind_fzf_match_tmpl, sh.rg_prompt.cond, cmd_grep, sh.rg_prompt.op)
			end,
		},
		rga = {
			grep = "rga --color=always --files-with-matches --smart-case" .. opts.rga,
			prev = "rga --context 5 --no-messages --pretty " .. opts.rga_preview .. " {q} {}",
			prev_window = "up,66%",
			prompt = "--prompt='rga> '",
		},
	}

	local cmd = cmd_tbl[search_type]
	if not cmd then
		fail("`%s` is not a valid argument for content search. Use `rg` or `rga` instead", search_type)
		return nil
	end

	local fzf_tbl = {
		"fzf",
		"--ansi",
		"--no-multi",
		"--reverse",
		"--delimiter=:",
		"--disabled",
		"--nth=3..",
		cmd.prompt,
		"--preview-label='content'",
		string.format("--preview='%s'", cmd.prev),
		string.format("--preview-window='%s'", cmd.prev_window),
		"--bind='start:reload:" .. cmd.grep .. " {q}'",
		"--bind='change:reload:sleep 0.1; " .. cmd.grep .. " {q} || true'",
		"--bind='ctrl-]:change-preview-window(80%|66%)'",
		"--bind='ctrl-\\:change-preview-window(right|up)'",
		"--bind='ctrl-r:clear-query+reload:" .. cmd.grep .. " {q} || true'",
		"--bind='ctrl-o:execute:$EDITOR {1} +{2}'",
		string.format(
			"--bind='alt-c:change-preview-label(content)+change-preview-window(~3,+{2}+3/2,up)+change-preview:%s'",
			cmd.prev
		),
		string.format(
			"--bind='alt-m:change-preview-label(metadata)+change-preview-window(~6,+{2}+3/2,up)+change-preview(%s)'",
			eza_preview("meta_rg", opts)
		),
		opts.fzf,
	}

	-- fzf match option is only available for `rg`
	if cmd.fzf_match then
		table.insert(fzf_tbl, cmd.fzf_match(cmd.grep))
	end

	return table.concat(fzf_tbl, " ")
end

-- fzf with `fd` search
local function get_fzf_cmd_for_name_search(search_type, opts)
	local sh = get_sh_helper()
	local cmd_tbl = {
		all = sh.wrap("fd --type=d " .. opts.fd .. " {q}; fd --type=f " .. opts.fd .. " {q}"),
		cwd = sh.wrap("fd --max-depth=1 --type=d " .. opts.fd .. " {q}; fd --max-depth=1 --type=f " .. opts.fd .. " {q}"),
		dir = "fd --type=dir " .. opts.fd .. " {q}",
		file = "fd --type=file " .. opts.fd .. " {q}",
	}

	local fd_cmd = cmd_tbl[search_type]
	if not fd_cmd then
		fail("`%s` is not a valid argument for file search. Use `all`, `cwd`, `dir` or `file` instead", search_type)
		return nil
	end

	local bat_prev = "bat --color=always " .. opts.bat .. " {}"
	local default_prev = string.format("test -d {} && %s || %s", sh.wrap(eza_preview("default", opts)), bat_prev)

	-- fzf match option <ctrl-s>
	local bind_fzf_match_tmpl = "--bind='ctrl-s:transform:%s "
		.. [[echo "rebind(change)+change-prompt(fd> )+clear-query+reload:%s" %s ]]
		.. [[echo "unbind(change)+change-prompt(fzf> )+clear-query"']]

	local fzf_tbl = {
		"fzf",
		"--ansi",
		"--no-multi",
		"--reverse",
		"--no-sort",
		"--prompt='fd> '",
		"--preview-label='content'",
		"--preview-window=up,66%",
		string.format("--preview='%s'", default_prev),
		string.format("--bind='start:reload:%s'", fd_cmd),
		string.format("--bind='change:reload:sleep 0.1; %s || true'", fd_cmd),
		"--bind='ctrl-]:change-preview-window(80%|66%)'",
		"--bind='ctrl-\\:change-preview-window(right|up)'",
		"--bind='ctrl-r:clear-query+reload:" .. fd_cmd .. "'",
		"--bind='ctrl-o:execute:$EDITOR {1}'",
		string.format("--bind='alt-c:change-preview-label(content)+change-preview:%s'", default_prev),
		string.format("--bind='alt-m:change-preview-label(metadata)+change-preview:%s'", eza_preview("meta_fd", opts)),
		string.format(bind_fzf_match_tmpl, sh.fd_prompt.cond, fd_cmd, sh.fd_prompt.op),
		opts.fzf,
	}

	return table.concat(fzf_tbl, " ")
end

local function entry(_, job)
	local _permit = ya.hide()
	local custom_opts = get_custom_opts() -- from user setup
	ya.dbg(custom_opts)
	local cwd = tostring(get_cwd())

	local search_type, search_opt = job.args[1], job.args[2]
	local args

	if search_type == "content" then
		args = get_fzf_cmd_for_content_search(search_opt or "rg", custom_opts) -- fallback to `rg` search by default
	elseif search_type == "name" then
		args = get_fzf_cmd_for_name_search(search_opt or "all", custom_opts) -- fallback to `fd` "all" search (dirs and files)
	else
		return fail("Search argument required. Make sure to pass 'content' or 'name' as the first argument.")
	end

	if not args then
		return -- unreachable?
	end

	local child, err = Command(shell)
		:args({ "-c", args })
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
				ya.manager_emit("reveal", { file_url })
			end
		elseif search_type == "name" then
			local is_dir = target:sub(-1) == "/"
			ya.manager_emit(is_dir and "cd" or "reveal", { target })
		end
	end
end

local function setup(self, opts)
	opts = opts or {}

	self.custom_opts = {
		fzf = opts.fzf,
		-- content search options
		rg = opts.rg,
		rga = opts.rga,
		-- path/filename search options
		fd = opts.fd,
		-- preview options
		bat = opts.bat,
		eza = opts.eza,
		eza_meta = opts.eza_meta,
		rga_preview = opts.rga_preview,
	}
end

return { entry = entry, setup = setup }
