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

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
  end

  # Public board
  scope "/", ChorusWeb do
    pipe_through [:browser, :dev_auth]

    live "/", BoardLive
    live "/ideas/:identifier", IdeaLive
  end

  # Admin UI
  scope "/admin", ChorusWeb do
    pipe_through [:browser, :dev_auth]

    live "/", AdminLive
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

  # Admin JSON API
  scope "/api/admin", ChorusWeb.Api do
    pipe_through [:api, :dev_auth]

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
