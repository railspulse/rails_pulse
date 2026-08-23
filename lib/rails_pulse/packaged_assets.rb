# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module RailsPulse
  # Copies gem-built dashboard files into the host's public/assets with a
  # content digest, then records them in a small manifest. This is hooked to
  # assets:precompile so CDNs (asset_sync, CloudFront on /assets) and
  # CDN-only CSP policies see the same URLs as the rest of the host app —
  # without running the host js_compressor over the already-minified bundle.
  class PackagedAssets
    LOGICAL_NAMES = %w[
      rails-pulse.css
      rails-pulse.js
      rails-pulse-icons.js
      rails-pulse-logo.png
      search.svg
    ].freeze

    MANIFEST_FILENAME = ".rails-pulse-manifest.json"

    class << self
      def install!(destination: default_destination)
        FileUtils.mkdir_p(destination)
        entries = {}

        LOGICAL_NAMES.each do |logical_name|
          source = source_path(logical_name)
          next unless source.exist?

          digested_name = digested_filename(logical_name, source)
          FileUtils.cp(source, destination.join(digested_name))
          copy_adjacent_source_map(source, destination)
          entries[logical_name] = digested_name
        end

        File.write(destination.join(MANIFEST_FILENAME), JSON.pretty_generate(entries))
        patch_host_manifests(destination, entries)
        reset!
        entries
      end

      def url_path(logical_name)
        digested = manifest[logical_name.to_s]
        return if digested.blank?

        "/assets/#{digested}"
      end

      def manifest
        @manifest ||= load_manifest
      end

      def reset!
        @manifest = nil
      end

      def uninstall!(destination: default_destination)
        path = destination.join(MANIFEST_FILENAME)
        if path.exist?
          JSON.parse(path.read).each_value do |filename|
            FileUtils.rm_f(destination.join(filename))
          end
          FileUtils.rm_f(path)
        end
        %w[rails-pulse.js.map rails-pulse.css.map rails-pulse-icons.js.map].each do |map|
          FileUtils.rm_f(destination.join(map))
        end
        reset!
      end

      private

      def default_destination
        Rails.public_path.join("assets")
      end

      def source_path(logical_name)
        Engine.root.join("public", "rails-pulse-assets", logical_name)
      end

      def digested_filename(logical_name, source)
        ext = File.extname(logical_name)
        base = File.basename(logical_name, ext)
        digest = Digest::SHA256.file(source).hexdigest
        "#{base}-#{digest}#{ext}"
      end

      def copy_adjacent_source_map(source, destination)
        map = Pathname.new("#{source}.map")
        FileUtils.cp(map, destination.join(map.basename)) if map.exist?
      end

      def load_manifest
        path = Rails.public_path.join("assets", MANIFEST_FILENAME)
        return {} unless path.exist?

        JSON.parse(path.read)
      rescue JSON::ParserError
        {}
      end

      def patch_host_manifests(destination, entries)
        patch_propshaft_manifest(destination, entries)
        patch_sprockets_manifests(destination, entries)
      end

      def patch_propshaft_manifest(destination, entries)
        path = destination.join(".manifest.json")
        return unless path.exist?

        data = JSON.parse(path.read)
        File.write(path, JSON.pretty_generate(data.merge(entries)))
      rescue JSON::ParserError
        nil
      end

      def patch_sprockets_manifests(destination, entries)
        Dir.glob(destination.join(".sprockets-manifest-*.json")).each do |path|
          data = JSON.parse(File.read(path))
          data["assets"] ||= {}
          data["files"] ||= {}
          entries.each do |logical_name, digested_name|
            data["assets"][logical_name] = digested_name
            file = destination.join(digested_name)
            data["files"][digested_name] = {
              "logical_path" => logical_name,
              "mtime" => file.mtime.iso8601,
              "size" => file.size,
              "digest" => digested_name[/-([a-f0-9]{32,})\./, 1],
              "integrity" => integrity_for(file)
            }
          end
          File.write(path, JSON.pretty_generate(data))
        rescue JSON::ParserError
          next
        end
      end

      def integrity_for(file)
        "sha256-#{Digest::SHA256.base64digest(file.binread)}"
      end
    end
  end
end
