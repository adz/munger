begin
  require 'builder'
rescue LoadError
  require 'rubygems'
  require 'builder'
end

module Munger  #:nodoc:
  module Render  #:nodoc:
    class Html
    
      attr_reader :report, :classes
      
      def initialize(report, options = {})
        @report = report
        set_classes(options[:classes])
      end
      
      def set_classes(options = nil)
        options = {} if !options
        default = {:table => 'report-table'}
        @classes = default.merge(options)
      end
      
      def render
        x = Builder::XmlMarkup.new
        
        x.table(:class => @classes[:table]) do
          
          x.thead do
            x.tr do
              @report.columns.each do |column|
                x.th(:class => 'columnTitle') { x << @report.column_title(column) }
              end
            end
          end
          
          x.tbody do
            @report.process_data.each do |row|   
              
              row_attrs = {:class => row_css_classes(row).join(' ')}
              if row[:meta][:group_header]
                x.thead do
                  x.tr(row_attrs) do
                    header = @report.column_title(row[:meta][:group_name]) + ' : ' + row[:meta][:group_value].to_s
                    x.th(:colspan => @report.columns.size) { x << header }
                  end
                end
              else
                x.tr(row_attrs) do
                  @report.columns.each do |column|
                    cell_attrs = {:class => cell_css_classes(row, column).join(' ')}
                    x.td(cell_attrs) do
                      x << format_cell(@report, row, column).to_s
                    end
                  end
                end
              end
              
            end # each rows
            
          end # x.tbody
          
        end # x.table
        
      end
      
      def cycle(one, two)
        if @current == one
          @current = two
        else
          @current = one
        end
      end
      
      def valid?
        @report.is_a? Munger::Report
      end

      
      private

      # Should be done a bit more nicerly
      # - depends on @report.column_formatter hash
      # - is probably better on :meta of cell
      # - need way of distinguishing if it's just for HTML, etc...
      def format_cell(report, row, column)
        formatter, *args = *report.column_formatter(column)
        col_data = row[:data] #[column]
        
        if formatter && col_data[column]
          if formatter.class == Proc
            data = col_data.respond_to?(:data) ? col_data.data : col_data            
            formatter.call(data)
          elsif col_data[column].respond_to? formatter
            col_data[column].send(formatter, *args)
          elsif
            col_data[column].to_s
          end
        else
          col_data[column].to_s
        end        
      end
      
      def row_css_classes(row)
        classes = []
        classes << row[:meta][:row_styles]
        classes << 'group' + row[:meta][:group].to_s if row[:meta][:group]
        classes << cycle('even', 'odd')
        classes.compact!

        if row[:meta][:group_header]
          classes << 'groupHeader' + row[:meta][:group_header].to_s 
        end
        classes
      end
      
      def cell_css_classes(row, column)
        column_cell_styles = row[:meta][:cell_styles]
        return [] if column_cell_styles.blank?
        
        Item.ensure(column_cell_styles)[column] || []
      end
    end
  end
end