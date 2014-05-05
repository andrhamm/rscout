require 'rscout/version'
require 'dotenv'
require 'yaml'
require 'hashie'
require 'pagerduty'
require 'mail'
require 'logger'
require 'active_support/core_ext/string'

require 'rspec'
require 'rspec/core'
require 'rspec/core/formatters/json_formatter'
require 'rspec/core/formatters/documentation_formatter'
require 'rspec/core/formatters/html_formatter'

module RScout
  def self.logger
    @@LOGGER ||= begin
      logger = Logger.new STDOUT
      logger.level = Logger::ERROR
      logger
    end
  end

  def self.load(options={})
    Dotenv.load

    @@ENVS ||= begin
      envs = options[:envs] ? Hashie::Mash.new(YAML.load_file(options[:envs])) : []

      raise "No environments found." unless envs.keys

      envs
    end

    @@SUITES ||= begin
      suites = options[:suites] ? Hashie::Mash.new(YAML.load_file(options[:suites])) : []

      raise "No suites found." unless suites.keys

      suites
    end
  end

  def self.envs(env_names=nil)
    if env_names
      envs = {}
      env_names.each do |env_name|
        raise "Unknown environment '#{env_name}'." unless @@ENVS[env_name]
        envs[env_name] = @@ENVS[env_name]
      end
      envs
    else
      @@ENVS
    end
  end

  def self.suites(suite_names=nil)
    if suite_names
      suites = {}
      suite_names.each do |suite_name|
        raise "Unknown suite '#{suite_name}'." unless @@SUITES[suite_name]
        suites[suite_name] = @@SUITES[suite_name]
      end
      suites
    else
      @@SUITES
    end
  end

  def self.run(options={}, &block)
    verbose = options[:verbose] || false
    RScout.logger.level = verbose ? Logger::DEBUG : Logger::ERROR
    logger.debug "Running…"
    RScout.envs(options[:envs].map(&:to_sym)).each do |env_name, env_config|
      RScout.logger.debug "Running tests for #{env_name}…"
      env_config.name = env_name
      $target_env = env_config
      RScout.suites(options[:suites].map(&:to_sym)).each do |suite_name, suite_config|
        suite_config.name = suite_name
        $target_suite = suite_config
        RScout.logger.debug "Running tests for #{suite_name} on #{env_name}…"

        yield if block_given?

        output = Hashie::Mash.new({
          txt: StringIO.new,
          html: StringIO.new,
          json: StringIO.new,
          stdout: nil,
          results: nil,
          error: Hashie::Mash.new({backtrace:[], message:nil})
        })

        failed = false
        begin
          html_formatter = RSpec::Core::Formatters::HtmlFormatter.new output.html
          txt_formatter = RSpec::Core::Formatters::DocumentationFormatter.new output.txt
          json_formatter = RSpec::Core::Formatters::JsonFormatter.new output.json

          reporter = RSpec::Core::Reporter.new(json_formatter, txt_formatter, html_formatter)

          rspec = RSpec.configuration
          # RSpec::Core::Runner.disable_autorun!
          rspec.instance_variable_set(:@reporter, reporter)

          rspec_task = lambda { RSpec::Core::Runner.run(Dir["#{ENV['RSCOUT_SUITE_DIR']}/#{suite_name}/*.rb"]) }

          if verbose
            rspec_task.call
          else
            output.stdout = RScout.capture_stdout &rspec_task
          end

          output.results = json_formatter.output_hash

          failed = output.results[:summary][:failure_count] > 0
          failure_count = output.results[:summary][:failure_count].to_s
        rescue => e
          failed = true
          RScout.logger.error "Exception encountered while running RSpec: #{e.message}"
          RScout.logger.error e.backtrace
          output.error = e
        ensure
          output.txt.close unless output.txt.closed?
          output.html.close unless output.html.closed?
          output.json.close unless output.json.closed?
        end

        if failed
          RScout.logger.info "Tests failed."
          RScout.send_failure_notifications env_config, suite_config, output
        end
      end
    end
  rescue => e
    RScout.logger.fatal e.message
  end

  def self.send_failure_notifications(env, suite, output)
    email_body = [output.txt.string, output.error.backtrace.join("\n")].join("\n")
    if env.email_enabled && suite.email
      RScout.logger.info "Sending emails alert to #{suite.email}"
      begin
        mail = Mail.new do
          from     'Scout <platform+scout@evertrue.com>'
          to       suite.email
          subject  "Scout Alert: Tests failing on #{suite.name.to_s.humanize.titleize} (#{env.name.downcase})"
          add_file filename: 'results.html', content: output.html.string

          header["X-Priority"] = "1 (Highest)"
          header["X-MSMail-Priority"] = "High"
          header["Importance"] = "High"

          text_part do
            body email_body
          end
        end

        mail.deliver!
      rescue => e
        RScout.logger.error "Failed to send email alert!"
        RScout.logger.error e.message + "\n " + e.backtrace.join("\n ")
      end
    end

    if env.pagerduty_enabled && suite.pagerduty_service_key
      RScout.logger.info "Triggering PagerDuty incident to #{suite.pagerduty_service_key}"
      begin
        if suite.pagerduty_service_key.match(/@(.*)pagerduty.com$/)
          mail = Mail.new do
             from    'RScout <platform+rscout@evertrue.com>'
             to      suite.pagerduty_service_key
             subject "DOWN alert: RScout tests failing on #{suite.name.to_s.humanize.titleize} (#{env.name.downcase})"
             body    email_body
          end

          mail.deliver!
        else
          p = Pagerduty.new suite.pagerduty_service_key, ['scout', env.name].join('_')
          incident = p.trigger 'RScout tests failing!', output.results
        end
      rescue => e
        RScout.logger.error "Failed to send PagerDuty alert!"
        RScout.logger.error e.message + "\n " + e.backtrace.join("\n ")
      end
    end
  end

  def self.capture_stdout(&block)
    RScout.logger.debug "Starting stdout capture…"
    previous_stdout, $stdout = $stdout, StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = previous_stdout
    RScout.logger.debug "Ended stdout capture."
  end
end
