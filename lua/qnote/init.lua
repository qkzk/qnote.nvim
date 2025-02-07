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
	-- print("username", username, "password", password)
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

	-- print(cmd)

	local response = vim.fn.systemlist(cmd)
	-- print(response)

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
	-- print(cmd)
	local response = vim.fn.systemlist(cmd)

	-- 🚀 Convertit la table en string JSON
	response = table.concat(response, "\n")

	-- print(response) -- Afficher le JSON brut pour vérifier

	-- Si la requête échoue, tenter de se reconnecter puis refaire la requête
	if vim.v.shell_error ~= 0 or response:match("Unauthorized") then
		print("Session expirée, tentative de reconnexion...")
		if login() then
			response = vim.fn.systemlist(cmd) -- Retenter la récupération
			response = table.concat(response, "\n") -- 🔥 Transformer encore en string
			-- print(response)
			return response
		else
			return response
		end
	end

	-- Ouvre un buffer et affiche la réponse brute (DEBUG)
	-- vim.api.nvim_command("new")
	-- vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(response, "\n"))
	return response
end

local telescope_qnote = require("qnote.telescope")

function M.show_todos()
	local todos_json = M.fetch_todos()
	-- print(todos_json)
	-- print(vim.inspect(todos_json)) -- Debug: voir la vraie valeur retournée
	if not todos_json or type(todos_json) ~= "string" then
		print("Erreur : fetch_todos() ne retourne pas un JSON valide")
		return
	end

	local success, todos = pcall(vim.json.decode, todos_json)
	if not success then
		print("Erreur : impossible de décoder les todos")
		return
	end

	telescope_qnote.pick_todo(todos)
end

function M.open_todo(todo)
	-- Crée un nouveau buffer et une nouvelle fenêtre
	local bufnr = vim.fn.bufnr(string.format("qnote_%d.md", todo.id))

	if bufnr == -1 then
		-- Crée un nouveau buffer s'il n'existe pas encore
		bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(bufnr, string.format("qnote_%d.md", todo.id))
		vim.bo[bufnr].bufhidden = "wipe"
		vim.bo[bufnr].swapfile = false
	end

	-- Change le buffer courant sans ouvrir une nouvelle fenêtre
	vim.api.nvim_set_current_buf(bufnr)

	-- Remplit le buffer avec le titre et le contenu
	local lines = {
		"# " .. todo.title, -- Titre
		"", -- Ligne vide pour séparation
	}

	-- Ajoute le contenu en fonction du type
	if todo.content.Text then
		table.insert(lines, todo.content.Text)
	elseif todo.content.Checkboxes then
		table.insert(lines, "**TODO:**")
		for _, item in ipairs(todo.content.Checkboxes.todo) do
			table.insert(lines, "- [ ] " .. item)
		end
		table.insert(lines, "")
		table.insert(lines, "**DONE:**")
		for _, item in ipairs(todo.content.Checkboxes.done) do
			table.insert(lines, "- [x] " .. item)
		end
	end
	-- Nom du fichier temporaire basé sur le titre ou l'ID
	local filename = string.format("qnote_%d.md", todo.id)

	-- Définit le nom du buffer (sans l'écrire sur disque)
	vim.api.nvim_buf_set_name(bufnr, filename)
	vim.bo.bufhidden = "wipe" -- Ferme le buffer proprement après fermeture
	vim.bo.swapfile = false -- Désactive les fichiers swap pour éviter les alertes

	-- Écrit dans le buffer
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

return M
