require 'how_is/version'
require 'contracts'
require 'cacert'

Cacert.set_in_env

C = Contracts

class HowIs
  include Contracts::Core

  require 'how_is/fetcher'
  require 'how_is/analyzer'
  require 'how_is/report'

  DEFAULT_FORMAT = :html

  ##
  # Generate a report file.
  #
  # TODO: Remnant of old API. Remove or rename.
  # If this is removed, remove various .export_file
  # methods throughout Report/*Report.
  def self.generate_report_file(report:, **kw_args)
    analysis = self.generate_analysis(**kw_args)

    Report.export_file(analysis, report)
  end

  ##
  # Generate a HowIs instance, so you can generate reports.
  #
  # @param repository [String] The name of a GitHub repository (of the
  #   format <user or organization>/<repository>).
  # @param analysis [HowIs::Analysis] Optional; if passed, this Analysis
  #   object is used instead of generating one.
  def initialize(repository, analysis = nil, **kw_args)
    # If no Analysis is passed, generate one.
    analysis ||= HowIs.generate_analysis(repository: repository, **kw_args)

    # Used by to_html, to_json, etc.
    @analysis = analysis
  end

  ##
  # Generate an HTML report.
  #
  # @returns [String] An HTML report.
  def to_html
    Report.export(@analysis, :html)
  end

  ##
  # Generate a JSON report.
  #
  # @returns [String] A JSON report.
  def to_json
    Report.export(@analysis, :json)
  end

  ##
  # Given a JSON report, create a new HowIs object (for generating other
  # reports).
  #
  # @param json [String] A JSON report object.
  # @returns [HowIs] A HowIs object that can be used for generating other
  #   reports, treating the JSON report as a cache.
  def self.from_json(json)
    analysis = HowIs::Analyzer.from_json(json)

    self.new(analysis.repository, analysis)
  end

  ##
  # Returns a list of possible export formats.
  #
  # @returns [Array<String>] An array of the types of reports you can
  #   generate.
  def self.supported_formats
    report_constants = HowIs.constants.grep(/.Report/) - [:BaseReport]
    report_constants.map {|x| x.to_s.split('Report').first.downcase }
  end

  ##
  # Returns whether or not the specified +file+ can be exported to.
  #
  # @param file [String] A filename.
  # @returns [Boolean] +true+ if HowIs can export to the file, +false+
  #   if it can't.
  def self.can_export_to?(file)
    # TODO: Check if the file is writable?
    supported_formats.include?(file.split('.').last)
  end

  # Generate an analysis. Used internally for generate_report{,_file}.
  Contract C::KeywordArgs[repository: String,
                          from: C::Optional[C::Or[String, nil]],
                          fetcher: C::Optional[Class],
                          analyzer: C::Optional[Class],
                          github: C::Optional[C::Any]] => C::Any
  def self.generate_analysis(repository:,
        from: nil,
        fetcher: Fetcher.new,
        analyzer: Analyzer.new,
        github: nil)
    if from
      analysis = analyzer.from_file(from)
    else
      raw_data = fetcher.call(repository, github)
      analysis = analyzer.call(raw_data)
    end

    analysis
  end

  # Generates YAML frontmatter, as is used in Jekyll and other blog engines.
  #
  # E.g.,
  #     generate_frontmatter({'foo' => "bar %{baz}"}, {'baz' => "asdf"})
  # =>  "---\nfoo: bar asdf\n"
  Contract C::HashOf[C::Or[String, Symbol] => String],
           C::HashOf[C::Or[String, Symbol] => C::Any] => String
  def self.generate_frontmatter(frontmatter, report_data)
    frontmatter = convert_keys(frontmatter, :to_s)
    report_data = convert_keys(report_data, :to_sym)

    frontmatter = frontmatter.map { |k, v|
      v = v % report_data

      [k, v]
    }.to_h

    YAML.dump(frontmatter)
  end

  ##
  # Generates a series of report files based on a config Hash.
  #
  # @param config [Hash] A Hash specifying the formats, locations, etc
  #   of the reports to generate.
  # @param github (You don't need this.) An object to replace the GitHub
  #   class when fetching data.
  # @param report_class (You don't need this.) An object to replace the
  #   HowIs::Report class when generating reports.
  def self.from_config(config,
        github: nil,
        report_class: nil)
    report_class ||= HowIs::Report

    date = Date.strptime(Time.now.to_i.to_s, '%s')
    date_string = date.strftime('%Y-%m-%d')
    friendly_date = date.strftime('%B %d, %y')

    analysis = HowIs.generate_analysis(repository: config['repository'], github: github)

    report_data = {
      repository: config['repository'],
      date: date,
      friendly_date: friendly_date,
    }

    generated_reports = {}

    config['reports'].map do |format, report_config|
      filename = report_config['filename'] % report_data
      file = File.join(report_config['directory'], filename)

      report = report_class.export(analysis, format)

      result = build_report(report_config['frontmatter'], report_data, report)

      generated_reports[file] = result

      result
    end

    generated_reports
  end

  # Combine the frontmatter, report data, and raw report into a report with
  # frontmatter.
  def self.build_report(frontmatter, report_data, report)
    str = StringIO.new

    if frontmatter
      str.puts generate_frontmatter(frontmatter, report_data)
      str.puts "---"
      str.puts
    end

    str.puts report

    str.string
  end

private
  # convert_keys({'foo' => 'bar'}, :to_sym)
  # => {:foo => 'bar'}
  def self.convert_keys(data, method_name)
    data.map {|k, v| [k.send(method_name), v]}.to_h
  end

end
