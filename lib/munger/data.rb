module Munger #:nodoc:
  
  # this class is a data munger
  #  it takes raw data (arrays of hashes, basically) 
  #  and can manipulate it in various interesting ways
  class Data
    
    attr_accessor :data
    
    # will accept active record collection or array of hashes
    def initialize(options = {})
      @data = options[:data] if options[:data]
      yield self if block_given?
    end
    
    def <<(data)
      add_data(data)
    end
    
    def add_data(data)
      if @data
        @data = @data + data 
      else
        @data = data
      end
      @data
    end
    

    #--
    # NOTE:
    # The name seems redundant; why:
    #   Munger::Data.load_data(data)
    # and not:
    #   Munger::Data.load(data)
    #++
    def self.load_data(data, options = {})
      Data.new(:data => data)
    end
    
    def columns
      @columns ||= clean_data(@data.first).to_hash.keys
    rescue
      puts clean_data(@data.first).to_hash.inspect
    end
    
    # :default:	The default value to use for the column in existing rows. 
    #           Set to nil if not specified.
    # if a block is passed, you can set the values manually
    def add_column(names, options = {})
      default = options[:default] || nil
      @data.each_with_index do |row, index|
        if block_given?
          col_data = yield Item.ensure(row)
        else
          col_data = default
        end
        
        if names.is_a? Array
          names.each_with_index do |col, i|
            row[col] = col_data[i]
          end
        else
          row[names] = col_data
        end
        @data[index] = clean_data(row)
      end
    end
    alias :add_columns :add_column
    alias :transform_column :add_column
    alias :transform_columns :add_column
    
    
    # Merge another data into this one 
    # based on the common merge_column(s)
    def merge_data(data_to_append, merge_columns)
      merge_columns = Data.array(merge_columns)
      new_cols = data_to_append.columns - merge_columns

      add_columns(new_cols) do |original_row|
        row_to_append = data_to_append.data.detect{|r|
          r.to_hash.values_at(*merge_columns) == original_row.to_hash.values_at(*merge_columns)
        }
        (row_to_append || {}).to_hash.values_at(*new_cols)
      end
    end

    def clean_data(hash_or_ar)
      if hash_or_ar.is_a? Hash
        return Item.ensure(hash_or_ar)
      elsif hash_or_ar.respond_to? :attributes
        return Item.ensure(hash_or_ar.attributes)
      end
      hash_or_ar
    end
        
    def filter_rows
      new_data = []
      
      @data.each do |row|
        row = Item.ensure(row)
        if (yield row)
          new_data << row
        end
      end
      
      @data = new_data
    end
    
    class AggregateGrouping      
      def initialize(group_cols, cols)
        @group_cols = Data.array(group_cols)
        @cols = Data.array(cols)
        @aggregates = {}
      end
      
      def <<(row)
        @aggregates[key_for(row)] ||= Aggregate.new(@cols)
        @aggregates[key_for(row)] << row
      end
      
      def each
        @aggregates.each do |key, aggregate|
          yield key, aggregate
        end
      end
      
      private
      def key_for(row) 
        @group_cols.map{|col| row[col] }
      end
    end
    
    class Aggregate
      attr_accessor :row, :count, :cells
      
      def initialize(cols)
        @cols = cols
        
        @cells = {}
        @cols.each do |col|
          @cells[col] = []
        end
        @row = {}  # last hit row
        @count = 0
      end
      
      def <<(row)
        @row = row  # wipes out anything from before!
        @count += 1
        @cols.each do |col|
          @cells[col] << row[col]
        end
      end
      
      def sum_of(col)
        @cells[col].inject { |sum, a| sum + a }
      end
      
      def average_of(col)
        sum_of(col) / @count
      end
    end
    
    # Group the data like sql
    # 
    # group_cols Which columns to group on
    # agg_hash   A hash of aggregate functions to columns.  This format:
    #   {aggregate_type => cols, ...}
    #   
    # Note:
    #  - On aggregate_type 
    #    - It can be a symbol, or an array [:prefix, proc]
    #    - It is prepended to new columns for generated aggregate values
    # 
    #  - Field values for non-grouped columns will be the last row iterated on
    #  
    # Returns columns of new data
    def group(group_cols, agg_hash = {})
      
      agg_columns = agg_hash.values.flatten.uniq.compact
      aggregate_group = AggregateGrouping.new(group_cols, agg_columns)
      
      # Build aggregate into aggregate_group for each row
      @data.each do |row|
        aggregate_group << row       
      end
            
      new_data = []
      new_keys = []
      
      aggregate_group.each do |group_values, aggregate|
        new_row = aggregate.row
        
        agg_hash.each do |key, columns|
          
          Data.array(columns).each do |col|  # column name
            
            newcol = ''
            
            # If aggregates given like this:
            #   {[:prefix, lambda{|values| does_something_to(values)] => [:field_one, :field_two], ...}
            if key.is_a?(Array) && key[1].is_a?(Proc)
              newcol = key[0].to_s + '_' + col.to_s
              new_row[newcol] = key[1].call(aggregate.cells[col])
              
            # Else, expect:
            #   {:sum => [:field_one, :field_two], ... }
            else
              newcol = key.to_s + '_' + col.to_s
              new_row[newcol] = 
                case key
                when :average then aggregate.average_of(col)
                when :count then aggregate.count
                else            
                  aggregate.sum_of(col)
                end
            end
            
            new_keys << newcol            
          end
        end
        
        new_data << Item.ensure(new_row)        
      end    
      
      @data = new_data
      new_keys.compact
    end
    
    def pivot(columns, rows, value, aggregation = :sum, column_lambda = nil)
      
      # keys: row_key  which is values in the row
      # 
      # 
      data_hash = {}     
      @data.each do |row|
        column_key = Data.array(columns).map { |rk| row[rk] }
        row_key = Data.array(rows).map { |rk| row[rk] }
        
        data_hash[row_key] ||= {}
        data_hash[row_key][column_key] ||= {:sum => 0, :data => {}, :count => 0}
        
        focus = data_hash[row_key][column_key]
        focus[:data] = clean_data(row)
        focus[:count] += 1
        focus[:sum] += row[value]
      end
      
      new_data = []
      new_keys = []
      
      data_hash.each do |row_key, row_hash|
        new_row = {}
        
        row_index = 0
        row_hash.each do |column_key, row_data|
          row_index += 1
          column_key.each do |ckey|
            
            column_title = column_lambda ? column_lambda.call(row_data[:data], row_index) : ckey
            new_keys << column_title
            
            new_row.merge!(row_data[:data])
            new_row[column_title] = 
              case aggregation
              when :average
                (row_data[:sum] / row_data[:count])
              when :count
                row_data[:count]
              else            
                row_data[:sum]
              end
          end
        end
        
        new_data << Item.ensure(new_row)
      end
      
      @data = new_data
      
      new_keys  # TODO: why not return indexed?
    end
    
    def self.array(string_or_array)
      if string_or_array.is_a? Array
        return string_or_array
      else
        return [string_or_array]
      end
    end
    
    def size
      @data.size
    end
    alias :length :size
    
    def valid?
      if ((@data.size > 0) &&
        (@data.respond_to? :each_with_index) &&
        (@data.first.respond_to?(:keys) || 
         @data.first.respond_to?(:attributes) || 
         @data.first.is_a?(Munger::Item))) &&
        (!@data.first.is_a? String)
        return true
      else
        return false
      end
    rescue
      false
    end

    # cols is an array of column names, if given, the nested arrays are built in this order
    def to_a(cols=nil)
      array = []
      cols ||= self.columns
      @data.each do |row|
        array << cols.inject([]){ |a,col| a << row[col] }
      end
      array
    end
    
  end
  
end

