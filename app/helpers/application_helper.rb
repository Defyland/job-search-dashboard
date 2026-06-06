module ApplicationHelper
  def flash_class(type)
    case type.to_sym
    when :notice
      "border-emerald-400/30 bg-emerald-500/10 text-emerald-100"
    when :alert
      "border-rose-400/30 bg-rose-500/10 text-rose-100"
    else
      "border-slate-400/30 bg-slate-500/10 text-slate-100"
    end
  end

  def tone_class(tone)
    case tone.to_sym
    when :strong
      "bg-sky-400/15 text-sky-100 ring-sky-300/30"
    when :borderline
      "bg-amber-400/15 text-amber-100 ring-amber-300/30"
    when :active
      "bg-emerald-400/15 text-emerald-100 ring-emerald-300/30"
    when :expired
      "bg-slate-400/15 text-slate-100 ring-slate-300/30"
    when :applied
      "bg-fuchsia-400/15 text-fuchsia-100 ring-fuchsia-300/30"
    when :ignored
      "bg-zinc-400/15 text-zinc-100 ring-zinc-300/30"
    else
      "bg-slate-400/15 text-slate-100 ring-slate-300/30"
    end
  end

  def pagination_window(current_page, total_pages)
    ((current_page - 2)..(current_page + 2)).select { |page| page.between?(1, total_pages) }
  end

  def match_label(job)
    job.match_strength == "strong" ? "Forte" : "Borderline"
  end

  def user_state_label(job)
    case job.user_state
    when "new_match" then "Nova"
    when "seen" then "Vista"
    when "applied" then "Aplicada"
    when "ignored" then "Ignorada"
    else job.user_state.humanize
    end
  end

  def lifecycle_label(job)
    job.lifecycle_state == "active" ? "Ativa" : "Expirada"
  end

  def run_status_label(search_run)
    case search_run.status
    when "succeeded" then "Concluida"
    when "failed" then "Falhou"
    when "partial" then "Parcial"
    when "running" then "Rodando"
    else search_run.status.humanize
    end
  end

  def source_kind_label(source)
    case source.source_kind
    when "ats" then "ATS"
    when "platform" then "Plataforma"
    when "company" then "Empresa"
    when "aggregator" then "Agregador"
    else source.source_kind.humanize
    end
  end

  def source_scan_status_label(source_scan)
    case source_scan.status
    when "succeeded" then "Concluida"
    when "failed" then "Falhou"
    when "partial" then "Parcial"
    when "running" then "Rodando"
    when "exhausted" then "Esgotada"
    else source_scan.status.humanize
    end
  end

  def source_scan_tone(source_scan)
    case source_scan.status
    when "failed"
      :expired
    when "partial"
      :borderline
    else
      :active
    end
  end
end
