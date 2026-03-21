module Devmetrics
  class LogWriter
    LOG_BASE = -> { Rails.root.join("log", "devmetrics", "runs") }

    def self.open(run_id, file_key)
      dir = LOG_BASE.call.join(run_id.to_s)
      FileUtils.mkdir_p(dir)
      new(dir.join("#{file_key}.log"))
    end

    def initialize(path)
      @path = path
      @file = File.open(path, "w")
    end

    def write(line)
      @file.puts(line)
      @file.flush
    end

    def close
      @file.close
    end

    def path
      @path.to_s
    end
  end
end
