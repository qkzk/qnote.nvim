-- lua/qnote/init.lua
local M = {}

function M.hello()
	print("Hello, world!")
end

function M.fetch_todos()
	local url = "https://qkzk.ddns.net:4000/api/get_todos"
	local response = vim.fn.systemlist("curl -s " .. url)

	if vim.v.shell_error ~= 0 then
		print("Erreur lors de la récupération des todos.")
		return
	end

	-- Ouvre un buffer et affiche la réponse brute
	vim.api.nvim_command("new")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, response)
end

return M
