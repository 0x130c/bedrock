defmodule BedrockWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use BedrockWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint BedrockWeb.Endpoint

      use BedrockWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import BedrockWeb.ConnCase
    end
  end

  setup tags do
    Bedrock.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Registers an Auditor (`User`) and stores them in the connection's session, so
  LiveViews mounted under `:live_user_required` see a `current_user`.

  Returns `%{conn: conn, user: user}` for use as a `setup` callback.
  """
  def register_and_sign_in_user(%{conn: conn}) do
    user = register_user()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)

    %{conn: conn, user: user}
  end

  @doc "Registers an Auditor (`User`) via the password strategy, returning the record."
  def register_user(attrs \\ %{}) do
    email = attrs[:email] || "auditor#{System.unique_integer([:positive])}@acme.test"

    Bedrock.Accounts.User
    |> Ash.Changeset.for_create(
      :register_with_password,
      %{email: email, password: "password1234", password_confirmation: "password1234"},
      authorize?: false
    )
    |> Ash.create!()
  end
end
