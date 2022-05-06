defmodule FzHttpWeb.Router do
  @moduledoc """
  Main Application Router
  """

  use FzHttpWeb, :router

  # Limit total requests to 20 per every 10 seconds
  @root_rate_limit [rate_limit: {"root", 10_000, 50}, by: :ip]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {FzHttpWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers

    # XXX: Make this configurable
    plug Hammer.Plug, @root_rate_limit
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_admin_user do
    plug FzHttpWeb.Plug.Authorization, :admin
  end

  pipeline :require_unprivileged_user do
    plug FzHttpWeb.Plug.Authorization, :unprivileged
  end

  pipeline :require_authenticated do
    plug Guardian.Plug.EnsureAuthenticated
  end

  pipeline :require_unauthenticated do
    plug FzHttpWeb.Plug.Authorization, :test
    plug Guardian.Plug.EnsureNotAuthenticated
  end

  pipeline :guardian do
    plug FzHttpWeb.Authentication.Pipeline
  end

  # Ueberauth routes
  scope "/auth", FzHttpWeb do
    pipe_through [
      :browser,
      :guardian,
      :require_unauthenticated
    ]

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    post "/:provider/callback", AuthController, :callback
  end

  # Unauthenticated routes
  scope "/", FzHttpWeb do
    pipe_through [
      :browser,
      :guardian,
      :require_unauthenticated
    ]

    get "/", RootController, :index
  end

  # Authenticated routes
  scope "/", FzHttpWeb do
    pipe_through [
      :browser,
      :guardian,
      :require_authenticated
    ]

    delete "/sign_out", AuthController, :delete
  end

  # Authenticated Unprivileged routes
  scope "/", FzHttpWeb do
    pipe_through [
      :browser,
      :guardian,
      :require_authenticated,
      :require_unprivileged_user
    ]

    # Unprivileged Live routes
    live_session(
      :unprivileged,
      on_mount: {FzHttpWeb.LiveAuth, :unprivileged},
      root_layout: {FzHttpWeb.LayoutView, :unprivileged}
    ) do
      live "/user_devices", DeviceLive.Unprivileged.Index, :index
      live "/user_devices/new", DeviceLive.Unprivileged.Index, :new
      live "/user_devices/:id", DeviceLive.Unprivileged.Show, :show
    end
  end

  # Authenticated Admin routes
  scope "/", FzHttpWeb do
    pipe_through [
      :browser,
      :guardian,
      :require_authenticated,
      :require_admin_user
    ]

    # Admins can delete themselves synchronously
    delete "/user", UserController, :delete

    # Admin Live routes
    live_session(
      :admin,
      on_mount: {FzHttpWeb.LiveAuth, :admin},
      root_layout: {FzHttpWeb.LayoutView, :admin}
    ) do
      live "/users", UserLive.Index, :index
      live "/users/new", UserLive.Index, :new
      live "/users/:id", UserLive.Show, :show
      live "/users/:id/edit", UserLive.Show, :edit
      live "/users/:id/new_device", UserLive.Show, :new_device
      live "/rules", RuleLive.Index, :index
      live "/devices", DeviceLive.Admin.Index, :index
      live "/devices/:id", DeviceLive.Admin.Show, :show
      live "/settings/site", SettingLive.Site, :show
      live "/settings/security", SettingLive.Security, :show
      live "/settings/account", SettingLive.Account, :show
      live "/settings/account/edit", SettingLive.Account, :edit
      live "/diagnostics/connectivity_checks", ConnectivityCheckLive.Index, :index
    end
  end

  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through [:browser]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
