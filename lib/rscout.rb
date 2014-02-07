require "rscout/version"
require "dotenv"
require "yaml"
require "hashie"
require "pagerduty"
require "mail"

module RScout
  def self.load(options={})
    Dotenv.load

    @@ENVS ||= begin
      options[:envs] ? Hashie::Mash.new(YAML.load_file(options[:envs])) : []
    end

    @@SUITES ||= begin
      options[:suites] ? Hashie::Mash.new(YAML.load_file(options[:suites])) : []
    end
  end

  def self.envs
    @@ENVS
  end

  def self.suites
    @@SUITES
  end

  def self.run(options={}, &block)
    @@ENVS.keep_if {|env_k, env_v| options[:envs] == nil || options[:envs].include?(env_k.to_sym) }.each do |env_name, env_config|
      env_config.name = env_name
      $target_env = env_config
      @@SUITES.keep_if {|suite_k, suite_v| options[:suites] == nil || options[:suites].include?(suite_k.to_sym) }.each do |suite_name, suite_config|
        suite_config.name = suite_name
        $target_suite = suite_config
        puts "#{env_name} .. #{suite_name}"
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
          rspec.instance_variable_set(:@reporter, reporter)

          rspec_task = lambda { RSpec::Core::Runner.run(Dir["#{ENV['RSCOUT_SUITE_DIR']}/#{suite_name}/*.rb"]) }

          if options[:verbose]
            rspec_task.call
          else
            output.stdout = RScout.capture_stdout &rspec_task
          end

          output.results = json_formatter.output_hash

          failed = output.results[:summary][:failure_count] > 0
          failure_count = output.results[:summary][:failure_count].to_s
        rescue => e
          failed = true
          puts "Exception encountered while running RSpec: #{e.message}", e.backtrace
          output.error = e
        ensure
          output.txt.close unless output.txt.closed?
          output.html.close unless output.html.closed?
          output.json.close unless output.json.closed?
        end

        if failed
          puts "Tests failed."
          RScout.handle_failure env_config, suite_config, output
        end
      end
    end
  end

  def self.handle_failure(env, suite, output)
    email_body = [output.txt_string, output.error.backtrace.join("\n")].join("\n")
    if env.email_enabled && suite.email
      puts "Sending emails alert to #{suite.email}"
      begin
        mail = Mail.new do
           from     'Scout <platform+scout@evertrue.com>'
           to       suite.email
           subject  "Scout Alert: Tests failing on #{suite.name.humanize.titleize} (#{env.name.capitalize})"
           body     email_body
           add_file filename: 'results.html', content: output.html.string
        end

        mail.deliver!
      rescue => e
        puts "Failed to send email alert!", e.message, e.backtrace
      end
    end

    if env.pagerduty_enabled && suite.pagerduty_service_key
      puts "Triggering PagerDuty incident to #{suite.pagerduty_service_key}"
      begin
        if suite.pagerduty_service_key.match(/@(.*)pagerduty.com$/)
          mail = Mail.new do
             from    'RScout <platform+rscout@evertrue.com>'
             to      suite.pagerduty_service_key
             subject "DOWN alert: RScout tests failing on #{suite.name.humanize.titleize} (#{env.name.capitalize})"
             body    email_body
          end

          mail.deliver!
        else
          p = Pagerduty.new suite.pagerduty_service_key, ['scout', env.name].join('_')
          incident = p.trigger 'RScout tests failing!', output.results
        end
      rescue => e
        puts "Failed to send PagerDuty alert!", e.message, e.backtrace
      end
    end
  end

  def self.capture_stdout(&block)
    puts "starting stdout capture..."
    previous_stdout, $stdout = $stdout, StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = previous_stdout
    puts "ended stdout capture."
  end
end
