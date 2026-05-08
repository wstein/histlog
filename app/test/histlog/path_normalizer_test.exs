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

  test "path analyzer expands simple brace path copies without shell execution" do
    root =
      Path.join(System.tmp_dir!(), "histlog-brace-path-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf!(root) end)
    File.mkdir_p!(root)
    File.write!(Path.join(root, "histlog.db"), "")

    assert [
             %{
               "arg_position" => 0,
               "path" => original,
               "exists" => true,
               "type" => "f"
             },
             %{
               "arg_position" => 0,
               "path" => backup,
               "exists" => false,
               "type" => "u"
             }
           ] = PathAnalyzer.command_paths("cp histlog.db{,-bak}", root)

    assert original == PathNormalizer.normalize(Path.join(root, "histlog.db"))
    assert backup == PathNormalizer.normalize(Path.join(root, "histlog.db-bak"))
  end

  test "path analyzer skips shell runtime expansions" do
    root = Path.join(System.tmp_dir!(), "histlog-runtime-expansion-#{System.unique_integer()}")
    on_exit(fn -> File.rm_rf!(root) end)
    File.mkdir_p!(root)

    assert [] = PathAnalyzer.command_paths("cat $HOME/.ssh/config", root)
    assert [] = PathAnalyzer.command_paths("cat $(pwd)/mix.exs", root)
    assert [] = PathAnalyzer.command_paths("cat `pwd`/mix.exs", root)
    assert [] = PathAnalyzer.command_paths("echo {alpha,beta}", root)
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
