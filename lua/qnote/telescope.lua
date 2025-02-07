local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local previewers = require("telescope.previewers")

local M = {}

function M.pick_todo(todos)
	pickers
		.new({}, {
			prompt_title = "Todos",
			finder = finders.new_table({
				results = todos,
				entry_maker = function(todo)
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
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				define_preview = function(self, entry, status)
					if entry and entry.preview_command then
						entry.preview_command(entry, self.state.bufnr)
					end
				end,
			}),
			attach_mappings = function(_, map)
				map("i", "<CR>", function(prompt_bufnr)
					local selection = require("telescope.actions.state").get_selected_entry()
					require("telescope.actions").close(prompt_bufnr)
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
