module RailsPulse
  module BacktraceHelper
    APP_FRAME_PATTERN = %r{/app/|/config/|/lib/}
    GEM_FRAME_PATTERN = %r{/gems/|/rubygems/|/bundler/|/ruby/}

    def app_frame?(frame)
      file = frame["file"].to_s
      file.match?(APP_FRAME_PATTERN) && !file.match?(GEM_FRAME_PATTERN)
    end

    # Strip everything before /app/, /lib/, /config/ so paths are relative.
    # Falls back to gem-name/rest for gem frames, or just basename for stdlib.
    def frame_display_path(frame)
      file = frame["file"].to_s
      # Gem frames: /…/gems/[ruby-ver]/gems/[gem-name]/lib/… → gem-name/lib/…
      if (match = file.match(%r{/gems/[^/]+/gems/([^/]+)/(.+)}))
        "#{match[1]}/#{match[2]}"
      # Bundler path gems: /…/gems/[gem-name]/lib/… → gem-name/lib/…
      elsif (match = file.match(%r{/gems/([^/]+)/(.+)}))
        "#{match[1]}/#{match[2]}"
      # App frames: strip absolute prefix, keep /app/…, /lib/…, /config/…
      elsif (match = file.match(%r{(/(?:app|lib|config)/.+)}))
        match[1]
      else
        File.basename(file)
      end
    end

    def frame_dirname(frame)
      File.dirname(frame_display_path(frame)) + "/"
    end

    def frame_basename(frame)
      File.basename(frame_display_path(frame))
    end

    def frame_source_lines(frame, radius: 3)
      file = frame["file"].to_s
      line = frame["line"].to_i
      return nil if file.blank? || line < 1
      return nil unless File.exist?(file) && File.file?(file)

      first_line = [ line - radius, 1 ].max
      last_line  = line + radius

      lines = {}
      File.foreach(file).with_index(1) do |content, lineno|
        break if lineno > last_line
        lines[lineno] = content.rstrip if lineno >= first_line
      end
      lines
    rescue Errno::EACCES, Errno::ENOENT
      nil
    end
  end
end
