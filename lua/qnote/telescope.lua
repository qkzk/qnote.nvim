local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local previewers = require("telescope.previewers")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local M = {}

---Fill the preview buffer of telescope with todo content
---@param entry table
---@param bufnr number
local function fill_preview(entry, bufnr)
	-- Fill preview
	local lines = {}
	table.insert(lines, "# " .. entry.value.title)
	table.insert(lines, "")
	if entry.value.content.Text then
		vim.list_extend(lines, vim.split(entry.value.content.Text, "\n", { plain = true }))
	elseif entry.value.content.Checkboxes then
		table.insert(lines, "**TODO:**")
		for _, item in ipairs(entry.value.content.Checkboxes.todo) do
			vim.list_extend(lines, vim.split("- [ ] " .. item, "\n", { plain = true }))
		end
		table.insert(lines, "")
		table.insert(lines, "**DONE:**")
		for _, item in ipairs(entry.value.content.Checkboxes.done) do
			vim.list_extend(lines, vim.split("- [x] " .. item, "\n", { plain = true }))
		end
	end
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

---Creates a telescope entry for this todo
---@param todo table
---@return table
local function make_entry(todo)
	local kind = todo.content.Text and "Text" or "Checkbox"
	return {
		value = todo,
		display = string.format("[%d] %s (%s)", todo.id, todo.title, kind),
		ordinal = todo.title,
		preview_command = fill_preview,
	}
end

---Creates a telescope finder
---@param todos any
---@return table
local function make_finder(todos)
	return {
		value = "INFO",
		display = " [Ctrl-A] Archive  |  [Ctrl-D] Delete ",
		results = todos,
		entry_maker = make_entry,
	}
end

---Creates telescope keybinds
---<Return> opens a todo
---<C-a> toggle archived state of the todo
---<C-d> deletes the todo from server
---@param prompt_bufnr number
---@param map table
---@return boolean
local function create_mappings(prompt_bufnr, map)
	-- <Return> opens a todo
	actions.select_default:replace(function()
		actions.close(prompt_bufnr)
		local selection = action_state.get_selected_entry()
		if selection then
			require("qnote").open_todo(selection.value)
		end
	end)

	-- <C-a> toggle archived state of the todo
	map("i", "<C-a>", function()
		local selection = action_state.get_selected_entry()
		if selection then
			actions.close(prompt_bufnr)
			require("qnote").send_qnote_request("PATCH", "toggle_archived", selection.value.id)
		end
	end)

	-- <C-d> deletes the todo from server
	map("i", "<C-d>", function()
		local selection = action_state.get_selected_entry()
		if selection then
			actions.close(prompt_bufnr)
			require("qnote").send_qnote_request("DELETE", "delete_todo", selection.value.id)
		end
	end)

	return true
end

---Creates the preview command
---@param self any
---@param entry table
---@param status any
function make_preview(self, entry, status)
	if entry and entry.preview_command then
		entry.preview_command(entry, self.state.bufnr)
	end
end

---Action executed when a todo is picked.
---@param todos table
function M.pick_todo(todos)
	pickers
		.new({}, {
			prompt_title = "Todos",
			finder = finders.new_table(make_finder(todos)),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				define_preview = make_preview,
			}),
			attach_mappings = create_mappings,
		})
		:find()
end
return M
