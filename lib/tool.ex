defmodule Tool do
  use Bitwise
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

#  # 获取|设置用户的所在的时区差值(单位/秒)
#  def set_tz_diff(val), do: Process.put(:timezone_diff, val)
#
#  def tz_diff(), do: Process.get(:timezone_diff) || Timex.local().utc_offset


  # 获取访客所在时区与格林时区的差值,单位秒（默认服务器所在的时区）
  def timezone_diff(timezone_diff) do
    cond do
      is_binary(timezone_diff) ->
        String.to_integer(timezone_diff)

      is_nil(timezone_diff) ->
        Timex.local().utc_offset

      true ->
        timezone_diff
    end
  end

  # utc转前端本地时区时间
  def to_local_tz(utc_time, tz_diff_time),
      do: Timex.shift(utc_time, seconds: tz_diff_time)

  # 前端本地时区转utc时间
  def from_local_tz(local_time, tz_diff_time),
      do: Timex.shift(local_time, seconds: -tz_diff_time)

  # utc转前端本地时区时间戳
  def to_local_ux(utc_time, tz_diff_time),
      do: to_local_tz(utc_time, tz_diff_time) |> Timex.to_unix()

  def to_local_date(utc_time, tz_diff_time),
      do: to_local_tz(utc_time, tz_diff_time) |> NaiveDateTime.to_date()

  def to_local_tz_str(time, tz_diff) do
    to_local_tz(time, tz_diff)
    |> to_hyphen_ymdhms_string()
  end

  @doc "将时间转为 2017-01-01 00：00：00 格式"
  def format_time(naive_time) ,do: Timex.format!(naive_time,"{YYYY}-{0M}-{0D} {h24}:{m}:{s}")
  @doc "将时间转为 NaiveDateTime 格式"
  def parse_time(str_time) ,do: Timex.parse!(str_time, "{YYYY}-{0M}-{0D} {h24}:{m}:{s}")

  def to_dot_time_string(naive_time), do: Timex.format!(naive_time, "{YYYY}.{0M}.{0D} {h24}:{m}")
  def string_to_dot_time(str_time), do: Timex.parse!(str_time, "{YYYY}.{0M}.{0D} {h24}:{m}")

  def to_dot_ymdhms_string(naive_time),
      do: Timex.format!(naive_time, "{YYYY}.{0M}.{0D} {h24}:{m}:{s}")

  def to_dot_hm_string(naive_time), do: Timex.format!(naive_time, "{h24}:{m}")

  def to_hyphen_ymdhms_string(naive_time),
      do: Timex.format!(naive_time, "{YYYY}-{0M}-{0D} {h24}:{m}:{s}")

  @doc """
   switch "2017-06-01 18:30:00" or ~N[2017-06-01 18:30:00] to ~N[2017-06-01 18:30:00]
  """
  def hyphen_to_naive(hyphen_time) do
    if is_binary(hyphen_time),
       do: Timex.parse!(hyphen_time, "{YYYY}-{0M}-{D} {h24}:{m}:{s}"),
       else: hyphen_time
  end


  @doc """
  过滤包含指定filter的键值对
  """
  @spec map_filter_by_val(map,charlist) :: map
  def map_filter_by_val(params,filter) do
    Map.new(Enum.filter(params,fn({_k,v}) -> v != filter end))
  end


  @spec map_atomKey_to_stringKey(map) :: map
  def map_atomKey_to_stringKey(params) do
    Map.new(Enum.map(params, fn({k,v}) -> {to_string(k),v} end))
  end

  @spec map_stringKey_to_atomKey(map,atom) :: map | list
  def map_stringKey_to_atomKey(params, type \\ :map) do
    case type do
      :map ->
        Map.new(Enum.map(params, fn({k,v}) -> {String.to_atom(k),v} end))
      _ ->
        Enum.map(params, fn({k,v}) -> {String.to_atom(k),v} end)
    end
  end

  def pmap(f,l) do
    s = self()
    ref = :erlang.make_ref
    for e <- l do
      spawn(fn() -> do_f(s,ref,f,e) end)
    end
    gather(length(l),ref,[])
  end

  def do_f(parent,ref,f,e) do
    send(parent,{ref,apply(f,[e])})
  end

  def gather(0,_,l) do
    l
  end

  def gather(n,ref,l) do
    receive do
      {^ref,[]} -> gather(n-1,ref,l)
      {^ref,ret} ->
        gather(n-1,ref,[ret|l])
    end
  end


  #  F1(Pid, X) -> 发送 {Key,Val} 消息到 Pid
  #  F2(Key, [Val], AccIn) -> AccOut
  def mapreduce(f1,f2,acc0,l) do
    s=self()
    _pid = spawn(fn () -> reduce(s,f1,f2,acc0,l) end)
    receive do
      {_pid,ret} ->
        ret
    end
  end

  def reduce(_parent,f1,f2,acc0,l) do
    Process.flag(:trap_exit,true)
    reduce_pid = self()
    for x <- l do
      spawn_link(fn () -> do_job(reduce_pid,f1,x) end)
    end
    n = length(l)

    #生成一个字典来保存各个Key
    #  等待N个Map进程终止
    dict = collect_replys(n,:dict.new)
    acc = :dict.fold(f2,acc0,dict)
    send(self(),acc)
  end

  #  收集与合并来自N个进程的{Key, Value}消息
  def collect_replys(0,dict) do
    dict
  end

  def collect_replys(n,dict) do
    receive do
      {k,v} ->
        case :dict.is_key(k,dict) do
          true->
            dict1 = :dict.append(k,v,dict)
            collect_replys(n,dict1)
          _fase->
            dict1 = :dict.store(k,[v],dict)
            collect_replys(n,dict1)
        end
      {'EXIT',_,_why}->
        collect_replys(n-1,dict)
    end
  end

  def do_job(reduce_pid,f,x) do
    apply(f,[reduce_pid,x])
  end


  @doc """
  获取今日天开始时间
  """
  @spec get_today_startTime() :: NaiveDateTime.t
  def get_today_startTime, do: Timex.beginning_of_day(NaiveDateTime.utc_now)


  @doc """
  获取现在时间
  """
  @spec get_now_time() :: NaiveDateTime.t
  def get_now_time, do: Timex.to_naive_datetime(Timex.now)

  @doc """
  获取指定长度的随机字符串
  """
  @spec random_string(integer) :: binary
  def random_string(size),do: Regex.replace(~r/\=|\/|\+/ ,:crypto.strong_rand_bytes(size) |> Base.encode64,to_string(Enum.random(0..9))) |> binary_part(0, size)

  @doc """
  获取指定日期的开始时间 eg: date = "2016-9-1"
  """
  @spec beginning_of_day(binary) :: NaiveDateTime.t
  def beginning_of_day(date), do: Timex.parse!(date, "{YYYY}-{0M}-{D}")

  @doc """
  获取指定日期的结束时间 eg: startTime = "2016-9-1"
  """
  @spec end_of_day(binary) :: NaiveDateTime.t
  def end_of_day(date), do: Timex.shift(Timex.parse!(date, "{YYYY}-{0M}-{D}"),days: 1)


  @doc """
  获取当前时间的时位 "2010-1-1"
  """
  @spec string_to_naivedate(binary) :: Date.t
  def string_to_naivedate(date) do
    Timex.parse!(date, "{YYYY}-{0M}-{D}")
  end

  @doc """
  24小时map
  """
  @spec map_24h_period(fun) :: list
  def map_24h_period(f) do
    Enum.map(0..23,f)
  end

  @doc """
  map date [~D[2010-01-01],~D[2010-01-02],~D[2010-01-03]]
  """
  @spec map_date_period(list,fun) :: list
  def map_date_period(datelist,f) do
    Enum.map(datelist,f)
  end


  #秒转时分秒
  def seconds_to_hms(seconds) do
    h = div(seconds,3600)
    res_sec = rem(seconds,3600)
    m = div(res_sec,60)
    res_sec2 = rem(res_sec,60)
    "#{String.pad_leading(to_string(h),2,"0")}:#{String.pad_leading(to_string(m),2,"0")}:#{String.pad_leading(to_string(res_sec2),2,"0")}"
  end

  @doc """
    profiling ...
  """
  def start_prof() do
    :fprof.trace(:start)
  end
  def stop_prof() do
    :fprof.trace(:stop)
    :fprof.profile()
    :fprof.analyse(sort: :own, dest: 'fprof.analysis')
  end


  @doc "Return top n (default 1) ets table sorted by memory occupy."
  def top_memory_ets(n \\ 1) do
    :ets.all()
    |> Enum.map(fn tb -> {tb, :ets.info(tb, :memory)} end)
    |> Enum.sort_by(&(elem(&1, 1)), &>=/2)
    |> :lists.sublist(n)
    |> Enum.map(fn {x, y} -> %{tb: x, memory: y} end)
  end


  @doc """
    md5签名
  """
  def sign_md5(str),do: Base.encode16(:erlang.md5(str), case: :lower)

  @doc """
    ip转int
  """
  def ip_to_int({a,b,c,d}),do: (a*16777216)+(b*65536)+(c*256)+(d)
  def ip_to_int(var),do: String.split(var,".") |> Enum.map(&String.to_integer/1)|> List.to_tuple() |> ip_to_int()

  @doc """
    int转ip
  """
  def int_to_ip(var),do: int_to_ip(var,:string)
  def int_to_ip(var,:tuple),do: {bsr(var,24), bsr(band(var,16711680),16), bsr(band(var,65280),8), band(var,255)}
  def int_to_ip(var,:string),do: int_to_ip(var,:tuple) |> Tuple.to_list() |> Enum.join(".")

  def to_millisecond(dt) do
    DateTime.from_naive!(dt,"Etc/UTC")
    |> DateTime.to_unix(:millisecond)
  end

  @doc """
  Changes String Map to Map of Atoms e.g. %{"c"=> "d", "x" => %{"yy" => "zz"}} to
          %{c: "d", x: %{yy: "zz"}}, i.e changes even the nested maps.
  """

  def  convert_to_atom_map(map), do: to_atom_map(map)

  defp to_atom_map(map) when is_map(map), do: Map.new(map, fn {k,v} -> {String.to_atom(k),to_atom_map(v)} end)
  defp to_atom_map(v), do: v



  @doc """
  Decimal 转 Integer
  """
  def parse_decimal(%Decimal{} = decimal) do
    Decimal.round(decimal)
    |> Decimal.to_integer()
  end

  def parse_decimal(nil), do: 0
  def parse_decimal(integer), do: integer

  def get_rate(val1, val2, decimal \\ 2) do
    val1 =parse_decimal(val1)
    val2 =parse_decimal(val2)

    case val2 != 0 do
      true ->
        Float.floor(val1 / val2, decimal)

      false ->
        0.0
    end
  end


  @doc """
  pack_params(%{pa: 1, pb: "ok", pc: :a}) == "pa=1&pb=ok&pc=a"
  """
  def pack_params(params) do
    Enum.map(params, fn {name, value} -> to_string(name) <> "=" <> to_string(value) end)
    |> Enum.join("&")
  end


  def gen_order_id(n \\ 6) do
    {{y,mon,d},{h,m,s}} = NaiveDateTime.to_erl(Timex.shift(NaiveDateTime.utc_now(), hours: 8))
    stime = fitzero(y, 4) <> fitzero(mon,2) <> fitzero(d, 2) <> fitzero(h, 2) <> fitzero(m, 2) <> fitzero(s, 2)
    stime <> random_int_string(n)
  end

  defp fitzero(i, n) do
    s = to_string(i)
    case n - String.length(s) do
      x when x <= 0 -> s;
      n0 -> String.duplicate("0", n0) <> s
    end
  end
  defp random_int_string(n) do
    1..n |> Enum.map(fn _ -> :rand.uniform(10)-1+?0 end) |> to_string
  end
end
