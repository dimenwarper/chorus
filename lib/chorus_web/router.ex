defmodule ChorusWeb.Router do
  use ChorusWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ChorusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :dev_auth do
    plug ChorusWeb.Plugs.DevAuth
  end

  pipeline :require_auth do
    plug ChorusWeb.Plugs.RequireAuth
  end

  pipeline :require_admin do
    plug ChorusWeb.Plugs.RequireAuth, admin: true
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
  end

  # Auth routes (OAuth callbacks)
  scope "/auth", ChorusWeb do
    pipe_through [:browser]

    get "/logout", AuthController, :logout
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  # Public board
  scope "/", ChorusWeb do
    pipe_through [:browser, :dev_auth]

    live "/", BoardLive
    live "/ideas/:identifier", IdeaLive
  end

  # Admin UI (requires admin)
  scope "/admin", ChorusWeb do
    pipe_through [:browser, :dev_auth, :require_admin]

    live "/", AdminLive
  end

  # Webhooks (no session/auth needed)
  scope "/api/webhooks", ChorusWeb do
    pipe_through [:api]

    post "/github", WebhookController, :github
  end

  # Public JSON API
  scope "/api", ChorusWeb.Api do
    pipe_through [:api, :dev_auth]

    get "/ideas", IdeaController, :index
    get "/ideas/:identifier", IdeaController, :show
    post "/ideas", IdeaController, :create
    post "/ideas/:id/upvote", IdeaController, :upvote
    delete "/ideas/:id/upvote", IdeaController, :remove_upvote
  end

  # Admin JSON API (requires admin)
  scope "/api/admin", ChorusWeb.Api do
    pipe_through [:api, :dev_auth, :require_admin]

    get "/review", AdminController, :review_queue
    post "/review/batch", AdminController, :batch_review
    patch "/ideas/:id", AdminController, :update_idea
    get "/settings", AdminController, :board_settings
    patch "/settings", AdminController, :update_board_settings
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:chorus, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ChorusWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
