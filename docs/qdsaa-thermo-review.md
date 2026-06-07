Escopo analisado:
- app Rails 8 `/Users/allanflavio/Documents/projects/PERSONAL/backend-challenges/job-search-dashboard`
- objetivo auditado: evoluir o dashboard para sair do motor principal em Codex e abrir descoberta deterministica no Rails, mantendo Codex como fallback estreito para fontes bloqueadas, rate-limited ou instaveis para worker nativo
- superficies revisadas: autenticacao, ingestao, dedupe, filtros/paginacao, historico de runs, source scans, discovered jobs, worker Solid Queue e configuracao de deploy

Verificacao executada:
- `bin/rails db:migrate`: schema atualizado com `SourceScan` e `DiscoveredJob`
- `bin/rails test`: 59 testes, 221 assertions, sem falhas
- `bin/rubocop`: 105 arquivos inspecionados, sem offenses
- `bin/brakeman -q -w2`: 0 warnings
- `bundle exec ruby -rfugit -e 'Fugit.parse("every day at 11:30 UTC").next_time'`: parse valido, proxima execucao em `08:30 -03:00`
- automacao `daily-senior-ruby-react-job-search` removida do app; o heartbeat legado nao esta mais presente em `/Users/allanflavio/.codex/automations`
- novo contrato de fallback: `JobSource` agora registra `codex_fallback_enabled`, `codex_fallback_reason` e `last_codex_fallback_at`, e a API `GET /api/v1/codex_fallback_sources` expoe apenas as fontes que o Codex deve cobrir de forma assistida
- smoke local do adapter `Remotar`: `18` candidatos aderentes nas primeiras `4` paginas, com links diretos para `Gupy` e `Inhire`
- smoke local do adapter `Workable`: `0` matches fortes nas primeiras `10` paginas recentes, o que sugere baixo volume atual para o nicho monitorado
- smoke local do adapter `Sólides`: `3` borderline e `0` strong em `20d` com as queries padrao `react`, `react native`, `ruby` e `rails`; a integracao publica esta funcional, mas o indice atual da fonte parece entregar mais titulos senior genericos do que titulos com stack explicita
- smoke local do adapter `Teamtailor`: `0` candidatos em `20d` no board publico `career.teamtailor.com`; a integracao de paginação/extração ficou funcional, mas o board atual nao expõe titulos aderentes ao recorte monitorado
- smoke local do adapter `SmartRecruiters`: `0` strong, `0` borderline e `3` rejected em `20d` para `company_identifier=smartrecruiters`; a API oficial respondeu bem, mas o board atual trouxe Python e frontend generico fora do foco estrito do radar
- investigacao publica de `Coodesh`:
  - `https://coodesh.com/sitemaps/jobs.xml` expõe a lista publica de vagas ativas e evita depender de API privada ou paginação opaca
  - cada detalhe `https://coodesh.com/jobs/<slug>` carrega um payload SSR em `self.__next_f.push(...)` com `title`, `company`, `publish_date`, `created`, `skills`, `home_office_formatted`, `status_formatted` e `external_url`
  - smoke local do adapter `Coodesh`: `0` candidatos no recorte Ruby/React senior em `20d`; a integracao esta saudavel, mas o inventario atual da fonte nao trouxe titulos aderentes ao radar
- investigacao publica de `Trampos`:
  - `https://trampos.co/api/v2/opportunities` expõe feed paginado publico com `pagination.total_pages`, `published_at`, empresa e metadata suficiente para corte por janela
  - `https://trampos.co/oportunidades/:id` e `GET /api/v2/opportunities/:id` expõem o detalhe canonico da vaga, incluindo `url`, `apply_url`, `apply_method`, `home_office` e corpo completo
  - a busca por termo no endpoint (`tr=react`, `tr=ruby`, `tr=rails`) nao trouxe valor operacional confiavel; o caminho correto foi varrer o feed cronologico global e filtrar no backend
  - smoke local do adapter `Trampos`: `19` paginas varridas em `20d`, `0` strong, `0` borderline e `1` rejected; a integracao esta saudavel, mas o feed atual quase nao tem titulo tecnico aderente ao recorte Ruby/React senior
- smoke local dos novos adapters ATS:
  - `Recrutei` com URL publica real `maxxi/145107`: `1` strong em `20d`, extraido do HTML atual com link direto em `talent.recrutei.com.br`; o mesmo board `maxxi/vacancies` retornou `0` resultados por SSR, o que confirmou a necessidade do fallback por URLs ja conhecidas
  - `Inhire` com career pages `yandeh`, `deal`, `mb`, `lighthouseit`, `matera`, `dotgroup`, `inco` e `casacred`: `2` strong e `7` rejected em `20d`; os matches fortes vieram da `Lighthouse`
  - `Lever` com boards `ciandt`, `jobgether`, `decilegroup` e `toptal`: depois do prefilter por politica completa no payload do board, o smoke atual caiu para `33` strong, `1` borderline e `0` rejected materializados em `20d`; antes disso o mesmo recorte gerava `261` rejeicoes estruturais sem ganho de cobertura
  - `Greenhouse` com boards `rdsourcing` e `fueledcareers`: `2` strong, `2` borderline e `1` rejected em `20d`
  - `Ashby` com boards `ruby-labs` e `Skydropx`: `0` matches fortes na janela e `3` rejected
- investigacao de fontes restantes:
  - `APInfo` permaneceu fora do worker nativo porque o endpoint publico de busca respondeu com rate-limit temporario; a fonte agora fica marcada como Codex fallback
  - `RubyOnRemote` permaneceu fora do worker nativo porque as paginas publicas responderam com challenge Cloudflare para o perfil de cliente usado pelo Rails; a fonte agora fica marcada como Codex fallback
- revisao estatica dos adapters `Gupy`, `Sólides`, `Recrutei`, `Inhire`, `Lever`, `Greenhouse`, `Ashby`, `Teamtailor`, `SmartRecruiters`, `ProgramaThor`, `Remotar`, `Workable`, do `JobDiscovery::Orchestrator` e da extracao reutilizavel `JobIngestions::Recorder`
- validacao em producao no Railway:
  - deploy novo do `web` e `worker` com `bin/predeploy`
  - healthcheck `GET /up` verde no dominio publico
  - trigger autenticado de `POST /search_runs`
  - `DiscoverJobsRunJob` executado em producao em ~43s no `Run #7`
  - `Run #7` confirmou scans nativos bem-sucedidos de `Gupy`, `Lever`, `Greenhouse`, `Ashby`, `ProgramaThor`, `Remotar` e `Workable`
  - `Run #7` mostrou impacto real no inbox: `Lever` com `295` candidatos vistos e `34` aceitos; `Greenhouse` com `5` candidatos vistos e `4` aceitos
  - logs do `worker` apos o deploy mostram o `Scheduler` carregando `["clear_solid_queue_finished_jobs", "daily_discovery_run", "expire_stale_jobs"]`
  - `dashboard:seed_sources` em producao agora materializa `settings` curados para fontes antes vazias; isso ficou visivel nas telas de edicao de `Gupy`, `Lever`, `Greenhouse`, `Ashby` e `Inhire`
  - `Run #10` validou efeito operacional dos seeds em producao: backfill source-scoped de `Inhire` terminou `Concluida`, com `10` paginas, `22` candidatos vistos, `7` aceitas e `15` rejeitadas; a fonte deixou de ficar zerada no catalogo
  - a tela `Fontes` em producao agora exibe o ultimo scan por fonte com link para o run, timestamp e contadores; a linha de `Inhire` mostra `Run #10`, `Paginas: 10`, `Candidatos: 22`, `Aceitas: 7` e `Rejeitadas: 15`
  - `Recrutei` e `SmartRecruiters` tambem passaram a receber seeds curados no deploy; a tela de edicao mostra `vacancy_urls/company_labels` para `Recrutei` e `company_identifiers` para `SmartRecruiters`
  - `Run #11` validou efeito operacional de `Recrutei` em producao: backfill source-scoped terminou `Concluida`, com `1` pagina, `1` candidato visto, `1` aceita e `0` rejeitadas
- validacao operacional de admin:
  - tela de fontes agora permite editar `settings` JSON, prioridade, janela e flags de participacao, sem cirurgia manual no banco
  - o dashboard agora consegue disparar backfill por fonte especifica, entao editar `settings` e validar um adapter deixou de exigir um run global do catalogo inteiro

Assumptions:
- o app continua pessoal e privado; login unico/pequena administracao continuam suficientes
- a descoberta ampla ainda nao esta 100% no Rails; a revisao considera o primeiro slice deterministicamente implementado
- candidatura automatica continua fora de escopo

Q: Requisitos questionados
- Mantidos:
  - dashboard privado autenticado
  - persistencia duravel das vagas
  - links diretos de candidatura
  - filtros, ordenacao e paginacao
  - status manual por vaga
  - historico de runs
  - ingestao segura por token
  - deploy em Railway com `web` e `worker`
  - backfill deterministico no Rails com rastreabilidade por fonte
- Alterados:
  - o sistema agora tem dois caminhos validos: `Codex -> ingestao` e `Rails adapters -> source scans -> inbox`
  - esse desenho foi estreitado: Rails e dono diario/canonico; Codex so atua em fontes marcadas como fallback ou em descoberta complementar pontual
- Suspeitos/deletados:
  - thread como memoria canonica
  - `jobs.json` como banco
  - Netlify/site estatico como produto final
  - depender de prompt conversacional para provar cobertura por fonte
  - componentes gerados do Rails sem responsabilidade no produto

D: Delecoes propostas
- Sem finding P1 aberto de delecao estrutural obrigatoria no estado atual.
- Delecoes aplicadas nesta etapa:
  - duplicacao de regra de upsert entre ingestao externa e futura descoberta Rails; isso foi colapsado em `JobIngestions::Recorder`

S: Simplificar/Otimizar
- Sem finding P1 aberto depois dos ajustes desta rodada.
- Ajustes estruturais feitos nesta etapa:
  - `JobSource` deixou de ser apenas catalogo passivo e passou a carregar `adapter_key`, `supports_backfill` e janela padrao de scan
  - `SourceScan` e `DiscoveredJob` adicionaram memoria operacional de cobertura, algo que nao existia no fluxo anterior
  - a politica de exclusao e match saiu da prompt e entrou no backend (`JobDiscovery::Policy`)
  - os adapters ATS agora podem redescobrir board slugs, tokens e career pages a partir das URLs de vagas ja persistidas, usando o proprio banco como memoria operacional
  - `Gupy` agora respeita a janela temporal quando a fonte expõe `datePosted`
  - `Gupy` deixou de depender apenas de jobs ja associados a `JobSource=gupy`; agora ele consegue minerar boards vistos por outras fontes, como `Remotar`
  - `Sólides` saiu de `manual_only`; o adapter usa o endpoint publico `portal-vacancies-new/`, quebra a paginação quando a janela temporal esgota e valida a vaga na pagina publica antes de aceitar o link direto de candidatura
  - `Inhire` ganhou descoberta publica em duas etapas (`tenants/public/resolve` -> `job-posts/public/pages`) e usa `X-Tenant` no backend, em vez de depender da SPA
  - `Lever`, `Greenhouse` e `Ashby` sairam de `manual_only` e ganharam adapters nativos
  - cada scan por fonte agora roda com transacao propria para evitar contador agregado adiantado em rollback
  - `Remotar` passou a funcionar como discovery hub para ATSs externos porque a API publica entrega `externalLink`
  - `Workable` entrou por API publica global, mas o valor real no nicho atual parece menor que o de `Remotar`
  - `Teamtailor` saiu do gap principal; o adapter usa boards `*.teamtailor.com/jobs`, paginação por `show_more` e validacao da propria pagina da vaga antes de aceitar a candidatura na URL canonica
  - `SmartRecruiters` saiu do backlog de ATS principais; o adapter usa a Posting API oficial por `company_identifier`, pagina em `limit/offset` e evita depender das paginas publicas com challenge JS
  - `Trampos` saiu de `manual_only`; o adapter usa a API publica `api/v2/opportunities`, pagina cronologicamente ate a janela expirar e, quando a candidatura é interna (`apply_url` vazio), usa a propria URL canonica da vaga como link aplicavel
  - `Coodesh` saiu de `manual_only`; o adapter usa o sitemap publico de jobs e extrai o payload SSR de cada detalhe, com fallback do link canônico quando a candidatura é interna a `coodesh.com`
  - `Lever` deixou de materializar rejeicoes estruturais obvias; o adapter agora aplica a politica completa ainda no payload do board e so materializa matches aceitos, reduzindo drasticamente ruido operacional sem perder os matches fortes observados no smoke
  - o contrato entre catalogo e discovery nativa ficou mais forte: `JobSource` nao aceita mais `supports_backfill=true` com `adapter_key` fora do registry, e o `Orchestrator` deixou de pular silenciosamente fontes backfillable quebradas; agora ele cria `SourceScan failed` explicito para qualquer registro legado ou manual que escape dessa validacao
  - o deploy Railway deixou de falhar por `ActiveRecord::ConcurrentMigrationError` quando `web` e `worker` sobem juntos; `bin/predeploy` agora faz retry de `db:prepare`
  - o status final de `SearchRun` na descoberta Rails nao trata mais rejeicoes normais como `partial`; agora `partial` significa apenas falha real de alguma fonte
  - a descoberta diaria nativa agora existe no proprio Rails via `config/recurring.yml`, com `DiscoverJobsRunJob(window_days: 1, trigger_source: "cron")` agendado para `08:30 BRT`
  - a administracao de fontes deixou de ser read-only; como varios adapters dependem de `JobSource.settings`, editar `board_urls`, `company_labels`, `company_slugs`, `search_queries` e `max_pages` pela UI agora fecha um gap operacional real do desenho
  - o disparo manual tambem deixou de ser tudo-ou-nada; `source_slug` agora permite rodar discovery de uma unica fonte, o que reduz feedback loop e custo operacional quando se ajusta um adapter
  - `dashboard:seed_sources` deixou de sobrescrever configuracao manual existente; o seed agora so cria fontes novas e preenche lacunas de catalogo, preservando overrides operacionais feitos pela UI para `adapter_key`, `priority`, `enabled`, `supports_backfill`, `scan_window_days`, `host`, `base_url` e `settings`
  - o catalogo default agora tambem carrega seeds curados para fontes que antes dependiam de memoria previa ou cirurgia manual em `settings`; no estado atual isso bootstrapa `Gupy`, `Recrutei`, `Lever`, `Greenhouse`, `Ashby`, `Inhire` e `SmartRecruiters` sem sobrescrever customizacao do operador
  - o catalogo de fontes deixou de ser apenas tela de configuracao; agora ele tambem mostra a ultima verdade operacional por fonte, o que encurta o diagnostico de cobertura sem abrir cada `SearchRun`
  - a UI de fontes deixou de aceitar `adapter_key` como texto livre; a edicao agora oferece apenas o registry suportado mais `manual_only`, preservando valores legados invalidos apenas para correcao explicita do operador
  - fontes bloqueadas deixaram de ficar escondidas em comentario/documentacao; o catalogo agora mostra explicitamente se a fonte participa do fallback Codex, por que participa e quando uma ingestao Codex dela aconteceu pela ultima vez
  - a automacao Codex deixou de precisar manter uma lista paralela de fontes; ela pode buscar `GET /api/v1/codex_fallback_sources` e postar o resultado validado de volta no endpoint de ingestao existente
- Risco residual real:
  - o slice Rails ainda nao cobre todo o catalogo, apesar de agora incluir `Gupy`, `Sólides`, `Recrutei`, `Inhire`, `Lever`, `Greenhouse`, `Ashby`, `Teamtailor`, `SmartRecruiters`, `ProgramaThor`, `Remotar`, `Workable`, `Trampos` e `Coodesh`
  - `Recrutei` ja consegue revalidar e redescobrir a partir de URLs publicas conhecidas, mas o board `/<label>/vacancies` nao expõe uma listagem SSR confiavel hoje; por isso a cobertura nativa dessa fonte ainda depende de URLs ja vistas ou `settings.company_labels`/`settings.vacancy_urls`
  - `Sólides` usa uma busca publica orientada por termo, nao um board oficial por empresa; a cobertura atual depende da qualidade das queries configuradas e hoje a fonte parece produzir pouco titulo senior com stack explicita, apesar de a integracao estar saudavel
  - `Teamtailor` hoje cobre boards `*.teamtailor.com`, mas nao consegue redescobrir boards servidos por dominios customizados sem o sufixo `teamtailor.com`
  - `SmartRecruiters` depende de `company_identifiers` seedados via URL conhecida ou tela de fontes; sem isso, a API oficial nao oferece um indice global publico por empresa
  - `SmartRecruiters` nao valida a pagina HTML publica porque ela esta protegida por challenge JS; a confianca operacional fica ancorada no `active` + `applyUrl` retornados pela API oficial
  - `Trampos` hoje nao oferece busca por stack confiavel na API publica; a cobertura depende do scan cronologico global e da filtragem backend por titulo/descricao
  - `Coodesh` hoje depende do payload SSR `self.__next_f.push(...)` embutido na pagina da vaga; o sitemap publico é estavel, mas qualquer mudanca forte na serializacao React Server Components exigira ajuste do parser
  - `ProgramaThor` nao expõe recencia forte nas paginas usadas; o adapter ainda depende de ordem do board e limite de paginas como fallback
  - `APInfo` expõe busca publica por formulario, mas o endpoint respondeu com `Erro : 178.076-H - Seu limite de consultas esta temporariamente esgotado` no ambiente de desenvolvimento durante a investigacao; ela agora fica em Codex fallback em vez de ganhar um adapter nativo fragil
  - `RubyOnRemote` respondeu `403` com challenge Cloudflare para `Net::HTTP`, `urllib` e user-agents de navegador nos endpoints principais e no sitemap; enquanto esse bloqueio existir para o mesmo perfil de cliente do worker, ela fica em Codex fallback
  - o endpoint de ingestao Codex continua complementar; a diferenca agora e que existe um contrato explicito de fontes fallback e observabilidade de `last_codex_fallback_at`

A: Acelerar ciclo de feedback
- O ciclo local esta curto e suficiente:
  - `bin/rails test`
  - `bin/rubocop`
  - `bin/brakeman -q -w2`
- O novo ciclo de descoberta ganhou um caminho operacional simples:
  - botao manual em `Runs`
  - botao manual por fonte em `Fontes`
  - `bin/rails "dashboard:discover[20]"`
  - jobs de background via `DiscoverJobsRunJob`

A: Automatizar por ultimo
- Agora:
  - o Rails ja consegue fazer backfill deterministico manual com `Gupy`, `Sólides`, `Recrutei`, `Inhire`, `Lever`, `Greenhouse`, `Ashby`, `Teamtailor`, `SmartRecruiters`, `ProgramaThor`, `Remotar` e `Workable`
  - Railway roda `web` e `worker`, com tarefas recorrentes internas do Solid Queue para limpeza/expiracao e descoberta diaria de `24h` as `08:30 BRT`
  - a automacao Codex ampla foi removida; Codex volta apenas como fallback estreito para fontes marcadas pelo Rails e sempre posta em `POST /api/v1/job_ingestions`
- Adiado com intencao:
  - cobrir o resto do catalogo com adapters nativos
  - candidatura automatica
  - notificacoes externas adicionais

Descartados por falta de evidencia:
- necessidade de Redis
- necessidade de React SPA
- necessidade de multiusuario avancado
- necessidade de browser headless para o slice atual
- qualquer finding estrutural novo de alta confianca alem do risco de cobertura ainda incompleta dos adapters
