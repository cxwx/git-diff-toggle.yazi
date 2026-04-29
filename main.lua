-- git-diff-toggle.yazi
-- Toggle between git diff and normal file preview

local M = {}

local set_state = ya.sync(function(st, key, value) st[key] = value end)
local get_state = ya.sync(function(st, key) return st[key] end)

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
	local sr = Command("git")
		:arg({ "--no-optional-locks", "status", "--porcelain", "--", filename })
		:cwd(cwd)
		:output()
	if not sr then return nil, "not_repo" end

	local s = sr.stdout or ""
	if s == "" then return nil, "clean" end
	if s:sub(1, 2):find("?") then return nil, "untracked" end

	-- Get unstaged diff
	local dr = Command("git")
		:arg({ "diff", "--color=always", "-U3", "--", filename })
		:cwd(cwd)
		:output()
	local out = dr and dr.stdout or ""
	if out ~= "" then return out, "diff" end

	-- Get staged diff
	dr = Command("git")
		:arg({ "diff", "--cached", "--color=always", "-U3", "--", filename })
		:cwd(cwd)
		:output()
	out = dr and dr.stdout or ""
	if out ~= "" then return out, "staged" end

	return nil, "clean"
end

function M:peek(job)
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
	local cached_kind = get_state("cache_kind")

	if cached_key == file_key and cached_diff then
		ya.preview_widget(job, ui.Text.parse(cached_diff:gsub("\r", "")):area(job.area))
		return
	elseif cached_key == file_key and cached_kind then
		-- Known state with no diff
		return peek_normal(job)
	end

	-- Compute diff (this is the Command() call that may leak)
	local out, kind = get_diff(filename, cwd)

	if kind == "not_repo" then
		ya.notify { title = "Git Diff", content = "Not in git repo", timeout = 2 }
		set_state("enabled", false)
		set_state("cache_key", nil)
		set_state("cache_diff", nil)
		set_state("cache_kind", nil)
		return peek_normal(job)
	end

	-- Cache the result
	set_state("cache_key", file_key)
	set_state("cache_diff", out)
	set_state("cache_kind", kind)

	if not out then
		return peek_normal(job)
	end

	ya.preview_widget(job, ui.Text.parse(out:gsub("\r", "")):area(job.area))
end

function M:seek(job)
	local enabled = get_state("enabled")
	if not enabled then
		local ok, code = pcall(require, "code")
		if ok and code and code.seek then
			return code:seek(job)
		end
	end
	local h = cx.active.current.hovered
	if h and h.url == job.file.url then
		ya.emit("peek", { math.max(0, cx.active.preview.skip + job.units), only_if = h.url })
	end
end

function M:entry(_)
	local enabled = not get_state("enabled")
	set_state("enabled", enabled)
	-- Clear cache on toggle
	set_state("cache_key", nil)
	set_state("cache_diff", nil)
	set_state("cache_kind", nil)
	ya.notify { title = "Git Diff", content = enabled and "ON" or "OFF", timeout = 1 }
	local h = cx.active.current.hovered
	if h then
		ya.emit("peek", { 0, only_if = h.url })
	end
end

return M
