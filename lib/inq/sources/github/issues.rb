# frozen_string_literal: true

require "inq/date_time_helpers"
require "inq/sources/github"
require "inq/sources/github_helpers"
require "inq/sources/github/issue_fetcher"
require "inq/template"
require "date"

module Inq
  module Sources
    class Github
      ##
      # Fetches various information about GitHub Issues.
      class Issues
        include Inq::DateTimeHelpers
        include Inq::Sources::GithubHelpers

        attr_reader :config, :start_date, :end_date, :cache

        # @param repository [String] GitHub repository name, of the format user/repo.
        # @param start_date [String] Start date for the report being generated.
        # @param end_date   [String] End date for the report being generated.
        # @param cache      [Cacheable] Instance of Inq::Cacheable to cache API calls
        def initialize(config, start_date, end_date, cache)
          @config = config
          @cache = cache
          @repository = config["repository"]
          raise "#{self.class}.new() got nil repository." if @repository.nil?
          @start_date = start_date
          @end_date = end_date
        end

        def url(values = {})
          defaults = {
            "is" => singular_type,
            "created" => "#{@start_date}..#{@end_date}",
          }
          values = defaults.merge(values)
          raw_query = values.map { |k, v|
            [k, v].join(":")
          }.join(" ")

          query = CGI.escape(raw_query)

          "https://github.com/#{@repository}/#{url_suffix}?q=#{query}"
        end

        def average_age
          average_age_for(data)
        end

        def oldest
          result = oldest_for(data)
          return {} if result.nil?

          result["date"] = pretty_date(result["createdAt"])

          result
        end

        def newest
          result = newest_for(data)
          return {} if result.nil?

          result["date"] = pretty_date(result["createdAt"])

          result
        end

        def summary
          number_open = to_a.length
          pretty_number = pluralize(pretty_type, number_open, zero_is_no: false)
          was_were = (number_open == 1) ? "was" : "were"

          "<p>A total of <a href=\"#{url}\">#{pretty_number}</a> #{was_were} opened during this period.</p>"
        end

        def to_html
          return summary if to_a.empty?

          Inq::Template.apply("issues_or_pulls_partial.html", {
            summary: summary,
            average_age: average_age,
            pretty_type: pretty_type,

            oldest_link: oldest["url"],
            oldest_date: oldest["date"],

            newest_link: newest["url"],
            newest_date: newest["date"],
          })
        end

        def to_a
          obj_to_array_of_hashes(data)
        end

        def type
          singular_type + "s"
        end

        def pretty_type
          "issue"
        end

        private

        def url_suffix
          "issues"
        end

        def singular_type
          "issue"
        end

        def data
          return @data if instance_variable_defined?(:@data)

          fetcher = IssueFetcher.new(self)
          @data = fetcher.data
        end
      end
    end
  end
end
