# frozen_string_literal: true

require_relative './spec_helper'
require 'logger'

require 'loggerstash'

describe Loggerstash do
  let(:ls) { Loggerstash.new(logstash_server: "192.0.2.42:5151") }
  let(:mock_writer) { instance_double(LogstashWriter) }

  before :each do
    allow(LogstashWriter).to receive(:new).and_return(mock_writer)
    allow(mock_writer).to receive(:start!)
    allow(mock_writer).to receive(:send_event)
  end

  describe ".new" do
    it "explodes without a logstash_server" do
      expect { Loggerstash.new }.to raise_error(ArgumentError)
    end

    it "works given just a logstash_server" do
      expect { Loggerstash.new(logstash_server: "192.0.2.42:5151") }.to_not raise_error
    end

    it "accepts a metrics registry" do
      ls = Loggerstash.new(logstash_server: "speccy", metrics_registry: "registry")
      ls.attach(Class.new)

      expect(LogstashWriter).to have_received(:new).with(server_name: "speccy", metrics_registry: "registry")
    end

    it "accepts a formatter" do
      ls = Loggerstash.new(logstash_server: "speccy", formatter: ->(s, t, p, m) { { a: "a", b: "b" } })
      l = Logger.new("/dev/null")
      ls.attach(l)

      l.info("asdf") { "ohai" }

      expect(mock_writer).to have_received(:send_event).with(a: "a", b: "b")
    end

    it "accepts a logger" do
      ls = Loggerstash.new(logstash_server: "speccy", logger: logger = Logger.new("/dev/null"))

      expect(LogstashWriter).to receive(:new).with(server_name: "speccy", logger: logger)

      ls.attach(logger)
    end
  end

  describe "#attach" do
    it "attaches to a class" do
      klass = Class.new

      ls.attach(klass)

      expect(klass.ancestors.first).to eq(Loggerstash::Mixin)
    end

    it "attaches to an instance" do
      obj = Class.new.new

      ls.attach(obj)

      expect(obj.singleton_class.ancestors.first).to eq(Loggerstash::Mixin)
    end

    it "starts the logstash writer" do
      klass = Class.new

      ls.attach(klass)

      expect(LogstashWriter).to have_received(:new).with(server_name: "192.0.2.42:5151")
      expect(mock_writer).to have_received(:start!)
    end

    it "starts the logstash writer only once" do
      k1 = Class.new
      k2 = Class.new

      ls.attach(k1)
      ls.attach(k2)

      expect(LogstashWriter).to have_received(:new).with(server_name: "192.0.2.42:5151").exactly(:once)
      expect(mock_writer).to have_received(:start!).exactly(:once)
    end
  end

  describe "#logstash_server=" do
    it "sets the logstash server for the writer to use" do
      ls.logstash_server = "192.0.2.42:5151"
      ls.attach(Class.new)

      expect(LogstashWriter).to have_received(:new).with(server_name: "192.0.2.42:5151")
    end

    it "raises an exception if called after attachment" do
      ls.attach(Class.new)

      expect { ls.logstash_server = "speccy" }.to raise_error(Loggerstash::AlreadyRunningError)
    end
  end

  describe "#metrics_registry=" do
    let(:mock_registry) { instance_double(Prometheus::Client::Registry) }

    it "sets a metrics registry for the writer to use" do
      ls.metrics_registry = mock_registry

      ls.attach(Class.new)

      expect(LogstashWriter).to have_received(:new).with(server_name: "192.0.2.42:5151", metrics_registry: mock_registry)
    end

    it "raises an exception if called after attachment" do
      ls.attach(Class.new)

      expect { ls.metrics_registry = mock_registry }.to raise_error(Loggerstash::AlreadyRunningError)
    end
  end

  describe "#formatter=" do
    it "updates the formatter" do
      ls.formatter = ->(s, t, p, m) { { m: "utf" } }
      l = Logger.new("/dev/null")
      ls.attach(l)

      l.info("asdf") { "ohai" }

      expect(mock_writer).to have_received(:send_event).with(m: "utf")
    end

    it "raises an exception if called after attachment" do
      ls.attach(Class.new)

      expect { ls.formatter = ->(s, t, p, m) { { m: "utfwr" } } }.to raise_error(Loggerstash::AlreadyRunningError)
    end
  end

  describe "logging" do
    it "writes a log event" do
      allow(Time).to receive(:now).and_return(Time.strptime("1234567890.987654321Z", "%s.%N%Z"))
      l = Logger.new("/dev/null")
      ls.attach(l)

      l.info("asdf") { "ohai" }

      expect(mock_writer)
        .to have_received(:send_event)
        .with(
          "@timestamp":  "2009-02-13T23:31:30.987654321Z",
          "@metadata":   {
            event_type: "loggerstash",
          },
          log: {
            level: "info",
            logger: "Loggerstash",
            origin: {
              base_function: "<top (required)>",
              file: {
                line: __LINE__ - 15,
                name: __FILE__,
              },
              function: "block (3 levels) in <top (required)>",
            },
          },
          host: {
            hostname: instance_of(String),
          },
          message:       "ohai",
          process: {
            name: "asdf",
            pid: kind_of(Numeric),
            thread: {
              id: kind_of(Numeric),
            },
          },
        )
    end

    it "accepts a lack of progname" do
      allow(Time).to receive(:now).and_return(Time.strptime("1234567890.987654321Z", "%s.%N%Z"))
      l = Logger.new("/dev/null")
      ls.attach(l)

      l.info("ohai")

      expect(mock_writer)
        .to have_received(:send_event)
        .with(
          "@timestamp":  "2009-02-13T23:31:30.987654321Z",
          "@metadata":   {
            event_type: "loggerstash",
          },
          log: {
            level: "info",
            logger: "Loggerstash",
            origin: {
              base_function: "<top (required)>",
              file: {
                line: __LINE__ - 15,
                name: __FILE__,
              },
              function: "block (3 levels) in <top (required)>",
            },
          },
          host: {
            hostname: instance_of(String),
          },
          message:       "ohai",
          process: {
            pid: kind_of(Numeric),
            thread: {
              id: kind_of(Numeric),
            },
          },
        )
    end

    it "duplicates the message to the original I/O object" do
      l = Logger.new(sio = StringIO.new)
      ls.attach(l)

      allow(mock_writer).to receive(:send_event)
      l.info("asdf") { "ohai" }

      expect(sio.string).to match(/asdf.*ohai/)
    end

   context "when attached to a class" do
     let(:klass) { Class.new(Logger) }

     it "finds the writer and writes to it" do
       ls.attach(klass)

       l = klass.new("/dev/null")

       l.info("ohai!")

       expect(mock_writer).to have_received(:send_event)
     end
   end
  end
end
