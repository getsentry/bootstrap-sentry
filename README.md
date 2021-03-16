# bootstrap-sentry
Shell script to bootstrap a development environment for sentry

## How to use

```bash
bash <(curl -s https://raw.githubusercontent.com/getsentry/bootstrap-sentry/main/bootstrap.sh)
```

## What does it do?

Besides setting up your development environment so you can do development for [sentry](https://github.com/getsentry/sentry),
it also does the following:

* Report errors to Sentry.io (`dev-env-cli` project)
* Report metrics
