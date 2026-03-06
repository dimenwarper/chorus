defmodule ChorusWeb.PageControllerTest do
  use ChorusWeb.ConnCase

  test "GET / renders board LiveView", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "No board configured"
  end
end
