module JobsHelper
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
