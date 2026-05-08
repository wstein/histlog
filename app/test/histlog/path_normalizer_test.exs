defmodule Histlog.PathNormalizerTest do
  use ExUnit.Case, async: true

  alias Histlog.PathAnalyzer
  alias Histlog.PathNormalizer
  alias Histlog.Database
  alias Histlog.Database.Projection
  alias Histlog.Database.Schema

  test "normalizes the current user's home directory to tilde" do
    home = System.user_home!()

    assert PathNormalizer.normalize(home) == "~"
    assert PathNormalizer.normalize(Path.join(home, "project/file.txt")) == "~/project/file.txt"
    assert PathNormalizer.expand("~/project/file.txt") == Path.join(home, "project/file.txt")
  end

  test "path analyzer returns normalized path facts" do
    home = System.user_home!()
    command = "cat ./project/file.txt"
    cwd = home

    assert [
             %{
               "arg_position" => 0,
               "path" => "~/project/file.txt",
               "exists" => false,
               "type" => "u"
             }
           ] = PathAnalyzer.command_paths(command, cwd)
  end

  test "projection stores home-relative path dimension values" do
    root = Path.join(System.tmp_dir!(), "histlog-path-normalizer-#{System.unique_integer()}")
    on_exit(fn -> File.rm_rf!(root) end)
    File.mkdir_p!(root)

    home_path = Path.join(System.user_home!(), "project")

    assert :ok =
             Database.with_connection(root, fn conn ->
               :ok = Schema.ensure(conn)
               assert {:ok, _path_id} = Projection.upsert_path(conn, home_path)

               assert {:ok, "~/project"} =
                        Database.query_value(conn, "SELECT path AS value FROM paths LIMIT 1")

               :ok
             end)
  end
end
