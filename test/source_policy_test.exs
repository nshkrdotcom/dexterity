defmodule Dexterity.SourcePolicyTest do
  use ExUnit.Case, async: true

  @text_extensions MapSet.new([
                     ".ex",
                     ".exs",
                     ".md",
                     ".sh",
                     ".py",
                     ".json",
                     ".lock",
                     ".svg"
                   ])
  @text_basenames MapSet.new([
                    ".credo.exs",
                    ".formatter.exs",
                    ".gitignore",
                    ".tool-versions",
                    "CHANGELOG.md",
                    "LICENSE",
                    "README.md",
                    "mix.exs",
                    "mix.lock"
                  ])

  test "tracked text sources avoid dynamic atom and pattern-engine tokens" do
    hits =
      tracked_text_files()
      |> Enum.flat_map(fn path ->
        body = File.read!(path)

        token_hits =
          forbidden_tokens()
          |> Enum.filter(&String.contains?(body, &1))
          |> Enum.map(&{path, &1})

        token_hits ++ dynamic_quoted_atom_hits(path, body)
      end)

    assert hits == []
  end

  defp tracked_text_files do
    {output, 0} = System.cmd("git", ["ls-files"])

    output
    |> String.split("\n", trim: true)
    |> Enum.filter(fn path ->
      text_file?(path) and valid_text?(path)
    end)
  end

  defp text_file?(path) do
    MapSet.member?(@text_extensions, Path.extname(path)) or
      MapSet.member?(@text_basenames, Path.basename(path))
  end

  defp valid_text?(path) do
    case File.read(path) do
      {:ok, body} -> String.valid?(body)
      _ -> false
    end
  end

  defp forbidden_tokens do
    [
      "String.to_" <> "atom",
      "String.to_" <> "existing_atom",
      "binary_to_" <> "atom",
      "binary_to_" <> "existing_atom",
      "list_to_" <> "atom",
      "list_to_" <> "existing_atom",
      "Module." <> "concat",
      ":" <> "#" <> "{",
      "Re" <> "gex",
      "re" <> "gex",
      "~" <> "r",
      ":" <> "re.",
      "String." <> "match",
      "Reg" <> "Exp",
      "reg" <> "exp",
      "re." <> "compile",
      "re." <> "search",
      "re." <> "match",
      "re." <> "fullmatch",
      "re." <> "sub",
      "re." <> "split",
      "re." <> "findall",
      "re." <> "finditer",
      "from " <> "re" <> " import",
      "import " <> "re"
    ]
  end

  defp dynamic_quoted_atom_hits(path, body) do
    atom_prefix = <<58, 34>>
    interpolation = "#" <> "{"

    body
    |> String.split(atom_prefix)
    |> Enum.drop(1)
    |> Enum.filter(fn suffix ->
      suffix
      |> String.split("\"", parts: 2)
      |> List.first()
      |> String.contains?(interpolation)
    end)
    |> Enum.map(fn _suffix -> {path, "dynamic quoted atom interpolation"} end)
  end
end
