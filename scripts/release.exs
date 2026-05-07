#!/usr/bin/env elixir

defmodule Histlog.ReleaseWizard do
  @moduledoc false

  @semver ~r/^\d+\.\d+\.\d+(?:[-+].+)?$/

  def main(argv \\ System.argv(), env \\ System.get_env()) do
    print_header("Release Wizard")

    cwd = File.cwd!()
    state = release_state(cwd)

    assert_preconditions!(state)

    print_step(1, 4, "Inspect repository state")

    IO.puts("""
    Current version: #{bold(state.current_version)}
    Branch: #{bold(state.branch)}
    Worktree: #{bold("clean")}
    """)

    print_tip(version_tip(state))

    requested_version =
      env["VERSION"]
      |> fallback(List.first(argv))
      |> normalize_version_input()

    action = choose_action(state, requested_version)
    version = choose_version(state, requested_version, action)

    assert_version_available!(cwd, state, version, action)

    if confirm_plan(action, version) do
      run_release_action(cwd, action, version)
    else
      warn("Release wizard cancelled.")
    end
  rescue
    exception ->
      error(Exception.message(exception))
      System.halt(1)
  end

  defp release_state(cwd) do
    current_version = read_mix_version!(Path.join(cwd, "app/mix.exs"))
    tag_name = "v#{current_version}"

    %{
      current_version: current_version,
      suggested_version: suggest_release_version(current_version),
      branch: git!(cwd, ["branch", "--show-current"], capture: true),
      worktree_clean?: git!(cwd, ["status", "--short"], capture: true) |> String.trim() == "",
      current_version_tag_exists?:
        git!(cwd, ["tag", "--list", tag_name], capture: true) |> String.trim() == tag_name,
      head_tags:
        git!(cwd, ["tag", "--points-at", "HEAD"], capture: true)
        |> String.split("\n", trim: true)
        |> Enum.map(&String.trim/1)
    }
  end

  defp assert_preconditions!(state) do
    if state.branch != "develop" do
      raise """
      Release wizard must run on develop.
      Current branch: #{if state.branch == "", do: "(detached HEAD)", else: state.branch}
      """
    end

    unless state.worktree_clean? do
      raise """
      Release wizard requires a clean worktree so the candidate and tag map to a single audited state.
      """
    end
  end

  defp choose_action(state, requested_version) do
    explicit_action =
      infer_explicit_release_action(
        current_version: state.current_version,
        requested_version: requested_version
      )

    if explicit_action do
      explicit_action
    else
      print_step(2, 4, "Choose release phase")

      print_tip("""
      Use the first pass to prepare the candidate on develop.
      After CI is green, rerun make release VERSION=v#{state.current_version} to finalize the tag.
      """)

      choices =
        [
          {"1", "start", "Start release candidate from #{state.current_version}"}
        ] ++
          if !state.current_version_tag_exists? and
               !development_version?(state.current_version) do
            [{"2", "finalize", "Finalize current candidate as v#{state.current_version}"}]
          else
            []
          end

      Enum.each(choices, fn {key, _value, label} ->
        IO.puts("  #{key}) #{label}")
      end)

      selected =
        prompt("? Release phase", "1")
        |> String.trim()

      case Enum.find(choices, fn {key, _value, _label} -> key == selected end) do
        {_key, value, _label} -> value
        nil -> raise "Invalid release phase selection: #{inspect(selected)}"
      end
    end
  end

  defp choose_version(_state, requested_version, "start") when requested_version != "" do
    requested_version
  end

  defp choose_version(state, _requested_version, "start") do
    print_step(3, 4, "Choose candidate version")

    prompt("? Release version", state.suggested_version)
    |> normalize_version_input()
  end

  defp choose_version(state, _requested_version, "finalize") do
    state.current_version
  end

  defp confirm_plan(action, version) do
    print_step(4, 4, "Confirm plan")

    case action do
      "start" ->
        IO.puts("""
        Start release candidate #{bold("v#{version}")} on #{bold("develop")}:
          - update version files
          - commit the candidate
          - push develop
        """)

      "finalize" ->
        IO.puts("""
        Finalize release #{bold("v#{version}")}:
          - create annotated tag on current certified commit
          - push only the tag
        """)
    end

    prompt("? Continue?", "Y")
    |> String.downcase()
    |> then(&(&1 in ["y", "yes", ""]))
  end

  defp run_release_action(cwd, action, version) do
    normalized_version = normalize_version_input(version)
    tag_name = "v#{normalized_version}"

    case action do
      "start" ->
        update_release_version_files!(cwd, normalized_version)

        version_files = version_files(cwd)
        git!(cwd, ["add" | version_files])
        git!(cwd, ["commit", "-m", "chore(release): start #{tag_name}"])
        git!(cwd, ["push", "origin", "develop"])

        complete("Release candidate #{tag_name} started")

        IO.puts("""
        Next:
          let CI go green on develop, then rerun:

            make release VERSION=#{tag_name}

          to create and push the release tag.
        """)

      "finalize" ->
        git!(cwd, ["tag", "-a", tag_name, "-m", "Release #{tag_name}"])
        git!(cwd, ["push", "origin", tag_name])

        complete("Release tag #{tag_name} pushed")

        IO.puts("""
        Next:
          watch the release workflow publish the certified build inputs.
        """)
    end
  end

  defp assert_version_available!(cwd, state, version, action) do
    normalized_version = normalize_version_input(version)

    unless semver?(normalized_version) do
      raise "Invalid version: #{inspect(version)}"
    end

    if action == "finalize" and development_version?(normalized_version) do
      raise """
      Version #{normalized_version} is a development baseline.
      Start a release candidate before finalizing a tag.
      """
    end

    if action == "start" and normalized_version == state.current_version do
      raise """
      Version #{normalized_version} is already set in app/mix.exs.
      Rerun the wizard with the same version to finalize the tag, or choose a new version.
      """
    end

    if action == "start" do
      tag_name = "v#{normalized_version}"

      if git!(cwd, ["tag", "--list", tag_name], capture: true) == tag_name do
        raise "Tag #{tag_name} already exists. Start a different version."
      end
    end

    if action == "finalize" and state.current_version_tag_exists? do
      raise """
      Tag v#{normalized_version} already exists.
      The current candidate has already been finalized.
      """
    end
  end

  defp update_release_version_files!(cwd, version) do
    mix_path = Path.join(cwd, "app/mix.exs")
    mix_contents = File.read!(mix_path)

    version_pattern = ~r/version:\s*"[^"]+"/

    unless Regex.match?(version_pattern, mix_contents) do
      raise "app/mix.exs must declare a project version."
    end

    updated_mix =
      Regex.replace(version_pattern, mix_contents, ~s(version: "#{version}"), global: false)

    File.write!(mix_path, updated_mix)

    antora_path = Path.join(cwd, "docs/antora.yml")

    if File.exists?(antora_path) do
      antora_contents = File.read!(antora_path)
      antora_version = antora_version_from_release_version(version)

      antora_pattern = ~r/^version:\s*['"]?[^'"\n]+['"]?\s*$/m

      unless Regex.match?(antora_pattern, antora_contents) do
        raise "docs/antora.yml must declare an Antora version."
      end

      updated_antora =
        Regex.replace(
          antora_pattern,
          antora_contents,
          ~s(version: "#{antora_version}"),
          global: false
        )

      File.write!(antora_path, updated_antora)
    end
  end

  defp version_files(cwd) do
    ["app/mix.exs"]
    |> maybe_add(File.exists?(Path.join(cwd, "docs/antora.yml")), "docs/antora.yml")
  end

  defp maybe_add(files, true, file), do: files ++ [file]
  defp maybe_add(files, false, _file), do: files

  defp read_mix_version!(path) do
    contents = File.read!(path)

    case Regex.run(~r/version:\s*"([^"]+)"/, contents) do
      [_full, version] -> version
      _ -> raise "Could not read version from #{path}"
    end
  end

  defp infer_explicit_release_action(current_version: current, requested_version: requested) do
    requested = normalize_version_input(requested)

    cond do
      requested == "" -> nil
      requested == normalize_version_input(current) -> "finalize"
      true -> "start"
    end
  end

  defp suggest_release_version(current_version) do
    normalized = normalize_version_input(current_version)

    cond do
      !semver?(normalized) ->
        normalized

      development_version?(normalized) ->
        Regex.replace(~r/-dev(?:[.+-].*)?$/i, normalized, "")

      true ->
        Regex.replace(~r/(\d+)$/, normalized, fn patch ->
          patch
          |> String.to_integer()
          |> Kernel.+(1)
          |> Integer.to_string()
        end)
    end
  end

  defp antora_version_from_release_version(version) do
    normalized = normalize_version_input(version)

    case Regex.run(~r/^(\d+\.\d+)\.\d+(?:[-+].+)?$/, normalized) do
      [_full, antora_version] -> antora_version
      _ -> normalized
    end
  end

  defp semver?(version), do: Regex.match?(@semver, normalize_version_input(version))

  defp development_version?(version) do
    version
    |> normalize_version_input()
    |> then(&Regex.match?(~r/-dev(?:[.+-].*)?$/i, &1))
  end

  defp normalize_version_input(version) when is_binary(version) do
    version
    |> String.trim()
    |> String.replace(~r/^v/i, "")
  end

  defp normalize_version_input(_), do: ""

  defp fallback(nil, fallback), do: fallback
  defp fallback("", fallback), do: fallback
  defp fallback(value, _fallback), do: value

  defp git!(cwd, args, opts \\ []) do
    capture? = Keyword.get(opts, :capture, false)

    {output, status} = System.cmd("git", args, cd: cwd, stderr_to_stdout: true)

    if status != 0 do
      raise String.trim(output)
    end

    if capture? do
      String.trim(output)
    else
      IO.write(output)
      ""
    end
  end

  defp prompt(message, default) do
    suffix =
      case default do
        "" -> ""
        nil -> ""
        value -> " [#{value}]"
      end

    IO.write(cyan("#{message}#{suffix}: "))

    case IO.gets("") do
      nil ->
        default || ""

      value ->
        value = String.trim(value)
        if value == "", do: default || "", else: value
    end
  end

  defp print_header(title) do
    IO.puts("")
    IO.puts(cyan(String.duplicate("=", 50)))
    IO.puts(cyan("  #{title}"))
    IO.puts(cyan(String.duplicate("=", 50)))
    IO.puts("")
  end

  defp print_step(current, total, title) do
    IO.puts("#{cyan("[#{current}/#{total}]")} #{bold(title)}")
  end

  defp print_tip(message) do
    IO.puts(gray(String.trim_trailing(message)))
    IO.puts("")
  end

  defp version_tip(state) do
    cond do
      development_version?(state.current_version) ->
        """
        Current version v#{state.current_version} is a develop baseline.
        Start a release candidate like v#{state.suggested_version}.
        """

      state.current_version_tag_exists? ->
        """
        Tag v#{state.current_version} already exists.
        Start a newer candidate.
        """

      true ->
        """
        Current version v#{state.current_version} is untagged.
        It can be finalized if CI already certified this commit.
        """
    end
  end

  defp complete(message), do: IO.puts("\n#{green("* #{message}")}\n")
  defp warn(message), do: IO.puts(yellow(message))
  defp error(message), do: IO.puts(:stderr, red(message))

  defp bold(text), do: IO.ANSI.bright() <> to_string(text) <> IO.ANSI.reset()
  defp cyan(text), do: IO.ANSI.cyan() <> to_string(text) <> IO.ANSI.reset()
  defp green(text), do: IO.ANSI.green() <> to_string(text) <> IO.ANSI.reset()
  defp yellow(text), do: IO.ANSI.yellow() <> to_string(text) <> IO.ANSI.reset()
  defp red(text), do: IO.ANSI.red() <> to_string(text) <> IO.ANSI.reset()
  defp gray(text), do: IO.ANSI.light_black() <> to_string(text) <> IO.ANSI.reset()
end

Histlog.ReleaseWizard.main()
