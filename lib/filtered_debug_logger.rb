require 'logger'

# Filter debug-level log entries on progname
#
# Whilst well-thought-out debug logs are fantastic at showing you the
# fine-level detail of your program's execution, they can sometimes be
# "too much of a good thing".  Excessively verbose debug logs can obscure
# the important debug info, and turning on debug logging on a busy service
# can quickly swamp all but the most overprovisioned of log aggregation
# systems.
#
# Hence, there's this little module.  Require it in your program, and then
# set `logger.permitted_prognames = ['some', 'array']` on whatever logger
# is likely to want some debug logging.  Then, whenever debug logging is
# enabled, only those calls to `logger.debug` which provide a progname exactly
# matching an entry in the list you provided will actually get logged.
#
module FilteredDebugLogger
  # Set the list of prognames to log debug messages for.
  #
  # @param l [Array<String>] the (exact) prognames to log debug-level messages
  #   for.  If it's not in this list, it doesn't get emitted, even if debug
  #   logging is enabled.
  #
  def permitted_prognames=(l)
    raise ArgumentError, "Must provide an array" unless l.is_a?(Array)

    @permitted_prognames = l
  end

  # Decorate Logger#add with our "reject by progname" logic.
  #
  def add(s, m = nil, p = nil)
    return if s == Logger::DEBUG && @permitted_prognames && !@permitted_prognames.include?(p)

    super
  end

  alias log add
end

Logger.prepend(FilteredDebugLogger)
