defmodule Badge.Chat.SocketTest do
  use ExUnit.Case, async: true

  alias Badge.Chat.Socket

  @base "wss://badge-chat.protolux.io"

  describe "the base url" do
    test "falls back to the compiled default when nothing is provisioned" do
      assert Socket.base_url(nil) == "wss://badge-chat.protolux.io"
    end

    test "uses the provisioned value when there is one" do
      assert Socket.base_url("ws://192.168.1.50:4000") == "ws://192.168.1.50:4000"
    end

    test "treats an empty provisioned value as unset" do
      assert Socket.base_url("") == "wss://badge-chat.protolux.io"
    end
  end

  describe "the connect url" do
    test "carries the serializer version and the identity as query params" do
      url = Socket.url(@base, "90DA7247F828", "Gus")

      assert url ==
               @base <> "/badge/socket/websocket" <>
                 "?vsn=2.0.0&chip=90DA7247F828&name=Gus"
    end

    test "builds against a plaintext base just as well" do
      assert Socket.url("ws://192.168.1.50:4000", "90DA7247F828", "Gus") ==
               "ws://192.168.1.50:4000/badge/socket/websocket" <>
                 "?vsn=2.0.0&chip=90DA7247F828&name=Gus"
    end

    test "does not double the separator when the base has a trailing slash" do
      assert Socket.url(@base <> "/", "90DA7247F828", "Gus") ==
               Socket.url(@base, "90DA7247F828", "Gus")
    end

    test "escapes the spaces in a real badge name" do
      assert Socket.url(@base, "90DA7247F828", "Gus Workman") =~ "&name=Gus%20Workman"
    end

    test "escapes everything a profile name might carry" do
      assert Socket.url(@base, "90DA7247F828", "a&b=c?d/e#f+g") =~
               "&name=a%26b%3Dc%3Fd%2Fe%23f%2Bg"
    end

    test "leaves the unreserved set alone" do
      assert Socket.url(@base, "90DA7247F828", "aZ09-_.~") =~ "&name=aZ09-_.~"
    end

    test "a nameless badge still produces the key" do
      assert Socket.url(@base, "90DA7247F828", "") =~ "&name="
    end
  end

  describe "what the driver is asked for" do
    test "a wss base verifies against the public ca bundle" do
      assert Socket.opts(@base, "90DA7247F828", "Gus").verify == :crt_bundle
    end

    test "a ws base runs in the clear" do
      assert Socket.opts("ws://192.168.1.50:4000", "90DA7247F828", "Gus").verify == :none
    end

    test "carries the url it was built from" do
      opts = Socket.opts(@base, "90DA7247F828", "Gus")

      assert opts.url == Socket.url(@base, "90DA7247F828", "Gus")
    end
  end
end
