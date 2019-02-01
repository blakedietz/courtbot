defmodule CourtbotWeb.TwilioController do
  use CourtbotWeb, :controller

  require Logger

  alias Courtbot.{Case, Hearing, Repo, Subscriber}
  alias CourtbotWeb.{Response, Twiml}

  @debug_phase "beepboop"

  @accept_keywords [
    gettext("y"),
    gettext("ye"),
    gettext("yes"),
    gettext("sure"),
    gettext("ok"),
    gettext("plz"),
    gettext("please")
  ]

  @reject_keywords [
    gettext("n"),
    gettext("no"),
    gettext("dont"),
    gettext("stop")
  ]

  # These are defined by Twilio. See https://support.twilio.com/hc/en-us/articles/223134027-Twilio-support-for-opt-out-keywords-SMS-STOP-filtering- for more detail.
  @unsubscribe_keywords [
    gettext("stop"),
    gettext("stopall"),
    gettext("cancel"),
    gettext("end"),
    gettext("quit"),
    gettext("unsubscribe")
  ]

  @county gettext("county")

  @request_defaults %{locale: "en"}

  #  def sms(conn, params = %{"From" => phone_number, "Body" => body}), do: sms(conn, Map.merge(params, %{"Formatted_From" => phone_number, "Formatted_Body" => body}))

  def sms(conn, _ = %{"From" => phone_number, "Body" => @debug_phase}) do
    [%Case{id: case_id}] = Case.find_by_case_number(@debug_phase)

    response =
      if Subscriber.already_subscribed?(case_id, phone_number) do
        "Boop."
      else
        %Subscriber{}
        |> Subscriber.changeset(%{case_id: case_id, phone_number: phone_number, locale: "en"})
        |> Repo.insert()

        "Beep."
      end

    conn
    |> encode(response)
  end

  def sms(conn, params = %{"From" => phone_number, "Body" => body}) do
    %Plug.Conn{private: %{plug_session: session}} = conn

    # Filter and perform some slight sanitization on our session
    session =
      session
      |> Map.take(["requires_county", "reminder", "delete"])
      |> Enum.map(fn {k, v} ->
        value =
          v
          |> String.trim()
          |> String.downcase()

        key = String.to_atom(k)
        {key, value}
      end)
      |> Enum.into(%{})

    # Preprocess our SMS message to make it a bit friendlier to use.
    message =
      body
      |> String.trim()
      |> String.downcase()

    # Add our defaults, SMS details, and sanitized message.
    request =
      Enum.reduce([@request_defaults, session, %{from: phone_number, body: body, message: message}], &Map.merge/2)

    cond do
      # If the user wants to unsubscribe handle that up front.
      Enum.member?(@unsubscribe_keywords, message) ->
        Logger.info(log_safe_phone_number(phone_number) <> ": user is unsubscribing")

        subscriptions = Repo.all(Subscriber.find_by_number(phone_number))

        # User shouldn't receive this message as Twilio would have blocked the response but try and send it anyway.
        response =
          if Enum.empty?(subscriptions) do
            Logger.info(log_safe_phone_number(phone_number) <> ": user had no subscriptions")

            Response.message(:no_subscriptions, request)
          else
            Logger.info(log_safe_phone_number(phone_number) <> ": deleting all subscriptions")

            Repo.delete_all(Subscriber.find_by_number(phone_number))
            Response.message(:unsubscribe, request)
          end

        conn
        |> configure_session(drop: true)
        |> encode(response)

      message == "start" ->
        Logger.info(log_safe_phone_number(phone_number) <> ": user has 'unblocked' us")

        # Inform the user we blew away all their subscriptions due to being blocked
        response = Response.message(:resubscribe, request)

        conn
        |> configure_session(drop: true)
        |> encode(response)

      true ->
        # Begin the response state machine
        respond(conn, request)
    end
  end

  # If they want to delete a subscription to a specific case
  defp respond(
         conn,
         %{
           from: phone_number,
           message: message,
           delete: case_id
         }
       ) do
    cond do
      message === "delete" ->
        Logger.info(
          log_safe_phone_number(phone_number) <> ": user is unsubscribing to a specific case"
        )

        # Delete the subscription
        Repo.delete!(Subscriber.find_by_number_and_case(case_id, phone_number))

        conn
        |> configure_session(drop: true)
        |> put_status(:ok)

      Enum.member?(@reject_keywords, message) ->
        Logger.info(log_safe_phone_number(phone_number) <> ": user does not want to unsubscribe")
        # User does not want us to delete the subscription
        conn
        |> configure_session(drop: true)
        |> put_status(:ok)
    end
  end

  # If we've previously asked them for a county.
  defp respond(
         conn,
         params = %{
           from: phone_number,
           message: message,
           requires_county: case_number
         }
       ) do
    message =
      message
      |> String.replace(@county, "")
      |> String.trim()

    if Enum.member?(Case.all_counties(), message) do
      params =
        params
        |> Map.merge(%{county: message, case_number: case_number})
        |> Map.delete(:requires_county)

      conn
      |> delete_session(:requires_county)
      |> respond(params)
    else
      Logger.info(log_safe_phone_number(phone_number) <> ": No county data for #{case_number}")

      params =
        params
        |> Map.merge(%{case_number: case_number})
        |> Map.delete(:requires_county)

      response = Response.message([:not_found, :help], params)

      conn
      |> configure_session(drop: true)
      |> encode(response)
    end
  end

  # If we've asked them if they would like a reminder
  defp respond(
         conn,
         params = %{
           from: phone_number,
           body: body,
           message: message,
           locale: locale,
           reminder: case_id
         }
       ) do
    cond do
      Enum.member?(@accept_keywords, message) ->
        Logger.info(
          log_safe_phone_number(phone_number) <> ": user is subscribing to case: " <> case_id
        )

        %Subscriber{}
        |> Subscriber.changeset(%{case_id: case_id, phone_number: phone_number, locale: locale})
        |> Repo.insert()

        response = Response.message(:accept_reminder, params)

        conn
        |> configure_session(drop: true)
        |> encode(response)

      Enum.member?(@reject_keywords, message) ->
        Logger.info(log_safe_phone_number(phone_number) <> ": user rejected reminder offer")

        response = Response.message(:reject_reminder, params)

        conn
        |> configure_session(drop: true)
        |> encode(response)

      true ->
        Logger.info(
          log_safe_phone_number(phone_number) <>
            ": user has responded with an unknown reply: " <> body
        )

        response = Response.message(:yes_or_no, params)

        conn
        |> encode(response)
    end
  end

  # Lets lookup the case based upon the context we're given.
  defp respond(conn, params = %{from: phone_number, message: message}) do
    case_number = clean_case_number(message)

    # We may have several entries points, being a case number or a couple of rounds of back and forth with the user.
    result =
      case params do
        %{county: county, case_number: case_number} ->
          Case.find_with_county(case_number, county)

        %{message: _} ->
          Case.find_by_case_number(case_number)
      end

    case result do
      [%Case{id: case_id}] ->
        if Subscriber.already_subscribed?(case_id, phone_number) do
          response = Response.message(:already_subscribed, params)

          conn
          |> put_session(:delete, case_id)
          |> encode(response)
        else
          respond(conn, params, result)
        end

      _ ->
        respond(conn, params, result)
    end
  end

  defp respond(conn, params, [case = %Case{hearings: []}]),
    do: prompt_no_hearings(conn, params, case)

  defp respond(conn, params, [case = %Case{hearings: _}]), do: prompt_remind(conn, params, case)
  defp respond(conn, params, [_ | _]), do: prompt_county(conn, params)
  defp respond(conn, params, _), do: prompt_not_found(conn, params)

  defp prompt_no_hearings(conn, params = %{from: phone_number}, case) do
    Logger.info(
      log_safe_phone_number(phone_number) <>
        ": No hearings found for case number: #{case.case_number}"
    )

    response = Response.message(:no_hearings, params)

    conn
    |> put_session(:reminder, case.id)
    |> encode(response)
  end

  defp prompt_not_found(conn, params = %{from: phone_number, message: message}) do
    Logger.info(log_safe_phone_number(phone_number) <> ": No case found for input: #{message}")

    response = Response.message(:help, params)

    conn
    |> configure_session(drop: true)
    |> encode(response)
  end

  defp prompt_remind(conn, params = %{from: phone_number}, case) do
    Logger.info(
      log_safe_phone_number(phone_number) <>
        ": asking user if they want a reminder about case: " <> case.id
    )

    response =
      Response.message([:hearing_details, :prompt_reminder], Map.merge(params, %{case: case}))

    conn
    |> put_session(:reminder, case.id)
    |> encode(response)
  end

  defp prompt_county(conn, params = %{from: phone_number, message: case_number}) do
    Logger.info(
      log_safe_phone_number(phone_number) <>
        ": asking user about which county they are interested in"
    )

    response = Response.message(:requires_county, params)

    conn
    |> put_session(:requires_county, case_number)
    |> encode(response)
  end

  defp clean_case_number(case_number) do
    case_number
    |> String.trim()
    |> String.replace("-", "")
    |> String.replace("_", "")
    |> String.replace(",", "")
  end

  defp log_safe_phone_number(phone_number) do
    String.slice(phone_number, -4..-1)
  end

  defp encode(conn, response) do
    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, Twiml.sms(response))
  end
end
