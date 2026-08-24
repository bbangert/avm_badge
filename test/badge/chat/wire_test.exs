defmodule Badge.Chat.WireTest do
  use ExUnit.Case, async: true

  alias Badge.Chat.Wire

  # Every frame below was captured from the running Phoenix server. A websocket
  # frame is the bare five element array, with no envelope and no second layer
  # of json.
  @join_reply ~s(["1","1","chat:lobby","phx_reply",{"status":"ok","response":{}}])

  @broadcast ~s([null,null,"chat:lobby","new_msg",) <>
               ~s({"at":1787410248,"body":"hello","from":"Gus","chip":"90DA7247F828"}])

  describe "decoding a frame" do
    test "answers the message as a map" do
      assert {:ok, message} = Wire.decode_frame(@join_reply)

      assert message == %{
               join_ref: "1",
               ref: "1",
               topic: "chat:lobby",
               event: "phx_reply",
               payload: %{"status" => "ok", "response" => %{}}
             }
    end

    test "a broadcast has no refs, and null becomes nil rather than the atom null" do
      assert {:ok, message} = Wire.decode_frame(@broadcast)

      assert message.join_ref == nil
      assert message.ref == nil
      assert message.event == "new_msg"
      assert message.payload["body"] == "hello"
      assert message.payload["from"] == "Gus"
    end

    test "anything that is not a five element array is not a frame" do
      assert Wire.decode_frame("not json") == :error
      assert Wire.decode_frame("") == :error
      assert Wire.decode_frame("[]") == :error
      assert Wire.decode_frame(~s({"status":200})) == :error
    end

    test "a five element array whose topic is not a string is not a frame" do
      assert Wire.decode_frame(~s([null,null,1,"new_msg",{}])) == :error
    end
  end

  describe "encoding a message to send" do
    test "is the five element array Phoenix expects" do
      encoded = Wire.encode("1", "2", "chat:lobby", "new_msg", %{"body" => "hi"})

      assert encoded == ~s(["1","2","chat:lobby","new_msg",{"body":"hi"}])
    end

    test "a nil ref encodes as null, which is what a heartbeat carries" do
      encoded = Wire.encode(nil, "3", "phoenix", "heartbeat", %{})

      assert encoded == ~s([null,"3","phoenix","heartbeat",{}])
    end

    test "an empty payload encodes as an object, not a list" do
      encoded = Wire.encode("1", "1", "chat:lobby", "phx_join", %{})

      assert encoded == ~s(["1","1","chat:lobby","phx_join",{}])
    end

    test "round trips through the frame decoder" do
      encoded = Wire.encode("1", "3", "chat:lobby", "new_msg", %{"body" => "round trip"})

      assert {:ok, message} = Wire.decode_frame(encoded)
      assert message.ref == "3"
      assert message.payload == %{"body" => "round trip"}
    end
  end
end
