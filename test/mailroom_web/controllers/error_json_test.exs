defmodule MailroomWeb.ErrorJSONTest do
  use MailroomWeb.ConnCase, async: true

  test "renders 404" do
    assert MailroomWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert MailroomWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
