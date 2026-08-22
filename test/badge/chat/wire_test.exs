defmodule Badge.Chat.WireTest do
  use ExUnit.Case, async: true

  alias Badge.Chat.Wire

  # Every body below was captured from the running Phoenix server.
  @new_session ~s({"messages":[],"status":410,"token":"SFMyNTY.abc"})

  @join_reply ~s({"status":200,"messages":) <>
                ~s(["[\\"1\\",\\"1\\",\\"chat:lobby\\",\\"phx_reply\\",) <>
                ~s({\\"status\\":\\"ok\\",\\"response\\":{}}]"]})

  @broadcast ~s({"status":200,"messages":) <>
               ~s(["[null,null,\\"chat:lobby\\",\\"new_msg\\",) <>
               ~s({\\"at\\":1787410248,\\"body\\":\\"hello\\",\\"from\\":\\"Gus\\",) <>
               ~s(\\"chip\\":\\"90DA7247F828\\"}]"]})

  @timed_out ~s({"messages":[],"status":204,"token":"SFMyNTY.xyz"})

  describe "the envelope" do
    test "a new session carries a token and no messages" do
      assert {:ok, envelope} = Wire.decode(@new_session)

      assert envelope.status == 410
      assert envelope.token == "SFMyNTY.abc"
      assert envelope.messages == []
    end

    test "a timed out poll is 204 with a fresh token" do
      assert {:ok, %{status: 204, token: "SFMyNTY.xyz", messages: []}} = Wire.decode(@timed_out)
    end

    test "a body with no token still decodes" do
      assert {:ok, %{status: 403, token: nil}} = Wire.decode(~s({"status":403}))
    end

    test "nonsense is not an envelope" do
      assert Wire.decode("not json") == :error
      assert Wire.decode("") == :error
      assert Wire.decode("[]") == :error
    end
  end

  describe "messages inside the envelope" do
    test "are decoded from their own json, not left as strings" do
      assert {:ok, %{messages: [message]}} = Wire.decode(@join_reply)

      assert message.join_ref == "1"
      assert message.ref == "1"
      assert message.topic == "chat:lobby"
      assert message.event == "phx_reply"
      assert message.payload == %{"status" => "ok", "response" => %{}}
    end

    test "a broadcast has no refs, and null becomes nil rather than the atom null" do
      assert {:ok, %{messages: [message]}} = Wire.decode(@broadcast)

      assert message.join_ref == nil
      assert message.ref == nil
      assert message.event == "new_msg"
      assert message.payload["body"] == "hello"
      assert message.payload["from"] == "Gus"
      assert message.payload["chip"] == "90DA7247F828"
    end

    test "a message that will not decode is dropped, not fatal" do
      body = ~s({"status":200,"messages":["not json","[null,null,\\"t\\",\\"e\\",{}]"]})

      assert {:ok, %{messages: [only]}} = Wire.decode(body)
      assert only.event == "e"
    end
  end

  describe "encoding a message to send" do
    test "is the five element array Phoenix expects" do
      encoded = Wire.encode("1", "2", "chat:lobby", "new_msg", %{"body" => "hi"})

      assert is_binary(encoded)
      assert {:ok, [join_ref, ref, topic, event, payload]} = Wire.decode_message(encoded)
      assert join_ref == "1"
      assert ref == "2"
      assert topic == "chat:lobby"
      assert event == "new_msg"
      assert payload == %{"body" => "hi"}
    end

    test "an empty payload encodes as an object, not a list" do
      encoded = Wire.encode("1", "1", "chat:lobby", "phx_join", %{})

      assert :binary.match(encoded, "{}") != :nomatch
    end

    test "round trips through the envelope decoder" do
      encoded = Wire.encode("1", "3", "chat:lobby", "new_msg", %{"body" => "round trip"})
      body = ~s({"status":200,"messages":[) <> quoted(encoded) <> ~s(]})

      assert {:ok, %{messages: [message]}} = Wire.decode(body)
      assert message.payload["body"] == "round trip"
    end

    defp quoted(binary), do: :erlang.iolist_to_binary(:json.encode(binary))
  end

  describe "query strings" do
    test "keeps characters that need no escaping" do
      assert Wire.query([{"vsn", "2.0.0"}, {"chip", "90DA7247F828"}]) ==
               "vsn=2.0.0&chip=90DA7247F828"
    end

    test "escapes the spaces in a real badge name" do
      assert Wire.query([{"name", "Gus Workman"}]) == "name=Gus%20Workman"
    end

    test "escapes everything a profile name might carry" do
      assert Wire.query([{"name", "a&b=c?d/e#f+g"}]) == "name=a%26b%3Dc%3Fd%2Fe%23f%2Bg"
    end

    test "leaves the unreserved set alone" do
      assert Wire.query([{"k", "aZ09-_.~"}]) == "k=aZ09-_.~"
    end

    test "an empty value still produces the key" do
      assert Wire.query([{"name", ""}]) == "name="
    end
  end
end
