module Devmetrics
  module BulletLogParser
    Warning = Data.define(:type, :endpoint, :model_class, :associations, :fix_suggestion, :line_number, :call_stack)

    BLOCK_START = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\[WARN\]/

    def self.parse(content)
      blocks = content.split(BLOCK_START).map(&:strip).reject(&:empty?)
      blocks.filter_map { |block| parse_block(block) }
    end

    def self.parse_block(block)
      lines = block.lines.map(&:chomp)

      endpoint     = lines.find { |l| l.match?(/^(GET|POST|PUT|PATCH|DELETE|HEAD)\s+/) }&.strip
      type_line    = lines.find { |l| l.include?("eager loading detected") }
      model_line   = lines.find { |l| l.match?(/\w+ => \[/) }
      fix_line     = lines.find { |l| l.include?("Add to your query") || l.include?("Remove from your query") }

      return nil unless type_line && model_line

      type = type_line.strip.start_with?("USE") ? :add_eager_load : :remove_eager_load

      model_class  = model_line.match(/^\s*(\w+)\s*=>/)[1] rescue nil
      associations = model_line.match(/=>\s*(\[.+\])/)[1] rescue nil

      fix_suggestion = fix_line&.strip

      call_stack_start = lines.index { |l| l.strip == "Call stack" }
      call_stack = call_stack_start ? lines[(call_stack_start + 1)..].map(&:strip).reject(&:empty?) : []

      app_line = call_stack.find { |l| !l.include?("/gems/") && !l.include?("/ruby/") && l.match?(/\.rb:\d+/) }
      line_number = app_line&.match(/:(\d+):/)&.[](1)&.to_i

      Warning.new(
        type:          type,
        endpoint:      endpoint,
        model_class:   model_class,
        associations:  associations,
        fix_suggestion: fix_suggestion,
        line_number:   line_number,
        call_stack:    call_stack
      )
    end
    private_class_method :parse_block
  end
end
