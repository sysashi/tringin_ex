defmodule Tringin.Sources.Elixir do
  @moduledoc false

  # 1. func doc
  # 2. func spec (also module types will be handy here)
  # 3. func arity
  # 3. func added_since
  # 4. mod doc

  @behaviour Tringin.Source

  @modules_of_intereset [
    Kernel,
    Kernel.SpecialForms,
    Atom,
    Base,
    Bitwise,
    Calendar,
    Date,
    DateTime,
    Exception,
    Float,
    Integer,
    NaiveDateTime,
    Record,
    Regex,
    String,
    Time,
    Tuple,
    URI,
    Version,
    Access,
    Enum,
    Keyword,
    List,
    Map,
    MapSet,
    Range,
    Stream,
    File,
    IO,
    OptionParser,
    Path,
    Port,
    System,
    Code,
    Macro,
    Module,
    Agent,
    Application,
    DynamicSupervisor,
    GenServer,
    Node,
    Process,
    Registry,
    Supervisor,
    Task
  ]

  @topics [
    :fun_doc,
    :fun_spec,
    :fun_added_since,
    :mod_doc
  ]

  alias __MODULE__.Helper

  @formatted_modules_docs Helper.load_docs(@modules_of_intereset)

  def next_question(_context, _params) do
    question =
      topic(
        Enum.random(@topics),
        Enum.random(@modules_of_intereset)
      )

    answers =
      Tringin.Question.prepare_answers(
        [question.answer | question.incorrect_answers],
        question.answer
      )

    {:ok, Map.put(answers, :text, question.text)}
  end

  defp topic(:mod_doc, mod) do
    {mod_doc, _docs} = @formatted_modules_docs[mod]

    question_text =
      mod_doc
      |> Helper.nth_sentence(1)
      |> String.split()
      |> Enum.map(fn word ->
        if String.starts_with?(word, format_mod(mod)) do
          String.duplicate("_", String.length(word))
        else
          word
        end
      end)
      |> Enum.join(" ")

    %{
      text: question_text,
      answer: format_mod(mod),
      incorrect_answers: @modules_of_intereset |> Enum.take_random(3) |> Enum.map(&format_mod/1)
    }
  end

  defp topic(:fun_doc, mod) do
    take_random_funs_with_docs = fn mod, n ->
      take_random_funs(mod, n, &match?(%{"en" => _}, &1.doc))
    end

    answer_fun = hd(take_random_funs_with_docs.(mod, 1))
    question_text = Helper.nth_sentence(answer_fun.doc["en"], 1)

    # FIXME answer can repeat
    incorrect_answers =
      @modules_of_intereset
      |> Enum.take_random(3)
      |> Enum.map(fn mod ->
        fun = hd(take_random_funs_with_docs.(mod, 1))
        format_fun(mod, fun)
      end)

    %{
      text: String.replace(question_text, "\n", " "),
      answer: format_fun(mod, answer_fun),
      incorrect_answers: incorrect_answers
    }
  end

  # TODO: improve type specs and fetch'n'show `t()` definition
  defp topic(:fun_spec, mod) do
    funs = take_random_funs(mod, 4, & &1.spec)
    fun = Enum.random(funs)

    [_, correct_spec] = String.split(fun.spec, "(", parts: 2)

    %{
      text: "<function name>(" <> correct_spec,
      answer: fun.name,
      incorrect_answers: Enum.map(funs, & &1.name) -- [fun.name]
    }
  end

  defp topic(:fun_added_since, mod) do
    [fun] = take_random_funs(mod, 1, & &1.meta[:since])

    %{major: major, minor: minor} = Version.parse!(fun.meta[:since])

    # 1.6.0 is where @since were introduced iirc
    incorrect_answers =
      for possible_major <- 1..1,
          possible_minor <- 6..10,
          {major, minor} != {possible_major, possible_minor} do
        "#{possible_major}.#{possible_minor}"
      end

    %{
      text: format_fun(mod, fun),
      answer: "#{major}.#{minor}",
      incorrect_answers: Enum.take_random(incorrect_answers, 3)
    }
  end

  defp take_random_funs(mod, n, filter_fun \\ fn _ -> true end) do
    {_mod_doc, docs} = @formatted_modules_docs[mod]

    docs
    |> Enum.filter(&(&1.type == :function && filter_fun.(&1)))
    |> Enum.take_random(n)
  end

  defp format_fun(mod, fun) do
    "#{format_mod(mod)}.#{fun.name}/#{fun.arity}"
  end

  defp format_mod(mod) do
    parts =
      case Module.split(mod) do
        ["Elixir" | rest] -> rest
        parts -> parts
      end

    Enum.join(parts, ".")
  end
end
