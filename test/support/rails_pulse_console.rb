# frozen_string_literal: true

# Terminal styling shared by the Rakefile and the Minitest reporter.
#
# Draws the heavy-rule headings and footers used by `rake test`:
#
#   ━━ RAILS PULSE ━━━━━━━━━━━━━━━━━━━━ sqlite3 · rails 8.1.3.1 · seed 19335 ━━
#
# Everything degrades to plain ASCII when stdout is not a TTY, NO_COLOR is set,
# or TERM is dumb, so CI logs stay readable.
module RailsPulseConsole
  RESULTS_DIR = File.expand_path("../../tmp/pulse_test_results", __dir__)

  BOLD  = "\e[1m"
  DIM   = "\e[2m"
  RESET = "\e[0m"

  # Brand yellow (RailsPulse::ChartColors::P95), with an 8-color fallback.
  TRUECOLOR = {
    yellow: "\e[38;2;234;179;8m",
    green: "\e[38;2;34;197;94m",
    red: "\e[38;2;239;68;68m",
    gray: "\e[38;2;107;114;128m"
  }.freeze

  BASIC = {
    yellow: "\e[33m",
    green: "\e[32m",
    red: "\e[31m",
    gray: "\e[90m"
  }.freeze

  module_function

  def tty?(io = $stdout)
    io.respond_to?(:tty?) && io.tty?
  end

  # Colour and box-drawing characters go together: a terminal that has one has the other.
  def fancy?(io = $stdout)
    return false if ENV["NO_COLOR"] || ENV["TERM"] == "dumb"

    tty?(io)
  end

  def truecolor?
    ENV["COLORTERM"].to_s.match?(/truecolor|24bit/i)
  end

  def code(name)
    (truecolor? ? TRUECOLOR : BASIC).fetch(name)
  end

  def paint(text, *styles, io: $stdout)
    return text.to_s unless fancy?(io)

    prefix = styles.map { |s| s.is_a?(Symbol) ? code(s) : s }.join
    "#{prefix}#{text}#{RESET}"
  end

  def bold(text, io: $stdout)
    paint(text, BOLD, io: io)
  end

  def dim(text, io: $stdout)
    paint(text, DIM, io: io)
  end

  def width(io = $stdout)
    cols = begin
      io.winsize[1]
    rescue StandardError
      nil
    end
    cols = ENV["COLUMNS"].to_i if cols.nil? || cols <= 0
    cols = 80 if cols <= 0
    cols.clamp(60, 120)
  end

  def visible_length(str)
    str.to_s.gsub(/\e\[[0-9;]*m/, "").length
  end

  def heavy(io = $stdout)
    fancy?(io) ? "━" : "="
  end

  def light(io = $stdout)
    fancy?(io) ? "─" : "-"
  end

  # "  ━━ LEFT ━━━━━━━━━━━━━━━━━━━ right ━━"
  def rule(left, right = nil, color: :yellow, io: $stdout)
    h = heavy(io)
    head = "#{paint(h * 2, color, io: io)} #{paint(left, BOLD, color, io: io)} "
    tail = right ? " #{right} #{paint(h * 2, color, io: io)}" : paint(h * 2, color, io: io)
    fill = width(io) - 2 - visible_length(head) - visible_length(tail)
    fill = 4 if fill < 4
    "  #{head}#{paint(h * fill, color, io: io)}#{tail}"
  end

  def number(n)
    n.to_s.gsub(/\B(?=(\d{3})+(?!\d))/, ",")
  end

  def duration(seconds)
    seconds = seconds.to_f
    return format("%.1fs", seconds) if seconds < 60

    minutes, rest = seconds.divmod(60)
    format("%dm %02ds", minutes, rest)
  end

  def plural(n, word)
    "#{number(n)} #{word}#{n == 1 ? '' : 's'}"
  end

  TAGS = {
    ok: [ :green, "[ok]" ],
    fail: [ :red, "[!!]" ],
    warn: [ :yellow, "[ !]" ],
    info: [ :yellow, "[..]" ]
  }.freeze

  def tag(kind, io: $stdout)
    color, text = TAGS.fetch(kind)
    paint(text, color, io: io)
  end

  # "  [ok]  synced schema"
  def line(kind, text, io: $stdout)
    "  #{tag(kind, io: io)}  #{text}"
  end

  # "[ 3/14]"
  def counter(current, total)
    format("[%#{total.to_s.length}d/%d]", current, total)
  end
end
