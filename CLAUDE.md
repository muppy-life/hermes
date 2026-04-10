# Instructions for Claude Code

- Do not commit automatically every request made
- Wait for explicit user instruction before committing changes
- Allow the user to review changes and decide when to commit
- Run `mix format` after making code changes to ensure consistent formatting
- Keep PR descriptions concise and focused on the changes
- Do not include Claude Code signatures in PRs, commit messages, or comments

## Project
Elixir/Phoenix application. Always use the Makefile for running commands.

## Rules
- Always use zsh when running terminal commands
- Never run `mix test` directly, use `make test`
- Never run `iex` directly, use `make shell`
- Never modify the Makefile

## Makefile Commands
- `make db` - Start the database
- `make db-stop` - Stop the database
- `make db-status` - Check database status
- `make server` - Start the Phoenix server
- `make iex` - Start interactive Elixir shell with Phoenix server
- `make test` - Run tests (optionally pass test file/pattern as argument)
- `make consistency` - Format code and run static analysis
- `make shell` - Connect to a running hermes node via remote shell
- `make start` - Start Phoenix server with named node (for distributed Erlang)
- `make start_ia` - Start Phoenix server on a free port with unique node name
