defmodule BedrockWeb.PageController do
  use BedrockWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
