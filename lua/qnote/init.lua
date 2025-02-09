-- lua/qnote/init.lua
local M = {}

M.config = {
	creds_file = "~/creds.txt",
	cookie_file = "/tmp/qnote_cookies.txt", -- Par défaut
	server_url = "https://qkzk.ddns.net:4000", -- Par défaut
}

function M.setup(config)
	M.config = vim.tbl_extend("force", M.config, config or {})
end

local sets = { { 97, 122 }, { 65, 90 }, { 48, 57 } } -- a-z, A-Z, 0-9

local function string_random(chars)
	local str = ""
	for i = 1, chars do
		math.randomseed(os.clock() ^ 5)
		local charset = sets[math.random(1, #sets)]
		str = str .. string.char(math.random(charset[1], charset[2]))
	end
	return str
end

local function read_creds()
	local file = io.open(M.config.creds_file, "r")

	if not file then
		print("Impossible de lire " .. M.config.creds_file)
		return nil, nil
	end

	local username = file:read("*l") -- Lire la première ligne
	local password = file:read("*l") -- Lire la deuxième ligne
	file:close()

	if not username or not password then
		print("Fichier " .. M.config.creds_file .. " invalide")
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
		print("Échec de l'authentification.")
		return false
	end

	print("Connexion réussie.")
	return true
end

function M.fetch_todos()
	login()
	local url = string.format("%s/api/get_todos", M.config.server_url)
	local cmd = string.format("curl -s -b %s %s", M.config.cookie_file, url)
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
	-- Vérifie si un buffer existe déjà pour ce todo
	local bufnr = vim.fn.bufnr(string.format("/tmp/qnote_%d.md", todo.id))

	if bufnr == -1 then
		-- Crée un nouveau buffer s'il n'existe pas encore
		bufnr = vim.api.nvim_create_buf(true, false) -- Buffer listé, non éphémère
		vim.api.nvim_buf_set_name(bufnr, string.format("/tmp/qnote_%d.md", todo.id))

		-- Assurer que le buffer est sauvegardable
		vim.bo[bufnr].buflisted = true
		vim.bo[bufnr].buftype = "" -- Important pour permettre la sauvegarde
		vim.bo[bufnr].bufhidden = "hide" -- Conserver le buffer sans le supprimer
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
		local text_lines = vim.split(todo.content.Text, "\n", { plain = true })
		vim.list_extend(lines, text_lines)
	elseif todo.content.Checkboxes then
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

	-- Écrit dans le buffer
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

function M.setup_autosave()
	vim.api.nvim_create_autocmd("BufWritePost", {
		pattern = "qnote_*.md",
		callback = function(args)
			local bufnr = args.buf
			local filename = vim.api.nvim_buf_get_name(bufnr)

			-- Extrait l'ID du todo depuis le nom du fichier
			local todo_id = filename:match("qnote_(%d+)%.md")
			if not todo_id then
				print("Erreur : Impossible d'extraire l'ID du todo.")
				return
			end

			-- Récupère le contenu du buffer
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

			-- Analyse le type de contenu
			local content_type, payload = M.parse_todo_content(lines)

			-- Envoie le todo mis à jour
			if content_type and payload then
				M.send_todo_update(todo_id, content_type, payload)
			else
				print("Erreur : Contenu invalide, aucune mise à jour envoyée.")
			end
		end,
	})
end
function M.parse_todo_content(lines)
	-- Vérifie qu'il y a au moins une ligne
	if #lines == 0 then
		return nil, "Erreur : contenu vide"
	end

	-- Récupère le titre de la première ligne (suppose le format "# titre")
	local title = lines[1]:match("^#%s*(.+)")
	if not title then
		return nil, "Erreur : titre introuvable"
	end

	-- Récupère le contenu (sans le titre et les lignes vides en début)
	local content_lines = {}
	for i = 2, #lines do
		if lines[i] ~= "" then
			table.insert(content_lines, lines[i])
		end
	end

	-- Si c'est un simple texte, retourne `Text`
	if not vim.tbl_contains(content_lines, "**TODO:**") then
		return "Text", { title = title, content = table.concat(content_lines, "\n") }
	end

	-- Sinon, on parse les checkboxes
	local todos, dones = {}, {}

	for _, line in ipairs(content_lines) do
		if line:match("%- %[ %] (.+)") then
			table.insert(todos, line:match("%- %[ %] (.+)"))
		elseif line:match("%- %[x%] (.+)") then
			table.insert(dones, line:match("%- %[x%] (.+)"))
		end
	end

	return "Checkboxes", { title = title, todo = todos, done = dones }
end

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
		print("Todo mis à jour avec succès !")
	else
		print("Erreur lors de la mise à jour du todo.")
	end
end

function M.create_todo(content_type)
	local bufnr = vim.api.nvim_create_buf(false, true)
	local filename = "/tmp/qnote_new_" .. string_random(4) .. ".md"

	vim.api.nvim_buf_set_name(bufnr, filename)
	vim.bo[bufnr].buflisted = true
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].buftype = "" -- Important pour permettre la sauvegarde
	vim.bo[bufnr].swapfile = false

	local default_content
	if content_type == "text" then
		default_content = { "# Title", "", "Your content here..." }
	else
		default_content = { "# Title", "", "**TODO:**", "- [ ] Task 1", "", "**DONE:**", "- [x] Completed task" }
	end

	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, default_content)
	vim.api.nvim_set_current_buf(bufnr)

	-- Ajouter un autocmd pour sauvegarder et envoyer
	vim.api.nvim_create_autocmd("BufWritePost", {
		buffer = bufnr,
		callback = function()
			M.send_new_todo(bufnr, content_type)
		end,
	})
end

function M.send_new_todo(bufnr, content_type)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local title = lines[1]:gsub("^#%s*", "") -- Supprime le `#` devant le titre

	-- Parser le contenu
	local content_type, payload = M.parse_todo_content(lines)
	payload.title = title -- Ajouter le titre

	-- Sélectionner la route
	local route = (content_type == "Text") and "/api/post_text" or "/api/post_checkboxes"
	local url = M.config.server_url .. route
	local json_data = vim.fn.json_encode(payload)

	-- Exécuter la requête
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

function M.send_qnote_request(method, endpoint, id)
	local url = string.format("%s/api/%s/%d", M.config.server_url, endpoint, id)
	local cmd = string.format("curl -s -X %s -b %s '%s'", method, M.config.cookie_file, url)

	print(cmd)
	local response = vim.fn.systemlist(cmd)
	print(response)

	if vim.v.shell_error == 0 then
		print(string.format("Todo %d mis à jour avec succès !", id))
	else
		print(string.format("Erreur lors de la requête %s sur le todo %d.", method, id))
	end
end

-- vim.api.nvim_create_user_command("Qnote", function(opts)
-- 	local arg = table.concat(opts.fargs, " ")
-- 	if arg == "show" then
-- 		require("qnote").show_todos()
-- 	elseif arg == "new text" then
-- 		require("qnote").create_todo("text")
-- 	elseif arg == "new todo" then
-- 		require("qnote").create_todo("checkboxes")
-- 	else
-- 		print("Usage: :Qnote show | new text | new checkboxes")
-- 	end
-- end, { nargs = "+" }) -- Accepte plusieurs arguments

M.usage = "Usage: Qnote show | new text | new todo | {archive|delete} {id}"

vim.api.nvim_create_user_command("Qnote", function(opts)
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
end, {
	nargs = "*",
	complete = function(_, line)
		local commands = { "show", "new text", "new todo", "archive", "delete" }
		local words = vim.split(line, "%s+")
		if #words == 2 and (words[2] == "archive" or words[2] == "delete") then
			return { "1", "2", "3" } -- Remplace par la récupération des IDs réels
		end
		return vim.tbl_filter(function(cmd)
			return vim.startswith(cmd, words[#words])
		end, commands)
	end,
})

M.setup_autosave()

return M
