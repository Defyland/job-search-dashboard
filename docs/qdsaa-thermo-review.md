Escopo analisado:
- app Rails 8 `/Users/allanflavio/Documents/projects/PERSONAL/backend-challenges/job-search-dashboard`
- objetivo auditado: evoluir o dashboard para sair do motor principal em Codex e abrir descoberta deterministica no Rails, mantendo a ingestao Codex como caminho complementar
- superficies revisadas: autenticacao, ingestao, dedupe, filtros/paginacao, historico de runs, source scans, discovered jobs, worker Solid Queue e configuracao de deploy

Verificacao executada:
- `bin/rails db:migrate`: schema atualizado com `SourceScan` e `DiscoveredJob`
- `bin/rails test`: 28 testes, 84 assertions, sem falhas
- `bin/rubocop`: 84 arquivos inspecionados, sem offenses
- `bin/brakeman -q -w2`: 0 warnings
- revisao estatica dos novos adapters `Gupy` e `ProgramaThor`, do `JobDiscovery::Orchestrator` e da extracao reutilizavel `JobIngestions::Recorder`

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
  - `Gupy` agora respeita a janela temporal quando a fonte expõe `datePosted`
  - cada scan por fonte agora roda com transacao propria para evitar contador agregado adiantado em rollback
- Risco residual real:
  - o slice Rails ainda cobre pouco do catalogo: `Gupy` por boards ja conhecidos e `ProgramaThor` por listagem central
  - `ProgramaThor` nao expõe recencia forte nas paginas usadas; o adapter ainda depende de ordem do board e limite de paginas como fallback
  - fontes como `Inhire`, `Sólides`, `Lever`, `Greenhouse`, `Ashby` e `Workable` ainda nao migraram para adapters nativos

A: Acelerar ciclo de feedback
- O ciclo local esta curto e suficiente:
  - `bin/rails test`
  - `bin/rubocop`
  - `bin/brakeman -q -w2`
- O novo ciclo de descoberta ganhou um caminho operacional simples:
  - botao manual em `Runs`
  - `bin/rails "dashboard:discover[20]"`
  - jobs de background via `DiscoverJobsRunJob`

A: Automatizar por ultimo
- Agora:
  - automacao Codex diaria continua publicando e ingerindo via `POST /api/v1/job_ingestions`
  - o Rails ja consegue fazer backfill deterministico manual com `Gupy` e `ProgramaThor`
  - Railway roda `web` e `worker`, com tarefas recorrentes internas do Solid Queue para limpeza/expiracao
- Adiado com intencao:
  - cobrir o resto do catalogo com adapters nativos
  - trocar a busca diaria principal do Codex por cron Rails quando a cobertura native atingir o catalogo minimo
  - candidatura automatica
  - notificacoes externas adicionais

Descartados por falta de evidencia:
- necessidade de Redis
- necessidade de React SPA
- necessidade de multiusuario avancado
- necessidade de browser headless para o slice atual
- qualquer finding estrutural novo de alta confianca alem do risco de cobertura ainda incompleta dos adapters
