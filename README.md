Run integration tests on your live APIs. Write tests in RSpec and get email and/or PagerDuty notifications when tests are failing.

At EverTrue, we run a dedicated server we call Scout, which has many projects' RScout tests deployed to it. Our Scout server is a Sinatra web app which has a REST API which leverages RScout to run the many test suites for our various REST APIs.

## Features

* Sends email notifications with details of failing tests
* Sends PagerDuty notifications
* YAML configuration supports multiple environments
* Simple command-line interface

## Installation

Add this line to your application's Gemfile:

    gem 'rscout'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rscout

## Configuration

Recommended directory structure:

```
myproject
| rscout_tests
| | config
| | | rscout.yml
| | spec
| | | myfirsttest_spec.rb
| | | spec_helper.rb
| | Gemfile
```

We keep our RScout tests separate from our main tests, for consistency accross all our projects. You'll be running the `rscout` command from the `rscout_tests` directory (name not important) and the relation of the `Gemfile`, `config/rscout.yml` and `spec/` are important.

Example `rscout.yml` file:

```
default: &default
  name: myproject
  pagerduty_id: PM3WJQN
  pagerduty_service_key: my-api@myteam.pagerduty.com
  pagerduty_enabled: false
  email: andrew@example.com
  email_enabled: true

development:
  <<: *default

staging:
  <<: *default

production:
  <<: *default
  pagerduty_enabled: true
```

Note: For PagerDuty configurations, you should use their REST API to determine the values for `pagerduty_id` and `pagerduty_service_key`. Only one is necessary. If your PagerDuty service is setup with a "service_key" then RScout will send the notification to that email address since their REST API does not support REST notifications for these service configurations. For us, this was based on if the given service was integrated with Pingdom.

## Usage

The `rscout` command should be run from the directory where you keep your RScout test Gemfile. See Configuration section above.

  $ cd myproject
  $ SMTP_ADDRESS=localhost SMTP_PORT=1025 bundle exec rscout test --env production`

Supply the rscout command with the necessary SMTP ENV keys if applicable.

## TODO

* Abstract notification modules, support other services
* Pingdom integration
* Slack/HipChat integration

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request