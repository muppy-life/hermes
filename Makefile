.PHONY: db db-stop db-status server iex

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
