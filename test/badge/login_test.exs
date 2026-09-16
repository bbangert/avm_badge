defmodule Badge.LoginTest do
  use ExUnit.Case, async: true

  alias Badge.Login

  describe "base_url/1" do
    test "falls back to the compiled server when nothing is provisioned" do
      assert Login.base_url(nil) == Login.default_url()
      assert Login.base_url("") == Login.default_url()
    end

    test "keeps a provisioned server" do
      assert Login.base_url("http://10.0.0.5:4000") == "http://10.0.0.5:4000"
    end

    test "the default is the conference site over TLS" do
      assert Login.default_url() == "https://goatmire.com"
    end
  end

  describe "endpoint/1" do
    test "https defaults to 443" do
      assert Login.endpoint("https://goatmire.com") == {:ok, :https, "goatmire.com", 443}
    end

    test "http defaults to 80" do
      assert Login.endpoint("http://goatmire.com") == {:ok, :http, "goatmire.com", 80}
    end

    test "an explicit port is read, which is how a bench server is reached" do
      assert Login.endpoint("http://192.168.1.20:4000") == {:ok, :http, "192.168.1.20", 4000}
    end

    test "a trailing path is dropped, since the paths are this module's" do
      assert Login.endpoint("https://goatmire.com/") == {:ok, :https, "goatmire.com", 443}
      assert Login.endpoint("https://goatmire.com/api") == {:ok, :https, "goatmire.com", 443}
    end

    test "anything else is an error rather than a crash" do
      assert Login.endpoint("goatmire.com") == :error
      assert Login.endpoint("wss://goatmire.com") == :error
      assert Login.endpoint("https://") == :error
      assert Login.endpoint("http://host:port") == :error
    end
  end

  describe "paths and bodies" do
    test "a login starts with the email as JSON" do
      assert Login.start_path() == "/api/badge_login"
      assert Login.start_body("me@example.com") == ~s({"email":"me@example.com"})
    end

    test "a poll carries the token and how long to hold" do
      assert Login.poll_path("abc", 0) == "/api/badge_login/abc"
      assert Login.poll_path("abc", 25) == "/api/badge_login/abc?long=25"
    end
  end

  describe "parse_start/2" do
    test "reads the request token" do
      assert Login.parse_start(200, ~s({"request_token":"tok","message":"Check"})) == {:ok, "tok"}
    end

    test "a 200 without a token is a bad response" do
      assert Login.parse_start(200, ~s({"message":"hi"})) == {:error, :bad_response}
      assert Login.parse_start(200, "not json") == {:error, :bad_response}
      assert Login.parse_start(200, ~s({"request_token":5})) == {:error, :bad_response}
    end

    test "any other status is reported as such" do
      assert Login.parse_start(400, ~s({"error":"x"})) == {:error, {:http, 400}}
      assert Login.parse_start(502, "") == {:error, {:http, 502}}
    end
  end

  describe "parse_poll/2" do
    test "pending is pending" do
      assert Login.parse_poll(200, ~s({"status":"pending"})) == {:ok, :pending}
    end

    test "verified carries the account" do
      body = ~s({"status":"verified","email":"me@example.com","role":"attendee"})

      assert Login.parse_poll(200, body) ==
               {:ok, {:verified, %{email: "me@example.com", role: :attendee}}}
    end

    test "every role the site knows becomes an atom" do
      for {name, role} <- [{"staff", :staff}, {"presenter", :presenter}, {"attendee", :attendee}] do
        body = ~s({"status":"verified","email":"a@b.c","role":"#{name}"})

        assert Login.parse_poll(200, body) == {:ok, {:verified, %{email: "a@b.c", role: role}}}
      end
    end

    test "a role this firmware does not know is an error, not an atom leak" do
      body = ~s({"status":"verified","email":"a@b.c","role":"overlord"})

      assert Login.parse_poll(200, body) == {:error, {:role, "overlord"}}
    end

    test "404 means the server has forgotten the token" do
      assert Login.parse_poll(404, ~s({"status":"unknown"})) == {:error, :unknown_token}
    end

    test "garbage and other statuses are errors" do
      assert Login.parse_poll(200, "{") == {:error, :bad_response}
      assert Login.parse_poll(200, ~s({"status":"verified"})) == {:error, :bad_response}
      assert Login.parse_poll(500, "") == {:error, {:http, 500}}
    end
  end

  describe "roles" do
    test "round-trip through their stored spelling" do
      for role <- [:staff, :presenter, :attendee] do
        assert Login.role(Login.role_name(role)) == role
      end
    end

    test "an unknown name is nil and an unknown atom is spelled out" do
      assert Login.role("nobody") == nil
      assert Login.role_name(:nobody) == "unknown"
    end
  end

  describe "account/2" do
    test "needs both parts and a known role" do
      assert Login.account("a@b.c", "staff") == %{email: "a@b.c", role: :staff}
      assert Login.account(nil, "staff") == nil
      assert Login.account("a@b.c", nil) == nil
      assert Login.account("a@b.c", "overlord") == nil
    end
  end

  describe "describe/1" do
    test "every reason the flow can report fits one panel line" do
      reasons = [
        :no_wifi,
        :timeout,
        :unknown_token,
        :bad_url,
        :bad_response,
        {:http, 503},
        {:role, "x"},
        {:connect, {:ssl, :closed}},
        {:recv, :closed},
        {:down, :killed}
      ]

      for reason <- reasons do
        text = Login.describe(reason)

        assert is_binary(text)
        assert byte_size(text) <= 38
      end
    end
  end

  describe "flow/3" do
    test "a base that is not a URL fails before touching the network" do
      test = self()

      assert Login.flow("goatmire.com", "a@b.c", &send(test, &1)) == :ok
      assert_received {:login, {:failed, :bad_url}}
    end
  end
end
