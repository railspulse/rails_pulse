require "securerandom"
require "socket"

module RailsPulse
  # In-memory aggregates of the requests and SQL operations that detail
  # capture folds instead of persisting: one bucket per route per hour and one
  # per query per hour, holding counts, status counts, exact duration sums,
  # min, max and a DurationHistogram. Tracker drains the dirty buckets about
  # once a minute into rails_pulse_rollups. Decision 0022.
  #
  # Rows are written by replace-upsert under this incarnation's writer_id, so
  # a bucket's row must only ever be overwritten with a larger total from the
  # same live bucket. Whenever buckets are discarded — a stale hour, the key
  # cap, a fork — the accumulator takes a fresh writer_id, so later counts
  # accumulate under a new row instead of overwriting the finished one.
  #
  # A drain whose write fails is handed back via retain_failed and retried by
  # the next drain, so no fold is lost to a transient database error: a
  # retained row either carries a retired writer_id (final, safe to write any
  # time) or is superseded by the fresher row the same bucket drains next.
  class RollupAccumulator
    FLUSH_INTERVAL = 60                 # seconds between drains
    STALE_HOUR_GRACE = 10 * 60          # keep a bucket this long past its hour, for backfill of stragglers
    MAX_KEYS = 5_000                    # buckets held before rotating, bounding memory
    MAX_RETAINED_ROWS = 5_000           # failed-flush rows kept for retry, bounding memory while the database is down

    ROUTE_TYPE = "RailsPulse::Route"
    QUERY_TYPE = "RailsPulse::Query"

    Bucket = Struct.new(
      :count, :error_count,
      :status_2xx, :status_3xx, :status_4xx, :status_5xx,
      :sum_duration, :sum_square_duration, :min_duration, :max_duration,
      :histogram
    )

    def initialize
      @mutex = Mutex.new
      @host = Socket.gethostname
      reset_state
    end

    def fold_route(route_id:, occurred_at:, duration:, status:)
      fold(ROUTE_TYPE, route_id, occurred_at, duration, status)
    end

    def fold_query(query_id:, occurred_at:, duration:)
      fold(QUERY_TYPE, query_id, occurred_at, duration, nil)
    end

    def flush_due?
      @mutex.synchronize do
        ensure_current_process
        (@dirty.any? || @failed_rows.any?) && monotonic_now - @last_flush_at >= FLUSH_INTERVAL
      end
    end

    # Rows for every bucket touched since the last drain, carrying cumulative
    # totals, plus any rows retained from a failed write. Also the only place
    # buckets retire: after the rows are built, a stale hour or a full table
    # clears everything under a fresh writer_id. The rows built here outlive
    # that rotation — a write that fails is handed back via retain_failed and
    # the rows ride along with the next drain.
    def drain_rows(now: Time.current)
      @mutex.synchronize do
        ensure_current_process
        @last_flush_at = monotonic_now
        rows = @dirty.map { |key| row_for(key, now) }
        @dirty.clear
        rotate! if rotation_due?(now)
        merge_failed_rows(rows)
      end
    end

    # Rows from a drain whose write failed, kept to be retried by the next
    # drain. Bounded: past MAX_RETAINED_ROWS the oldest are dropped, so only
    # an outage that outlasts the cap loses counts — the same trade the
    # writer queue makes.
    def retain_failed(rows)
      @mutex.synchronize do
        if @pid == Process.pid
          @failed_rows = rows.last(MAX_RETAINED_ROWS)
        else
          # A forked child never retries the parent's rows; the parent still
          # owns them.
          reset_state
        end
      end
    end

    def writer_id
      @mutex.synchronize { @writer_id }
    end

    def bucket_count
      @mutex.synchronize { @buckets.size }
    end

    private

    def fold(type, id, occurred_at, duration, status)
      duration = duration.to_f
      hour_epoch = Summary.normalize_period_start("hour", occurred_at).to_i

      @mutex.synchronize do
        ensure_current_process
        key = [ type, id.to_i, hour_epoch ]
        bucket = (@buckets[key] ||= empty_bucket)

        bucket.count += 1
        apply_status(bucket, status) if status
        bucket.sum_duration += duration
        bucket.sum_square_duration += duration * duration
        bucket.min_duration = duration if bucket.min_duration.nil? || duration < bucket.min_duration
        bucket.max_duration = duration if bucket.max_duration.nil? || duration > bucket.max_duration
        bucket.histogram.record(duration)

        @dirty << key
      end
    end

    def apply_status(bucket, status)
      status = status.to_i
      bucket.error_count += 1 if status >= 500
      case status
      when 200..299 then bucket.status_2xx += 1
      when 300..399 then bucket.status_3xx += 1
      when 400..499 then bucket.status_4xx += 1
      when 500..599 then bucket.status_5xx += 1
      end
    end

    def row_for(key, now)
      type, id, hour_epoch = key
      bucket = @buckets.fetch(key)
      {
        rollupable_type: type,
        rollupable_id: id,
        period_start: Time.zone.at(hour_epoch),
        writer_id: @writer_id,
        count: bucket.count,
        error_count: bucket.error_count,
        status_2xx: bucket.status_2xx,
        status_3xx: bucket.status_3xx,
        status_4xx: bucket.status_4xx,
        status_5xx: bucket.status_5xx,
        sum_duration: bucket.sum_duration,
        sum_square_duration: bucket.sum_square_duration,
        min_duration: bucket.min_duration,
        max_duration: bucket.max_duration,
        histogram: bucket.histogram.dump,
        created_at: now,
        updated_at: now
      }
    end

    # A retained row is retried unless this drain carries a fresher row for
    # the same bucket (the bucket folded again, so its cumulative totals
    # supersede the failed snapshot). A rotated-away bucket's retained row
    # carries a retired writer_id no fresh row can share, so it always
    # survives to be retried.
    def merge_failed_rows(fresh_rows)
      return fresh_rows if @failed_rows.empty?

      fresh_keys = fresh_rows.map { |row| row_key(row) }.to_set
      retries = @failed_rows.reject { |row| fresh_keys.include?(row_key(row)) }
      @failed_rows = []
      retries + fresh_rows
    end

    def row_key(row)
      [ row[:rollupable_type], row[:rollupable_id], row[:period_start].to_i, row[:writer_id] ]
    end

    def rotation_due?(now)
      return true if @buckets.size > MAX_KEYS

      stale_before = now.to_i - 3600 - STALE_HOUR_GRACE
      @buckets.each_key.any? { |_, _, hour_epoch| hour_epoch < stale_before }
    end

    def rotate!
      @buckets.clear
      @dirty.clear
      @writer_id = new_writer_id
    end

    # A forked child inherits the parent's buckets, but the parent still owns
    # their rows; start clean under a new writer_id.
    def ensure_current_process
      return if @pid == Process.pid

      reset_state
    end

    def reset_state
      @pid = Process.pid
      @buckets = {}
      @dirty = Set.new
      @failed_rows = []
      @writer_id = new_writer_id
      @last_flush_at = monotonic_now
    end

    def new_writer_id
      "#{@host}:#{Process.pid}:#{SecureRandom.uuid}"
    end

    def empty_bucket
      Bucket.new(0, 0, 0, 0, 0, 0, 0.0, 0.0, nil, nil, DurationHistogram.new)
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
