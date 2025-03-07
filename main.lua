--- @since 25.2.7

--[[
{
  fzf = "",            -- global fzf options
  -- content search options
  rg = "",             -- ripgrep options
  rga = "",            -- ripgrep-all options
  -- path/filename search options
  fd = "",             -- fd options
  -- preview options
  bat = "",            -- bat options for file preview (rg/fd)
  eza = "",            -- eza options for directory preview (fd)
  eza_meta = "",       -- eza metadata options (fd)
  rga_preview = "",    -- ripgrep-all preview options (rga)
}
--]]

local M = {}

-- utilities
local shell = os.getenv("SHELL"):match(".*/(.*)")
local get_cwd = ya.sync(function()
	return cx.active.current.cwd
end)
local fail = function(s, ...)
	ya.notify({ title = "frank", content = string.format(s, ...), timeout = 5, level = "error" })
end
local fmt_opts = function(opt)
	if type(opt) == "string" then
		return " " .. opt
	elseif type(opt) == "table" then
		return " " .. table.concat(opt, " ")
	end
	return ""
end

-- shell compatibility
local sh_compat = {
	default = {
		wrap = function(cmd)
			return "(" .. cmd .. ")"
		end,
		rg_logic = { cond = "[[ ! $FZF_PROMPT =~ rg ]] &&", op = "||" },
		fd_logic = { cond = "[[ ! $FZF_PROMPT =~ fd ]] &&", op = "||" },
	},
	fish = {
		wrap = function(cmd)
			return "begin; " .. cmd .. "; end"
		end,
		rg_logic = { cond = 'not string match -q "*rg*" $FZF_PROMPT; and', op = "; or" },
		fd_logic = { cond = 'not string match -q "*fd*" $FZF_PROMPT; and', op = "; or" },
	},
}

local function shell_helper()
	return sh_compat[shell] or sh_compat.default
end

-- get custom options from setup
local get_custom_opts = ya.sync(function()
	local opts = M.custom_opts or {}

	return {
		fzf = fmt_opts(opts.fzf),
		bat = fmt_opts(opts.bat),

		-- content search options
		rg = fmt_opts(opts.rg),
		rga = fmt_opts(opts.rga),
		rga_preview = fmt_opts(opts.rga_preview),

		-- file search options
		fd = fmt_opts(opts.fd),
		eza = fmt_opts(opts.eza),
		eza_meta = fmt_opts(opts.eza_meta),
	}
end)

-- preview functions for `fd` search
local function eza_preview(prev_type, opts)
	-- mimic bat grid,header style
	local bar =
		[[echo -e "\x1b[38;2;148;130;158m────────────────────────────────────────────────────────────────────────────────\x1b[m";]]
	local bar_n =
		[[echo -e "\n\x1b[38;2;148;130;158m────────────────────────────────────────────────────────────────────────────────\x1b[m";]]

	local name = {
		default = [[echo -ne "Dir: \x1b[1m\x1b[38m{}\x1b[m";]],
		meta = [[test -d {} && echo -ne "Dir: \x1b[1m\x1b[38m{}\x1b[m"]]
			.. [[ || echo -ne "File: \x1b[1m\x1b[38m{}\x1b[m";]],
	}

	local extra_flags = {
		default = "--oneline " .. opts.eza,
		meta = "--git --git-repos --header --long --mounts --no-user --octal-permissions " .. opts.eza_meta,
	}

	return table.concat({
		bar,
		name[prev_type],
		[[test -z "$(eza -A {})" && echo -ne "  <EMPTY>\n" ||]],
		bar_n,
		"eza",
		extra_flags[prev_type],
		"--color=always --group-directories-first --icons {};",
		bar,
	}, " ")
end

-- FZF command builders for different modes
local function build_content_search_cmd(search_type, opts)
	local sh = shell_helper()
	local cmd_tbl = {
		rg = {
			grep = "rg --color=always --line-number --smart-case" .. opts.rg,
			prev = "--preview='bat --color=always "
				.. opts.bat
				.. " --highlight-line={2} {1}' --preview-window=~3,+{2}+3/2,up,66%",
			prompt = "--prompt='rg> '",
			extra = function(cmd_grep)
				local lgc = sh.rg_logic
				local extra_bind = "--bind='ctrl-s:transform:%s "
					.. [[echo "rebind(change)+change-prompt(rg> )+disable-search+clear-query+reload(%s {q} || true)" %s ]]
					.. [[echo "unbind(change)+change-prompt(fzf> )+enable-search+clear-query"']]
				return string.format(extra_bind, lgc.cond, cmd_grep, lgc.op)
			end,
		},
		rga = {
			grep = "rga --color=always --files-with-matches --smart-case" .. opts.rga,
			prev = "--preview='rga --context 5 --no-messages --pretty "
				.. opts.rga_preview
				.. " {q} {}' --preview-window=up,66%",
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
		"--delimiter=:",
		"--disabled",
		"--layout=reverse",
		"--no-multi",
		"--nth=3..",
		cmd.prev,
		cmd.prompt,
		"--bind='start:reload:" .. cmd.grep .. " {q}'",
		"--bind='change:reload:sleep 0.1; " .. cmd.grep .. " {q} || true'",
		"--bind='ctrl-]:change-preview-window(80%|66%)'",
		"--bind='ctrl-\\:change-preview-window(right|up)'",
		"--bind='ctrl-r:clear-query+reload:" .. cmd.grep .. " {q} || true'",
		opts.fzf,
	}

	if cmd.extra then
		table.insert(fzf_tbl, cmd.extra(cmd.grep))
	end

	return table.concat(fzf_tbl, " ")
end

local function build_file_search_cmd(search_type, opts)
	local sh = shell_helper()
	local cmd_tbl = {
		all = sh.wrap("fd --type=d " .. opts.fd .. " {q}; fd --type=f " .. opts.fd .. " {q}"),
		cwd = sh.wrap(
			"fd --max-depth=1 --type=d " .. opts.fd .. " {q}; fd --max-depth=1 --type=f " .. opts.fd .. " {q}"
		),
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

	-- bind toggle fzf match
	local bind_match_tmpl = "--bind='ctrl-s:transform:%s "
		.. [[echo "rebind(change)+change-prompt(fd> )+clear-query+reload:%s" %s ]]
		.. [[echo "unbind(change)+change-prompt(fzf> )+clear-query"']]

	local fzf_tbl = {
		"fzf",
		"--no-multi",
		"--no-sort",
		"--reverse",
		"--preview-label='content'",
		"--prompt='fd> '",
		"--preview-window=up,66%",
		string.format("--preview='%s'", default_prev),
		string.format("--bind='start:reload:%s'", fd_cmd),
		string.format("--bind='change:reload:sleep 0.1; %s || true'", fd_cmd),
		"--bind='ctrl-]:change-preview-window(80%|66%)'",
		"--bind='ctrl-\\:change-preview-window(right|up)'",
		string.format("--bind 'alt-c:change-preview-label(content)+change-preview:%s'", default_prev),
		string.format("--bind 'alt-m:change-preview-label(metadata)+change-preview:%s'", eza_preview("meta", opts)),
		string.format(bind_match_tmpl, sh.fd_logic.cond, fd_cmd, sh.fd_logic.op),
		opts.fzf,
	}

	return table.concat(fzf_tbl, " ")
end

function M.entry(_, job)
	local _permit = ya.hide()
	local custom_opts = get_custom_opts()
	local cwd = tostring(get_cwd())

	local mode, search_type = job.args[1], job.args[2]
	local args

	if mode == "content" then
		args = build_content_search_cmd(search_type or "rg", custom_opts)
	elseif mode == "file" then
		args = build_file_search_cmd(search_type or "all", custom_opts)
	else
		return fail("Invalid mode. Use 'content' or 'file'")
	end

	if not args then
		return
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
	if not output then
		return fail("Cannot read command output, error code %s", err)
	end

	if output.status.code == 130 then -- interrupted with <ctrl-c> or <esc>
		return nil
	elseif output.status.code == 1 then -- no match
		ya.notify({ title = "frank", content = "No match found", timeout = 5 })
		return nil
	elseif output.status.code ~= 0 then -- anything other than normal exit
		fail("`fzf` exited with error code %s", output.status.code)
		return nil
	end

	local target = output.stdout:gsub("\n$", "")
	if target ~= "" then
		if mode == "content" then
			local colon_pos = string.find(target, ":")
			local file_url = colon_pos and string.sub(target, 1, colon_pos - 1) or target
			if file_url then
				ya.manager_emit("reveal", { file_url })
			end
		elseif mode == "file" then
			local is_dir = target:sub(-1) == "/"
			ya.manager_emit(is_dir and "cd" or "reveal", { target })
		end
	end
end

function M.setup(opts)
	opts = opts or {}

	M.custom_opts = {
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

return M
