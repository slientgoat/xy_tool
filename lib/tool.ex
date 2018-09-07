defmodule Tool do
  @moduledoc """
  常用工具函数
  """

  @doc """
  utc转北京时间

  ## Examples

      iex> Tool.to_beijing(~N[2018-09-07 02:41:10.389091])
      "2018-09-07 10:41:10"

  """
  def to_beijing(time) do
    to_utc_offset(time, 28800)
  end

  def to_utc_offset(time, tz_diff) do
    Timex.shift(time, seconds: tz_diff)
    |> Timex.format!("{YYYY}-{0M}-{0D} {h24}:{0m}:{0s}")
  end
end
