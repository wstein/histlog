defmodule Histlog.CLI.Options do
  @moduledoc false

  def common_switches do
    [
      root: :string,
      date: :string
    ]
  end

  def common_aliases do
    [
      r: :root,
      d: :date
    ]
  end

  def time_switches do
    [
      time: :string,
      since: :string,
      before: :string,
      today: :boolean,
      yesterday: :boolean,
      week: :boolean
    ]
  end

  def parse(argv, switches, aliases \\ []) do
    case OptionParser.parse(argv, strict: switches, aliases: aliases) do
      {opts, args, []} -> {:ok, opts, args}
      {_opts, _args, invalid} -> {:error, "invalid options #{inspect(invalid)}"}
    end
  end

  def normalize(opts) do
    {:ok,
     Enum.map(opts, fn
       {:date, date} -> {:date, parse_date!(date)}
       option -> option
     end)}
  rescue
    exception in ArgumentError -> {:error, Exception.message(exception)}
  end

  def parse_date!(nil), do: Date.utc_today()

  def parse_date!(date) do
    case Date.from_iso8601(date) do
      {:ok, parsed} -> parsed
      {:error, reason} -> raise ArgumentError, "invalid date #{inspect(date)}: #{reason}"
    end
  end

  def one_optional_arg([]), do: {:ok, nil}
  def one_optional_arg([arg]), do: {:ok, arg}
  def one_optional_arg(args), do: {:error, "unexpected arguments #{inspect(args)}"}
end
