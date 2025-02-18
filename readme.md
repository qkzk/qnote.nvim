# qnote.nvim - A Neovim client for Qnote

qnote.nvim is a Neovim plugin that allows seamless interaction with the Qnote
server for managing todos and notes. It provides commands to list, create,
archive, and delete todos directly from Neovim.

## Repository:

- Qnote server: https://github.com/qkzk/qnote
- Neovim plugin: https://github.com/qkzk/qnote.nvim


## Usage

```vim 
Qnote show | new text | new todo | {archive|delete} {id}
```

Commands:
- `:Qnote show` → Open a Telescope picker to browse todos.
- `:Qnote new text` → Create a new text-based todo.
- `:Qnote new todo` → Create a new checklist-based todo.
- `:Qnote archive {id}` → Toggle archived state of a todo by its ID.
- `:Qnote delete {id}` → Delete a todo by its ID.


## Configuration

Add the following to your Neovim configuration (`lazy.nvim` example):

```lua
return {
  -- Client for Qnote
  'qkzk/qnote.nvim',
  config = function()
    require('qnote').setup {
      creds_file = '/home/user/creds.txt',
      cookie_file = '/tmp/qnote_cookies.txt',
      server_url = 'https://yourqnoteserver:port',
    }
  end,
}
```

### Configuration options:

- `creds_file` → Path to the credentials file. Login & password, one per line.

    ```
    mysuperlogin
    mysuperpassword
    ```
- `cookie_file` → Path to the session cookie storage.
- `server_url` → Base URL of the Qnote server.


## Dependencies

- Neovim 0.8+
- curl (for API requests)
- Telescope.nvim (for the note picker)


## Contributing

Issues and pull requests are welcome!
Visit https://github.com/qkzk/qnote.nvim for contributions and feature requests.


## TODO 

- [ ] better error messages
- [ ] autoformat 
