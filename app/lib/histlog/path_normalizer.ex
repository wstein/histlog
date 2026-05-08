defmodule Histlog.PathNormalizer do
  @moduledoc """
  Normalizes user-facing filesystem paths.

  Histlog stores and displays paths relative to the current user's home as `~`
  so local history is portable and does not repeat the full home directory.
  """

  def normalize(nil), do: nil
  def normalize(""), do: ""

  def normalize(path) when is_binary(path) do
    home = home()

    cond do
      home in [nil, ""] ->
        path

      path == home ->
        "~"

      String.starts_with?(path, home <> "/") ->
        "~" <> String.replace_prefix(path, home, "")

      true ->
        path
    end
  end

  def expand("~"), do: home() || Path.expand("~")
  def expand("~/" <> rest), do: Path.join(home() || Path.expand("~"), rest)
  def expand(path) when is_binary(path), do: Path.expand(path)

  defp home do
    System.user_home!()
  rescue
    _exception -> nil
  end
end
