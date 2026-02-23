defmodule Alem.LocalFirst.LibSQLRepo do
  @moduledoc """
  LibSQL/SQLite repository for local-first storage.
  Handles server-side SQLite for offline queue and local user/document metadata.
  """

  use Ecto.Repo,
    otp_app: :alem,
    adapter: Ecto.Adapters.SQLite3

  @impl true
  def init(_type, config) do
    # Ensure the data directory exists before connecting
    database = Keyword.get(config, :database, "")

    if is_binary(database) and database != "" and database != ":memory" do
      database |> Path.dirname() |> File.mkdir_p!()
    end

    {:ok, config}
  end

  @doc """
  Enable foreign key enforcement after each connection is established.
  Called automatically by Ecto via after_connect if configured,
  but Exqlite 0.34 handles this internally via its :foreign_keys pragma option.
  We use execute/2 on the repo directly instead.
  """
  def enable_foreign_keys do
    query!("PRAGMA foreign_keys = ON")
    :ok
  rescue
    _ -> :ok
  end

  @doc """
  Returns the filesystem path for a user's local SQLite database.
  """
  def local_db_path(user_id) do
    data_dir = Application.get_env(:alem, :local_first_data_dir, "priv/local_data")
    File.mkdir_p!(Path.join(data_dir, "users"))
    Path.join([data_dir, "users", "#{user_id}.db"])
  end
end
