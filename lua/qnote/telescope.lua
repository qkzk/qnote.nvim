local M = {}

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

function M.pick_todo(todos)
	pickers
		.new({}, {
			prompt_title = "qnote Todos",
			finder = finders.new_table({
				results = todos,
				entry_maker = function(todo)
					local kind = todo.content.Text and "Text" or "Checkboxes"
					return {
						value = todo,
						display = string.format("%d | %s | %s", todo.id, todo.title, kind),
						ordinal = todo.title,
						preview = function(_, entry, status)
							local preview_bufnr = status.preview_bufnr
							local lines = {}

							if entry.value.content.Text then
								table.insert(lines, entry.value.content.Text)
							elseif entry.value.content.Checkboxes then
								table.insert(lines, "**TODO:**")
								for _, item in ipairs(entry.value.content.Checkboxes.todo) do
									table.insert(lines, "- [ ] " .. item)
								end
								table.insert(lines, "")
								table.insert(lines, "**DONE:**")
								for _, item in ipairs(entry.value.content.Checkboxes.done) do
									table.insert(lines, "- [x] " .. item)
								end
							end

							vim.api.nvim_buf_set_lines(preview_bufnr, 0, -1, false, lines)
						end,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						require("qnote").open_todo(selection.value)
					end
				end)
				return true
			end,
		})
		:find()
end

return M
