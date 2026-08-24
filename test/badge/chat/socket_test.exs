defmodule Badge.Chat.SocketTest do
  use ExUnit.Case, async: true

  alias Badge.Chat.Socket

  describe "the connect url" do
    test "carries the serializer version and the identity as query params" do
      url = Socket.url("90DA7247F828", "Gus")

      assert url ==
               "wss://" <> Socket.host() <> "/badge/socket/websocket" <>
                 "?vsn=2.0.0&chip=90DA7247F828&name=Gus"
    end

    test "escapes the spaces in a real badge name" do
      assert Socket.url("90DA7247F828", "Gus Workman") =~ "&name=Gus%20Workman"
    end

    test "escapes everything a profile name might carry" do
      assert Socket.url("90DA7247F828", "a&b=c?d/e#f+g") =~ "&name=a%26b%3Dc%3Fd%2Fe%23f%2Bg"
    end

    test "leaves the unreserved set alone" do
      assert Socket.url("90DA7247F828", "aZ09-_.~") =~ "&name=aZ09-_.~"
    end

    test "a nameless badge still produces the key" do
      assert Socket.url("90DA7247F828", "") =~ "&name="
    end
  end
end
