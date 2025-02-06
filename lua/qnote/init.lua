-- lua/qnote/init.lua
local M = {}

local cookie_file = "/tmp/qnote_cookies.txt" -- Fichier temporaire pour stocker le cookie

local function login()
	local login_url = "https://qkzk.ddns.net:4000/login"
	local username = "ton_username" -- À remplacer ou demander dynamiquement
	local password = "ton_mdp" -- Idem, éviter de le stocker en dur

	local cmd = string.format(
		"curl -s -c %s -X POST -d 'username=%s&password=%s' -H 'Content-Type: application/x-www-form-urlencoded' %s",
		cookie_file,
		username,
		password,
		login_url
	)

	local response = vim.fn.systemlist(cmd)

	if vim.v.shell_error ~= 0 then
		print("Échec de l'authentification.")
		return false
	end

	print("Connexion réussie.")
	return true
end

function M.fetch_todos()
	local url = "https://qkzk.ddns.net:4000/api/get_todos"
	local cmd = string.format("curl -s -b %s %s", cookie_file, url)
	local response = vim.fn.systemlist(cmd)

	-- Si la requête échoue, tenter de se reconnecter puis refaire la requête
	if vim.v.shell_error ~= 0 or (response[1] and response[1]:match("Unauthorized")) then
		print("Session expirée, tentative de reconnexion...")
		if login() then
			response = vim.fn.systemlist(cmd) -- Retenter la récupération
		else
			return
		end
	end

	-- Ouvre un buffer et affiche la réponse brute
	vim.api.nvim_command("new")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, response)
end

return M
