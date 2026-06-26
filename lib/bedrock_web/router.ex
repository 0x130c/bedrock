defmodule BedrockWeb.Router do
  use BedrockWeb, :router

  use AshAuthentication.Phoenix.Router
  use AshAuthentication.Phoenix.Oauth2Server.Router
  import Oban.Web.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BedrockWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
    plug :set_actor, :user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  pipeline :mcp do
    plug AshAuthentication.Phoenix.Oauth2Server.BearerPlug,
      oauth2_server: Bedrock.Oauth2Server
  end

  scope "/" do
    pipe_through :browser
    oauth2_server_consent_routes(oauth2_server: Bedrock.Oauth2Server)
  end

  scope "/" do
    pipe_through :api
    oauth2_server_protocol_routes(oauth2_server: Bedrock.Oauth2Server)
  end

  scope "/", BedrockWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes do
      # in each liveview, add one of the following at the top of the module:
      #
      # If an authenticated user must be present:
      # on_mount {BedrockWeb.LiveUserAuth, :live_user_required}
      #
      # If an authenticated user *may* be present:
      # on_mount {BedrockWeb.LiveUserAuth, :live_user_optional}
      #
      # If an authenticated user must *not* be present:
      # on_mount {BedrockWeb.LiveUserAuth, :live_no_user}
    end
  end

  # The Auditor workbench. Scoped to one Organization (tenant) by `:org_id` in the
  # path (ADR-0007: schema-per-tenant); the User↔Organization mapping is a separate
  # concern. Requires an authenticated Auditor.
  scope "/orgs/:org_id", BedrockWeb do
    pipe_through :browser

    ash_authentication_live_session :auditor_workbench,
      on_mount: [{BedrockWeb.LiveUserAuth, :live_user_required}] do
      live "/cases", CaseLive.Index, :index
      live "/cases/:id", CaseLive.Show, :show
    end
  end

  scope "/", BedrockWeb do
    pipe_through :browser

    get "/", PageController, :home
    auth_routes AuthController, Bedrock.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{BedrockWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    BedrockWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  BedrockWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

    # Remove this if you do not use the confirmation strategy
    confirm_route Bedrock.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [BedrockWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(Bedrock.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [BedrockWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]
    )
  end

  scope "/mcp" do
    pipe_through :mcp

    forward "/", AshAi.Mcp.Router,
      tools: [],
      otp_app: :bedrock
  end

  # Other scopes may use custom stacks.
  # scope "/api", BedrockWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:bedrock, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BedrockWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/" do
      pipe_through :browser

      oban_dashboard("/oban")
    end
  end

  if Application.compile_env(:bedrock, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end
