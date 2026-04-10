.PHONY: db db-stop db-status server iex test consistency shell start start_ia help

help:
	@echo "Available commands:"
	@echo "  db          - Start the database"
	@echo "  db-stop     - Stop the database"
	@echo "  db-status   - Check database status"
	@echo "  server      - Start the Phoenix server"
	@echo "  iex         - Start interactive Elixir shell with Phoenix server"
	@echo "  test        - Run tests (optionally pass test file/pattern as argument)"
	@echo "  consistency - Format code and run static analysis"
	@echo "  shell       - Connect to a running hermes node via remote shell"
	@echo "  start       - Start Phoenix server with named node (for distributed Erlang)"
	@echo "  start_ia    - Start Phoenix server on a free port with unique node name"

db:
	./scripts/db.sh start

db-stop:
	./scripts/db.sh stop

db-status:
	./scripts/db.sh status

server:
	mix phx.server

iex:
	iex -S mix phx.server

test:
	@echo "Running tests..."
	mix test $(filter-out $@,$(MAKECMDGOALS))

consistency:
	@echo "Formatting code and running static analysis..."
	mix format && mix credo --strict

shell:
	@echo "Starting interactive Elixir shell..."
	iex --remsh hermes

start:
	@echo "Setting up development environment..."
	elixir --cookie hermes_cookie --sname hermes -S mix phx.server

start_ia:
	@echo "Setting up development environment on a free port..."
	@cd assets && npm install && cd .. && \
	PORT=$$(python3 -c "import socket; s = socket.socket(); s.bind(('', 0)); print(s.getsockname()[1])") && \
	NODENAME="hermes_ia_$$(date +%s)" && \
	echo "Using port $$PORT with node $$NODENAME" && \
	PORT=$$PORT elixir --sname $$NODENAME -S mix phx.server
