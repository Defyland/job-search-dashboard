module JobsHelper
  # Values that mean "no restriction" for each control inside "Filtros avancados".
  ADVANCED_FILTER_DEFAULTS = {
    stack: [ "" ],
    source: [ "" ],
    contract_type: [ "", "all" ],
    match_strength: [ "", "all" ],
    title_language: [ "", "all" ],
    lifecycle_state: [ "", "active" ],
    recency: [ "" ],
    sort: [ "", "newest" ]
  }.freeze

  def advanced_filter_count(filters)
    ADVANCED_FILTER_DEFAULTS.count { |key, defaults| !defaults.include?(filters[key].to_s) }
  end

  def radar_seen_label(job_match)
    timestamp = job_match.first_seen_at || job_match.created_at
    return "Captura sem data" unless timestamp

    "Capturada em #{timestamp.in_time_zone.strftime("%d/%m %H:%M")}"
  end

  def publication_signal_label(job)
    if job.published_at.present?
      "Publicada em #{job.published_at.in_time_zone.strftime("%d/%m %H:%M")}"
    elsif job.posted_text.present?
      job.posted_text
    else
      "Publicacao sem data"
    end
  end
end
