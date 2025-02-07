-- lua/qnote/init.lua
local M = {}

local cookie_file = "/tmp/qnote_cookies.txt" -- Fichier temporaire pour stocker le cookie

local function read_creds()
	local home = os.getenv("HOME") or "~"
	local creds_path = home .. "/creds.txt"
	local file = io.open(creds_path, "r")

	if not file then
		print("Impossible de lire " .. creds_path)
		return nil, nil
	end

	local username = file:read("*l") -- Lire la première ligne
	local password = file:read("*l") -- Lire la deuxième ligne
	file:close()

	if not username or not password then
		print("Fichier " .. creds_path .. " invalide")
		return nil, nil
	end

	return username, password
end

local function login()
	local username, password = read_creds()
	print("username", username, "password", password)
	if not username or not password then
		return false
	end

	local login_url = "https://qkzk.ddns.net:4000/login"

	local cmd = string.format(
		"curl -v -s -c %s -X POST -d 'username=%s&password=%s' -H 'Content-Type: application/x-www-form-urlencoded' %s",
		cookie_file,
		username,
		password,
		login_url
	)

	print(cmd)

	local response = vim.fn.systemlist(cmd)
	print(response)

	if vim.v.shell_error ~= 0 then
		print("Échec de l'authentification.")
		return false
	end

	print("Connexion réussie.")
	return true
end

function M.fetch_todos()
	login()
	local url = "https://qkzk.ddns.net:4000/api/get_todos"
	local cmd = string.format("curl -s -b %s %s", cookie_file, url)
	print(cmd)
	local response = vim.fn.systemlist(cmd)
	print(response)

	-- Si la requête échoue, tenter de se reconnecter puis refaire la requête
	if vim.v.shell_error ~= 0 or (response[1] and response[1]:match("Unauthorized")) then
		print("Session expirée, tentative de reconnexion...")
		if login() then
			response = vim.fn.systemlist(cmd) -- Retenter la récupération
			print(response)
		else
			return
		end
	end

	-- Ouvre un buffer et affiche la réponse brute
	vim.api.nvim_command("new")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, response)
end

local telescope_qnote = require("qnote.telescope")

function M.show_todos()
	local todos_json = M.fetch_todos()
	if not todos_json then
		print("Erreur : impossible de récupérer les todos")
		return
	end

	local success, todos = pcall(vim.json.decode, todos_json)
	if not success then
		print("Erreur : impossible de décoder les todos")
		return
	end

	telescope_qnote.pick_todo(todos)
end

return M
