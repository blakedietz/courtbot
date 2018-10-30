defmodule ExCourtbotWeb.TwilioHearingTest do
  use ExCourtbotWeb.ConnCase, async: true

  alias Ecto.Multi

  alias ExCourtbot.{Case, Hearing, Repo}
  alias ExCourtbotWeb.{Response, Twiml}

  @case_id Ecto.UUID.generate()
  @case_two_id Ecto.UUID.generate()

  @hearing_id Ecto.UUID.generate()

  @phone_number "2025550186"
  @case_number "aabbc000000000000"
  @case_two_number "aabbc000000000001"

  @locale "en"

  @time ~T[09:00:00]
  @date Date.utc_today()

  setup do
    Multi.new()
    |> Multi.insert(:case, %Case{
      id: @case_id,
      case_number: @case_number,
      county: "canyon"
    })
    |> Multi.insert(:case_two, %Case{
      id: @case_two_id,
      case_number: @case_two_number,
      county: "canyon"
    })
    |> Multi.insert(:hearing, %Hearing{
      id: @hearing_id,
      case_id: @case_id,
      time: @time,
      date: @date
    })
    |> Repo.transaction()

    :ok
  end

  test "you can inquire about a cases next hearing information", %{conn: conn} do
    initial_conn = post(conn, "/sms", %{"From" => @phone_number, "Body" => @case_number})

    assert initial_conn.status === 200
    assert initial_conn.private[:plug_session] === %{"reminder" => @case_id}

    params = %{
      "From" => @phone_number,
      "Body" => @case_number,
      "locale" => @locale,
      "time" => @time,
      "date" => @date
    }

    message =
      Response.message(:hearing_details, params) <>
        " " <> Response.message(:prompt_reminder, params)

    assert initial_conn.resp_body === Twiml.sms(message)
  end

  test "you can inquire about a case that has no hearing infomation", %{conn: conn} do
    initial_conn = post(conn, "/sms", %{"From" => @phone_number, "Body" => @case_two_number})

    assert initial_conn.status === 200
    assert initial_conn.private[:plug_session] === %{"reminder" => @case_two_id}

    params = %{"From" => @phone_number, "Body" => @case_number, "locale" => @locale}
    message = Response.message(:no_hearings, params)

    assert initial_conn.resp_body === Twiml.sms(message)
  end
end
