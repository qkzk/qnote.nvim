local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values

local M = {}

function M.pick_todo(todos)
	local entries = {}

	-- Transforme les todos en une liste d'entrées pour Telescope
	for _, todo in ipairs(todos) do
		local kind = todo.content.Text and "Text" or "Checkboxes"
		table.insert(entries, {
			id = todo.id,
			title = todo.title,
			kind = kind,
			content = todo.content,
		})
	end

	pickers
		.new({}, {
			prompt_title = "Todos",
			finder = finders.new_table({
				results = entries,
				entry_maker = function(entry)
					return {
						value = entry,
						display = string.format("[%d] %s (%s)", entry.id, entry.title, entry.kind),
						ordinal = entry.title,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				define_preview = function(self, entry)
					local content = entry.value.content
					local text = ""

					if content.Text then
						text = content.Text
					elseif content.Checkboxes then
						local todo_items = table.concat(content.Checkboxes.todo, "\n- [ ] ")
						local done_items = table.concat(content.Checkboxes.done, "\n- [x] ")
						text = string.format("# TODO\n- [ ] %s\n\n# DONE\n- [x] %s", todo_items, done_items)
					end

					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(text, "\n"))
				end,
			}),
		})
		:find()
end

return M
