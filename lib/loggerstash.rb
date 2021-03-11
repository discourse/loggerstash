# frozen_string_literal: true

require 'logstash_writer'
require 'thread'

# A sidecar class to augment a Logger with super-cow-logstash-forwarding
# powers.
#
class Loggerstash
  # Base class of all Loggerstash errors
  #
  class Error < StandardError; end

  # Raised if any configuration setter methods are called (`Loggerstash#<anything>=`)
  # after the loggerstash instance has been attached to a logger.
  #
  class AlreadyRunningError < Error; end

  # A new Loggerstash!
  #
  # @param logstash_server [String] an address:port, hostname:port, or srvname
  #   to which a `json_lines` logstash connection can be made.
  #
  # @param metrics_registry [Prometheus::Client::Registry] where the metrics
  #   which are used by the underlying `LogstashWriter` should be registered,
  #   for later presentation by the Prometheus client.
  #
  # @param formatter [Proc] a formatting proc which takes the same arguments
  #   as the standard `Logger` formatter, but rather than emitting a string,
  #   it should pass back a Hash containing all the fields you wish to send
  #   to logstash.
  #
  # @param logstash_writer [LogstashWriter] in the event that you've already
  #   got a LogstashWriter instance configured, you can pass it in here.  Note
  #   that any values you've set for logstash_server and metrics_registry
  #   will be ignored.
  #
  # @param logger [Logger] passed to the LogstashWriter we create.  May or
  #   may not, itself, be attached to the Loggerstash for forwarding to
  #   logstash (Logception!).
  #
  def initialize(logstash_server:, metrics_registry: nil, formatter: nil, logstash_writer: nil, logger: nil)
    @logstash_server  = logstash_server
    @metrics_registry = metrics_registry
    @formatter        = formatter
    @logstash_writer  = logstash_writer
    @logger           = logger

    @op_mutex = Mutex.new
  end

  # Associate this Loggerstash with a Logger (or class of Loggers).
  #
  # A single Loggerstash instance can be associated with one or more Logger
  # objects, or all instances of Logger, by attaching the Loggerstash to the
  # other object (or class).  Attaching a Loggerstash means it can no longer
  # be configured (by the setter methods).
  #
  # @param obj [Object] the instance or class to attach this Loggerstash to.
  #   We won't check that you're attaching to an object or class that will
  #   benefit from the attachment; that's up to you to ensure.
  #
  def attach(obj)
    run_writer

    @op_mutex.synchronize do
      obj.instance_variable_set(:@logstash_writer, @logstash_writer)
      obj.instance_variable_set(:@loggerstash_formatter, @formatter)

      if obj.is_a?(Module)
        obj.prepend(Mixin)
      else
        obj.singleton_class.prepend(Mixin)
      end
    end
  end

  %i{formatter logger logstash_server metrics_registry}.each do |sym|
    define_method(:"#{sym}=") do |v|
      @op_mutex.synchronize do
        if @logstash_writer
          raise AlreadyRunningError,
                "Cannot change #{sym} once writer is running"
        end
        instance_variable_set(:"@#{sym}", v)
      end
    end
  end

  private

  # Do the needful to get the writer going.
  #
  def run_writer
    @op_mutex.synchronize do
      if @logstash_writer.nil?
        {}.tap do |opts|
          opts[:server_name] = @logstash_server
          if @metrics_registry
            opts[:metrics_registry] = @metrics_registry
          end
          if @logger
            opts[:logger] = @logger
          end

          @logstash_writer = LogstashWriter.new(**opts)
          @logstash_writer.start!
        end
      end
    end
  end

  # The methods needed to turn any Logger into a Loggerstash Logger.
  #
  module Mixin
    attr_writer :logstash_writer, :loggerstash_formatter

    private

    # Hooking into this specific method may seem... unorthodox, but
    # it seemingly has an extremely stable interface and is the most
    # appropriate place to inject ourselves.
    #
    def format_message(s, t, p, m)
      loggerstash_log_message(s, t, p, m)

      super
    end

    # Send a logger message to logstash.
    #
    def loggerstash_log_message(s, t, p, m)
      logstash_writer.send_event(loggerstash_formatter.call(s, t, p, m))
    end

    # The current formatter for logstash-destined messages.
    #
    def loggerstash_formatter
      @loggerstash_formatter ||= self.class.ancestors.find { |m| m.instance_variable_defined?(:@loggerstash_formatter) }.instance_variable_get(:@loggerstash_formatter) || default_loggerstash_formatter
    end

    # Find the relevant logstash_writer for this Logger.
    #
    # We're kinda reimplementing Ruby's method lookup logic here, but there's
    # no other way to store our object *somewhere* in the object + class
    # hierarchy and still be able to get at it from a module (class variables
    # don't like being accessed from modules).  This is necessary because you
    # can attach Loggerstash to the Logger class, not just to an instance.
    def logstash_writer
      @logstash_writer ||= self.class.ancestors.find { |m| m.instance_variable_defined?(:@logstash_writer) }.instance_variable_get(:@logstash_writer).tap do |ls|
        if ls.nil?
          #:nocov:
          raise RuntimeError,
                "Cannot find loggerstash instance.  CAN'T HAPPEN."
          #:nocov:
        end
      end
    end

    # Mangle the standard sev/time/prog/msg set into a logstash event.
    #
    # Caller information is a https://www.rubydoc.info/stdlib/core/Thread/Backtrace/Location
    def default_loggerstash_formatter
      ->(s, t, p, m) do
        caller = caller_locations.find { |loc| ! [__FILE__, logger_filename].include? loc.absolute_path }

        {
          "@timestamp": t.utc.strftime("%FT%T.%NZ"),
          "@metadata": { event_type: "loggerstash" },
          ecs: {
            version: "1.8"
          },
          message: m,
          log: {
            level: s.downcase,
            logger: "Loggerstash",
            origin: {
              base_function: caller.base_label, # not in ECS
              file: {
                line: caller.lineno,
                name: caller.absolute_path,
              },
              function: caller.label,
            },
          },
          host: {
            hostname: Socket.gethostname,
          },
          process: {
            pid: $$,
            thread: {
              id: Thread.current.object_id,
            },
          },
        }.tap do |ev|
          ev[:process][:name] = p if p
          ev[:process][:thread][:name] = Thread.current.name if Thread.current.name
        end
      end
    end

    # Identify the absolute path of the file that defines the Logger class.
    #
    def logger_filename
      @logger_filename ||= Logger.instance_method(:format_message).source_location.first
    end
  end
end
