local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local previewers = require("telescope.previewers")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local M = {}

local function make_entry(todo)
	-- Affichage dans le picker
	local kind = todo.content.Text and "Text" or "Checkbox"
	return {
		value = todo,
		display = string.format("[%d] %s (%s)", todo.id, todo.title, kind),
		ordinal = todo.title,
		preview_command = function(entry, bufnr)
			-- Remplit la preview
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
		end,
	}
end
local function make_finder(todos)
	return {
		results = todos,
		entry_maker = make_entry,
	}
end

-- function M.pick_todo(todos)
-- 	pickers
-- 		.new({}, {
-- 			prompt_title = "Todos",
-- 			finder = finders.new_table(make_finder(todos)),
-- 			sorter = conf.generic_sorter({}),
-- 			previewer = previewers.new_buffer_previewer({
-- 				define_preview = function(self, entry, status)
-- 					if entry and entry.preview_command then
-- 						entry.preview_command(entry, self.state.bufnr)
-- 					end
-- 				end,
-- 			}),
-- 			attach_mappings = function(prompt_bufnr, map)
-- 				actions.select_default:replace(function()
-- 					actions.close(prompt_bufnr)
-- 					local selection = action_state.get_selected_entry()
-- 					if selection then
-- 						require("qnote").open_todo(selection.value)
-- 					end
-- 				end)
-- 				return true
-- 			end,
-- 		})
-- 		:find()
-- end

function M.pick_todo(todos)
	pickers
		.new({}, {
			prompt_title = "Todos",
			finder = finders.new_table(make_finder(todos)),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				define_preview = function(self, entry, status)
					if entry and entry.preview_command then
						entry.preview_command(entry, self.state.bufnr)
					end
				end,
			}),
			attach_mappings = function(prompt_bufnr, map)
				-- Ouvrir une note sur entrée
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						require("qnote").open_todo(selection.value)
					end
				end)

				-- Archiver avec <C-a>
				map("i", "<C-a>", function()
					local selection = action_state.get_selected_entry()
					if selection then
						actions.close(prompt_bufnr)
						M.send_qnote_request("PATCH", "toggle_archived", selection.value)
					end
				end)

				-- Supprimer avec <C-d>
				map("i", "<C-d>", function()
					local selection = action_state.get_selected_entry()
					if selection then
						actions.close(prompt_bufnr)
						M.send_qnote_request("DELETE", "delete_todo", selection.value)
					end
				end)

				return true
			end,
		})
		:find()
end
return M
