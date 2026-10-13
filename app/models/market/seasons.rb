# frozen_string_literal: true

# When a search peaks in the year, from its searches month by month
# ({"2026-03" => 880, …}): the month it peaks in and how far above the
# year's average, or nil when it barely moves (within 25%).
module Market::Seasons
  module_function

  def peak(months)
    values = months.to_h.transform_keys { it.to_s[5, 2].to_i }.select { |month, _| month.between?(1, 12) }
    return if values.size < 6

    by_month = values.group_by(&:first).transform_values { |pairs| pairs.sum(&:last).to_f / pairs.size }
    average = by_month.values.sum / by_month.size
    month, volume = by_month.max_by(&:last)
    return if average.zero? || volume < average * 1.25

    {"month" => month, "lift" => ((volume / average - 1) * 100).round}
  end

  def month_name(month) = Date::MONTHNAMES[month.to_i]

  # When to publish for a peak: two months ahead.
  def publish_by(peak) = peak && Date::MONTHNAMES[((peak["month"].to_i - 3) % 12) + 1]
end
