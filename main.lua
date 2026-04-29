-- git-diff-toggle.yazi
-- Toggle between git diff and normal file preview

-- luacheck: globals ya ui cx Command

local M = {}

local set_state = ya.sync(function(st, key, value) st[key] = value end)
local get_state = ya.sync(function(st, key) return st[key] end)
local get_hovered_url = ya.sync(function()
	local h = cx.active.current.hovered
	return h and h.url or nil
end)
local get_preview_skip = ya.sync(function() return cx.active.preview.skip end)

local function preview_text(job, text)
	local clean = (text or ""):gsub("\r", "")
	if clean == "" then
		return ya.preview_widget(job, ui.Text.parse(""):area(job.area))
	end

	local lines, from = {}, 1
	while true do
		local to = clean:find("\n", from, true)
		if not to then
			lines[#lines + 1] = clean:sub(from)
			break
		end
		lines[#lines + 1] = clean:sub(from, to - 1)
		from = to + 1
	end

	local start = math.max(0, job.skip) + 1
	local last = math.min(#lines, job.skip + job.area.h)
	if start > #lines or start > last then
		return ya.preview_widget(job, ui.Text.parse(""):area(job.area))
	end

	local visible = {}
	for i = start, last do
		visible[#visible + 1] = lines[i]
	end
	ya.preview_widget(job, ui.Text.parse(table.concat(visible, "\n")):area(job.area))
end

local function peek_normal(job)
	local ok, code = pcall(require, "code")
	if ok and code and code.peek then
		return code:peek(job)
	end
	local file = io.open(tostring(job.file.url), "r")
	if not file then
		return ya.preview_widget(job, ui.Text("Cannot open file"):area(job.area))
	end
	local lines, i = {}, 0
	for line in file:lines() do
		i = i + 1
		if i > job.skip then lines[#lines + 1] = line end
		if i >= job.skip + job.area.h then break end
	end
	file:close()
	ya.preview_widget(job, ui.Text.parse(table.concat(lines, "\n")):area(job.area))
end

-- Get diff for a file, cache result in plugin state
local function get_diff(filename, cwd)
	-- Check status first
	local sr, err = Command("git")
		:arg({ "--no-optional-locks", "status", "--porcelain", "--", filename })
		:cwd(cwd)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()
	if not sr then return nil, "error", err end
	if sr.status and sr.status.code ~= 0 then
		local stderr = sr.stderr or ""
		if stderr:find("not a git repository", 1, true) then
			return nil, "not_repo"
		end
		return nil, "error", stderr
	end

	local s = sr.stdout or ""
	if s == "" then return nil, "clean" end
	-- Treat lines starting with '??' as untracked files from 'git status --porcelain'
	if s:match("^%?%?") then return nil, "untracked" end

	-- Get unstaged diff
	local dr, derr = Command("git")
		:arg({ "diff", "--color=always", "-U3", "--", filename })
		:cwd(cwd)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()
	if not dr then return nil, "error", derr end
	if dr.status and dr.status.code ~= 0 then return nil, "error", dr.stderr or "" end
	local out = dr and dr.stdout or ""
	if out ~= "" then return out, "diff" end

	-- Get staged diff
	dr, derr = Command("git")
		:arg({ "diff", "--cached", "--color=always", "-U3", "--", filename })
		:cwd(cwd)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()
	if not dr then return nil, "error", derr end
	if dr.status and dr.status.code ~= 0 then return nil, "error", dr.stderr or "" end
	out = dr and dr.stdout or ""
	if out ~= "" then return out, "staged" end

	return nil, "clean"
end

function M:peek(job)
	local _ = self
	local enabled = get_state("enabled")
	if not enabled then
		return peek_normal(job)
	end

	local cwd = tostring(job.file.url.parent)
	local filename = tostring(job.file.url.name)
	local file_key = tostring(job.file.url)

	-- Use cached diff if available for same file
	local cached_key = get_state("cache_key")
	local cached_diff = get_state("cache_diff")

	if cached_key == file_key and cached_diff then
		preview_text(job, cached_diff)
		return
	end

	local out, kind, err = get_diff(filename, cwd)

	if kind == "not_repo" then
		ya.notify { title = "Git Diff", content = "Not in git repo", timeout = 2 }
		set_state("enabled", false)
		set_state("cache_key", nil)
		set_state("cache_diff", nil)
		return peek_normal(job)
	elseif kind == "error" then
		ya.notify { title = "Git Diff", content = "git command failed: " .. tostring(err or ""), timeout = 2 }
		set_state("cache_key", nil)
		set_state("cache_diff", nil)
		return peek_normal(job)
	end

	if not out then
		-- Don't cache clean/untracked states to avoid stale preview for same file.
		set_state("cache_key", nil)
		set_state("cache_diff", nil)
		return peek_normal(job)
	end

	set_state("cache_key", file_key)
	set_state("cache_diff", out)
	preview_text(job, out)
end

function M:seek(job)
	local _ = self
	local enabled = get_state("enabled")
	if not enabled then
		local ok, code = pcall(require, "code")
		if ok and code and code.seek then
			return code:seek(job)
		end
	end
	local hovered = get_hovered_url()
	if hovered and hovered == job.file.url then
		ya.emit("peek", { math.max(0, get_preview_skip() + job.units), only_if = hovered })
	end
end

function M:entry(_)
	local _ = self
	local enabled = not get_state("enabled")
	set_state("enabled", enabled)
	-- Clear cache on toggle
	set_state("cache_key", nil)
	set_state("cache_diff", nil)
	ya.notify { title = "Git Diff", content = enabled and "ON" or "OFF", timeout = 1 }
	local hovered = get_hovered_url()
	if hovered then
		ya.emit("peek", { 0, only_if = hovered })
	end
end

return M
