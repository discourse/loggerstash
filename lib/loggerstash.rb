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

  attr_writer :formatter

  def initialize(logstash_server:, metrics_registry: nil, formatter: nil)
    @logstash_server = logstash_server
    @metrics_registry = metrics_registry
    @formatter = formatter

    @op_mutex = Mutex.new
  end

  def attach(obj)
    @op_mutex.synchronize do
      obj.instance_variable_set(:@loggerstash, self)

      if obj.is_a?(Module)
        obj.prepend(Mixin)
      else
        obj.singleton_class.prepend(Mixin)
      end

      run_writer
    end
  end

  %i{logstash_server metrics_registry}.each do |sym|
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

  def log_message(s, t, p, m)
    @op_mutex.synchronize do
      if @logstash_writer.nil?
        #:nocov:
        run_writer
        #:nocov:
      end

      @logstash_writer.send_event((@formatter || default_formatter).call(s, t, p, m))
    end
  end
  private

  def run_writer
    unless @op_mutex.owned?
      #:nocov:
      raise RuntimeError,
            "Must call run_writer while holding @op_mutex"
      #:nocov:
    end

    if @logstash_writer.nil?
      {}.tap do |opts|
        opts[:server_name] = @logstash_server
        if @metrics_registry
          opts[:metrics_registry] = @metrics_registry
        end

        @logstash_writer = LogstashWriter.new(**opts)
        @logstash_writer.run
      end
    end
  end

  def default_formatter
    @default_formatter ||= ->(s, t, p, m) do
      {
        "@timestamp" => t.utc.strftime("%FT%T.%NZ"),
        message: m,
        severity: s.downcase,
      }.tap do |ev|
        ev[:progname] = p if p
      end
    end
  end

  module Mixin
    private

    # Hooking into this specific method may seem... unorthodox, but
    # it seemingly has an extremely stable interface and is the most
    # appropriate place to inject ourselves.
    def format_message(s, t, p, m)
      loggerstash.log_message(s, t, p, m)

      super
    end

    def loggerstash
      ([self] + self.class.ancestors).find { |m| m.instance_variable_defined?(:@loggerstash) }.instance_variable_get(:@loggerstash).tap do |ls|
        if ls.nil?
          #:nocov:
          raise RuntimeError,
                "Cannot find loggerstash instance.  CAN'T HAPPEN."
          #:nocov:
        end
      end
    end
  end
end
