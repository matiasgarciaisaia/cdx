class Aggregations
  def initialize
    @aggregations = Hash.new
    @last = @aggregations
  end

  def append fields, options={}
    if fields.first[:type] == :nested
      append_last count: {nested: {path: fields.first[:name]}}
    end

    fields.each do |field|
      append_last create_grouping_for(field)
    end
  end

  def to_hash
    @aggregations
  end

private

  def create_grouping_for field
    case field[:type]
    when :flat
      {
        count: {
          terms: {
            field: field[:name]
          }
        }
      }
    when :date
      format = case field[:interval]
        when "year"
          "yyyy"
        when "month"
          "yyyy-MM"
        when "week"
          "yyyy-'W'w"
        when "day"
          "yyyy-MM-dd"
        else
          raise "Invalid time interval."
       end
      {count: {date_histogram: {field: field[:name], interval: field[:interval], format: format}}}
    when :range
      {count: {range: {field: field[:name], ranges: convert_ranges_to_elastic_search(field[:ranges])}}}
    when :nested
      {
        count: {
          terms: {
            field: "#{field[:name]}.#{field[:sub_fields][:name]}"
          }
        }
      }
    else
      raise "Unsupported field type"
    end
  end

  def append_last field
    @last[:aggregations] = field
    @last = field[:count]
  end

  def convert_ranges_to_elastic_search(ranges)
    ranges.map do |range|
      {from: range[0], to: range[1]}
    end
  end
end
