module Debci

  # This class represents a single package. See Debci::Repository for how to
  # obtain one of these.

  class Package < Struct.new(:name, :repository)

    # Returns the architectures in which this package is available
    def architectures
      repository.architectures_for(self)
    end

    # Returns the suites in which this package is available
    def suites
      repository.suites_for(self)
    end

    # Returns a matrix of Debci::Status objects, where rows represent
    # architectures and columns represent suites:
    #
    #     [
    #       [ amd64_unstable , amd64_testing ],
    #       [ i386_unstable, i386_testing ],
    #     ]
    #
    # Each cell of the matrix contains a Debci::Status object.
    def status
      repository.status_for(self)
    end

    # Returns an array of Debci::Status objects that represent the test
    # history for this package
    def history(suite, architecture)
      repository.history_for(self, suite, architecture)
    end

    # Returns a list of Debci::Status objects that are newsworthy for this
    # package. The list is sorted with the most recent entries first and the
    # older entries last.
    def news
      repository.news_for(self)
    end

    # Returns an Array of statuses where this package is failing.
    def failures
      status.flatten.select { |p| p.status == :fail }
    end

    # Returns an Array of statuses where this package is failing or neutral.
    def fail_or_neutral
      status.flatten.select { |p| p.status == :fail or p.status == :neutral }
    end

    # Returns an Array of statuses where this package is temporarily failing. If
    def tmpfail
      status.flatten.select { |p| p.status == :tmpfail }
    end

    def to_s
      # :nodoc:
      "<Package #{name}>"
    end

    def to_str
      # :nodoc:
      name
    end

    def prefix
      name =~ /^((lib)?.)/
      $1
    end

    def blacklisted?
      Debci.blacklist.include?(self)
    end

  end

end
