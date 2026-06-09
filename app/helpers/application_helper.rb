module ApplicationHelper
  def submit_state_form_options(default_loading_text: "Processando...", data: {}, **options)
    options.merge(
      data: merge_submit_state_form_data(data, default_loading_text:)
    )
  end

  def submit_state_submit_options(loading_text:, data: {}, **options)
    options.merge(
      data: data.to_h.deep_dup.merge(submit_state_loading_text: loading_text)
    )
  end

  def submit_state_button_to_options(loading_text:, default_loading_text: nil, form: {}, data: {}, **options)
    effective_default_text = default_loading_text || loading_text
    button_options = submit_state_submit_options(loading_text:, data:, **options)
    button_options[:form] = submit_state_form_options(default_loading_text: effective_default_text, **form)
    button_options
  end

  def safe_external_url(url)
    uri = URI.parse(url.to_s)
    return unless uri.is_a?(URI::HTTP) && uri.host.present?

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

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

  def flash_role(type)
    type.to_sym == :alert ? "alert" : "status"
  end

  def flash_live_region(type)
    type.to_sym == :alert ? "assertive" : "polite"
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

  def match_label(match)
    match.match_strength == "strong" ? "Forte" : "Borderline"
  end

  def user_state_label(match)
    case match.user_state
    when "new_match" then "Nova"
    when "seen" then "Vista"
    when "applied" then "Aplicada"
    when "ignored" then "Ignorada"
    else match.user_state.humanize
    end
  end

  def lifecycle_label(job)
    job.lifecycle_state == "active" ? "Ativa" : "Expirada"
  end

  def contract_type_label(job)
    case job.contract_type
    when "clt" then "CLT"
    when "pj" then "PJ"
    when "clt_or_pj" then "CLT ou PJ"
    else "Sem sinal"
    end
  end

  def contract_type_tone(job)
    case job.contract_type
    when "clt" then :active
    when "pj" then :borderline
    when "clt_or_pj" then :strong
    else :expired
    end
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

  private
    def merge_submit_state_form_data(data, default_loading_text:)
      merged_data = data.to_h.deep_dup
      controllers = merged_data[:controller].to_s.split
      controllers << "submit-state"
      merged_data[:controller] = controllers.uniq.join(" ")
      merged_data[:submit_state_default_text_value] = default_loading_text
      merged_data
    end
end
