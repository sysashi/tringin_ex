defmodule Tringin.Sources.Elixir.Helper do
  @moduledoc false

  def load_docs(modules) do
    for mod <- modules, reduce: %{} do
      modules_with_docs ->
        case get_docs(mod) do
          {:ok, mod_doc, docs} ->
            Map.put(modules_with_docs, mod, {mod_doc, docs})

          other ->
            IO.warn("could not get docs for mod #{mod}, reason: #{inspect(other)}")
            modules_with_docs
        end
    end
  end

  def get_docs(module) do
    with {:docs_v1, _, :elixir, _, %{"en" => module_doc}, _, docs} <- Code.fetch_docs(module),
         {:ok, specs} <- get_formatted_specs(module) do
      formatted_docs =
        for {{type, name, arity}, _anno, sig, doc, meta} <- docs do
          %{
            type: type,
            name: name,
            arity: arity,
            signature: sig,
            doc: doc,
            meta: meta,
            spec: specs[{name, arity}]
          }
        end

      {:ok, module_doc, formatted_docs}
    end
  end

  def get_formatted_specs(module) do
    with {:ok, specs} <- Code.Typespec.fetch_specs(module) do
      specs =
        for {{name, _} = id, [first_spec | _]} <- specs, into: %{} do
          {id, Code.Typespec.spec_to_quoted(name, first_spec) |> Macro.to_string()}
        end

      {:ok, specs}
    end
  end

  def get_types(module) do
    with {:ok, types} <- Code.Typespec.fetch_types(module) do
      types =
        for {type, {name, _, _} = data} <- types, type == :type do
          {name, Code.Typespec.type_to_quoted(data) |> Macro.to_string()}
        end

      {:ok, types}
    end
  end

  def nth_sentence(string, n \\ 1) when is_binary(string) and n > 0 do
    with sentences <- String.split(string, ".", parts: n + 2) do
      Enum.at(sentences, n - 1)
    end
  end
end
