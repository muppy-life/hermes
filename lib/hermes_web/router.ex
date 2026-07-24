defmodule HermesWeb.Router do
  use HermesWeb, :router

  import HermesWeb.Plugs.Auth, only: [fetch_current_user: 2, require_authenticated_user: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HermesWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug HermesWeb.Plugs.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Token-authenticated API/MCP surface. ApiAuth resolves the token owner and
  # restricts access to the tech team.
  pipeline :api_authenticated do
    plug :accepts, ["json"]
    plug HermesWeb.Plugs.ApiAuth
  end

  pipeline :authenticated do
    plug :require_authenticated_user
  end

  # Health check endpoint for ALB/deployment checks
  scope "/health", HermesWeb do
    pipe_through :api
    get "/", HealthController, :index
  end

  # GitHub webhook (HMAC-verified, no auth)
  scope "/api/github", HermesWeb do
    pipe_through [:api, HermesWeb.Plugs.VerifyGitHubSignature]
    post "/webhook", GitHubWebhookController, :create
  end

  # Token-authenticated REST API (tech-ops tasks).
  scope "/api/v1", HermesWeb.Api do
    pipe_through :api_authenticated

    get "/me", MeController, :show
    resources "/tech_ops_tasks", TechOpsTaskController, only: [:index, :show, :create, :update]
    resources "/requests", RequestController, only: [:index, :show]
  end

  # MCP endpoint (JSON-RPC 2.0 over HTTP) for Claude and other MCP clients.
  scope "/mcp", HermesWeb.Api do
    pipe_through :api_authenticated

    post "/", MCPController, :handle
  end

  # Public routes
  scope "/", HermesWeb do
    pipe_through :browser

    live_session :public,
      on_mount: [{HermesWeb.Plugs.Auth, :mount_current_user}] do
      live "/", AuthLive.Login, :login
    end

    post "/login", AuthController, :create
    delete "/logout", AuthController, :delete
  end

  # Protected routes - require authentication
  scope "/", HermesWeb do
    pipe_through [:browser, :authenticated]

    live_session :authenticated,
      on_mount: [{HermesWeb.Plugs.Auth, :ensure_authenticated}] do
      live "/dashboard", DashboardLive, :index

      live "/metrics", MetricsLive, :index

      live "/objectives", ObjectivesLive, :index

      live "/backlog", RequestLive.Index, :index
      live "/backlog/:id", RequestLive.Show, :show
      live "/backlog/:id/edit", RequestLive.Edit, :edit

      live "/boards", KanbanLive.Index, :index
      live "/boards/:id", KanbanLive.Board, :show
      live "/boards/:id/metrics", KanbanLive.Metrics, :index

      live "/notifications", NotificationLive.Index, :index
    end

    # Tech ops routes - require tech team (dev_team or admin) access. Separate
    # live_session because the on_mount hook differs.
    live_session :tech_team,
      on_mount: [{HermesWeb.Plugs.Auth, :ensure_tech_team}] do
      live "/tech-ops", TechOpsLive.Index, :index
    end

    # Admin routes - require admin access. Separate live_session because the
    # on_mount hook differs; live navigation to/from admin does a full reload.
    live_session :admin,
      on_mount: [{HermesWeb.Plugs.Auth, :ensure_admin}] do
      live "/admin", Admin.DashboardLive.Index, :index
      live "/admin/users", Admin.UserLive.Index, :index
      live "/admin/teams", Admin.TeamLive.Index, :index
      live "/admin/github", Admin.GithubLive.Index, :index
      live "/admin/api-tokens", Admin.ApiTokenLive.Index, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", HermesWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:hermes, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev", HermesWeb do
      pipe_through :browser

      live "/github", DevLive.GithubInbox, :index
    end

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HermesWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
