# frozen_string_literal: true

module Bundler
  class Resolver
    class SpecGroup
      include GemHelpers

      attr_accessor :name, :version, :source
      attr_accessor :ignores_bundler_dependencies

      def initialize(all_specs)
        @all_specs = all_specs
        raise ArgumentError, "cannot initialize with an empty value" unless exemplary_spec = all_specs.first
        @name = exemplary_spec.name
        @version = exemplary_spec.version
        @source = exemplary_spec.source

        @activated_platforms = []
        @dependencies = nil
        @specs        = Hash.new do |specs, platform|
          specs[platform] = select_best_platform_match(all_specs, platform)
        end
        @ignores_bundler_dependencies = true
      end

      def to_specs
        @activated_platforms.map do |p|
          next unless s = @specs[p]
          lazy_spec = LazySpecification.new(name, version, s.platform, source)
          lazy_spec.dependencies.replace s.dependencies
          lazy_spec
        end.compact.uniq
      end

      def activate_platform!(platform)
        return unless for?(platform)
        return if @activated_platforms.include?(platform)
        @activated_platforms << platform
      end

      def copy_for(platform)
        copied_sg = self.class.new(@all_specs)
        copied_sg.ignores_bundler_dependencies = @ignores_bundler_dependencies
        return nil unless copied_sg.for?(platform)
        copied_sg.activate_platform!(platform)
        copied_sg
      end

      def spec_for(platform)
        @specs[platform]
      end

      def for?(platform)
        !spec_for(platform).nil?
      end

      def to_s
        activated_platforms_string = sorted_activated_platforms.join(", ")
        "#{name} (#{version}) (#{activated_platforms_string})"
      end

      def dependencies_for_activated_platforms
        dependencies = @activated_platforms.map {|p| __dependencies[p] }
        metadata_dependencies = @activated_platforms.map do |platform|
          metadata_dependencies(@specs[platform], platform)
        end
        dependencies.concat(metadata_dependencies).flatten
      end

      def ==(other)
        return unless other.is_a?(SpecGroup)
        name == other.name &&
          version == other.version &&
          sorted_activated_platforms == other.sorted_activated_platforms &&
          source == other.source
      end

      def eql?(other)
        return unless other.is_a?(SpecGroup)
        name.eql?(other.name) &&
          version.eql?(other.version) &&
          sorted_activated_platforms.eql?(other.sorted_activated_platforms) &&
          source.eql?(other.source)
      end

      def hash
        name.hash ^ version.hash ^ sorted_activated_platforms.hash ^ source.hash
      end

    protected

      def sorted_activated_platforms
        @activated_platforms.sort_by(&:to_s)
      end

    private

      def __dependencies
        @dependencies = Hash.new do |dependencies, platform|
          dependencies[platform] = []
          if spec = @specs[platform]
            spec.dependencies.each do |dep|
              next if dep.type == :development
              next if @ignores_bundler_dependencies && dep.name == "bundler".freeze
              dependencies[platform] << DepProxy.new(dep, platform)
            end
          end
          dependencies[platform]
        end
      end

      def metadata_dependencies(spec, platform)
        return [] unless spec
        # Only allow endpoint specifications since they won't hit the network to
        # fetch the full gemspec when calling required_ruby_version
        return [] if !spec.is_a?(EndpointSpecification) && !spec.is_a?(Gem::Specification)
        dependencies = []
        if !spec.required_ruby_version.nil? && !spec.required_ruby_version.none?
          dependencies << DepProxy.new(Gem::Dependency.new("Ruby\0", spec.required_ruby_version), platform)
        end
        if !spec.required_rubygems_version.nil? && !spec.required_rubygems_version.none?
          dependencies << DepProxy.new(Gem::Dependency.new("RubyGems\0", spec.required_rubygems_version), platform)
        end
        dependencies
      end
    end
  end
end
