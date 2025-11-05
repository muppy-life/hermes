#!/bin/bash

# PostgreSQL Docker container management for Hermes
# Uses port 5433 to avoid conflicts with other Phoenix apps

CONTAINER_NAME="hermes_postgres"
POSTGRES_USER="postgres"
POSTGRES_PASSWORD="postgres"
POSTGRES_DB="hermes_dev"
POSTGRES_PORT="5434"
POSTGRES_VERSION="16-alpine"

case "$1" in
  start)
    echo "Starting PostgreSQL container for Hermes..."

    # Check if container already exists
    if [ "$(docker ps -aq -f name=$CONTAINER_NAME)" ]; then
      echo "Container $CONTAINER_NAME already exists."

      # Check if it's running
      if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
        echo "Container is already running on port $POSTGRES_PORT"
      else
        echo "Starting existing container..."
        docker start $CONTAINER_NAME
        echo "PostgreSQL started on port $POSTGRES_PORT"
      fi
    else
      echo "Creating new PostgreSQL container..."
      docker run -d \
        --name $CONTAINER_NAME \
        -e POSTGRES_USER=$POSTGRES_USER \
        -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
        -e POSTGRES_DB=$POSTGRES_DB \
        -p $POSTGRES_PORT:5432 \
        -v hermes_postgres_data:/var/lib/postgresql/data \
        postgres:$POSTGRES_VERSION

      echo "PostgreSQL container created and started on port $POSTGRES_PORT"
      echo "Waiting for PostgreSQL to be ready..."
      sleep 3
    fi

    echo ""
    echo "Connection details:"
    echo "  Host: localhost"
    echo "  Port: $POSTGRES_PORT"
    echo "  User: $POSTGRES_USER"
    echo "  Password: $POSTGRES_PASSWORD"
    echo "  Database: $POSTGRES_DB"
    ;;

  stop)
    echo "Stopping PostgreSQL container..."
    docker stop $CONTAINER_NAME
    echo "PostgreSQL stopped"
    ;;

  restart)
    echo "Restarting PostgreSQL container..."
    docker restart $CONTAINER_NAME
    echo "PostgreSQL restarted on port $POSTGRES_PORT"
    ;;

  rm)
    echo "Removing PostgreSQL container..."
    docker stop $CONTAINER_NAME 2>/dev/null
    docker rm $CONTAINER_NAME
    echo "Container removed (data volume preserved)"
    echo "To remove data volume, run: docker volume rm hermes_postgres_data"
    ;;

  logs)
    echo "Showing PostgreSQL logs (Ctrl+C to exit)..."
    docker logs -f $CONTAINER_NAME
    ;;

  status)
    if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
      echo "PostgreSQL container is RUNNING on port $POSTGRES_PORT"
      docker ps -f name=$CONTAINER_NAME
    elif [ "$(docker ps -aq -f name=$CONTAINER_NAME)" ]; then
      echo "PostgreSQL container EXISTS but is NOT running"
    else
      echo "PostgreSQL container does NOT exist"
    fi
    ;;

  psql)
    echo "Connecting to PostgreSQL..."
    docker exec -it $CONTAINER_NAME psql -U $POSTGRES_USER -d $POSTGRES_DB
    ;;

  clean)
    echo "WARNING: This will remove the container AND all data!"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
      docker stop $CONTAINER_NAME 2>/dev/null
      docker rm $CONTAINER_NAME 2>/dev/null
      docker volume rm hermes_postgres_data 2>/dev/null
      echo "Container and data volume removed"
    else
      echo "Cancelled"
    fi
    ;;

  rebuild)
    echo "🔄 Reconstructing database..."
    echo "This will reset the database, run migrations, and load seed data."
    echo ""

    # Check if container is running
    if [ ! "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
      echo "❌ PostgreSQL container is not running"
      echo "Starting container first..."
      $0 start
      sleep 2
    fi

    echo "🛑 Stopping any running Phoenix servers..."
    pkill -f "mix phx.server" 2>/dev/null || true
    sleep 2

    echo "📦 Resetting database (drop + create + migrate)..."
    mix ecto.reset

    echo ""
    echo "🌱 Loading seed data..."
    mix run priv/repo/seeds.exs

    echo ""
    echo "📊 Loading additional test data..."
    mix run priv/repo/add_test_data.exs

    echo ""
    echo "✅ Database reconstruction complete!"
    echo ""
    echo "You can now start the Phoenix server with: mix phx.server"
    ;;

  *)
    echo "Hermes PostgreSQL Docker Management"
    echo ""
    echo "Usage: ./scripts/db.sh {start|stop|restart|rm|logs|status|psql|clean|rebuild}"
    echo ""
    echo "Commands:"
    echo "  start    - Start PostgreSQL container (creates if doesn't exist)"
    echo "  stop     - Stop PostgreSQL container"
    echo "  restart  - Restart PostgreSQL container"
    echo "  rm       - Remove container (keeps data volume)"
    echo "  logs     - Show container logs"
    echo "  status   - Check container status"
    echo "  psql     - Connect to PostgreSQL using psql"
    echo "  clean    - Remove container AND data volume (WARNING: deletes all data)"
    echo "  rebuild  - Drop database, run migrations, and load seed data"
    echo ""
    echo "Port: $POSTGRES_PORT (custom port to avoid conflicts)"
    exit 1
    ;;
esac
