# frozen_string_literal: true

require "json"
require "fileutils"
require "minitest/reporters"
require_relative "rails_pulse_console"

# One live row per test process:
#
#   [..]  main suite            ━━━━━━━━━━━━━━━━━━━━━──────────  2417/3409  12 workers  21.3s
#
# Failures print above the row as they happen, with a rerun command. Under
# Rails' process parallelization the workers ship every result back to this
# process, so a single reporter here sees all of them in real time.
#
# When RAILS_PULSE_TEST_PHASE is set the Rakefile owns the heading and footer and
# reads this process's totals from tmp/pulse_test_results/<phase>.json.
# Otherwise (plain `bin/rails test ...`) the reporter prints its own.
class RailsPulseTestReporter < Minitest::Reporters::BaseReporter
  LABEL_WIDTH = 21
  COUNT_WIDTH = 11 # "99999/99999", fixed so rows from separate processes line up
  FRAMES = [ "[. ]", "[..]", "[ .]", "[  ]" ].freeze
  TICK = 0.1

  def initialize(label: ENV.fetch("RAILS_PULSE_TEST_LABEL", "tests"), phase: ENV["RAILS_PULSE_TEST_PHASE"])
    super()
    @label = label
    @phase = phase
    @mutex = Mutex.new
    @failed = []
    @frame = 0
    @total = 0
    @workers = 1
    @fancy = RailsPulseConsole.fancy?(io)

    print_heading unless @phase
    print_boot_row if @fancy
  end

  # Hooks from Minitest::Reporters; the forked workers call these too, so keep them inert.
  def before_test(_test); end
  def after_test(_test); end

  def start
    super
    @total = options[:total_count] || count_runnables
    @workers = worker_count
    @started_at = clock
    if @fancy
      redraw
      start_ticker
    else
      io.puts row_plain("[..]", "#{RailsPulseConsole.plural(@total, 'test')} · #{workers_label}")
    end
  end

  def record(result)
    @mutex.synchronize do
      super
      if !result.passed? && !result.skipped?
        @failed << result
        print_failure(result)
      end
      redraw
    end
  end

  def report
    super
    stop_ticker
    @mutex.synchronize do
      if @fancy
        io.print "\r\e[2K#{row_live(final: true)}\n"
      else
        io.puts row_plain(passed? ? "[ok]" : "[!!]", "#{count}/#{@total} · #{RailsPulseConsole.duration(total_time)}")
      end
      io.flush
    end
    write_results
    print_footer unless @phase
  end

  private

  def clock
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # ---- Layout -----------------------------------------------------------

  def status_cell(final: false)
    if final
      passed? ? paint("[ok]", :green) : paint("[!!]", :red)
    elsif @failed.any?
      paint("[!!]", :red)
    else
      paint(FRAMES[@frame % FRAMES.size], :yellow)
    end
  end

  def row_live(final: false)
    elapsed = final ? total_time : clock - (@started_at || clock)
    done = count
    counts = format("%#{COUNT_WIDTH}s", "#{done}/#{@total}")
    workers = format("%10s", workers_label)
    time = format("%7s", RailsPulseConsole.duration(elapsed))
    label = @label.ljust(LABEL_WIDTH)

    fixed = 2 + 4 + 2 + LABEL_WIDTH + 1 + 2 + counts.length + 2 + workers.length + 2 + time.length
    bar_width = [ RailsPulseConsole.width(io) - fixed, 10 ].max

    "  #{status_cell(final: final)}  #{label} #{bar(bar_width, done)}  #{paint(counts, RailsPulseConsole::BOLD)}  #{dim(workers)}  #{dim(time)}"
  end

  def row_plain(status, detail)
    "  #{status}  #{@label.ljust(LABEL_WIDTH)} #{detail}"
  end

  def bar(width, done)
    filled = @total.zero? ? width : [ (done * width) / @total, width ].min
    colour = @failed.any? ? :red : :yellow
    paint("━" * filled, colour) + paint("─" * (width - filled), RailsPulseConsole::DIM)
  end

  def workers_label
    @workers > 1 ? "#{@workers} workers" : "1 worker"
  end

  def paint(text, *styles)
    RailsPulseConsole.paint(text, *styles, io: io)
  end

  def dim(text)
    RailsPulseConsole.dim(text, io: io)
  end

  # ---- Output -----------------------------------------------------------

  def print_heading
    meta = [ ENV["DB"] || "sqlite3", "rails #{Rails.version}", "ruby #{RUBY_VERSION}" ].join(" · ")
    io.puts
    io.puts RailsPulseConsole.rule("RAILS PULSE", dim(meta), io: io)
    io.puts
  end

  def print_footer
    left, colour = passed? ? [ "PASS", :green ] : [ "FAIL", :red ]
    parts = [ RailsPulseConsole.plural(count, "test"), RailsPulseConsole.plural(assertions, "assertion") ]
    parts << paint(RailsPulseConsole.plural(failures, "failure"), :red) if failures > 0
    parts << paint(RailsPulseConsole.plural(errors, "error"), :red) if errors > 0
    parts << dim("#{skips} skipped") if skips > 0
    parts << RailsPulseConsole.duration(total_time)
    io.puts
    io.puts RailsPulseConsole.rule(left, parts.join(dim(" · ")), color: colour, io: io)
    io.puts
  end

  def print_boot_row
    io.print "  #{paint(FRAMES[0], :yellow)}  #{@label.ljust(LABEL_WIDTH)} #{dim('loading tests')}"
    io.flush
  end

  def print_failure(result)
    io.print "\r\e[2K" if @fancy
    kind = result.error? ? "ERROR" : "FAIL"
    io.puts "  #{paint('[!!]', :red)}  #{paint(kind, RailsPulseConsole::BOLD, :red)}  #{result.klass}##{result.name}"
    io.puts "        #{dim(rerun_command(result))}"
    message_lines(result).each { |line| io.puts "        #{line}" }
    io.puts
  end

  # Minitest's error messages already carry a filtered backtrace; dim those frames.
  def message_lines(result)
    lines = result.failure.message.to_s.lines.map(&:rstrip).reject(&:empty?)
    lines = lines.first(14) + [ "…" ] if lines.length > 14
    lines.map { |line| line.match?(/:\d+:in [`']/) ? dim(line.strip) : line }
  end

  def rerun_command(result)
    file, line = result.source_location
    return "bin/rails test -n #{result.name}" unless file

    path = file.sub("#{Dir.pwd}/", "")
    "bin/rails test #{path}:#{line}"
  end

  # ---- Live redraw ------------------------------------------------------

  def redraw
    return unless @fancy

    io.print "\r\e[2K#{row_live}"
    io.flush
  end

  def start_ticker
    @ticker = Thread.new do
      loop do
        sleep TICK
        @mutex.synchronize do
          @frame += 1
          redraw
        end
      end
    end
  end

  def stop_ticker
    @ticker&.kill
    @ticker = nil
  end

  # ---- Environment ------------------------------------------------------

  def count_runnables
    Minitest::Runnable.runnables.sum { |r| r.runnable_methods.size }
  end

  def worker_count
    executor = Minitest.parallel_executor
    return 1 unless executor.is_a?(ActiveSupport::Testing::ParallelizeExecutor)
    return 1 unless executor.send(:parallelized?)

    executor.send(:parallel_executor).size
  end

  def write_results
    return unless @phase

    FileUtils.mkdir_p(RailsPulseConsole::RESULTS_DIR)
    File.write(File.join(RailsPulseConsole::RESULTS_DIR, "#{@phase}.json"), JSON.generate(
      label: @label, runs: count, assertions: assertions, failures: failures,
      errors: errors, skips: skips, time: total_time, passed: passed?
    ))
  end
end

# The reporter's row already says how many workers are running; silence Rails'
# "Running N tests in parallel using M processes" line.
module ActiveSupport
  module Testing
    class ParallelizeExecutor
      private

      def show_execution_info; end
    end
  end
end
