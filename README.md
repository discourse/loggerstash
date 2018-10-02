Ever wanted to have your loggers send their data direct to logstash, without
going through a dozen intermediate processing steps?  Do you worry your log
entries are being dropped because you're forced to use UDP for sending log
events?  Would you like to have actionable metrics showing exactly how your
log forwarding system is working?  Do you dream of being able to use modern
DNS record types, such as SRV (standardised in the year 2000!), to indicate
where your logstash servers are?

If so, you're in the right place.


# Installation

It's a gem:

    gem install loggerstash

There's also the wonders of [the Gemfile](http://bundler.io):

    gem 'loggerstash'

If you're the sturdy type that likes to run from git:

    rake install

Or, if you've eschewed the convenience of Rubygems entirely, then you
presumably know what to do already.


# Logstash Configuration

In order for logstash to receive the events being written, it must have a
`json_lines` TCP input configured.  Something like this will do the trick:

    input {
      tcp {
        id    => "json_lines"
        port  => 5151
        codec => "json_lines"
      }
    }


# Usage

Start by including the necessary file:

    require 'loggerstash'

next, create a new instance of `Loggerstash`, pointing to the logstash
server you wish to use:

    ls = Loggerstash.new(logstash_server: "192.0.2.42:5151")

Anything that is a valid [logstash_writer
`server_name`](https://github.com/discourse/logstash_writer#usage) can be
specified as the `logstash_server`.

Once you have a Loggerstash, you just need to attach your `Loggerstash`
instance to either the `Logger` class (to have all loggers forward to
logstash), or to individual instances of Logger that you wish to forward:

    # Forward just this logger's messages to logstash
    l = Logger.new($stderr)
    ls.attach(l)

    # Forward all Logger instances' messages to logstash
    ls.attach(Logger)

    # Forward multiple loggers' messages to logstash
    some_logger = Logger.new($stderr)
    another_logger = Logger.new($stderr)

    ls.attach(some_logger)
    ls.attach(another_logger)

You can, in *theory*, attach Loggerstash to other things, but since it hooks
into the deep internals of Logger, it's unlikely to work very well on
anything else.

If you'd like to provide a richer event to logstash than the default (which
basically just maps progname, timestamp, severity, and message into a hash),
you can extend the default formatter:

    ls.formatter = ->(s, t, p, m) do
      default_formatter.call(s, t, p, m).merge(some_tag: "ohai!")
    end

Of course, you can do entirely your own thing, and not call the default
formatter at all if you'd prefer.

You can also specify the formatter as a parameter to the constructor:

    ls = Loggerstash.new(logstash_server: "...", formatter: ->(s, t, p, m) { ... }

If you want to expose the metrics maintained by the underlying
LogstashWriter instance, you can specify a `Prometheus::Client::Registry` to
register the metrics:

    Loggerstash.new(logstash_server: "...", metrics_registry: @metrics_server.registry)

    # ... OR ...
    ls.metrics_registry = @metrics_server.registry

You can only pass a given metrics registry to one instance of `Loggerstash`,
because otherwise the registered metrics will conflict and everything will
be awful.  If anyone ever comes up with a real-world use-case for needing
multiple Loggerstashes pointing to the same metrics registry, a PR would be
accepted to specify a prefix on the registered metrics.

Note that once you have attached a `Loggerstash` instance to a logger, you
can't change the `Loggerstash` configuration -- calls to any of the
configuration setters will raise an exception.


## Prometheus Metrics

If you specify a metrics registry to use, a set of metrics with a
`logstash_writer_` prefix will be included and maintained.  For the complete
set of metrics and their meanings, refer to [the `LogstashWriter`
documentation](https://github.com/discourse/logstash_writer#prometheus-metrics).


# Contributing

Patches can be sent as [a Github pull
request](https://github.com/discourse/loggerstash).  This project is
intended to be a safe, welcoming space for collaboration, and contributors
are expected to adhere to the [Contributor Covenant code of
conduct](CODE_OF_CONDUCT.md).


# Licence

Unless otherwise stated, everything in this repo is covered by the following
copyright notice:

    Copyright (C) 2018  Civilized Discourse Construction Kit, Inc.

    This program is free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License version 3, as
    published by the Free Software Foundation.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
