defmodule Mix.Tasks.Courtbot.Import do
  @moduledoc false
  use Mix.Task

  @shortdoc "Run the Courtbot import"
  def run(_) do
    Mix.Task.run("app.start", [])

    Courtbot.Import.run()
  end
end
