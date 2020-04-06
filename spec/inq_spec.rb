# frozen_string_literal: true

require "spec_helper"
require "inq"
require "inq/config"
require "inq/frontmatter"
require "json"
require "open3"
require "timecop"
require "tmpdir"
require "yaml"

HOW_IS_CONFIG_FILE = File.expand_path("./data/how_is/cli_spec/how_is.yml", __dir__)

HOW_IS_EXAMPLE_REPOSITORY_JSON_REPORT = File.expand_path("./data/how-is-example-repository-report.json", __dir__)
HOW_IS_EXAMPLE_REPOSITORY_HTML_REPORT = File.expand_path("./data/how-is-example-repository-report.html", __dir__)

INQ_DATE_INTERVAL_EXAMPLE_REPOSITORY_HTML_REPORT = File.expand_path("./data/how-is-date-interval-example-repository-report.html", __dir__)
INQ_DATE_INTERVAL_EXAMPLE_REPOSITORY_JSON_REPORT = File.expand_path("./data/how-is-date-interval-example-repository-report.json", __dir__)


HOW_IS_EXAMPLE_EMPTY_REPOSITORY_HTML_REPORT =
  File.expand_path("./data/how-is-example-empty-repository-report.html", __dir__)

JEKYLL_HEADER =
  <<~HEADER
    ---
    title: rubygems/rubygems report
    layout: default
    ---
  HEADER

describe Inq do
  context "#from_config" do
    let(:config) {
      Inq::Config.new
        .load_defaults
        .load_files(HOW_IS_CONFIG_FILE)
    }

    it "generates valid report files", skip: env_vars_hidden? do
      Dir.mktmpdir { |dir|
        Dir.chdir(dir) {
          reports = nil

          VCR.use_cassette("how-is-with-config-file") do
            expect {
              reports = Inq.from_config(config, "2017-08-01").to_h
            }.to_not raise_error
            # This instance, and all other instances in this file, of
            # ".to_not output.to_stderr" are replaced with
            # ".to_not raise_error" due to a deprecation warning.
            #}.to_not output.to_stderr
          end

          html_report = reports["output/report.html"]
          json_report = reports["output/report.json"]

          expect(html_report).to include(JEKYLL_HEADER)
          expect {
            JSON.parse(json_report)
          }.to_not raise_error
        }
      }
    end

    it "adds correct frontmatter", skip: env_vars_hidden? do
      reports = nil

      VCR.use_cassette("how-is-from-config-frontmatter") do
        reports = Inq.from_config(config, "2017-08-01").to_h
      end

      actual_html = reports["output/report.html"]
      # NOTE: If JSON reports get frontmatter applied in the future,
      #       uncomment the following line (+ the one at the end of
      #       this block) to test it.
      # actual_json = reports["output/report.json"]

      expected_frontmatter = <<~FRONTMATTER
        ---
        title: rubygems/rubygems report
        layout: default
        ---

      FRONTMATTER

      expect(actual_html).to start_with(expected_frontmatter)
      # NOTE: If JSON reports get frontmatter applied in the future,
      #       uncomment the following line (+ the one earlier in
      #       this block) to test it.
      # expect(actual_json).to start_with(expected_frontmatter)
    end
  end

  context "HTML report for how-is/example-repository" do
    # TODO: Stop using Timecop once reports are no longer time-dependent.

    before do
      # 2016-11-01 00:00:00 UTC.
      # TODO: Stop pretending to always be in UTC.
      date = DateTime.parse("2016-11-01").new_offset(0)
      Timecop.freeze(date)
    end

    after do
      Timecop.return
    end

    it "generates a valid report", skip: env_vars_hidden? do
      expected_html = File.open(HOW_IS_EXAMPLE_REPOSITORY_HTML_REPORT).read.chomp
      expected_json = File.open(HOW_IS_EXAMPLE_REPOSITORY_JSON_REPORT).read.chomp
      actual_report = nil

      VCR.use_cassette("how-is-example-repository") do
        expect {
          actual_report = Inq.new("how-is/example-repository", "2016-09-01")
        }.to_not raise_error
        #}.to_not output.to_stderr

        expect(actual_report.to_html_partial).to eq(expected_html)
        expect(actual_report.to_json).to eq(expected_json)
      end
    end

    context "when a date interval is passed" do
      it "generates a valid report", skip: env_vars_hidden? do
        expected_html = File.open(INQ_DATE_INTERVAL_EXAMPLE_REPOSITORY_HTML_REPORT).read.chomp
        expected_json = File.open(INQ_DATE_INTERVAL_EXAMPLE_REPOSITORY_JSON_REPORT).read.chomp
        actual_report = nil

        VCR.use_cassette("how-is-example-repository-with-date-interval") do
          expect {
            actual_report = Inq.new("how-is/example-repository", "2016-08-01", "2016-12-01")
          }.to_not raise_error

          expect(actual_report.to_html_partial).to eq(expected_html)
          expect(actual_report.to_json).to eq(expected_json)
        end
      end
    end
  end

  context "HTML report for repository with no PRs or issues" do
    it "generates a valid report file", skip: env_vars_hidden? do
      expected = File.open(HOW_IS_EXAMPLE_EMPTY_REPOSITORY_HTML_REPORT).read.chomp
      actual = nil

      VCR.use_cassette("how-is-example-empty-repository") do
        expect {
          actual = Inq.new("how-is/example-empty-repository", "2017-01-01").to_html_partial
        }.to_not raise_error
        #}.to_not output.to_stderr
      end

      expect(actual).to eq(expected)
    end
  end

  context "#generate_frontmatter" do
    it "works with frontmatter parameter using String keys, report_data using String keys" do
      actual = nil
      expected = nil

      VCR.use_cassette("how-is-example-repository") do
        actual = Inq::Frontmatter.generate({"foo" => "bar %{baz}"}, {"baz" => "asdf"})
        expected = "---\nfoo: bar asdf\n---\n\n"
      end

      expect(actual).to eq(expected)
    end

    it "works with frontmatter parameter using Symbol keys, report_data using Symbol keys" do
      actual = nil
      expected = nil

      VCR.use_cassette("how-is-example-repository") do
        actual = Inq::Frontmatter.generate({:foo => "bar %{baz}"}, {:baz => "asdf"})
        expected = "---\nfoo: bar asdf\n---\n\n"
      end

      expect(actual).to eq(expected)
    end
  end
end
