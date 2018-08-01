defmodule ExCourtbotWeb.Case do
  use Ecto.Schema

  alias ExCourtbot.Repo
  alias ExCourtbotWeb.{Case, Hearing, Subscriber}

  import Ecto.{Changeset, Query}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cases" do
    field(:type, :string)
    field(:case_number, :string)
    field(:first_name, :string)
    field(:last_name, :string)
    field(:county, :string)

    has_many(:hearings, Hearing, on_delete: :delete_all)
    has_many(:subscribers, Subscriber, on_delete: :delete_all)

    timestamps()
  end

  def changeset(changeset, params \\ %{}) do
    changeset
    |> cast(params, [:type, :case_number, :first_name, :last_name, :county])
    |> update_change(:case_number, &clean_case_number/1)
    |> update_change(:county, &clean_county/1)
    |> cast_assoc(:hearings)
    |> validate_required([:case_number])
  end

  def find_by_case_number(case_number) do
    latest_hearing = from(h in Hearing, order_by: [h.date, h.time], limit: 1, where: h.date >= ^Date.utc_today())

    from(
      c in Case,
      where: c.case_number == ^case_number,
      preload: [hearings: ^latest_hearing]
    )
    |> Repo.all()
  end

  def find(id) do
    latest_hearing = from(h in Hearing, order_by: [h.date, h.time], limit: 1, where: h.date >= ^Date.utc_today())
    from(
      c in Case,
      where: c.id == ^id,
      preload: [hearings: ^latest_hearing]
    )
    |> Repo.one()
  end

  def find_with_county(case_number, county) do
    latest_hearing = from(h in Hearing, order_by: [h.date, h.time], limit: 1, where: h.date >= ^Date.utc_today())
    from(
      c in Case,
      where: c.case_number == ^case_number,
      where: c.county == ^county,
      preload: [hearings: ^latest_hearing]
    )
    |> Repo.all()
  end

  def all_counties() do
    from(c in Case, select: c.county) |> Repo.all()
  end

  defp clean_county(county) do
    county
    |> String.trim()
    |> String.downcase()
  end

  defp clean_case_number(case_number) do
    case_number
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "")
    |> String.replace("_", "")
    |> String.replace(",", "")
  end
end
