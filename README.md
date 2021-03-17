# bootstrap-sentry
Shell script to bootstrap a development environment for sentry

## How to use

```bash
bash <(curl -s https://raw.githubusercontent.com/getsentry/bootstrap-sentry/main/bootstrap.sh)
```

## What does it do?

Besides setting up your host so you can do development for [sentry](https://github.com/getsentry/sentry),
it also does the following:

* It reports any errors to Sentry.io (`bootstrap-sentry` project)
* It reports metrics

## How to develop?

Install `pre-commit` to help you catch issues when commiting code ([other installation methods](https://pre-commit.com/#installation)):
```
brew install pre-commit
pre-commit install
```

Test your changes locally by running:
```
./bootstraph.sh
```