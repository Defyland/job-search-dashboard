Escopo analisado:
- app Rails 8 `/Users/allanflavio/Documents/projects/PERSONAL/backend-challenges/job-search-dashboard`
- objetivo auditado: implementar o dashboard definitivo `Codex -> Rails`, testar no padrao dos outros projetos Rails desta pasta, publicar no Railway e validar em producao
- superficies revisadas: autenticacao, ingestao, dedupe, filtros/paginacao, historico de runs, worker Solid Queue e configuracao de deploy

Verificacao executada:
- `bin/rails test`: 21 testes, 56 assertions, sem falhas
- `bin/rubocop`: 66 arquivos inspecionados, sem offenses
- `bin/brakeman -q -w2`: 0 warnings
- `curl -fsS https://web-production-b2243.up.railway.app/up`: healthcheck verde em producao
- `curl -I https://web-production-b2243.up.railway.app/session/new`: `HTTP/2 200`
- smoke test HTTP de login em producao: `302` para `/` e dashboard autenticado com `200`
- smoke test de ingestao em producao: `POST /api/v1/job_ingestions` retornando `search_run_id=2`
- `railway service status -a`: `web` e `worker` com status `SUCCESS`
- consulta em producao ao Postgres: heartbeats ativos de `Supervisor`, `Dispatcher`, `Worker` e `Scheduler`

Assumptions:
- a descoberta ampla continua sendo responsabilidade do Codex, porque esse ambiente ja tem busca e navegacao web; o Rails nao tenta reimplementar SERP
- o produto definitivo aqui e o inbox persistente com login, memoria, dedupe, filtros, pagina e historico
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
- Alterados:
  - a busca principal nao roda dentro do Rails; o fluxo final e `Codex automation -> POST /api/v1/job_ingestions -> dashboard`
- Suspeitos/deletados:
  - thread como memoria canonica
  - `jobs.json` como banco
  - Netlify/site estatico como produto final
  - crawler Rails amplo para Google-style discovery
  - componentes gerados do Rails sem responsabilidade no produto

D: Delecoes propostas
- Sem findings ativos de delecao obrigatoria no estado atual.
- Delecoes ja aplicadas durante a implementacao:
  - `Action Mailer`, `Action Cable`, `Active Storage`, `Kamal`, `solid_cache` e `solid_cable`
  - runtime packages desnecessarios no container
  - `db/queue_schema.rb` apos consolidar Solid Queue no schema principal do banco

S: Simplificar/Otimizar
- Sem findings P1/P2/P3 abertos depois da revisao final.
- A forma que sobreviveu esta coerente com o problema:
  - models pequenos e com ownership claro: `Job`, `JobSource`, `SearchRun`, `SearchRunItem`, `User`, `Session`
  - ingestao centralizada em um unico servico: `/Users/allanflavio/Documents/projects/PERSONAL/backend-challenges/job-search-dashboard/app/services/job_ingestions/importer.rb`
  - UI server-rendered com Turbo/ERB; sem SPA, sem websocket, sem API publica de leitura
  - Solid Queue simplificado para banco unico no Railway, com tabelas no schema principal em vez de schema paralelo
- Correcao estrutural mais importante encontrada e ja resolvida:
  - o filtro de fontes duplicava ATSs porque a ingestao criava `JobSource` redundante por host. Isso foi corrigido em `/Users/allanflavio/Documents/projects/PERSONAL/backend-challenges/job-search-dashboard/app/models/job_source.rb` e `/Users/allanflavio/Documents/projects/PERSONAL/backend-challenges/job-search-dashboard/app/services/job_ingestions/importer.rb`
- Risco residual real:
  - a qualidade da descoberta continua dependente da prompt/heuristica da automacao Codex e da variabilidade externa dos boards. O Rails esta correto como inbox, mas nao mede cobertura de mercado por si so.

A: Acelerar ciclo de feedback
- O ciclo local esta curto e suficiente:
  - `bin/rails test`
  - `bin/rubocop`
  - `bin/brakeman -q -w2`
- O deploy ficou verificavel com smoke tests baratos:
  - `GET /up`
  - login HTTP
  - `POST /api/v1/job_ingestions`
  - `railway service status -a`
  - consulta direta aos heartbeats do Solid Queue

A: Automatizar por ultimo
- Agora:
  - automacao Codex diaria publica digest na thread e persiste resultados no dashboard via `POST /api/v1/job_ingestions`
  - Railway roda `web` e `worker`, com tarefas recorrentes internas do Solid Queue para limpeza/expiracao
- Adiado com intencao:
  - descoberta feita pelo proprio Rails
  - candidatura automatica
  - notificacoes externas adicionais

Descartados por falta de evidencia:
- necessidade de Redis
- necessidade de React SPA
- necessidade de multiusuario avancado
- necessidade de cron do Railway para a busca principal
- qualquer finding estrutural novo de alta confianca; a revisao final nao encontrou regressao relevante aberta
