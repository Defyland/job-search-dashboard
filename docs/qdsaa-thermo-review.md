Escopo analisado:
- app Rails 8 `/Users/allanflavio/Documents/projects/PERSONAL/backend-challenges/job-search-dashboard`
- objetivo auditado: evoluir o dashboard para sair do motor principal em Codex e abrir descoberta deterministica no Rails, mantendo a ingestao Codex como caminho complementar
- superficies revisadas: autenticacao, ingestao, dedupe, filtros/paginacao, historico de runs, source scans, discovered jobs, worker Solid Queue e configuracao de deploy

Verificacao executada:
- `bin/rails db:migrate`: schema atualizado com `SourceScan` e `DiscoveredJob`
- `bin/rails test`: 39 testes, 131 assertions, sem falhas
- `bin/rubocop`: 96 arquivos inspecionados, sem offenses
- `bin/brakeman -q -w2`: 0 warnings
- smoke local do adapter `Remotar`: `18` candidatos aderentes nas primeiras `4` paginas, com links diretos para `Gupy` e `Inhire`
- smoke local do adapter `Workable`: `0` matches fortes nas primeiras `10` paginas recentes, o que sugere baixo volume atual para o nicho monitorado
- smoke local dos novos adapters ATS:
  - `Inhire` com career pages `yandeh`, `deal`, `mb`, `lighthouseit`, `matera`, `dotgroup`, `inco` e `casacred`: `2` strong e `7` rejected em `20d`; os matches fortes vieram da `Lighthouse`
  - `Lever` com boards `ciandt`, `jobgether`, `decilegroup` e `toptal`: `33` strong, `1` borderline e `261` rejected em `20d`
  - `Greenhouse` com boards `rdsourcing` e `fueledcareers`: `2` strong, `2` borderline e `1` rejected em `20d`
  - `Ashby` com boards `ruby-labs` e `Skydropx`: `0` matches fortes na janela e `3` rejected
- revisao estatica dos adapters `Gupy`, `Inhire`, `Lever`, `Greenhouse`, `Ashby`, `ProgramaThor`, `Remotar`, `Workable`, do `JobDiscovery::Orchestrator` e da extracao reutilizavel `JobIngestions::Recorder`
- validacao em producao no Railway:
  - deploy novo do `web` e `worker` com `bin/predeploy`
  - trigger autenticado de `POST /search_runs`
  - `DiscoverJobsRunJob` executado em producao em ~43s no `Run #7`
  - `Run #7` confirmou scans nativos bem-sucedidos de `Gupy`, `Lever`, `Greenhouse`, `Ashby`, `ProgramaThor`, `Remotar` e `Workable`
  - `Run #7` mostrou impacto real no inbox: `Lever` com `295` candidatos vistos e `34` aceitos; `Greenhouse` com `5` candidatos vistos e `4` aceitos

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
  - os adapters ATS agora podem redescobrir board slugs, tokens e career pages a partir das URLs de vagas ja persistidas, usando o proprio banco como memoria operacional
  - `Gupy` agora respeita a janela temporal quando a fonte expõe `datePosted`
  - `Gupy` deixou de depender apenas de jobs ja associados a `JobSource=gupy`; agora ele consegue minerar boards vistos por outras fontes, como `Remotar`
  - `Inhire` ganhou descoberta publica em duas etapas (`tenants/public/resolve` -> `job-posts/public/pages`) e usa `X-Tenant` no backend, em vez de depender da SPA
  - `Lever`, `Greenhouse` e `Ashby` sairam de `manual_only` e ganharam adapters nativos
  - cada scan por fonte agora roda com transacao propria para evitar contador agregado adiantado em rollback
  - `Remotar` passou a funcionar como discovery hub para ATSs externos porque a API publica entrega `externalLink`
  - `Workable` entrou por API publica global, mas o valor real no nicho atual parece menor que o de `Remotar`
  - o deploy Railway deixou de falhar por `ActiveRecord::ConcurrentMigrationError` quando `web` e `worker` sobem juntos; `bin/predeploy` agora faz retry de `db:prepare`
  - o status final de `SearchRun` na descoberta Rails nao trata mais rejeicoes normais como `partial`; agora `partial` significa apenas falha real de alguma fonte
- Risco residual real:
  - o slice Rails ainda nao cobre todo o catalogo, apesar de agora incluir `Gupy`, `Inhire`, `Lever`, `Greenhouse`, `Ashby`, `ProgramaThor`, `Remotar` e `Workable`
  - `ProgramaThor` nao expõe recencia forte nas paginas usadas; o adapter ainda depende de ordem do board e limite de paginas como fallback
  - `Lever` hoje gera muito rejeitado estrutural porque a heuristica de pre-filtro aceita muitos titulos senior genericos antes da checagem final de stack; isso infla logs e counters sem aumentar cobertura util
  - fontes como `Sólides`, `Recrutei` e `Teamtailor` ainda nao migraram para adapters nativos

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
  - o Rails ja consegue fazer backfill deterministico manual com `Gupy`, `Inhire`, `Lever`, `Greenhouse`, `Ashby`, `ProgramaThor`, `Remotar` e `Workable`
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
