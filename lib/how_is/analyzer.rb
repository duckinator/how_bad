require 'contracts'
require 'ostruct'
require 'date'
require 'json'

module HowIs
  ##
  # Represents a completed analysis of the repository being analyzed.
  class Analysis < OpenStruct
  end

  class Analyzer
    include Contracts::Core

    class UnsupportedImportFormat < StandardError
      def initialize(format)
        super("Unsupported import format: #{format}")
      end
    end

    Contract Fetcher::Results, C::KeywordArgs[analysis_class: C::Optional[Class]] => Analysis
    def call(data, analysis_class: Analysis)
      issues = data.issues
      pulls = data.pulls

      analysis_class.new(
        issues_url: "https://github.com/#{data.repository}/issues",
        pulls_url: "https://github.com/#{data.repository}/pulls",

        repository: data.repository,

        number_of_issues:  issues.length,
        number_of_pulls:   pulls.length,

        issues_with_label: with_label_links(num_with_label(issues), data.repository),
        issues_with_no_label: {link: nil, total: num_with_no_label(issues)},

        average_issue_age: average_age_for(issues),
        average_pull_age:  average_age_for(pulls),

        oldest_issue: issue_or_pull_to_hash(oldest_for(issues)),
        oldest_pull: issue_or_pull_to_hash(oldest_for(pulls)),
      )
    end

    def from_file(file)
      extension = file.split('.').last
      raise UnsupportedImportFormat, extension unless extension == 'json'

      hash = JSON.parse(open(file).read)
      hash = hash.map do |k, v|
        v = DateTime.parse(v) if k.end_with?('_date')

        [k, v]
      end.to_h

      %w[oldest_issue oldest_pull].each do |key|
        hash[key]['date'] = DateTime.parse(hash[key]['date'])
      end

      Analysis.new(hash)
    end

    # Given an Array of issues or pulls, return a Hash specifying how many
    # issues or pulls use each label.
    def num_with_label(issues_or_pulls)
      # Returned hash maps labels to frequency.
      # E.g., given 10 issues/pulls with label "label1" and 5 with label "label2",
      # {
      #   "label1" => 10,
      #   "label2" => 5
      # }

      hash = Hash.new(0)
      issues_or_pulls.each do |iop|
        next unless iop['labels']

        iop['labels'].each do |label|
          hash[label['name']] += 1
        end
      end
      hash
    end

    def num_with_no_label(issues)
      issues.select { |x| x['labels'].empty? }.length
    end

    def average_date_for(issues_or_pulls)
      timestamps = issues_or_pulls.map { |iop| Date.parse(iop['created_at']).strftime('%s').to_i }
      average_timestamp = timestamps.reduce(:+) / issues_or_pulls.length

      DateTime.strptime(average_timestamp.to_s, '%s')
    end

    # Given an Array of issues or pulls, return the average age of them.
    def average_age_for(issues_or_pulls)
      ages = issues_or_pulls.map {|iop| time_ago_in_seconds(iop['created_at'])}
      raw_average = ages.reduce(:+) / ages.length

      seconds_in_a_year = 31_556_926
      seconds_in_a_month = 2_629_743
      seconds_in_a_week = 604_800
      seconds_in_a_day = 86_400

      years = raw_average / seconds_in_a_year
      years_remainder = raw_average % seconds_in_a_year

      months = years_remainder / seconds_in_a_month
      months_remainder = years_remainder % seconds_in_a_month

      weeks = months_remainder / seconds_in_a_week
      weeks_remainder = months_remainder % seconds_in_a_week

      days = weeks_remainder / seconds_in_a_day

      values = [
        [years, "year"],
        [months, "month"],
        [weeks, "week"],
        [days, "day"],
      ].reject {|(v, k)| v == 0}.map{ |(v,k)|
        k = k + 's' if v != 1
        [v, k]
      }

      most_significant = values[0, 2].map {|x| x.join(" ")}

      if most_significant.length < 2
        value = most_significant.first
      else
        value = most_significant.join(" and ")
      end

      "approximately #{value}"
    end

    # Given an Array of issues or pulls, return the creation date of the oldest.
    def oldest_for(issues_or_pulls)
      issues_or_pulls.sort_by {|x| DateTime.parse(x['created_at']) }.first
    end

    def date_for(issue_or_pull)
      DateTime.parse(issue_or_pull['created_at'])
    end

  private
    def with_label_links(labels, repository)
      labels.map do |label, num_issues|
        label_link = "https://github.com/#{repository}/issues?q=" + CGI.escape("is:open is:issue label:\"#{label}\"")

        [label, {'link' => label_link, 'total' => num_issues}]
      end.to_h
    end

    def time_ago_in_seconds(x)
      DateTime.now.strftime("%s").to_i - DateTime.parse(x).strftime("%s").to_i
    end

    def issue_or_pull_to_hash(iop)
      ret = {}

      ret['html_url'] = iop['html_url']
      ret['number'] = iop['number']
      ret['date'] = date_for(iop)

      ret
    end
  end
end
