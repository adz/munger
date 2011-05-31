module Munger #:nodoc:
  module Render #:nodoc:
    class CSV #:nodoc:
    
      attr_reader :report
      
      def initialize(report)
        @report = report
      end
      
      def render
        output = []

        # header
        output << @report.columns.collect { |col| quote(@report.column_title(col)) }.join(',')
        
        # body
        @report.process_data.each do |row|
          output << @report.columns.collect { |col| quote(row[:data][col]) }.join(',')
        end
        
        output.join("\n")
      end
      
      def valid?
        @report.is_a? Munger::Report
      end
      
      private
      
      # quote data if it contains a comma
      def quote(data)
        data.to_s.include?(',') ? "\"#{data}\"" : "#{data}"
      end
    end
  end
end