-- lua/qnote/init.lua
local M = {}

M.config = {
	creds_file = "~/creds.txt",
	cookie_file = "/tmp/qnote_cookies.txt", -- Par défaut
	server_url = "https://qkzk.ddns.net:4000", -- Par défaut
}

---Setup the config
---@param config table
function M.setup(config)
	M.config = vim.tbl_extend("force", M.config, config or {})
end

local sets = { { 97, 122 }, { 65, 90 }, { 48, 57 } } -- a-z, A-Z, 0-9

---returns a random string of len `size`
---@param size number positive integer
---@return string - of length `size`
local function string_random(size)
	local str = ""
	for i = 1, size do
		math.randomseed(os.clock() ^ 5)
		local charset = sets[math.random(1, #sets)]
		str = str .. string.char(math.random(charset[1], charset[2]))
	end
	return str
end

---returns login & password read from creds file
---If the file can't be opened or is invalid, returns `nil, nil`
---@return string | nil
---@return string | nil
local function read_creds()
	local file = io.open(M.config.creds_file, "r")

	if not file then
		print("Couldn't read " .. M.config.creds_file)
		return nil, nil
	end

	local username = file:read("*l")
	local password = file:read("*l")
	file:close()

	if not username or not password then
		print("Invalid file " .. M.config.creds_file)
		return nil, nil
	end

	return username, password
end

---login to the server, sending login & password through a POST request.
local function login()
	local username, password = read_creds()
	-- print("username", username, "password", password)
	if not username or not password then
		return false
	end

	local login_url = string.format("%s/login", M.config.server_url)

	local cmd = string.format(
		"curl -v -s -c %s -X POST -d 'username=%s&password=%s' -H 'Content-Type: application/x-www-form-urlencoded' %s",
		M.config.cookie_file,
		username,
		password,
		login_url
	)

	-- print(cmd)

	local response = vim.fn.systemlist(cmd)
	-- print(response)

	if vim.v.shell_error ~= 0 then
		print("Authentification failed.")
		return false
	end

	-- print("Authentification successful")
	return true
end

---fetch todos from server with a GET request. Returns a table of todos
---@return table - a table of todos
function M.fetch_todos()
	login()
	local url = string.format("%s/api/get_todos", M.config.server_url)
	local cmd = string.format("curl -s -b %s %s", M.config.cookie_file, url)
	-- print(cmd)
	local response = vim.fn.systemlist(cmd)

	-- parse the table into json
	response = table.concat(response, "\n")

	-- print(response)

	-- If the requests fails, try again.
	if vim.v.shell_error ~= 0 or response:match("Unauthorized") then
		print("Session has expired. Reconnect.")
		if login() then
			response = vim.fn.systemlist(cmd)
			response = table.concat(response, "\n")
			-- print(response)
			return response
		else
			return response
		end
	end

	return response
end

local telescope_qnote = require("qnote.telescope")

---Display todos in telescope finder
function M.show_todos()
	local todos_json = M.fetch_todos()
	-- print(todos_json)
	-- print(vim.inspect(todos_json))
	if not todos_json or type(todos_json) ~= "string" then
		print("Error : fetch_todos() didn't return a valid JSON")
		return
	end

	local success, todos = pcall(vim.json.decode, todos_json)
	if not success then
		print("Error : couldn't read the todos")
		return
	end

	telescope_qnote.pick_todo(todos)
end

---writes todo content into lines.
---@param todo table  _checkboxes_ kind
local function fill_checkboxes_line(todo, lines)
	table.insert(lines, "**TODO:**")
	for _, item in ipairs(todo.content.Checkboxes.todo) do
		local checkbox_lines = vim.split(item, "\n", { plain = true })
		for _, line in ipairs(checkbox_lines) do
			table.insert(lines, "- [ ] " .. line)
		end
	end
	table.insert(lines, "")
	table.insert(lines, "**DONE:**")
	for _, item in ipairs(todo.content.Checkboxes.done) do
		local checkbox_lines = vim.split(item, "\n", { plain = true })
		for _, line in ipairs(checkbox_lines) do
			table.insert(lines, "- [x] " .. line)
		end
	end
end

---Opens `todo` into a buffer
---@param todo table
function M.open_todo(todo)
	local bufname = string.format("/tmp/qnote_%d.md", todo.id)
	-- check if a buffer already exists for this todo
	local bufnr = vim.fn.bufnr(bufname)

	if bufnr == -1 then
		bufnr = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(bufnr, bufname)

		-- Ensure buffer is writable
		vim.bo[bufnr].buflisted = true
		vim.bo[bufnr].buftype = "" -- Allows saving
		vim.bo[bufnr].bufhidden = "hide" -- Keep the buffer don't delete
		vim.bo[bufnr].swapfile = false
	end

	vim.api.nvim_set_current_buf(bufnr)

	local lines = {
		"# " .. todo.title,
		"",
	}

	-- Fill the content depending of todo kind.
	if todo.content.Text then
		local text_lines = vim.split(todo.content.Text, "\n", { plain = true })
		vim.list_extend(lines, text_lines)
	elseif todo.content.Checkboxes then
		fill_checkboxes_line(todo, lines)
	end

	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

---Setup an autosave function, sending POST request when the buffer is written
function M.setup_autosave()
	vim.api.nvim_create_autocmd("BufWritePost", {
		pattern = "qnote_*.md",
		callback = function(args)
			local bufnr = args.buf
			local filename = vim.api.nvim_buf_get_name(bufnr)

			-- Read todo.id from buffer content
			local todo_id = filename:match("qnote_(%d+)%.md")
			if not todo_id then
				print("Error : couldn't read id from buffer")
				return
			end

			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

			local content_type, payload = M.parse_todo_content(lines)

			if content_type and payload then
				M.send_todo_update(todo_id, content_type, payload)
			else
				print("Error : invalid content, nothing sent.")
			end
		end,
	})
end

---parse the todo content
---@param lines table
---@return nil
---@return string | table
function M.parse_todo_content(lines)
	-- Check if the content has at least one line
	if #lines == 0 then
		return nil, "Error : empty content"
	end

	-- Extract title
	local title = lines[1]:match("^#%s*(.+)")
	if not title then
		return nil, "Erreur : titre introuvable"
	end

	-- Extract content, ignoring empty lines
	local content_lines = {}
	for i = 2, #lines do
		if lines[i] ~= "" then
			table.insert(content_lines, lines[i])
		end
	end

	-- if todo is "Text" kind, returns "Text" and payload
	if not vim.tbl_contains(content_lines, "**TODO:**") then
		return "Text", { title = title, content = table.concat(content_lines, "\n") }
	end

	-- else, parse the todo & done checkboxes...
	local todos, dones = {}, {}

	for _, line in ipairs(content_lines) do
		if line:match("%- %[ %] (.+)") then
			table.insert(todos, line:match("%- %[ %] (.+)"))
		elseif line:match("%- %[x%] (.+)") then
			table.insert(dones, line:match("%- %[x%] (.+)"))
		end
	end
	-- and returns it
	return "Checkboxes", { title = title, todo = todos, done = dones }
end

---Update the todo content
---@param id number
---@param content_type string
---@param payload table
function M.send_todo_update(id, content_type, payload)
	local url = string.format("https://qkzk.ddns.net:4000/api/patch_todo_%s/%s", content_type:lower(), id)
	local json_data = vim.fn.json_encode(payload)
	local cmd = string.format(
		"curl -s -X PATCH -b %s -H 'Content-Type: application/json' -d '%s' '%s'",
		M.config.cookie_file,
		json_data,
		url
	)

	-- print(cmd)
	local response = vim.fn.systemlist(cmd)
	-- print(response)

	if vim.v.shell_error == 0 then
		print("Todo updated successfuly")
	else
		print("Error udpating todo.")
	end
end

---Creates a new todo of given kind
---The todo is displayed in a randomly named buffer.
---@param content_type string "text" or "todo"
function M.create_todo(content_type)
	local bufnr = vim.api.nvim_create_buf(false, true)
	local filename = "/tmp/qnote_new_" .. string_random(4) .. ".md"

	vim.api.nvim_buf_set_name(bufnr, filename)
	vim.bo[bufnr].buflisted = true
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].buftype = "" -- allows saving
	vim.bo[bufnr].swapfile = false

	local default_content
	if content_type == "text" then
		default_content = { "# Title", "", "Your content here..." }
	else
		default_content = { "# Title", "", "**TODO:**", "- [ ] Task 1", "", "**DONE:**", "- [x] Completed task" }
	end

	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, default_content)
	vim.api.nvim_set_current_buf(bufnr)

	-- Creates an autocommand to send the todo
	vim.api.nvim_create_autocmd("BufWritePost", {
		buffer = bufnr,
		callback = function()
			M.send_new_todo(bufnr)
		end,
	})
end

---Send a new todo to the server
---The content kind is read from the buffer
---@param bufnr number
function M.send_new_todo(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local title = lines[1]:gsub("^#%s*", "") -- Supprime le `#` devant le titre

	-- Parse conctent
	local content_type, payload = M.parse_todo_content(lines)
	payload.title = title -- Ajouter le titre

	-- Pick correct route
	local route = (content_type == "Text") and "/api/post_text" or "/api/post_checkboxes"
	local url = M.config.server_url .. route
	local json_data = vim.fn.json_encode(payload)

	-- login
	login()
	-- Send the request
	local cmd = string.format(
		"curl -s -X POST -b %s -H 'Content-Type: application/json' -d %s '%s'",
		M.config.cookie_file,
		vim.fn.shellescape(json_data),
		url
	)

	print(cmd)
	local response = vim.fn.systemlist(cmd)
	print(response)

	if vim.v.shell_error == 0 then
		print("Todo créé avec succès !")
	else
		print("Erreur lors de la création du todo.", vim.v.shell_error)
	end
end

---Send qnote request.
---Used to update or delete todo.
---@param method string "DELETE" or "PATCH"
---@param endpoint string
---@param id number | nil
function M.send_qnote_request(method, endpoint, id)
	local url = string.format("%s/api/%s/%d", M.config.server_url, endpoint, id)
	local cmd = string.format("curl -s -X %s -b %s '%s'", method, M.config.cookie_file, url)

	login()
	-- print(cmd)
	local response = vim.fn.systemlist(cmd)
	-- print(response)

	if vim.v.shell_error == 0 then
		print(string.format("Todo %d updated successfuly", id))
	else
		print(string.format("Error sending request %s for todo %d.", method, id))
	end
end

---Usage message displayed when user types an unknown command
M.usage = "Usage: Qnote show | new text | new todo | {archive|delete} {id}"

---Execute a "qnote" command.
---If `opts` doesn't contain a valid "args" table, displays the usage and quits.
---@param opts table
local function run_command(opts)
	local args = vim.split(opts.args, " ")
	local action = args[1]

	if not action then
		print(M.usage)
		return
	end

	if action == "show" then
		M.show_todos()
	elseif action == "new" and args[2] == "text" then
		M.create_todo("text")
	elseif action == "new" and args[2] == "todo" then
		M.create_todo("checkboxes")
	elseif action == "archive" then
		local id = tonumber(args[2])
		M.send_qnote_request("PATCH", "toggle_archived", id)
	elseif action == "delete" then
		local id = tonumber(args[2])
		M.send_qnote_request("DELETE", "delete_todo", id)
	else
		print(M.usage)
	end
end

---Completion for COMMAND mode.
---@param _ any
---@param line string
---@return unknown[]
local function complete(_, line)
	local commands = { "show", "new text", "new todo", "archive", "delete" }
	local words = vim.split(line, "%s+")
	return vim.tbl_filter(function(cmd)
		return vim.startswith(cmd, words[#words])
	end, commands)
end

vim.api.nvim_create_user_command("Qnote", run_command, { nargs = "*", complete = complete })

M.setup_autosave()

return M
