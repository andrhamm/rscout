require 'rscout/version'
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
  DEFAULT_LOGGER  = Logger.new(STDOUT)
  DEFAULT_OPTIONS = {
    logger: DEFAULT_LOGGER,
    verbose: false,
    env: 'development',
    from_email: 'rscout@localhost'
  }

  class << self
    def options
      @@options ||= DEFAULT_OPTIONS.clone
    end

    def log(msg)
      options[:logger].add(options[:severity]) { msg }
    end

    def logger
      options[:logger]
    end

    def env
      options[:env]
    end

    def run_suite(dir)
      verbose = options[:verbose]
      gemfile = File.join(dir, 'Gemfile')
      configfile = File.join(dir, 'config', 'rscout.yml')

      Bundler.with_clean_env do
        Dir.chdir(dir) do
          yaml = Hashie::Mash.new(YAML.load_file configfile)
          config = yaml[env]

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
            rspec.instance_variable_set(:@reporter, reporter)

            tests = Dir.glob File.join(dir, 'spec/**/*_spec.rb')

            rspec_task = lambda { RSpec::Core::Runner.run tests }

            if verbose
              rspec_task.call
            else
              output.stdout = capture_stdout &rspec_task
            end

            output.results = json_formatter.output_hash

            failed = output.results[:summary][:failure_count] > 0
            failure_count = output.results[:summary][:failure_count].to_s
          rescue => e
            failed = true
            logger.error "Exception encountered while running RSpec: #{e.message}"
            logger.error e.backtrace
            output.error = e
          ensure
            output.txt.close unless output.txt.closed?
            output.html.close unless output.html.closed?
            output.json.close unless output.json.closed?
          end

          if failed
            logger.info "Tests failed."
            send_failure_notifications config, env, output
          end

          failed
        end
      end
    end

    def send_failure_notifications(config, env, output)
      email_body = [output.txt.string, output.error.backtrace.join("\n")].join("\n")
      if config.email_enabled && config.email
        logger.info "Sending emails alert to #{config.email}"
        begin
          mail = Mail.new do
            from     RScout.options[:from_email]
            to       config.email
            subject  "RScout Alert: Tests failing on #{config.name.to_s.humanize.titleize} (#{env})"
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
          logger.error "Failed to send email alert!"
          logger.error e.message + "\n " + e.backtrace.join("\n ")
        end
      end

      if config.pagerduty_enabled && config.pagerduty_service_key
        logger.info "Triggering PagerDuty incident to #{config.pagerduty_service_key}"
        begin
          if config.pagerduty_service_key.match(/@(.*)pagerduty.com$/)
            mail = Mail.new do
               from    RScout.options[:from_email]
               to      config.pagerduty_service_key
               subject "DOWN alert: RScout tests failing on #{config.name.to_s.humanize.titleize} (#{env})"
               body    email_body
            end

            mail.deliver!
          else
            p = Pagerduty.new config.pagerduty_service_key, ['scout', env].join('_')
            incident = p.trigger 'RScout tests failing!', output.results
          end
        rescue => e
          logger.error "Failed to send PagerDuty alert!"
          logger.error e.message + "\n " + e.backtrace.join("\n ")
        end
      end
    end

    def capture_stdout(&block)
      previous_stdout, $stdout = $stdout, StringIO.new
      yield
      if $stdout.respond_to?(:string)
        $stdout.string
      else
        logger.warn "Test suite hijacked our STDOUT capture."
        nil
      end
    ensure
      $stdout = previous_stdout
    end
  end
end
