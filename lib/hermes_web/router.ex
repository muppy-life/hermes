defmodule HermesWeb.Router do
  use HermesWeb, :router

  import HermesWeb.Plugs.Auth, only: [fetch_current_user: 2]

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
    pipe_through :browser

    live_session :authenticated,
      on_mount: [{HermesWeb.Plugs.Auth, :ensure_authenticated}] do
      live "/dashboard", DashboardLive, :index

      live "/backlog", RequestLive.Index, :index
      live "/backlog/new", RequestLive.New, :new
      live "/backlog/:id", RequestLive.Show, :show
      live "/backlog/:id/edit", RequestLive.Edit, :edit

      live "/boards", KanbanLive.Index, :index
      live "/boards/:id", KanbanLive.Board, :show
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

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HermesWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
